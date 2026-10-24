---
status: fixed
found: 2026-10-24
---
# Brauz 1.0.5.b2 opens no window from the Dock and hangs until killed

## Symptom
"Right now my Brauz (1.0.5.b2) crashed right out of the dock, I started it and it is not opening and later crashes with some logs."

The log is a system hang report (spindump), not a crash report. It was saved as `crash_dump.txt` in the checkout root, untracked.
- Event: hang. Duration 35.99s. Sampling covered 3.10s, after the app had been unresponsive for 33s.
- Taken at 2026-10-24 12:22, on macOS 27.0.1 (26A434), MacBookAir10,1.
- Binary: `/Applications/Brauz.app`, 1.0.5 (202610211427), UUID `1C7018C6-B3A4-3C36-BED8-9D66B51D0DF5`, tag `v1.0.5.b2`.
- The heaviest main-thread stack, 31 of 31 samples:
  1. The launch's open event: `_handleAEOpenEvent` → `_doOpenUntitled` → `AppDelegate.applicationOpenUntitledFile`.
  2. SwiftUI's `AppWindowsController.showInitialWindows` → `UpdateGroup.dispatchActions` → `Brauz+4825936`.
  3. In 20 of 31 samples: `Brauz+4813056` → `NSWindow makeKeyAndOrderFront:` → `_NSCGSWindowLocalOrderingState*`, which is AppKit's window ordering.
- CPU: the process used 23.9s of CPU in 33s; the main thread used 2.76s during the 3.1s sample.

The user also saw "empty hollow windows" spawn in Brauz before the hang.

## Loop
The live repro, 2026-10-24 12:45, PID 82827: launch `/Applications/Brauz.app` and count its window-server windows with `/tmp/brauz-triage/wincount.swift <pid>`.
- Red: 1,512 windows, 1,508 of them 0×0, none on screen.
- The count keeps growing, about 3.5 a second, and slows as it grows.
- `sample` shows the same stack as the report, `makeKeyAndOrderFront` under `showInitialWindows`.

## Cause
**The hang: launch restores thousands of saved windows.**
- `~/Library/Application Support/Brauz/windows.json` holds 2,393 records.
  - 2,256 are empty: one space, no tabs, no frame.
  - About 60 carry `macsleep.example.com` pins from `MacSleepTests`.
- At launch, `Windows.restore()` (`Windows.swift`, v1.0.5.b2) opens one `NSWindow` per record.
- Each `makeKeyAndOrderFront` re-sorts AppKit's window-ordering list, so the launch costs O(n²).
- The empty records are the user's "hollow windows".

**Why the profile filled up: the XCTest suite wrote into the real profile.**
- `Store.testing` is true only when `SEARCH_PROBE` is set or the executable sits under `/.build/`. Under `swift test` the executable is Xcode's `xctest`.
- `Store.folder` and `Store.world` are `static let`, fixed on first use.
- On `main`, the first class to touch `Store` is `BlockedPopupsTests`, which sets `SEARCH_PROBE` in `class setUp`. That's why full runs land in `Search (blocked-popups-<pid>)`.
- Branch `fix/0022-remember-sign-in` added `BasicAuthTests`, which sorts just before it, sets no probe, and touches `Store`/`Vault`.
- So every full run of the 0022 branch and of `try/2026-10-24` used the real folder, settings and website data store for all later tests. It also used the real Keychain, through `KeychainBasicAuthStore`.

**Evidence:**
- The two "flaky" failures in those full runs, which pass alone, are the guards firing:
  - `ExtensionUpdateTests`: "This test must never update real extensions".
  - `ImportFileTests`: a bookmark count off by the real bookmarks.
- The real profile's `bookmarks.json`, `history.json`, `pins.json`, `spaces.json`, `downloads.json` and `windows.json` were all rewritten 12:32–12:34, during the `try/2026-10-24` full run.
- `history.json` and `windows.json` contain test hosts.

These were misread as load flakes at first. That was wrong.

## Damage (to assess with the user)
- Real profile files listed above, likely overwritten with test data.
- Real `UserDefaults` keys that tests remove, such as `sleep.after`, `tabs.keepAwake`, `sites.awake`.
- Real Keychain items under Brauz's label, which `BasicAuthTests` adds and forgets for test hosts.
- No local APFS snapshots. The Time Machine destination was not mounted.

## Decisions (2026-10-24)
- No backup: the overwritten profile data is accepted as lost.
- `windows.json` was deleted, after a verified copy went to `/tmp/brauz-triage/windows.json.removed-2026-10-24`.
- Leak fix: an XCTest process is always a test run (`Store.testing`), and gets a world of its own. A guard test fails if a test sees the real folder.
- Launch guard: `restore()` skips records with no tabs, and `save()` stops re-appending them. No cap on the window count.

## Fix
- `fix/0029-test-isolation`, `Store.swift`: `Store.testing` is also true when `XCTestCase` exists. With no probe name, `Store.world` gives an XCTest run `xctest-<pid>`. The folder, settings suite, website data store and Keychain label all follow from it. This became FORK.md rule 12.
- `fix/0029-skip-empty-windows`, `Windows.swift`: `WindowRecord.isEmpty` and `Browsers.restorable(_:)` drop every record after the first that has no tabs. `restore()` opens only those records. `save()` re-appends only those, so a process that never restores no longer snowballs the file.
- `BasicAuthTests` (branch 0022) sets its own `SEARCH_PROBE`, and uses `XCTUnwrap` instead of force-unwraps. An empty result used to trap the whole test process.

## Guarded by
- `StoreIsolationTests.testTestRunIsIsolatedWithoutSearchProbe`
- `WindowRestoreTests`
- The done-check: the real profile's file times and `dev.aabc.brauz.plist` are unchanged across a full `swift test`.

## Test by hand
- Open Brauz from the Dock: one window opens, with the last session's tabs.
- Open a second window with a tab, quit and relaunch: both windows come back.
- No test covers the leftovers in the user's login Keychain. The test hosts listed in `BasicAuthTests` were removed by hand. A leftover `shared.example.com` form login makes `testSignInEntryDistinguishableFromFormLoginForSameHost` fail, because the Keychain treats the label as outside an item's identity.

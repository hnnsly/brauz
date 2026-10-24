---
status: fixing
found: 2026-10-23
---
# Mac system sleep offloads background tabs to reclaim RAM

## Symptom
Background tabs consume memory while the Mac is asleep because no system sleep notification triggers tab offloading.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter MacSleepTests`

## Cause
Brauz runs tab sleep checks on an in-app repeating timer and on dispatch memory pressure warnings in Sources/Search/Sleep.swift:91-112. The app does not listen to `NSWorkspace.willSleepNotification` anywhere in Sources/Search/App.swift:778-806, so background tabs remain active across Mac sleep. Furthermore, Tab.discard() in Sources/Search/Tab.swift:1460-1488 tears down Swift references and removes the web view from the superview, but omits WebKit's private `_close` selector, allowing WebKit process pools to retain WebContent processes.

Ranked hypotheses:
1. Adding an `NSWorkspace.willSleepNotification` observer that triggers `sleepIdle(within: 0)` will discard background tabs when the Mac sleeps. (Evidence: zero matches for `willSleepNotification` in Sources/Search/).
2. Calling `web.perform(NSSelectorFromString("_close"))` in `discard()` will force immediate `WebProcessProxy` invalidation and reclaim process memory. (Evidence: 0009 diagnostics showed helper processes and IOSurfaces lingering across background tabs).

Ruled out / wrong in the first draft:
- Process suspension (`tab.paused` / `_suspendPage:`) was intentionally removed during issue 0011 upstream integration and is forbidden by DOCS/FORK.md Rule 4.
- DraftSleepTests tests idle timer thresholds rather than Mac sleep or RAM reclamation.

## Decisions (2026-10-24)
- When the Mac goes to sleep (`NSWorkspace.willSleepNotification`), put background tabs to sleep at once, ignoring idle age.
- Pins, playing media, keep-awake and existing exemptions still apply, and drafts keep rule 4 protection (`max(sleep delay, 1h)`).
- Every background tab will reload after the Mac wakes; the user accepted that.
- Not chosen: measuring first inside 0009, calling the private `_close` in `discard()` alone, dropping the issue.

## Fix
Added `MacSleep.swift` observing `NSWorkspace.willSleepNotification` on `NSWorkspace.shared.notificationCenter` with a one-line hook in `watchForSleep` in `Sleep.swift`. On system sleep, `sleepIdle(within: 0)` runs across all open browsers to put background tabs to sleep immediately. Existing sleep exemptions remain intact: visible tabs (active tab and split partner) never sleep, media/audio, keep-awake, and active pins stay awake, and typed drafts keep rule 4 protection (idle >= 1 hour).

## Guarded by
`Tests/SearchTests/MacSleepTests.swift`

## Acceptance
- Mac sleep notification offloads eligible background tabs immediately.
- WebContent processes and IOSurfaces are released during Mac sleep.

## Files
- `Sources/Search/MacSleep.swift`
- `Sources/Search/Sleep.swift`
- `Tests/SearchTests/MacSleepTests.swift`

## Test by hand
Start Brauz (`./build.sh && open build/Brauz.app`).
1. Open multiple tabs with heavy pages, leaving one active and others in background. Put Mac to sleep (Apple menu › Sleep) and wake up. In Activity Monitor, verify background WebContent processes terminated; clicking a background tab reloads and restores it.
2. In split view with two tabs visible side-by-side, put Mac to sleep and wake up. Verify both visible tabs stayed awake without reloading.
3. In a tab playing audio or kept awake via site settings, put Mac to sleep and wake up. Verify the exempt tab stayed awake.
What no automated test covers: actual macOS kernel sleep/wake power state transitions and hardware memory retention.

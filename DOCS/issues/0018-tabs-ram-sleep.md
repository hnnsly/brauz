---
status: open
found: 2026-10-23
---
# Mac system sleep offloads background tabs to reclaim RAM

## Symptom
Background tabs consume memory while the Mac is asleep because no system sleep notification triggers tab offloading.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter DraftSleepTests`

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
Add an `NSWorkspace.willSleepNotification` observer in Sources/Search/Sleep.swift (or a fork-only file with a hook in Browser.watchForSleep) that calls `sleepIdle(within: 0)`. Invoke WebKit's private `_close` selector dynamically in Tab.discard() if available.

## Guarded by
`Tests/SearchTests/DraftSleepTests.swift`

## Acceptance
- Mac sleep notification offloads eligible background tabs immediately.
- WebContent processes and IOSurfaces are released during Mac sleep.

## Files
- `Sources/Search/Sleep.swift`
- `Sources/Search/Tab.swift`
- `Sources/Search/App.swift`

## Test by hand
Put Mac to sleep with background tabs open, check process count and RAM footprint on wake.

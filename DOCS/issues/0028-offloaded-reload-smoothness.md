---
status: open
found: 2026-10-23
---
# Optimize and smooth out reloading experience when restoring offloaded pages

## Symptom
Reloading and waking up offloaded pages feels ugly and noticeably slow, showing flash of white or rough transition states.

## Loop
A Python bench probe under Tests/ (e.g., `Tests/offloaded_wake_timing.py`) using the bench socket. It launches `build/Brauz.app`, puts an active tab to sleep via the bench sleep command, wakes it via `select`, and asserts that `tab.cover` transitions synchronously with WebKit's first frame rendering progress event rather than a fixed 0.45s timer.

## Cause
When an offloaded tab wakes (`Tab.wake()` in `Sources/Search/Tab.swift:1375`), it presents a snapshot cover and builds a fresh `PageView` with `alphaValue = 0` via `holdForFirstFrame()` (`Sources/Search/Tab.swift:1832`). In `Browser.swift:5650`, `webView(_:didCommit:)` starts an arbitrary 0.45s timer (`tab.uncover(after: 0.45)`). If the page takes longer than 0.45s to render its first visually non-empty layout, the snapshot cover fades away while the web view is still transparent, exposing the white window ground (`Palette.ground` in `Sources/Search/Design.swift:45`). Once rendering progress fires with first frame (`Sources/Search/Browser.swift:5657`), `showFirstFrame()` fades `alphaValue` to 1 (`Sources/Search/Tab.swift:1843`), causing a visible white flash. Furthermore, any click during wake reaches `PageView.mouseDown` (`Sources/Search/Tab.swift:1757`) because the cover disables hit-testing (`Sources/Search/Stage.swift:44`), immediately removing the cover with zero delay (`Sources/Search/Tab.swift:659`).

### Ruled out / wrong in the first draft
- Guessed that `revive()` was involved in restoring offloaded pages; ruled out because `Browser.swift:2936` calls `wake()` on sleeping tabs, and `revive()` only runs if `wake()` returns false.
- Guessed that document readiness synchronization in `loadAndVerify()` (`Sources/Search/Tab.swift:1328`) caused the delay; ruled out because cover removal was driven purely by the 0.45s timer in `didCommit` (`Sources/Search/Browser.swift:5650`).

## Decisions (2026-10-24)
- The snapshot cover of a waking tab stays until the first visually non-empty layout (`renderingProgressDidChange` firstFrame event in `Sources/Search/Browser.swift:5657`), then crossfades into the live page over 0.2s (`Sources/Search/Stage.swift:68`).
- Replaces the fixed 0.45s timer started in `didCommit` (`Sources/Search/Browser.swift:5650`).
- `didFinish` (`Sources/Search/Browser.swift:5664`) and the existing 4-second timeout stay as terminal fallbacks.
- Clicks on the waking tab do nothing until first paint so they cannot drop the cover early.

## Fix
The planned change, as the decision states.

## Guarded by
Offloaded wake timing and transition smoothness checks via python bench probe.

## Acceptance
- Waking an offloaded tab transitions smoothly from its snapshot cover to the live page without visual stutter or perceived slowness.
- The snapshot cover remains visible until the first visually non-empty layout is ready.

## Files
- `Sources/Search/Browser.swift`
- `Sources/Search/Tab.swift`
- `Sources/Search/Stage.swift`

## Test by hand
Let tabs sleep/offload, click them to wake, observe transition smoothness.

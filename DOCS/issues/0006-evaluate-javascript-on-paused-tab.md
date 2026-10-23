---
status: fixed
found: 2026-10-09
---
# Brauz crashes on space switch when Tab.revive evaluates JavaScript on a paused tab

## Symptom
Brauz 1.0.4 (build 202610081738, installed in /Applications) crashed on the main thread at 18:17 on 2026-10-09. Incident 312C0A97-7EDA-4D11-A6A9-5B645D404FF4.
Exception: `EXC_BREAKPOINT` (SIGTRAP) at `+[NSApplication _crashOnException:]` triggered by an uncaught Objective-C exception from WebKit:
`-[WKWebView evaluateJavaScript:completionHandler:]`.

Application specific backtrace:
- Frame 3: `WebKit -[WKWebView evaluateJavaScript:completionHandler:]`
- Frame 4: `Tab.revive()` (`Sources/Search/Tab.swift:1149`, evaluating `"document.readyState"`)
- Frame 5: `Browser.switchToSpace(_:)` (`Sources/Search/Spaces.swift:214`, in `for tab in tabs where visibleTabIDs.contains(tab.id) { if !tab.wake() { tab.revive() } }`)
- Frame 6+: SwiftUI layout and transaction update on the main thread.

## Loop
`swift test --filter PausedTabDiscardTests.testRevivingPausedTabDoesNotThrow`
Red: calling `tab.revive()` on a paused tab throws `NSInternalInconsistencyException` "The WKWebView is suspended" at `Tab.swift:1149`.
Green: returns immediately without throwing.

## Cause
When a background space is parked, its tabs can be paused by `Browser.pauseIdle` via WebKit's `_suspendPage:`.
When switching back to that parked space (`Spaces.swift:211-215`), the row is restored and visible tabs are woken up or revived:
```swift
for tab in tabs where visibleTabIDs.contains(tab.id) {
    if !tab.wake() { tab.revive() }
}
```
If a visible tab is paused, `tab.wake()` returns `false` because the tab is not asleep (`tab.built != nil`).
`tab.revive()` was then called without resuming the tab first.
`Tab.revive()` unconditionally called `web.evaluateJavaScript("document.readyState")`.
WebKit throws `NSInternalInconsistencyException` "The WKWebView is suspended" whenever `evaluateJavaScript` is invoked on a suspended page. Because nothing caught the Objective-C exception on the main thread, the app terminated immediately.

In addition:
- `Browser.swift:2280` (`addSplit`) called `pane.revive()` without `pane.resume()`.
- `Browser.swift:2417` (`replaceSplitMember`) called `tab.revive()` without `tab.resume()`.
- `Tab.revive()` lacked a guard against being called on a paused or suspended web view.

## Fix
1. In `Tab.swift`: in `Tab.revive()`, guard against paused or suspended web views (`guard !paused, !web.isSuspended else { return }`).
2. In `Spaces.swift`: when switching to a parked space, resume visible tabs before waking or reviving them (`tab.resume()`).
3. In `Browser.swift`: in `addSplit` and `replaceSplitMember`, resume panes before reviving.
Files: Sources/Search/Tab.swift, Sources/Search/Spaces.swift, Sources/Search/Browser.swift, Tests/SearchTests/PausedTabDiscardTests.swift.

## Verified
Full `swift test` on Apple Silicon with Xcode: 59 tests, 0 failures. `PausedTabDiscardTests` passes in 0.66 s.

## Guarded by
`Tests/SearchTests/PausedTabDiscardTests.swift`: `testRevivingPausedTabDoesNotThrow`.

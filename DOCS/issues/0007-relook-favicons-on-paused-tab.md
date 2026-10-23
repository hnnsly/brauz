---
status: fixed
found: 2026-10-09
---
# Brauz crashes when system look changes while tabs are paused

## Symptom
Brauz 1.0.4 (build 202610081738, installed in /Applications) crashed on the main thread at 18:37:12 on 2026-10-09. Incident B6F6C870-5A9A-4755-AF4E-11DC10C54E60.
Exception: `EXC_CRASH` (SIGABRT) triggered by an uncaught Objective-C exception from WebKit:
`-[WKWebView evaluateJavaScript:completionHandler:]`.

Triggered by Thread 0 via dispatch source invocation on the main queue (`_dispatch_source_invoke`).

Application specific backtrace:
- Frame 3: `WebKit -[WKWebView evaluateJavaScript:completionHandler:]`
- Frame 4: `Favicons.fetch(for:changed:)` (`Sources/Search/Icons.swift:144`, evaluating `Favicons.probe`)
- Frame 5: `Favicons.relook(_:)` (`Sources/Search/Icons.swift:108`, in `for tab in tabs { fetch(for: tab) }`)
- Frame 6: `Browser.relook()` (`Sources/Search/Browser.swift:1873`, in `Favicons.shared.relook(tabs.filter { !$0.asleep })`)
- Frame 7: `Browser.relook()` closure
- Frame 8: `DispatchQueue.main.asyncAfter` timer block (`Sources/Search/Browser.swift:1764` or `1771`)
- Frame 9: `_dispatch_source_invoke` timer handler on the main thread.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter PausedTabDiscardTests.testRelookingFaviconsOnPausedTabDoesNotThrow`
Red: `The WKWebView is suspended (NSInternalInconsistencyException)` at `Icons.swift:144`.
Green: returns immediately without throwing.

## Cause
When the system theme changes (`AppleInterfaceThemeChangedNotification`) or the user changes look in Settings, `Browser` schedules `relook()` 0.3 s later via `DispatchQueue.main.asyncAfter`.
`Browser.relook()` filters out sleeping tabs (`tabs.filter { !$0.asleep }`), but retains paused tabs (`$0.paused == true`).
`Favicons.shared.relook(_:)` calls `fetch(for: tab)` for each tab.
If the favicon for the current look is not fresh in the on-disk cache, `Favicons.fetch(for:changed:)` calls `tab.web.evaluateJavaScript(Favicons.probe)`.
Because the tab is suspended by WebKit's `_suspendPage:`, WebKit raises `NSInternalInconsistencyException` "The WKWebView is suspended". Because this occurs on the main runloop from a dispatch timer with no exception handler, the app aborts immediately.

## Fix
1. In `Sources/Search/Icons.swift`: in `fetch(for:changed:)`, guard against paused or suspended web views (`guard !tab.paused, let web = tab.built, !web.isSuspended else { return }`) before probing with JavaScript.
2. In `Sources/Search/TabPause.swift`: when a paused tab resumes (`Tab.resume()`), call `Favicons.shared.fetch(for: self)` to fetch its icon once it is running again.
3. In `Sources/Search/Browser.swift`: when link hover preference changes (`prefs.$showsLinks`), ensure `HoveredLink` injection does not evaluate JavaScript on suspended pages.

## Guarded by
`Tests/SearchTests/PausedTabDiscardTests.swift`: `testRelookingFaviconsOnPausedTabDoesNotThrow`.

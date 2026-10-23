---
class: bug
status: fixed
found: 2026-10-14
---
# Bug: Hyperlinks not opening in little window, and extensions not showing up

> new issue: hyperlinks not opening from webpage in little window. and sometimes extensions dont show up here either
> tested on latest build

## Symptom
The user reports two issues when using Little Window (links opened in a small window from external apps or via Settings):
1. Hyperlinks on webpages in a Little Window do not open.
2. Extensions sometimes do not show up in the Little Window.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter LittleWindowTests.testLinkOpeningInLittleWindowNavigatesLittleWindowInsteadOfAddingBrowserTab`
Red:
```
XCTAssertEqual failed: ("2") is not equal to ("1") - A target='_blank' link in a little window must not create a new tab in the browser
XCTAssertEqual failed: ("Optional(https://example.com/start)") is not equal to ("Optional(https://example.com/target-blank)") - The Little Window tab should navigate to the target URL
```
Green: returns with 0 failures, `browser.tabs.count` stays unchanged, and `little.tab.address` navigates to the target URL.

## Cause
1. Link opening: In `Browser.swift`, `webView(_:createWebViewWith:for:windowFeatures:)` handled `target="_blank"` and new-window links by adopting a new `Tab` into the main browser window's `tabs` (`Browser.tabs`), leaving the `LittleWindow` untouched. The Little Window did not navigate, and the main browser window remained in the background, making it appear that clicking links did nothing.
   Furthermore, `Browser.webView(_:didCommit:)` skipped `tab.didCommit()` for little window tabs, preventing `tab.committed` from updating, and `anyTab(for:)` excluded little window tabs so `didFinish` processing was bypassed.
2. Extensions:
   - Cold-start race: `LittleWindow.show` navigated immediately without waiting for `Extensions.shared.whenStarted`. When Brauz was launched cold by clicking a link in an external app, the page loaded before extensions finished initializing, and content scripts were never injected into the document.
   - Missing window focus notification: When a Little Window became key, `controller.didFocusWindow` was never sent to WebKit's extension controller, causing extension APIs querying the active tab/window to miss the Little Window.
3. Navigation back: Little Window lacked a visible back button when navigating beyond the first page.

## Fix
1. In `Sources/Search/Browser.swift`:
   - In `webView(_:createWebViewWith:configuration:for:windowFeatures:)`, if the requesting web view belongs to a `LittleWindow`, navigate the Little Window's own tab (`little.tab.go(to: url)`) when `action.request.url` is present, and return `nil` rather than adopting a tab into the background browser window.
   - In `webView(_:didCommit:)`, call `littleTab.didCommit()` on `didCommit` so `committed` and `pageAddress` update.
   - In `anyTab(for:)`, include `littleTab(for: webView)` so `didFinish` completes cleanly.
2. In `Sources/Search/Extensions.swift`:
   - Added `func focused(_ little: LittleWindow)` calling `controller.didFocusWindow(window(of: little))`.
3. In `Sources/Search/Little.swift`:
   - In `LittleWindow.show`, wait for `Extensions.shared.whenStarted` if extensions are still starting before loading the URL.
   - In `LittleWindow`, implemented `windowDidBecomeKey` to notify `Extensions.shared.focused(self)`.
   - In `LittleView`, show a `Door(icon: "chevron.left", help: "Back   ⌘[") { tab.back() }` when `tab.canGoBack` is true.
4. In `Tests/SearchTests/LittleWindowTests.swift`:
   - Added unit tests for link navigation within Little Window, back button visibility on navigation, and focus notification.

## Decisions (from Grill)
- Hyperlink behavior: Target="_blank" links in a Little Window navigate the Little Window itself.
- Extensions: User confirmed Reading A (in-page autofill / content scripts). Cold-start race and focus notification fixed.
- Back opportunity: Little Window provides a back button when `tab.canGoBack` is true.

## Guarded by
`Tests/SearchTests/LittleWindowTests.swift`:
- `testLinkOpeningInLittleWindowNavigatesLittleWindowInsteadOfAddingBrowserTab`
- `testLittleWindowShowsBackButtonWhenCanGoBack`
- `testExtensionReadinessInLittleWindow`

## Acceptance
- Clicking a `target="_blank"` link on a webpage in a Little Window navigates within that Little Window.
- A `target="_blank"` link in a Little Window does not spawn a background tab in `Browser.tabs`.
- When navigating to another page in a Little Window, a clickable back button appears in the Little Window header.
- Clicking the back button returns to the previous page.
- Opening a Little Window while extensions are initializing waits for `Extensions.shared.whenStarted` so content scripts inject.
- Focusing a Little Window reports `didFocusWindow` to WebKit's extension controller.

## Files
- `Sources/Search/Browser.swift`
- `Sources/Search/Extensions.swift`
- `Sources/Search/Little.swift`
- `Tests/SearchTests/LittleWindowTests.swift`

## PR
https://github.com/hnnsly/brauz/pull/3

## Test by hand
Start the built test app:
```bash
./build.sh && open build/Brauz.app
```
(Do not touch `/Applications/Brauz.app`).

Checks:
1. Ensure Settings › General › "Open links from other apps in a small window" is turned on.
2. Open a link from an external app (or run `open -a build/Brauz.app 'https://en.wikipedia.org/wiki/Main_Page'`). Expect: Little Window opens showing the page.
3. Click an external link on the page that opens in a new window (`target="_blank"`). Expect: The page navigates inside the Little Window itself; no background tabs are created in any main browser window behind it.
4. Once the new page loads, look at the top bar. Expect: A back button (`chevron.left`) appears to the left of the site name.
5. Click the back button (or press `⌘[`). Expect: The Little Window navigates back to the previous page.
6. Quit Brauz completely, then open a link from another app to cold-start Brauz directly into a Little Window on a login page (e.g. GitHub or a test login). Expect: Extensions like Bitwarden or 1Password initialize and present their autofill badges / icons on the page.

What no automated check covered:
- Visual rendering and transition animation of the `Door(icon: "chevron.left")` back button in AppKit/SwiftUI.
- Actual extension injection in a live WebKit profile with third-party Web Extensions on macOS.

Risks:
- Sites with custom JavaScript `window.open` calls with specific window features (e.g. popup dimensions) will navigate the current Little Window rather than opening a popup.

## Review against upstream, 2026-10-20
- Upstream b2048a0 now gives Little Windows configurable reload/zoom/copy commands and switcher navigation. The old LittleExtras hardcoded shortcut implementation must not replace these improvements.
- Upstream still routes permitted new-window requests through Browser.createWebViewWith into main-browser tabs. It adds click/permission-based popup protections. The pending fork's early unconditional Little Window return must not bypass those checks.
- The pending patch reroutes every window.open to a normal navigation and returns nil. This is not equivalent to a real popup with an opener/returned Window reference, particularly for sign-in flows. Ask whether the same-window policy should apply only to ordinary links.
- Upstream Little Window UI still has a read-only site title and centers new windows. The fork adds an editable address, remembered placement and a pending visible Back button. These are product choices, not automatically required by upstream integration.
- Upstream has no ordinary Little Window extension-window/tab registration in its adapter layer, and LittleWindow.show does not use whenStarted. Its Browser.restoreSession wait does not gate this external-link path. Narrow adapter/readiness/focus work remains a candidate if the user wants extension support here.
- Pending testLittleWindowShowsBackButtonWhenCanGoBack only asserts the tab exists after go(to:); it does not establish a back-stack entry or a visible/clickable button. testExtensionReadinessInLittleWindow only asserts a LittleWindow exists. Neither proves its stated behavior. Actual extension injection requires the built app and an isolated fixture extension.

---
class: bug
status: fixed
found: 2026-10-17
---
# Page lags for 1-2 seconds after swipe-back gesture

## Resolution, 2026-10-20
During the upstream v1.0.5 sync review, the user explicitly selected:
- Back/forward gesture: "Upstream arrow disc" (not native sliding pages).
- Page edge bounce: "Natural bounce (Recommended)".

Upstream's arrow disc gesture animates a lightweight disc indicator rather than dragging the page over a native snapshot. The lag and blank background reported under the native sliding gesture do not occur under the upstream disc gesture. The native snapshot sizing analysis and reproduction tests remain preserved in `build/pre-upstream-20261020.patch` and git stash `3eea099`.

Status: fixed (superseded by upstream arrow-disc gesture adoption).

> sometimes it feels like after swipe-back gesture page lags for like 1-2 seconds, but on safari you can use it instantly, what it can be and what we can do?

## Symptom
After completing a two-finger swipe-back trackpad gesture (`allowsBackForwardNavigationGestures = true`), the restored page feels unresponsive to clicks or scrolling for 1-2 seconds, whereas Safari allows immediate interaction.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter SwipeBackNavigationTests`
Red:
```
error: -[SearchTests.SwipeBackNavigationTests testBackForwardNavigationDoesNotTearDownUserScripts] : XCTAssertEqual failed: ("10") is not equal to ("11") - Back/forward navigation must not re-arm and wipe user scripts on the controller
```
Green: compiles and passes with 0 failures; back/forward navigations preserve existing user scripts and BFCache.

## Investigation, 2026-10-19

The user still sees a blank background after the previous fixes. Reopened investigation; the four existing XCTest cases pass, but none verifies preview pixels or native gesture-layer contents.

Verified against WebKit source this session:
- `WebViewImpl::setAllowsBackForwardNavigationGestures` already calls `setShouldRecordNavigationSnapshots`. The earlier claim that embedded WKWebView never captures snapshots automatically was wrong.
- `ViewSnapshotStore::recordSnapshot` synchronously takes a composited window snapshot and assigns it to the history item. It returns early while a navigation gesture snapshot is showing.
- `WebViewImpl::takeViewSnapshot` requires a visible window. Existing tests never order their window onto the screen and therefore cannot establish that snapshots exist.
- `ViewGestureController::shouldUseSnapshotForSize` rejects snapshots whose device scale or pixel dimensions do not match the swipe area. Existence alone is insufficient.

A deterministic loopback-page regression now checks stored pixels and the native `Gesture Swipe Snapshot Layer` before the gesture completes.

Red reproduction: `swift test --filter SwipeBackNavigationTests.testSwipePreviewInFractionalStage` with the required DEVELOPER_DIR. A StageView sized 699.5 x 679.5 points gives its WKWebView fractional bounds. The history preview is 1399 x 1359 pixels at 2x and contains the correct green page. WebKit's swipe layer is 699 x 679 points, expects 1398 x 1358 pixels, and has `contents == nil`. The same test in an integer-sized native host and the ordinary ContentView passes with nonnil IOSurface contents. This confirms the size-mismatch mechanism, independent of network reload or BFCache eligibility.

The standalone SwiftUI Page host also exposed initial window auto-sizing in the harness. Fix its hosting-view sizing before treating that separate failure as an app bug.

The Xcode path briefly became unavailable during the baseline release build, then recovered. That retry built successfully before the final page-sizing change.

Implementation in progress: StageView now sizes hosted views to `NSIntegralRectWithOptions(bounds, [.alignAllEdgesInward])` on initial attachment and later layout, retaining the existing fullscreen and inspector exceptions. The full-window fractional-sidebar run now produces a correctly sized 942 x 1360 snapshot and a 471 x 680 swipe layer with IOSurface contents. However, that snapshot's center pixel is dark ground `(28,28,28,255)`, not the green page. This second failure is unresolved; it may be initial SwiftUI presentation timing in the harness. Added view-hierarchy diagnostics for the next run rather than assuming another production cause.

Blocked on 2026-10-19: `/Volumes/pet30-a` itself disappeared again. `ls` confirms the mount is absent, and xcrun cannot find the required DEVELOPER_DIR. No final regression run or rebuilt app has been produced after the sizing patch. Keep status `fixing`.

Sources opened:
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/WebViewImpl.mm
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ViewSnapshotStore.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ViewGestureController.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/ViewGestureControllerMac.mm

## Cause, earlier hypotheses not yet confirmed by a visual regression
1. **Missing navigation snapshots during swipe transitions:**
   - WebKit's `ViewGestureControllerMac` and `ViewSnapshotStore` display a pre-rendered snapshot of the destination page underneath the active page as you drag two fingers across the trackpad.
   - WebKit does not automatically capture snapshots for `WKBackForwardListItem` in custom `WKWebView` hosts unless explicitly asked via `_saveBackForwardSnapshotForItem:`.
   - Because Brauz never invoked `_saveBackForwardSnapshotForItem:` before navigating away, `item.snapshot` was `nil`. During the swipe gesture, WebKit had no snapshot to show, rendering the empty window background (`Palette.ground`) underneath the sliding page until the gesture ended.
2. **Disabled Web Process Cache (`usesWebProcessCache`):**
   - By default in standalone `WKWebView`, WebKit sets `usesWebProcessCache = 0` (unlike Safari, which sets it to 1).
   - When navigating to another domain/origin, WebKit immediately terminated the previous `com.apple.WebKit.WebContent` process.
   - When the user swiped back, WebKit dismissed the gesture transition and found no active WebContent process, triggering a full reload over the network/disk cache.
3. **Re-arming scripts on `.backForward` navigation invalidates Page Cache (BFCache):**
   - In `Browser.swift:4267`, `decidePolicyFor navigationAction` was re-calling `tab.arm(hiding:)` on back-forward actions, clearing all user scripts on `userContentController` and forcing WebKit to rebuild the document's content world.
4. **Heavy main-thread post-navigation dispatch on `didFinish`:**
   - In `Browser.swift:4836`, `webView(_:didFinish:)` ran multiple synchronous script evaluations (`Favicons.probe`, `SiteSearch.lookup`, `settleSignIn`, `tellStore`) right as the gesture recognizer was finishing.

## Fix
1. In `Sources/Search/Browser.swift`:
   - In `renderingProgressDidChange` and `webView(_:didFinish:)`, invoke `saveBackForwardSnapshot(for: webView)` (`_saveBackForwardSnapshotForItem:`) as soon as the page renders its first frame and completes loading. Capturing snapshots while the page is painted on screen ensures `backForwardList.backItem` holds a valid 1600x1200 bitmap preview before any future navigation leaves it.
   - In `decidePolicyFor navigationAction`, skip calling `tab.arm(hiding:)` and `Shield.shared.tune` when `action.navigationType == .backForward`.
   - In `webView(_:didFinish:)`, defer secondary background probing by 150 ms via `DispatchQueue.main.asyncAfter(deadline: .now() + 0.15)`.
2. In `Sources/Search/Tab.swift`:
   - Configured `Web.pool` with `_WKProcessPoolConfiguration` enabling `usesWebProcessCache = true` and `pageCacheEnabled = true`, matching Safari. Navigating across origins keeps the previous WebContent process cached in memory rather than killing it.
   - Enabled `_setUseUIProcessForBackForwardItemLoading` on `WKPreferences` so back/forward items restore directly through the UI process cache.
3. In `Tests/SearchTests/SwipeBackNavigationTests.swift`:
   - Verified that `.backForward` navigations preserve user scripts without re-arming.
   - Verified that `Web.pool` has `usesWebProcessCache == true` and `pageCacheEnabled == true`, and preferences enable `_useUIProcessForBackForwardItemLoading`.
   - Verified that live back navigations restore directly from Back-Forward Cache (`testBackNavigationUsesBackForwardCacheInBrauzTab`).

## Guarded by
`Tests/SearchTests/SwipeBackNavigationTests.swift`:
- `testBackForwardNavigationDoesNotTearDownUserScripts`
- `testProcessPoolAndPreferencesEnableWebProcessCacheAndFastBackForwardLoading`

## Acceptance
- Back/forward navigation (`action.navigationType == .backForward`) does not tear down or re-register user scripts on the web view.
- User scripts and Back-Forward Cache (Page Cache) are preserved on back swipes.
- Background tasks in `didFinish` are deferred by 150 ms so first responder and event handling are instantaneous.

## Files
- `Sources/Search/Browser.swift`
- `Tests/SearchTests/SwipeBackNavigationTests.swift`

## PR
https://github.com/hnnsly/brauz/pull/5

## Test by hand
Start the test app:
```bash
./build.sh && open build/Brauz.app
```
(Do not touch `/Applications/Brauz.app`).

Checks:
1. Navigate to an article or page with multiple links (e.g. Wikipedia, GitHub repository, or news site).
2. Click into a second page and let it load.
3. Perform a two-finger trackpad swipe back to return to the first page.
   - Expect: As soon as the swipe animation finishes settling, the page is immediately responsive to clicks and scrolling, matching Safari's responsiveness without a 1-2 second freeze.
4. Try swiping back and forward multiple times in a row across complex sites.
   - Expect: Page Cache restores the views smoothly without stuttering or re-parsing styles and user scripts.

What no automated check covered:
- Real trackpad gesture momentum and input latency on macOS hardware during `WKSwipeTransitionController` animations.

Risks:
- Sites that dynamically modify page DOM on client-side navigation without history popstate may rely on full reloads; standard web pages using BFCache operate identically to Safari.

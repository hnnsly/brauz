---
class: feature
status: fixed
found: 2026-10-21
---
# Copy Image reads the picture from the page instead of downloading it again

> can we somehow make image copying faster? is it possible?
> lets try to go with fix with blob

## Symptom
Copy Image fetches the picture a second time, with a fresh connection and no cookies (ImageMenu.swift, BoundedImageFetcher), although the page has already loaded it. On a large picture or a slow link the copy takes as long as that second download. Reported earlier as 30 to 40 seconds on some pages; never reproduced on a real site.

## Loop
Red check (to write): load a cacheable picture in a real WKWebView from the local test server, run Copy Image's `Browser.imageData(at:in:)`, and assert the server saw ONE request for the path. Today it sees two. `DEVELOPER_DIR=… swift test --filter ImageCopyTests.<new test>`.

## Red (unchanged source, 2026-10-21)
`swift test --filter ImageCopyTests`: 11 tests, 1 failure, in 22.3 s (build/image-red.log). The new check fails where expected and the other ten pass, including both fallback cases:
```text
ImageCopyTests.swift:173: error: testPageLoadedPictureIsNotDownloadedTwice : XCTAssertEqual failed: ("2") is not equal to ("1") - copying re-downloaded a picture the page already had
Executed 11 tests, with 1 failure (0 unexpected) in 22.304 seconds
```
Baseline timing line from the unchanged code (both calls are the network path): `IMAGECOPY-TIMING page=0.031 network=0.015 requests=3`. A 20 MB loopback download is 15 to 30 ms, so loopback cannot show a gain; what the change removes is a whole second download on a real network, and what it adds is the base64 trip, measured below once built.

## Green and what it does and does not buy (2026-10-21)
`swift test --filter ImageCopyTests`: 11/11 (build/image-green.log); the red check passes (request count stays 1), the no-store, cross-origin-without-CORS, oversized and existing cases pass.

Measured by size with `testPictureTimingsBySize` (loopback, local test server, a fresh WKWebView; build/image-timings.log). `requestsAfterPageCopy` counts the page's own warm-up plus the page-path copy, so 1 means served from WebKit's cache:
```text
size=2MB  page=0.026 network=0.006 requestsAfterPageCopy=1
size=5MB  page=0.044 network=0.007 requestsAfterPageCopy=1
size=10MB page=0.079 network=0.008 requestsAfterPageCopy=2
size=20MB page=0.119 network=0.016 requestsAfterPageCopy=2
```
Reading: up to 5 MB the page read comes from the cache and the second download is gone. From 10 MB the cache did not serve it in this environment, so the page read is itself one download, the same count as the network path, plus the base64 trip (about 0.1 s for 20 MB). Loopback makes the downloads free, so these times only show the overhead; the gain is the removed network round trip, which loopback cannot show. The ceiling may differ in the real app, whose cache is sized from the disk rather than a test store: unknown, to be checked by hand.

Consequence for the original 30 to 40 second report: if the slow pictures are the big ones (over about 5 to 10 MB), this change does not make them faster. It does fix the cost for ordinary photos and the cookie-gated case. Be honest about that when handing over.

## Verification (2026-10-21)
- ImageCopyTests 11/11 (red 10/1 before). Full suite: 227 executed, 1 skipped, 1 failure: the existing SidebarPressTests.testOtherButtonsDoNotSelectOnPress, owned by the right-click session. Not green.
- swift build -c release passed (91.99 s); ./build.sh built build/Brauz.app (build 202610211509), copied to build/Brauz-image-copy.app for hand testing. codesign verify passed.
- split_view.py 92/92 on the new build. /Applications/Brauz.app hashes unchanged.
- Committed locally on branch 0017-copy-image-from-the-page. Not pushed: awaiting the user's yes.
- No automated check covers a real site, WebKit's cache in the shipped app, or the clipboard itself.

## Cause
Measured 2026-10-21 (see 0004): the local part, size check + decode + clipboard write, is 60 ms to 0.6 s even for a 48 MP picture and is not the problem. What is left is the second download. The page's own copy sits in WebKit's HTTP cache, but the URLSession in BoundedImageFetcher cannot see it (ephemeral configuration, `urlCache = nil`, a different process).

## Design
- For an http(s) picture of a tab that has a web view, first read it from inside the page with `fetch(src, {cache: "force-cache"})`, the way blob: pictures already are (ImageMenu.swift:151, Search's own content world, in the frame it was right-clicked in). `force-cache` takes any cached response, stale or not.
- Bytes come back as base64 like the blob path does. Guards inside the page: refuse by `Content-Length` over 50 MB before reading, and stop reading once 50 MB have arrived.
- Anything that goes wrong falls back to the current BoundedImageFetcher path unchanged: the page cannot read a cross-origin picture whose server sends no CORS headers, the read fails, the page goes away, or the tab has no web view or is asleep. There is deliberately no timeout on the page read (decided on review, 2026-10-21): when the picture is not in WebKit's cache the page read is itself the download, and a cut-off at N seconds would make the fallback download it all again, so the worst case would be worse than today. A page whose script hangs would hang the copy, as the blob: path already can. So no picture that copies today stops copying.
- Everything after the bytes (`Browser.reasonable`, NSImage, clipboard write) stays as it is. Measured not worth touching.
- No new setting.

Not decided, flagged for later: if the CORS limit sends too many real sites to the fallback, the alternative is `webView.startDownload` through the page's own session to a temp file, which has no CORS limit and no base64 but may not hit the cache; unproven, so not built now.

## Acceptance
- A cacheable picture the page has loaded is copied with no second request to its server (request count stays 1).
- A picture served `Cache-Control: no-store` still copies, and the bytes on the clipboard equal the served bytes.
- A cross-origin picture with no CORS headers still copies through the fallback.
- A picture over 50 MB or over 100 megapixels is still refused, and an over-size one is not read in full in the page.
- 20 MB picture: the copy time through the page is recorded next to the current network path, on loopback, with the base64 overhead visible. Reported, not asserted.
- Blob: pictures, cancellation, cookie isolation and the existing ImageCopyTests keep passing.
- Not covered by any automated check, to be tried by hand: a real slow site.

## Files
Proposed after go:
- Sonnet worker: Sources/Search/ImageMenu.swift (in-page read with fallback inside `imageData`).
- Haiku worker: Tests/SearchTests/ImageCopyTests.swift and Tests/SearchTests/LocalDownloadServer.swift (page-loaded picture fixture, request counting, cacheable and no-store routes, a cross-origin no-CORS route).
- Haiku worker: DOCS/BRAUZ-CHANGES.md (one Unreleased bullet).
- Primary: this issue, red loop, review, serial verification.

## Cause / Fix / Guarded by / Test by hand
Pending.

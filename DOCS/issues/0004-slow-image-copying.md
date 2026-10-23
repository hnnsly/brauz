---
status: fixed
found: 2026-10-08
github: https://github.com/hnnsly/Search/issues/1
---
# Copy Image takes 30 to 40 seconds on some pages

## Symptom
Right-click, Copy Image on some pages takes 30 to 40 seconds to put the picture on the clipboard. On other pages it is instant. The pages that are slow have not been listed yet.

## Loop
`swift test --filter ImageCopyTests` (Tests/SearchTests/ImageCopyTests.swift).
Red on the unfixed code: a 20 MB picture read from a local file takes 70.7 seconds, and `Browser.imageData` returns nil.
Green with the fix: the copy passes in about 2 seconds, including writing the file.

## Cause
`Browser.imageData(at:in:)` read http(s) pictures with `for try await byte in bytes` and appended one byte at a time. The time grows with the picture's size, which fits "some pages slow, some instant" if the slow pages carry large pictures. The loop was measured only with a local 20 MB file, not on a real page.

Not established:
- Why the unfixed 20 MB read returns nil after 70 seconds. The 30-second `timeoutIntervalForRequest` on `Browser.fetcher` is a candidate, not checked.
- Whether `blob:` pictures are slow too. They take a different path, base64 through page JavaScript, which the test does not touch.

## Fix
`imageData` reads http(s) pictures with `Browser.fetcher.data(from:)` and still refuses pictures over 50 MB.
Tradeoff: `data(from:)` downloads the whole response before the size check. An oversized picture is now fully downloaded before it is refused. The old loop stopped at the limit. If that matters, the read needs a delegate that stops early.
Files: Sources/Search/ImageMenu.swift, Tests/SearchTests/ImageCopyTests.swift.

## Superseded by the v1.0.5.b1 rewrite
The `data(from:)` version above was replaced during the upstream 1.0.5 integration (commit 964b790, shipped in release v1.0.5.b1). `BoundedImageFetcher` in ImageMenu.swift streams chunks through a URLSession delegate on an ephemeral configuration, refuses an `expectedContentLength` over 50 MB up front, and cancels the task once the accumulated bytes pass 50 MB. That removes the tradeoff noted above: an oversized picture is no longer downloaded in full before it is refused. Measured against upstream b2048a0 with a local HTTP server: 20 MB copy red at 62.6 s (returned nil), green at 2.2 s. ImageCopyTests also covers the oversized-header, 50 MB cutoff, cookie isolation and cancellation cases.

## Measured after the rewrite: is the local part worth speeding up? (2026-10-21)
Throwaway benchmark outside the repo, private pasteboard, Apple Silicon, release-optimised. Time from "bytes arrived" to "on the clipboard", current path (`Browser.reasonable` + `NSImage(data:)` + `writeObjects([image])`):

| picture | JPEG | PNG |
|---|---|---|
| 12 MP | 61 ms | 156 ms |
| 24 MP | 108 ms | 300 ms |
| 48 MP (63 MB PNG, 144 MB TIFF on the board) | 253 ms | 612 ms |

The size check and `NSImage(data:)` cost under 10 ms. Writing the original bytes instead takes 1 to 14 ms, but the receiving app then pays the same decode on paste (reading back: 75 to 596 ms), so it moves the cost rather than removing it, and some apps read only TIFF or PNG. Conclusion: the clipboard path is not the 30 to 40 second problem and is not worth the compatibility risk. Whatever remains slow on a real page is the download. Not measured: a real slow site, in-page `fetch()` as a replacement for the second download (cross-origin images without CORS headers cannot be read that way), `blob:` pictures. To tell the cases apart on a real page: `curl -o /dev/null -w '%{time_total}\n' <image URL>` against the time Copy Image takes.

## Verified (original fix)
Full `swift test` on Apple Silicon with Xcode 26.6: 58 tests, 0 failures. `testALargePictureArrivesQuickly` passes in 2.2 s.

## Guarded by
Tests/SearchTests/ImageCopyTests.swift, `testALargePictureArrivesQuickly`. It uses a local `file://` picture, so it does not cover the network path or `blob:` pictures.

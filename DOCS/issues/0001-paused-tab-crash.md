---
status: fixed
found: 2026-10-07
---
# Brauz quits on its own while tabs sit in the background

## Symptom
Crash report 2026-10-07 16:50, build 202610071423: `NSInternalInconsistencyException` "The WKWebView is suspended", raised from `-[WKWebView stopLoading]`, on the main queue under `_dispatch_source_invoke` (the memory-pressure source in `Sleep.swift`).

## Loop
`swift test --filter PausedTabDiscardTests`. Red: each test fails with "The WKWebView is suspended (NSInternalInconsistencyException)" at the `Tab.swift` line that called WebKit.

## Cause
Tab pausing (81a1b7e) suspends a tab's page with WebKit's `_suspendPage:`. WebKit throws on `stopLoading`, `load`, `reload`, back and forward while a page is suspended. A memory warning put an already-paused tab to sleep, and `discard()` called `stopLoading()` on it. Closing a paused tab took the same path; an extension reloading or navigating a background tab hit `reload`/`go`.

Two more defects behind it:
- `isSuspended` read WebKit's `_isSuspended`, which reports whether the content process is suspended, not the page. Every existing guard (`unsaved`, `snapshot`, `evaluateInSearch`) was a no-op.
- `pause()`/`resume()` declared WebKit's completion block as non-escaping and without its `Bool`. Debug builds trapped on it; release builds got away with it.

A paused tab whose content process dies stays suspended (WebKit's `resume` returns early without a process), so reloading it later would throw too.

## Fix
- `PageView.suspended`, set by `pause()`/`resume()`; `isSuspended` reads it (`TabPause.swift`).
- `discard()` skips `stopLoading()` on a suspended page; `stop()` does nothing on a paused tab; `go(to:)`, `reload`, `back`, `forward` resume first (`Tab.swift`).
- A paused tab whose process dies is put to sleep instead of marked stale (`Dialogs.swift`).
- Block types corrected in `TabPause.swift`.

## Guarded by
`Tests/SearchTests/PausedTabDiscardTests.swift`: sleeping, closing and reloading a paused tab. The process-death branch has no test: the test target can't kill a page's content process.

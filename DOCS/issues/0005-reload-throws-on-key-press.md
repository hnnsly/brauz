---
status: fixed
found: 2026-10-08
---
# Brauz aborts on a key press when WKWebView reload throws

## Symptom
Brauz 1.0.4 (build 202610071423, installed in /Applications) quit with SIGABRT at 18:19 on 2026-10-08. Incident 3016668D-FDE2-4D9C-8786-0D74873F11A4. The app's code called `-[WKWebView reload]`, WebKit raised an Objective-C exception, nothing caught it, and the process aborted. The crash came in through a key event. Which key, and whether the tab was paused, are not known.

## Loop
Not run on the pre-fix code. A debug build of 1f1d8bd traps in `Tab.pause()` (TabPause.swift:59, a non-escaping block passed to Objective-C) before reaching reload, so the reload path could not be reached that way. Investigation was stopped at that point.

## Cause
Likely: reload on a paused tab. Commit b2dfebe ("a paused tab sleeps, closes and reloads without crashing") says WebKit throws "The WKWebView is suspended" on reload of a suspended page, and makes `reload()` resume a paused tab first. The installed build (202610071423) appears to predate b2dfebe, from its build time against commit 517fce2. Not confirmed from the binary.

## Fix
Already on main in b2dfebe: `Tab.reload()` resumes a paused tab first. Nothing new was written for this issue.

## Guarded by
`PausedTabDiscardTests.testReloadingPausedTabResumesIt` on main, from b2dfebe.

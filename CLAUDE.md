# Brauz

This checkout is Brauz, the fork `hnnsly/Search` of `driceroland/Search`. Read `DOCS/FORK.md` before syncing with upstream, adding a fork-only file, or touching scrolling, tab pausing, shortcuts, updates or the app's identity: it holds the rules those changes depend on.

## Building and testing

- Xcode lives on an external volume. Every `swift` and `./build.sh` command runs with `DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer`; the command-line tools alone lack SwiftUI's macro plugin and fail on `@State`. When `/Volumes/pet30-a` is missing, ask the user to mount it.
- `swift test` runs the XCTest suite in `Tests/SearchTests`. `swift build -c release` checks the release build.
- `./build.sh` writes `build/Brauz.app` and nothing else. The user's own Brauz is `/Applications/Brauz.app`; leave it alone.
- `python3 Tests/<name>.py` drives a hidden Brauz from `build/Brauz.app`, in a profile of its own, through the bench socket (`Sources/Search/Bench.swift`). Build first. This is the loop for anything XCTest can't host: extension pages, workers and messaging never load in the test process.
- An Objective-C exception inside an async XCTest kills the process with no message. Tests that may meet one (WebKit's "The WKWebView is suspended", for one) are synchronous, waiting with `RunLoop.current.run(until:)`; XCTest then reports the exception and the line.

## Crash reports

Match the report's UUID with `dwarfdump --uuid` on `/Applications/Brauz.app` and on `build/`. The dSYM of the build that crashed is usually gone; `atos` against the nearest build's dSYM gives approximate frames, and the stack's system frames and register values (`x1` holds the selector in `objc_msgSend`) narrow it down. Read WebKit's own source (`github.com/WebKit/WebKit`) when a frame is WebKit's.

## Issues

The work list is `issues/`, one Markdown file per issue, gitignored: it stays on this Mac. Copy one to GitHub issues on `hnnsly/Search` only when the user asks.

Name a file `NNNN-short-slug.md`, numbered one past the highest. Its shape:

```markdown
---
status: open        # open | fixing | fixed
found: 2026-10-08
---
# One line: what the user sees

## Symptom
What happens, in the user's words, with the crash report or steps.

## Loop
The one command that goes red on this bug, and what red looks like.

## Cause
What is actually wrong, and the evidence that showed it.

## Fix
What changed and why this way. Files touched.

## Guarded by
The test that fails if it comes back.
```

Write findings into the file as they come, not at the end: hypotheses ruled out, measurements, decisions the user made. A fixed issue keeps its file with `status: fixed`; `grep -l "status: open" issues/*` is the open work.

## How we work

The user plans with you; you run the work. For each issue:

1. Write the issue file with what the user reported, then get a red loop before theorising about the cause.
2. Show the user the ranked hypotheses and the plan; start the fix once they agree.
3. Hand the bounded parts to subagents: builds, test runs, audits of call sites, mechanical edits. The issue file is the brief's context: point the subagent at it, then name the exact files, the change, the done-check and the report format. Diagnosis, decisions and the final review stay with you.
4. Check every subagent report against the diff or the test output before telling the user it's done.
5. Update the issue file, then commit.

## Commits

One topical commit per fix, with its tests. The subject names the area and what changed, as a sentence: `Tabs: a paused tab sleeps and closes without crashing`. The body says what was wrong. A new fork-only file is added to the list in `DOCS/FORK.md` in the same commit.

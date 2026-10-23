---
status: fixed
found: 2026-10-20
---
# Choose a Little Window's browsing and destination space

## Symptom
During upstream-versus-fork review, the user requested "address and back, and also it should have space selector in which open tab". Asked whether the selector chooses only the destination, only the current browsing context, or both. The user selected both behaviors.

## Loop
Feature acceptance loop to add after the integration baseline is ready. No implementation or test has run yet.

## Cause
Neither the reviewed upstream Little Window header nor the existing LittleExtras address field provides this selector. This is a new feature, not a fork patch to replay.

## Decisions
- Changing the selector changes the Little Window's current browsing space and its cookie/account context immediately.
- Open in Brauz keeps the tab in the selected space, not whichever main-browser space happens to be active.
- The user also selected an editable address/search field, visible Back button, remembered placement and targeted extension support in issue 0008. Integrate with those choices and upstream's configurable shortcuts and popup protections.
- Treat a store/context switch as a real navigation/lifecycle operation, not merely a changed label. Do not promise preservation of arbitrary live editor state across a rebuilt WKWebView. Protect unsent work using the project's existing user-confirmation patterns.

## Implementation and review, 2026-10-20
Implementation is on integrate/upstream-reviewed. The primary assistant inspected upstream Browser.move(toSpace:), Browser.receive, Tab.rehome, Spaces.store and Ask confirmation routing before issuing bounded code tasks. Ask.sure targets Links.window, so the Little Window's store-switch confirmation uses a sheet attached to its own window.

Implemented candidate: LittleAddress observable state, header menu, real store rehome/wake, selected-space keep, weak controller references in hosted views and request-generation guards. Integrated source compiles. Real WebKit tests are now present; their runtime results are pending.

Primary review found cases to reproduce and correct:
- LittleAddress.updateSpaces silently changes the selected ID when its space disappears, without changing the live store. The label must not imply a context change that did not happen.
- keep(in:) silently falls back to the destination browser's space when selection is unavailable. It must leave the Little Window open instead of transferring into another account context.
- Recheck deferred extension-readiness behavior during space switching/keeping, shared-store switches and changed/deleted space lists.

## Fix
In progress. These findings are not accepted merely because a worker reported completion. Runtime regressions and final review precede fixed status.

## Guarded by
Pending tests for two distinct cookie/account stores, selected-space transfer, repeated switching and extension tab/window updates.

## Acceptance
- A Little Window can select among available Brauz spaces.
- Selecting a different space changes the page's actual account/cookie context.
- Open in Brauz sends the tab to that selected space even if a browser window currently shows another space.
- Address entry, Back navigation, ordinary same-window links and permitted JavaScript popups keep their agreed behavior.
- Closing or keeping a Little Window during a pending space switch does not resurrect a closed page or load it into the wrong store.
- The selector does not silently discard detected unsent work during an immediate context switch.

## Files
Expected areas: Sources/Search/Little.swift, LittleExtras.swift, Browser.swift, Spaces.swift, Tab.swift and isolated-profile tests. Exact ownership and files follow source inspection; these are not instructions to modify all of them.

## Test by hand
Pending a verified build. /Applications/Brauz.app remains untouched.

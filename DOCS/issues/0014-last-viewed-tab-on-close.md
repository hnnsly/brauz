---
class: feature
status: fixing
found: 2026-10-21
---
# Closing the current tab returns to the last-viewed open tab

> hey, i want brauz to show me not last in list, but previous tab, when i close current one. use ultracode with sonnet and haiku agents, use /blast-radius and /writing-for-agents

## Symptom
The user wants closing the current tab to return to the tab they last viewed, rather than choosing by sidebar order.

## Loop
```bash
DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --package-path /Users/daniil/Dev/Search --filter TabCloseTests
```

Run twice against unchanged production code on 2026-10-21, with the same verdict: six pass, one expected failure. The second run used --skip-build. First execution took 0.832 seconds after a 3.02-second build; second execution took 0.250 seconds.

Red output excerpts:
```text
Test Case '-[SearchTests.TabCloseTests testClosingCurrentReturnsToLastViewedNotNeighbour]' failed (0.088 seconds).
Executed 7 tests, with 1 failure (0 unexpected) in 0.250 (0.251) seconds
```
Assertion message: `Expected A last viewed, B sidebar neighbour`.
Logs: build/tab-close-blast-radius.log and build/tab-close-blast-radius-repeat.log.

## Cause
At baseline, the ordinary multi-tab branch of Browser.close selected a split partner or positional neighbor without consulting viewing history. The existing switcher correctly ordered C, A, B after viewing B, A, C, but closing C chose B. The feature reuses that existing departure history rather than introducing another tracker.

## Decisions
- The user chose "Last viewed (Recommended)": return to the tab used before the current one, regardless of sidebar position.
- The user invoked /blast-radius directly on 2026-10-21. Assess the planned change before implementation and distinguish executable proof from source-only reasoning.
- /writing-for-agents and coding-guidelines are loaded. Primary assistant owns diagnosis, design and final review; Sonnet and Haiku receive bounded implementation and lookup tasks.
- Grill answer, 2026-10-21: "Current space (Recommended)". Closing a tab must not switch spaces or windows to reach a history entry.
- Grill answer, 2026-10-21: "Keep other pane (Recommended)". The surviving split pane retains priority over recency.
- Preserve existing neighbor fallback when no eligible viewing-history entry survives. Preserve pinned-tab put-down, last-tab and newTabAfterLast behavior. Moves to another space/window keep their existing independent behavior; this feature changes closing only.
- Design frontier is empty. The user approved implementation with "go" on 2026-10-21, after both grill answers were recorded.
- Implementation branch: 0014-last-viewed-tab-on-close. Source, test and documentation workers were dispatched with disjoint ownership; no tests run while those files are being edited.

## Investigation
- Initial checkout: main, clean, no implementation diff.
- Existing related test suites: TabSelectionTests and TabSwitcherTests.
- Browser.close at Sources/Search/Browser.swift:2976 has separate pinned-tab, last-tab and last-ordinary-tab-with-pins branches. The ordinary multi-tab branch removes the closed tab, then selects its split partner or the right neighbor, falling back to the last tab (3052–3057).
- Browser.select at Browser.swift:2899 performs wake/revive, focus, draft and panel work. Replacing its call with a bare activeID assignment would reintroduce the blank sleeping-tab regression described by commit 1d3e1aa. Commit 18ac5ab added split-partner priority.
- Browser.activeID's observer records departures through TabSwitcher.left (Browser.swift:61–102). This observer has no switcher-enabled guard. TabSwitcher.ordered filters its recency list against the supplied current row, deduplicates IDs, appends unvisited tabs and limits display to ten (TabSwitcher.swift:123–169). Its row-order fallback must not silently define the no-history close policy.
- Split focus changes within the same pair are intentionally not recorded as separate switcher entries; leaving a pair records its left representative. Closing a focused split pane currently keeps its partner. A literal per-pane viewing history is not equivalent to the existing switcher history.
- Space switching parks one row and shows another (Spaces.swift:190–220). Recency can retain parked IDs, so a close candidate must be filtered against this browser's current tabs, not all live tabs.
- Move-to-space and move-to-window have independent neighbor-selection paths (Browser.swift:3319–3326 and 3407–3414). They are outside the requested close-only behavior unless the user expands scope.
- DOCS/FORK.md contains stale gesture and pause wording compared with the user's recorded upstream-integration decisions. That unrelated documentation is not evidence for the new selection policy and is outside this change.

## Fix
Implemented and verified, with the existing unrelated full-suite failure disclosed below:
- TabSwitcher.mostRecent(in:) returns the first recorded departure whose ID belongs to the supplied current row. It does not use the ten-card display cap or append unvisited tabs as history.
- The ordinary active-tab branch of Browser.close resolves that ID after removing the closing tab, then uses partner > recent > existing neighbor through Browser.select.
- Pinned put-down, last-tab, newTabAfterLast and move selection paths are unchanged.
- DOCS/FORK.md registers the new test and close-policy rule; DOCS/BRAUZ-CHANGES.md has one Unreleased note.
- Primary diff review found that the initial Haiku test worker made no changes and returned only a path. Its premature test run is not verification of this patch. A completed workflow worker could not be resumed, so a fresh Sonnet worker completed the tests.
- Primary reviewed the full source, docs and test diff. The suite now contains 19 synchronous tests, adding repeated closes, actual space transitions, moved-to-window filtering, sleeping-MRU wake, no-history fallback, pins/last-tab settings and a history entry older than the ten-card display cap.
- First focused run: 19/19 passed, 0.617 seconds after a 30.21-second debug build. Primary then strengthened the reorder test so the MRU destination A differs from neighbor B after moving current C into the middle; it also asserts the new row order. The strengthened focused run and full XCTest suite are in progress.
- Built-app verification script: build/tab_close_probe.py reuses the existing split-view harness in its own disposable tab-close-0014 profile. It will check MRU, successive closes, background closes, removed history, a space round trip and split-partner focus after packaging. Syntax check passed; execution awaits the rebuilt app.

## Verification
- Focused run after implementation: 19/19 passed. Strengthened reorder fixture then passed 19/19 again in 0.500 seconds.
- First full run: 241 tests executed, one skipped, nine assertion failures across three tests. One is the known upstream SidebarPressTests.testOtherButtonsDoNotSelectOnPress failure, selected count 2 instead of 0. The other eight assertions are in the two TabSelectionTests and include the new fixture URL about:blank#A as an unexpected fifth tab.
- Tight isolation red loop: run swift test --filter 'TabCloseTests|TabSelectionTests'. Reproduced 21 tests with eight assertion failures in 0.581 seconds. No production change is needed for this failure.
- Cause confirmed by source: Browser.writeSession (Browser.swift:2087–2100) calls Pins.set, which updates shared in-memory/disk pin definitions. TabCloseTests' pinned fixtures persisted A. browser.closeAll() closes views but does not restore Pins. The test suite now snapshots/restores Pins.bySpace and Pins.shared through Pins.set/setShared in setup/teardown.
- Isolation fix is green: ordered TabCloseTests + TabSelectionTests run passes 21/21 in 0.556 seconds. Primary reviewed the actual setup/teardown changes.
- Final full run: 241 tests executed, 239 passed, one existing skip and one existing failure, in 78.656 seconds. The sole failure is SidebarPressTests.testOtherButtonsDoNotSelectOnPress, selected 2 versus expected 0. Its body at SidebarPressTests.swift:196–207 instantiates ControlsFixture, not Browser, and never calls close. The new close tests and both selection tests pass together in the full suite. The suite as a whole is NOT green; this existing failure is kept separate under the approved scope policy.
- Skipped test: ExtensionFileAccessTests.testFilesAreNeverGrantedButSitesAre, because WebKit itself refuses the file grant pattern. This is an explicit existing XCTest skip, not a passing check.
- Release build: swift build -c release succeeded in 94.68 seconds with the required external Xcode. Existing compiler warnings remain outside scope.
- Packaging: build.sh succeeded in 82.35 seconds and produced build/Brauz.app, version 1.0.5, arm64, build 202610210937, signed as Brauz Signing. codesign --verify --deep --strict passed.
- Built-app close probe: build/tab_close_probe.py passed all six checks in a disposable tab-close-0014 profile: last-viewed over neighbor, successive closes, background-close stability, removed-history skipping, actual space round trip and surviving split-partner focus. The new selection path is now proven through a running built app, level 5. It uses the app's bench bridge, not actual keyboard/pointer event delivery.
- Installed app: SHA-256 of the executable, Info.plist, Assets.car and CodeResources all match the pre-build baseline under /Applications/Brauz.app. No installation or profile migration occurred.
- Full built-app split-view suite: python3 -I Tests/split_view.py passed 92/92. It runs in its own disposable split-tests profile. Logs: build/tab-close-split-view.log.
- Installed-app hashes were checked again after all app probes and still match the four-file pre-build baseline.
- Logs: build/tab-close-focused.log, build/tab-close-focused-final.log, build/tab-close-full-suite.log, build/tab-close-isolation-red.log, build/tab-close-isolation-green.log, build/tab-close-full-suite-final.log, build/tab-close-release-build.log, build/tab-close-package.log and build/tab-close-app-probe.log. All planned verification is complete, subject to the explicitly recorded existing sidebar failure and file-pattern skip.

## Guarded by
Tests/SearchTests/TabCloseTests.swift now contains 19 synchronous tests at the Browser selection/close seam. The original seven-probe baseline produced six passes and the same expected last-viewed-on-close failure twice. After implementation all 19 pass, including the original red feature test. After pin-store teardown restoration, the ordered TabCloseTests + TabSelectionTests loop passes 21/21 in 0.556 seconds.

Original passing baseline proofs:
- testSwitcherAlreadyOrdersLastViewedBeforeNeighbour
- testClosingBackgroundLeavesCurrentSelected
- testRecencyCandidatesExcludeRemovedTabs
- testRecencyCandidatesExcludeTabsOutsideCurrentRow
- testClosingFocusedSplitKeepsOtherPane
- testClosingCurrentWakesSleepingReplacement

Original red feature test, now passing:
- testClosingCurrentReturnsToLastViewedNotNeighbour

## Preimplementation blast-radius assessment
- What changes: only the ordinary current-tab replacement policy should consult recency before using positional fallback. No production diff exists yet.
- Central safety fact: the replacement must resolve to an eligible surviving tab in this browser's current row and still be selected through Browser.select. Existing row filtering and existing wake behavior are proven by executable tests, level 4. Their integration into the new close policy remains unproven until implementation.
- Split risk: switcher history collapses pairs to one representative. Replacing partner priority with a generic recency lookup can send focus away from the surviving visible pane. Existing partner behavior is proven by test; the desired new policy needs the user's answer.
- Wake risk: assigning activeID directly skips Browser.select's wake/revive path. The restored-neighbor test proves the existing close path wakes its destination; preserve that call.
- Scope risk: recency retains IDs from other spaces, while moves and detached windows have their own selection paths. Current-row filtering is proven, but actual switchSpace, move-to-window, reopen and repeated-close integration with the new policy remain unproven.
- Pinned-tab put-down and newTabAfterLast branches have separate existing semantics. Recommend retaining them unchanged. Preservation by the eventual patch is not tested yet.
- The row-filter test uses parked rows directly, not a full switchSpace operation. No running-app probe, full XCTest suite or release build was run for this preimplementation audit.
- Before merge: make the red feature test pass; preserve the six baseline checks; extend coverage to repeated closes, actual space transitions, moved/closed history entries, no-history fallback and pinned/last-tab settings. Run the full suite, release build and built-app split-view checks per /ship.
- Repository check after probes: no diff under Sources/Search. The only tracked working-tree addition is the new test file; the issue is local and gitignored. No commit or publication.

## Acceptance
- With open tabs A, B and C, view B, then A, then C. Close C. Brauz displays A, even though B is adjacent to C in the sidebar.
- After that close, close A. Brauz displays B rather than a closed tab or an unrelated tab.
- Closing a background tab leaves the current tab selected.
- Removing a tab that was in viewing history prevents later closes from selecting that removed tab.
- Closing the focused pane of a split keeps its surviving partner selected, even if another tab was viewed more recently.
- After switching spaces, closing the current tab selects only a surviving tab in the current space, never a parked tab or another window's tab.
- A previously viewed tab moved out of the current space/window is not a close destination.
- With no surviving eligible viewing history, keep the existing right-neighbor, then last-tab fallback.
- A sleeping replacement wakes through Browser.select, rather than remaining blank.
- Preserve pinned-tab put-down, last-tab and newTabAfterLast behavior.

## Implementation plan approved 2026-10-21
1. Start a topical branch for issue 0014, preserving the test-only working-tree addition.
2. Reuse TabSwitcher’s existing departure history through a narrow eligible-row lookup. Ordinary current-tab close chooses split partner first, then most recently viewed surviving tab in the current row, then the existing positional fallback. Keep Browser.select as the activation path. Add no setting, persisted history or new global tracker.
3. Extend the seven probes to cover successive closes, actual space transitions, moved-history entries, no-history fallback and pinned/last-tab semantics. Keep all tests synchronous and isolated from installed Brauz.
4. Register the new fork-only test in DOCS/FORK.md, add the durable close-policy rule there, and add one Unreleased note to DOCS/BRAUZ-CHANGES.md. Leave unrelated stale fork documentation alone.
5. Primary reviews the complete diff, runs the focused suite, full XCTest suite, release build and relevant isolated-profile app checks using the required external Xcode. Report any existing unrelated suite failure without treating it as success or silently expanding scope.
6. Update this issue and follow /ship's topical commit, publication-approval and PR handoff steps. Do not replace /Applications/Brauz.app.

## Files
Disjoint implementation ownership:
- Sonnet source worker: Sources/Search/Browser.swift and Sources/Search/TabSwitcher.swift. Only the eligible-row recency lookup and ordinary close hook.
- Sonnet test-completion worker, replacing the initial Haiku test worker: Tests/SearchTests/TabCloseTests.swift. Extend the defined acceptance cases; no production edits.
- Haiku docs worker: DOCS/FORK.md and DOCS/BRAUZ-CHANGES.md. New close-policy rule, test inventory entry and one Unreleased note only.
- Primary assistant: this local issue, diagnosis, design, complete diff review, verification and final judgment.
Run verification serially after source/test workers finish to avoid compiling partially edited files.

## Publication
- Local commit: 9e4c39c611eb1cdc05bad0879bea5f598f83a618, Tabs: closing the current tab returns to the last viewed tab.
- Branch: 0014-last-viewed-tab-on-close. Working tree is clean; this issue and build logs remain local and gitignored.
- Final commit contains exactly five files: Browser.swift, TabSwitcher.swift, TabCloseTests.swift, DOCS/FORK.md and DOCS/BRAUZ-CHANGES.md. No upstream CHANGELOG.md change.
- The user approved publication with "yes, push" on 2026-10-21. Pushed 0014-last-viewed-tab-on-close to origin and opened https://github.com/hnnsly/brauz/pull/7 against main.
- Desktop PR monitor is bound to that PR. Initial status: open, no CI checks reported, Auto-fix off and Auto-merge off. No auto-merge authorization was given.
- No release tag, release publication or installed-app replacement.
- Status stays fixing until manual acceptance. The full-suite baseline exception and manual-only checks are disclosed above and below.

## Test by hand
Build from this checkout with the required Xcode:
```bash
DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer /Users/daniil/Dev/Search/build.sh
```
Start a separate instance with a named test profile, not the installed app or its profile:
```bash
open -n --env SEARCH_PROBE=tab-close-manual /Users/daniil/Dev/Search/build/Brauz.app
```

Use throwaway pages in this profile:
1. Arrange tabs A, B, C. View B, A, C. Close C with Cmd+W. Expect A, not B.
2. Close A next. Expect B. Closed tabs never reappear as close destinations.
3. View B, A, C, then close background A with its sidebar cross. Expect C to stay selected. Close C. Expect B.
4. View B, A, C. Drag C between A and B, then close C. Expect A despite B being its right neighbor.
5. Make a split of A and B. View outside tab C, then focus B and close it. Expect the surviving A pane to stay in front.
6. View B, A, C in one space. Visit another space and return, then close C. Expect A in the original space, without a space or window jump.
7. View B, A, C. Move A to another window, then close C in the original window. Expect B; A remains open only in its destination window.
8. Return to a previously viewed tab after it has slept by closing the current tab. Expect the selected destination to wake and load, not remain blank.
9. After restarting the test instance, close a restored tab before recording new viewing history. Expect the existing neighbor fallback. Closing a sole nonblank tab still leaves one blank. With Leave a new tab when the last tab closes enabled and only pins remaining, expect a blank instead of entering a pin. Closing a pin still puts it down rather than removing it.

Not covered by automation: actual Cmd+W event delivery and the sidebar cross under a real pointer, tab-drag interaction itself, and visual wake smoothness on third-party sites. Model-level selection, move and wake assertions have dedicated XCTest cases; built-app checks are recorded separately after execution.

Risks and choices: history is per window and filtered to the current space; split partners have priority; viewing history itself is not newly persisted across restarts; no-history behavior keeps the existing positional fallback. /Applications/Brauz.app stays untouched.

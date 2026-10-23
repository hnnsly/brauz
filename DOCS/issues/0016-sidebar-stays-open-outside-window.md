---
class: feature
status: fixing
found: 2026-10-21
---
# Keep an open sidebar visible while the pointer is outside Brauz

> keep sidebar open if it was open and cursor left brauz window

## Symptom
The user wants an open sidebar to remain open when the pointer leaves the Brauz window, rather than hiding as a side effect of window exit.

## Loop
Feature acceptance is defined below. The current hide trigger has been inspected; no existing test reaches this pointer/timer combination.

Planned focused command:
```bash
DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter FoldPeekTests
```

The user approved implementation after the design checkpoint. Tests will use the actual pending-hide helper extracted from Fold.swift, not an independent copy of its decision logic or direct peeking assignments.

## Cause
Source inspection, not yet an executable reproduction:
- Sources/Search/Fold.swift:266–318 follows the global pointer position. For an open hover reveal it computes whether the pointer is over the sidebar, another app-owned panel, a held popup, or the existing 48-point side-edge overshoot band. Other outside-window positions produce peek(false).
- Fold.swift:343–360 schedules a hide after 0.065 seconds. Its callback checks editing and held menus but does not recheck whether the pointer is outside the window. Merely skipping new outside-window hide requests would leave an already scheduled hide able to fire after window exit.
- Fold.swift:211–217 also requests hiding when inline address editing or bookmarks end while the pointer is elsewhere. These paths need the same window-exit policy rather than a follow()-only fix.
- App.swift:778–789 cancels the tab switcher and manages inactive window buttons/video; it does not hide the sidebar directly. No new app-activation observer or pointer monitor is justified by these paths.
- Fold.swift:510–524 already monitors local and global mouse movement while folded. Reuse it rather than adding another global watcher.
- Fold handles both the vertical sidebar and horizontal top strip. The user requested sidebar behavior, so preserve top-strip behavior unless explicitly expanded.
- Bench.swift:2821–2829 can set hides/folded/peek, but setting peek directly bypasses the pointer decision and hide timer. That alone would not prove this feature. A test must reach the real decision and pending-hide path.

## Decisions
- The user chose "Hover reveal too (Recommended)": preserve any open sidebar while the pointer is outside the Brauz window, including a temporary hover reveal.
- The selected option also states that normal auto-hide resumes when the pointer returns to the page.
- Grill answer, 2026-10-21: "Keep open there too (Recommended)". A pointer over an overlapping window from another app counts as outside Brauz even when inside Brauz's geometric rectangle. Resume auto-hide only over Brauz's actual page, not based on frame coordinates alone.
- Preserve existing edge/dwell/48-point overshoot reveal behavior for a closed sidebar. Source inspection showed that this existing mechanism can intentionally reveal a closed sidebar just beyond its edge; this feature must not remove or broaden it.
- Apply to both left and right vertical sidebars. Leave the horizontal top strip unchanged. Explicit fold shortcuts, buttons and settings still work normally.
- Both user-facing design choices are settled. The user approved implementation with "go" on 2026-10-21. No new setting, global pointer monitor or app-focus observer is planned.
- Implementation branch: 0016-sidebar-stays-open-outside-window, created from main at 170ed30. The published tab-close feature stays in its own branch/PR.
- The non-left sidebar press bug is being fixed independently in another session, issue 0015-sidebar-other-buttons.md in its worktree. This intake was renumbered from 0015 to 0016 after coordination to avoid duplicate issue numbers.
- The independent session owns only Sources/Search/TabBar.swift's TabPress and Tests/SearchTests/SidebarPressTests.swift's non-left-button test. This feature must leave those files alone and use separate source/test ownership.
- The completed tab-close feature is published in https://github.com/hnnsly/brauz/pull/7. Do not add this feature to that branch/PR. Choose a separate base/branch at implementation time.

## Red (pre-change app)
Run 2026-10-21 against the existing build/Brauz.app (Fold.swift unchanged), in a disposable sidebar-exit-baseline profile, browser window ordered out so the pointer cannot be over it. Log: build/sidebar-window-exit-baseline.log.
```text
Baseline fixture: {'folded': True, 'peeking': True, 'visibleBrowserWindows': [False]}
After ending inline edit outside browser window: {'folded': True, 'peeking': False}
AssertionError: Open sidebar hid while the pointer could not be over its ordered-out browser window
```
The column hid on its own although the pointer was nowhere near Brauz. This is the editor-completion path (Fold.swift:211), one of the two hide paths. Pointer-move exit and the pending 65 ms callback are covered by FoldPeekTests only, since the bench cannot move the real pointer.

Permanent loop: `python3 -I Tests/sidebar_window_exit.py` (needs ./build.sh first). Run against the unfixed build.Brauz.app on 2026-10-21, it goes red on exactly the sidebar case and keeps the top-strip control green (log: build/sidebar-window-exit-red.log):
```text
  ok   sidebar fixture: folded and peeking
  FAIL sidebar revealed, pointer off the window: finishing an address edit keeps it open False
  ok   control fixture: folded and peeking
  ok   tabs across the top: the strip still goes back in when the edit ends
3 passed, 1 failed
```
It needs no Xcode, so it can only go green after ./build.sh rebuilds the app with the Fold.swift change.

## Fix
Implementation approved and dispatched with disjoint source/test/docs ownership. Fold.swift will use a small FoldHiding helper for its existing delayed hide; pointer eligibility will guard new requests and be re-evaluated by the callback. Verification has not run.

## Verification (after pet30-a was mounted again, 2026-10-21)
- swift test --filter FoldPeekTests: 10/10 passed.
- Full suite: 232 executed, 1 skipped, 1 failure: the existing SidebarPressTests.testOtherButtonsDoNotSelectOnPress (selected 2, expected 0), owned by the separate right-click session. Suite not green.
- swift build -c release succeeded (100.68 s); ./build.sh built build/Brauz.app, build 202610211406.
- Tests/sidebar_window_exit.py on the new build: 4/4 (red 3/1 before). Tests/split_view.py 92/92. Tests/edge_to_edge.py 29/29.
- /Applications/Brauz.app hashes unchanged.
- Not covered by any automated check: moving the real pointer out of the window or onto another app. That rests on the FoldPeekTests timer and policy cases plus the hand check below.
- Logs: build/sidebar-*.log.

## Environment block (resolved)
During source/test preparation on 2026-10-21, /Volumes/pet30-a unmounted. The required /Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer path is absent, independently confirmed in this checkout. The user has been asked to mount pet30-a. Source review may continue, but no Swift tests, build, app packaging, commit or publication will be claimed while verification is blocked. No fallback toolchain is authorized.

## Guarded by
Pending identification of the real hide-decision seam.

## Acceptance
- With sidebar auto-hide enabled, reveal the sidebar by hovering its edge, then move the pointer outside the Brauz window. The sidebar stays open.
- Leave the pointer outside the window longer than the normal hide delay. The open sidebar still stays open.
- Return the pointer directly to the page. The sidebar resumes its existing auto-hide behavior and delay.
- Return the pointer to the sidebar itself. The sidebar stays open.
- If the sidebar is manually open, moving the pointer outside the window does not close it.
- If the sidebar is closed, leaving the window away from the existing edge/overshoot reveal zone does not reveal it. Existing edge/dwell/overshoot opening still behaves as before.
- Moving from the revealed sidebar into the page without leaving the window still triggers the existing auto-hide behavior.
- If another app overlaps Brauz and the pointer moves onto that app, the sidebar stays open even inside Brauz's geometric frame. Returning to Brauz's actual page resumes auto-hide.
- Schedule a hide by moving into the page, then leave the window before the 65 ms grace expires. The queued hide must not close the sidebar outside Brauz.
- Finish inline address editing or dismiss bookmarks while the pointer is outside Brauz. The sidebar stays open until normal pointer-driven hiding is eligible again.
- Existing editing, drag, menu, manually unfolded sidebar and explicit fold-control behavior is preserved. Horizontal top-strip behavior is unchanged.

## Implementation plan approved 2026-10-21
1. Create 0016-sidebar-stays-open-outside-window from the appropriate main base, not on the tab-close PR branch. Keep the independent right-click fix separate; do not modify its TabPress or SidebarPressTests.swift.
2. In Fold.swift, preserve an already open vertical sidebar whenever the pointer is outside the real Brauz window or over another app. Reuse existing pointer observations. Cancel or suppress pending auto-hides and recheck eligibility when the delayed hide fires, including editing/bookmark completion paths. Keep opening, grace/dwell timing, popover protections, explicit fold commands and the top strip unchanged.
3. Add focused regression coverage at the real hide-decision/timer boundary with controlled pointer/window observations, so tests do not move the user's physical cursor. Cover outside-frame exits, overlapping apps, pending-hide races, return to page/sidebar, editor/bookmark completion and unchanged closed/top-strip behavior. Do not substitute direct browser.peeking assignments for exercising the actual hide path.
4. Add the durable policy and any new fork-only regression file to DOCS/FORK.md, with one Unreleased note in DOCS/BRAUZ-CHANGES.md. Avoid unrelated fork-doc cleanup.
5. Primary reviews the complete diff, runs the focused loop, full suite, release build and relevant isolated-profile app checks with the required external Xcode. Record any still-existing unrelated failure rather than silently calling the suite green. Keep /Applications/Brauz.app untouched.
6. Update this issue and follow /ship's topical commit, publication approval and manual-acceptance handoff.

## Files
Disjoint ownership:
- Sonnet source worker: Sources/Search/Fold.swift. Add internal @MainActor FoldHiding in the same file, with allowsHide(sidebar:inWindow:onWindow:), cancel(), and schedule(after:canHide:hide:). Fold uses this for its existing 65 ms hide and the actual pointer/window lookup is re-evaluated before a new request and at callback execution. Preserve editing/menu checks and existing opening/top-strip behavior. No new global monitor.
- Haiku test worker: Tests/SearchTests/FoldPeekTests.swift. Exercise FoldHiding's actual policy and timer through controlled observations, including an outside/covered transition after scheduling and before callback. Preserve reentry cancellation, editing/menu predicate protection, and non-sidebar behavior. No edits to SidebarPressTests.swift.
- Haiku docs worker: DOCS/FORK.md and DOCS/BRAUZ-CHANGES.md. Only the policy, regression-file registration and Unreleased note.
- Haiku app-regression worker: Tests/sidebar_window_exit.py. Convert the primary's reproduced hidden-window editor-completion scenario into a permanent app loop, with unchanged horizontal-strip behavior as a control. Use existing bench commands; no Bench.swift edits or physical cursor movement.
- Primary assistant: this local issue, design, real-loop construction, source/test review, cross-session coordination, serial verification and final judgment. Source/test workers have finished; review correction of unit-test names and queue-barrier assertions was applied serially by a replacement Haiku worker.
If an app-probe bridge is needed, the primary will name its exact observation seam and assign Bench.swift to the source worker before any edit. Do not add a broad test command that bypasses hide logic.

## Test by hand
Pending implementation. Build with the required external Xcode and use a named SEARCH_PROBE profile. Do not touch /Applications/Brauz.app or the user's real profile.

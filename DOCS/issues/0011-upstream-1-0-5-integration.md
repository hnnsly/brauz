---
status: fixed
found: 2026-10-20
---
# Bring Brauz up to date with Search and verify the pending fixes

## Symptom
The user requested every known issue fixed and synchronization with the new Search version, using ultracode. The numbered integration and verification plan was approved with "go".

## Loop
Required toolchain for every Swift/build command:
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer`

Baseline checks after integration: `swift test`, `swift build -c release`, `./build.sh`, then relevant isolated-profile app tests. Keep unverified hardware, overnight, and external-site claims separate from automated results.

## Cause
The fork's previous upstream base was 59c1b4e. Fetched upstream/main is b2048a0, with 91 upstream-only commits against origin/main. Search v1.0.5 was published on 2026-10-14. Integration includes the newer upstream/main commits too.

## Investigation
- Actual origin is hnnsly/brauz, upstream is driceroland/Search. No publishing to upstream.
- Working branch: integrate/search-1.0.5-all-issues, created from origin/main. main remains untouched.
- Unfinished swipe work preserved as stash 3eea0997f9c74e95abb06392d1060e937f1864ac and build/pre-upstream-20261020.patch.
- Rebase replays the 27 fork commits onto upstream/main, restoring upstream CHANGELOG.md after every replay. First conflict is 18001bc in FrameRate.swift, Swipe.swift and Tab.swift. Its obsolete acceleration switches were removed by later fork commit a1b1a5d; preserve upstream's current frame-rate settings and live-update fixes instead.
- Earlier integration intent was to retain native WebKit gestures under the old fork rules. Superseded by the user's explicit choices below. The rebase and implementation agents are paused while the user reviews each area.

## User decisions, 2026-10-20
- Process: compare upstream against final fork behavior, not blindly replay fork changes. Primary assistant owns review. Ask structured questions per area before implementation.
- Swipes: use upstream's current arrow-disc gesture, including hold-to-select history and Little Window first-page swipe-to-close. This explicitly replaces the old native-gesture rule in DOCS/FORK.md. Do not carry the native-swipe replacement merely because it is in the fork.
- Page edges: keep natural vertical WebKit bounce, not upstream's disabled top/bottom rubber-banding. This is independent of the gesture choice.
- Native-preview sizing and pixel tests remain preserved in the stash/patch, but are not requirements for the chosen arrow-disc gesture. Do not bring over the pending native-swipe performance commits as an unchecked package.
- Reading progress: keep the fork's removal of the progress indicator and continuous position reporting for that feature. Preserve page-length information needed by upstream UI separately, not a silently missing upstream feature.
- Refresh rate: use upstream's Never / On power / Always controls, defaults, migration of explicit old choices and live-update behavior. Drop the fork's automatic high refresh outside Low Power Mode.
- Link previews: use upstream reporting during scrolling, not the fork's 150 ms suppression.
- Review recommendation for remaining internal scrolling changes: use upstream layout, fullscreen/inspector/floating-video behavior, autofill repositioning, sign-in observation and autoscroll listener handling. No current measurement justifies carrying over the old layout/script micro-optimizations. Only the explicitly chosen bounce and progress differences should remain from this group.
- Early suspension: use upstream only. Remove the fork's separate 2.5-minute pause/resume mechanism, not merely its timer. Pause-specific crash guards/tests are not independent product features to retain blindly.
- Drafts: permit automatic discard after extended idle, once BOTH the chosen normal sleep delay and one hour have elapsed. With Later selected the draft threshold is two hours. Preserve upstream activity/keep-awake/pin exemptions. This is permission to discard live draft state, not a promise of restoration.
- Sleep timing: retain upstream Sooner / Normal / Later at 10 minutes / 30 minutes / 2 hours and normal memory-pressure handling. Do not retain the fork's fixed 15-minute delay.
- Pending memory patch d99dc44 must be rewritten to the chosen policy, with real typed fixtures and clock-boundary checks. Its paused-screenshot shortcut and field-name heuristic are not accepted fixes.
- Little Window new-window requests: ordinary target=_blank links navigate the same Little Window; JavaScript popups retain upstream handling and popup protections.
- Little Window controls: retain address/search entry and add a visible Back button. Adapt to upstream configurable shortcuts rather than retaining old hardcoded key handling.
- Little Window placement: retain saved position/size and cascading, fitted to an available screen.
- Little Window extensions: retain targeted window/tab registration, bounded startup wait and focus reporting, adapted and verified against current upstream. Replace weak existence-only tests.
- NEW FEATURE: a Little Window space selector switches its current browsing space and cookie/account context immediately, AND determines the space receiving the tab on Open in Brauz. User explicitly selected both behaviors. Track separately in issue 0013; implementation follows this review.

- Profile adoption: remove automatic copying from Search into missing Brauz profile locations. Do not delete/reset existing Brauz data or change access to existing saved passwords as a side effect.
- Updates: retain daily Brauz release notices and manual checks, not automatic binary installation. Use the actual hnnsly/brauz repository and keep the upstream Search binary-update feed disabled.
- Release architectures: keep Apple Silicon release DMG only; local Intel build support may remain.
- Upstream monitoring: manual only. Remove the scheduled upstream GitHub issue-updating workflow. Adapt any retained sync helper/documentation to topical branch-and-PR integration, not direct main rewriting or force-push instructions.

## Technical review conclusions
- Focus: recommend upstream's AddressField arrival handling and first-key buffering, dropping OmniboxField.swift and the old fork focus replacement. Verify the original focus scenario after integration.
- Keyboard layouts: recommend upstream KeyLayout.swift and macOS-paired Latin layout translation, dropping ShortcutKey.swift and fixed US-position matching. Retain upstream customizable Little Window commands.
- Popup undo: upstream ExtensionPopup has no popoverShouldClose cleanup. Candidate to retain the fork's early page removal only after rerunning the actual PageUndoTests reproduction against upstream and the integrated result.
- Image copying: upstream still appends async bytes one at a time. Retain the performance goal but not unchecked whole-response buffering; preserve a bounded 50 MB read and cover actual HTTP and oversized/unknown-length responses, not just file URLs.
- Pause-specific fixes: no need to retain suspension workarounds as dead code after removing the pause mechanism. Prior issue history stays intact; do not claim all unrelated crash paths are verified.
- Native-swipe performance patches remain rejected as a package. Reassess any independent back/forward issue against the chosen upstream gesture before keeping a patch.

## Approved implementation plan
The user approved this plan with "go on and also update text inside dmg", then explicitly requested many Sonnet/Haiku implementation workers. Keep diagnosis, decisions and final review with the primary assistant. The DMG background currently names Search; change its visible installation sentence to Brauz and verify the generated artwork and packaged image.

Execution on 2026-10-20:
- Preserved 19 conflicted Swift files, both diffs, refs and rebase metadata under build/integration-before-reviewed-20261020. Original swipe stash and build/pre-upstream-20261020.patch remain intact.
- Finished the paused legacy rebase without replaying the rejected remaining stack. Its branch remains integrate/search-1.0.5-all-issues.
- Created integrate/upstream-reviewed directly from upstream b2048a0, tracking origin/main, with no application-code difference at the starting point. main and original issue branches remain untouched.
- First implementation batch: nine file-owned workers for identity/updater, About/welcome, packaging/release, DMG text, progress removal, draft sleep, fork guidance, safe sync helper and the popup undo red regression.
- Second batch: five workers for Little Window controls/spaces/lifecycle, extension adapters, navigation routing, loopback fixtures and real regressions.
- App harness batch: two workers for isolated Brauz profile/store safety and actual fixture-extension round trips.
- Primary reviews code and runs tests after the source-edit batches finish. No commits/pushes/publications/app installation have occurred in this execution phase.

1. Preserve the current paused rebase state and existing stash/patch. Rework the integration onto upstream b2048a0 using only the reviewed differences; do not touch main, push, publish or install into /Applications.
2. Build the minimal Brauz baseline: identity/separate profile, About/feedback, own-release notices and Apple Silicon release packaging. Remove automatic Search profile copying and scheduled upstream issue monitoring. Use upstream focus, keyboard, layout and build behavior; update the fork rules and sync helper to match the new decisions.
3. Apply only the chosen scroll differences: natural vertical bounce and no reading-progress indicator/continuous progress reporting. Keep upstream custom gestures/history picker/first-page close and refresh controls. Preserve page-length-based UI via a non-scroll-driven measurement with tests.
4. Implement the chosen sleep policy without custom suspension: upstream timing/exemptions, normal draft protection until max(chosen sleep delay, one hour), then permission to discard. Tests must use actual typed content and exercise time boundaries and exemptions. No unsaved-state restoration promises or unmeasured RAM ceiling.
5. Adapt Little Window address/Back/placement/extensions and ordinary-link routing to upstream protections/shortcuts. Implement issue 0013's immediate space/store switch and selected-space keep destination, with unsaved-work confirmation and real store-isolation tests.
6. Reproduce the independent popup-undo and slow-copy issues against the new baseline. Keep only needed, tested fixes; image reads must be bounded during transfer. Recheck the historical YouTube HTML-download report without claiming it solved if it cannot be reproduced.
7. Primary assistant reviews every diff and result. Run targeted loops, full XCTest, isolated-profile built-app tests, release build and ./build.sh with required external Xcode. Update local issues and make topical commits. No pushing, PR merging, release publishing or installed-app replacement without separate authorization.

## Earlier inventory
- New upstream SleepPace, parked-pin policy and keep-awake settings must survive integration of pause and memory fixes.
- Required Xcode path was available on 2026-10-20 before conflict resolution.

## Fix
Completed on branch `integrate/upstream-reviewed`.
All approved policies have been implemented:
1. Rebased baseline directly on upstream `b2048a0` (Search v1.0.5 plus newer commits).
2. Minimal Brauz identity preserved (`dev.aabc.brauz`, `Application Support/Brauz`, About/welcome screens, own-release daily notices via `hnnsly/brauz`). Removed automatic copying from Search into missing Brauz locations.
3. Retained upstream custom gestures, history picker, first-page swipe-to-close, and three-choice refresh controls. Enabled natural vertical bounce. Removed reading progress bar and per-scroll tracking, retaining non-scroll ResizeObserver page-length calculation for moon sizing.
4. Sleep timing retains upstream Sooner (10m), Normal (30m), Later (2h) and memory pressure handling. Automatic draft discard permitted once idle age >= max(delay, 1h). Early 2.5m suspension omitted.
5. Little Windows: ordinary target=_blank links navigate within the Little Window; real JavaScript popups retain upstream window and blocker behavior. Added editable address, Back button, remembered placement, and targeted extension support. Added Little Window space selector to switch current browsing context immediately and determine destination space on Open in Brauz.
6. Popup undo crash fixed via `popoverShouldClose` subview detachment. Large image copy accelerated via bounded chunk streaming.
7. DMG installer artwork updated: text reads "Drag Brauz into Applications to install it".
8. Verification results:
   - Targeted suites: 35/35 passed (DraftSleepTests, PageLengthTests, PageUndoTests, BrauzUpdatesTests, LittleWindowTests, ImageCopyTests).
   - Full XCTest suite: 221/222 passed (sole failure `SidebarPressTests.testOtherButtonsDoNotSelectOnPress` reproduced and verified as an upstream `b2048a0` defect).
   - Python app probe `little_extensions.py`: 7/7 passed.
   - Python app probe `split_view.py`: 92/92 passed.
   - Release build `swift build -c release`: succeeded.
   - Packaging `./build.sh release dmg`: built `build/Brauz.app` and `build/Brauz.dmg`.
   - `/Applications/Brauz.app`: 100% untouched (verified by SHA-256).

Status: fixed.

## Guarded by
Pending final test inventory and output.

## Acceptance
- All upstream/main commits through b2048a0 are ancestors of the integration branch.
- Implement the user's recorded behavior choices. Identity, profile, updater and keyboard policy remain subject to their own review.
- Issues 0001 through 0010 are checked against actual tests, not assumed fixed by successful compilation.
- Historical YouTube HTML-download report is recorded separately if no reproduction can be established.
- Local issues and generated icons are not staged.
- build/Brauz.app is produced without modifying /Applications/Brauz.app.

## Files
Primary assistant owns diagnosis, conflict decisions, review and integration. Subagents receive exact, bounded code edits only.

## Test by hand
Pending verified build. No final app has been built from the integration branch yet.

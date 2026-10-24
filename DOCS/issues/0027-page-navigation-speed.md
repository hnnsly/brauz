---
status: fixing
found: 2026-10-23
---
# Page navigation speed: skip redundant user script re-arming on main frame navigation

## Symptom
Pages sometimes open slower in Brauz compared to Safari or Chrome.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter TabArmTests`

Red output before fix:
```
/Users/daniil/Dev/Search/.claude/worktrees/wf_3eb83816-b2f-8/Tests/SearchTests/TabArmTests.swift:37: error: -[SearchTests.TabArmTests testArmingTwiceWithSameInputsLeavesUserScriptsUntouched] : XCTAssertTrue failed - Script at index 0 was recreated despite identical inputs
```

## Cause
`Browser.decide()` in `/Users/daniil/Dev/Search/Sources/Search/Browser.swift:5005` runs `tab.arm(hiding:)` on every main frame navigation, which calls `controller.removeAllUserScripts()` and re-adds all 12-16 user scripts (`/Users/daniil/Dev/Search/Sources/Search/Tab.swift:813`). 

Ruled out / wrong in the first draft:
- WebKit private process cache and WebProcessPool configuration.
- Measuring first without profiling navigation delegates.

## Decisions (2026-10-24)
- User chose to go straight to the top suspect: `tab.arm(hiding:to:)` runs on every main-frame navigation (`Browser.swift:5005`) and removes and re-adds all 12-16 user scripts (`Tab.swift:813`).
- Skip that rebuild when its inputs have not changed, then measure Return to load start to first paint with the bench socket before and after.
- Not chosen: measuring first, WebKit private process cache.

## Fix
Introduced `ArmInputs` and `TabArming` in `Sources/Search/TabArming.swift` to capture the exact inputs determining user script generation. Keyed remembered inputs to the `WKUserContentController` via a weak-to-strong map so tabs sharing a controller (such as `Extensions.pages`) rebuild when interleaved with other inputs or when another tab discards the controller. In `Tab.arm(hiding:to:)`, compared the current inputs against the controller's remembered inputs: when all inputs match and user scripts are present, rebuilding all scripts is skipped. When any input differs or the controller is empty, scripts are rebuilt and recorded. In `Tab.discard()`, cleared remembered inputs for the controller.

Timings on local page via bench socket (`field` with `go: true`):
Before:
- Run 1 (cold): load start 16.14 ms, first paint 15 ms
- Run 2: load start 0.90 ms, first paint 8 ms
- Run 3: load start 0.91 ms, first paint 8 ms
- Run 4: load start 0.89 ms, first paint 9 ms
- Run 5: load start 0.81 ms, first paint 4 ms
Warm average (runs 2-5): load start 0.88 ms, first paint 7.25 ms

After:
- Run 1 (cold): load start 18.27 ms, first paint 10 ms
- Run 2: load start 0.62 ms, first paint 2 ms
- Run 3: load start 0.80 ms, first paint 6 ms
- Run 4: load start 0.79 ms, first paint 3 ms
- Run 5: load start 0.76 ms, first paint 5 ms
Warm average (runs 2-5): load start 0.74 ms (15% faster), first paint 4.00 ms (45% faster)

Files touched:
- `Sources/Search/TabArming.swift` (new fork-only file)
- `Sources/Search/Tab.swift` (hook in `arm` and reset in `discard`)
- `Tests/SearchTests/TabArmTests.swift` (guard test)

## Guarded by
`Tests/SearchTests/TabArmTests.swift`:
- `testArmingTwiceWithSameInputsLeavesUserScriptsUntouched`: asserts that arming with identical inputs leaves the controller's existing `WKUserScript` instances in place.
- `testChangingAnyInputRebuildsUserScripts`: asserts that changing CSS, destination host, `AutoScroll.on`, `HoveredLink.on`, `FormRelay.passkeysOffered`, or Dusk state rebuilds user scripts using a unique host per run.
- `testArmInputsEquality`: verifies value equality across every field of `ArmInputs`.
- `testTwoTabsSharingControllerRebuildsWhenInterleavedOrDiscarded`: asserts that tabs sharing a controller rebuild when interleaved with different inputs or when the other tab is discarded.

## Acceptance
- Arming twice with identical inputs leaves `WKUserScript` instances intact.
- Modifying any script input triggers a full rebuild.
- Page navigation on the same site reuses installed scripts and lowers first-paint latency.

## Files
- `Sources/Search/TabArming.swift`
- `Sources/Search/Tab.swift`
- `Tests/SearchTests/TabArmTests.swift`

## Test by hand
1. Run `./build.sh` and launch `open build/Brauz.app`.
2. Navigate between links on the same website (e.g. documentation or article pages).
3. Expect pages to start rendering immediately without script re-registration hitches.
4. Open Settings and toggle Auto-scroll or Dark mode; expect pages to pick up the setting change on next navigation.

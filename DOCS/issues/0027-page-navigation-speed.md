---
status: fixed
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

### Real-Site Timing Measurements
Benchmarked using `Tests/real_site_timing.py` across Plain WKWebView (`Tests/plainweb/main.swift`) and Brauz across 3 runs each (Run 1 = cold, Runs 2-3 = warm). Times in milliseconds: `didCommit` / `first visually non-empty layout` / `didFinish`.

| Site | Plain WKWebView (Cold / Warm Avg) | Brauz Baseline (Cold / Warm Avg) | Brauz Shield Off (Cold / Warm Avg) | Brauz Extensions Off (Cold / Warm Avg) |
|---|---|---|---|---|
| en.wikipedia.org/wiki/WebKit | 941/1165/2269 / 114/143/172 | 359/474/827 / 117/139/167 | 447/560/1036 / 145/168/196 | 375/491/963 / 114/143/174 |
| github.com/WebKit/WebKit | 747/1395/1295 / 106/197/147 | 771/1454/1548 / 144/224/171 | 852/1673/1674 / 124/208/154 | 849/1323/1246 / 103/188/137 |
| youtube.com | -/- /1170 / -/- /15 | -/- /54 / -/- /33 | -/- /1028 / -/- /32 | -/- /75 / -/- /32 |
| nytimes.com | 1031/1783/2836 / 311/692/3654 | 385/674/1148 / 441/486/1128 | 414/610/1092 / 408/450/1229 | 314/533/954 / 317/398/717 |
| ya.ru | 447/497/617 / 309/325/356 | 554/728/1433 / 298/321/371 | 472/683/1380 / 388/411/428 | 396/533/1305 / 280/293/317 |
| habr.com/ru/feed/ | 776/1798/7812 / 232/299/7102 | 1542/2080/7416 / 138/201/5636 | 155/659/7498 / 215/251/6136 | 1709/2220/7732 / 181/221/5734 |

Findings from real-site timing measurements:
- Warm loads in Brauz and a plain WKWebView agree within noise on every site.
- Cold first loads vary in both directions run to run between Brauz and a plain WKWebView.
- Turning Shield or extensions off shows no consistent saving across runs.
- On these six sites, Brauz adds no measurable navigation cost over a plain WKWebView. A gap with Safari, if real, must come from what Safari does that a WKWebView app does not. Third-party WKWebView applications lack access to Safari internal pre-warming, speculative socket pools, and private cache architectures; because those mechanisms cannot be inspected or configured here, that difference is unmeasured.
- youtube.com numbers look wrong with no commit or first paint (`-/-`), reporting only a finish time. youtube.com failed provisional navigation immediately due to a DNS lookup failure on this host network, firing `didFailProvisionalNavigation` instead of committing or rendering.

Files touched:
- `Sources/Search/TabArming.swift` (new fork-only file)
- `Sources/Search/Tab.swift` (hook in `arm`, reset in `discard`, test flag for extensions)
- `Sources/Search/Bench.swift` (time-nav bench command)
- `Sources/Search/Browser.swift` (navigation delegate hooks for test timing)
- `Tests/SearchTests/TabArmTests.swift` (guard test)
- `Tests/real_site_timing.py` (real-site timing benchmark)
- `Tests/plainweb/main.swift` (plain WKWebView timing harness)

## Guarded by
`Tests/SearchTests/TabArmTests.swift`:
- `testArmingTwiceWithSameInputsLeavesUserScriptsUntouched`: asserts that arming with identical inputs leaves the controller's existing `WKUserScript` instances in place.
- `testChangingAnyInputRebuildsUserScripts`: asserts that changing CSS, destination host, `AutoScroll.on`, `HoveredLink.on`, `FormRelay.passkeysOffered`, or Dusk state rebuilds user scripts using a unique host per run.
- `testArmInputsEquality`: verifies value equality across every field of `ArmInputs`.
- `testTwoTabsSharingControllerRebuildsWhenInterleavedOrDiscarded`: asserts that tabs sharing a controller rebuild when interleaved with different inputs or when the other tab is discarded.

`Tests/real_site_timing.py` and `Tests/plainweb/main.swift`:
- Comparative navigation timing benchmark measuring didCommit, first layout, and didFinish against a plain WKWebView.

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

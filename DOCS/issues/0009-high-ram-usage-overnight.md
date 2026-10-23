---
class: bug
status: fixing
found: 2026-10-17
---
# Brauz uses excessive RAM overnight (up to 7 GB footprint)

> right now check why brauz eating so much ram, get some dump idk, somewhat somehow, i think 7gigs overnight is too mcuh

## Symptom
Leaving Brauz running overnight results in excessive memory consumption (reported ~7 GB).

## Diagnostics from live running instance (PID 80939):
1. **Total physical footprint across Brauz processes**:
   - `Brauz [80939]` (UI process): 971 MB resident / 2.8 GB physical footprint (peak: 3.08 GB).
     - Breakdown in `footprint`:
       - `2655 MB` in `Owned physical footprint (unmapped)` across 8,425 regions (32 KB to 128 KB each).
       - `374 MB` in 404 `IOSurface` handles.
       - Only `76.5 MB` in malloc heap (`heap -s -H`).
     - Over 2.6 GB has been swapped out by the kernel (`swapped_out=2.7G`).
   - `com.apple.WebKit.WebContent [10421]`: 1.46 GB footprint (peak: 2.61 GB)
     - `2023 MB` in WebKit Malloc
     - `335 MB` Untagged
     - `89 MB` JS JIT Generated Code
   - `com.apple.WebKit.WebContent [62156]`: 868 MB footprint
   - `com.apple.WebKit.WebContent [3369]`: 223 MB footprint
   - `com.apple.WebKit.WebContent [2217]`: 117 MB footprint
   - `com.apple.WebKit.WebContent [2494]`: 109 MB footprint
   - `com.apple.WebKit.GPU [80941]`: 116 MB footprint (42 minutes CPU time)
   - Other helper processes (`81007`, `80966`, `80940`, `4212`): ~110 MB combined
   - **Total combined live footprint:** ~4.0 GB active (peak footprint ~7.0 GB across the cluster).

2. **Thread sampling of PID 80939 (`sample 80939`)**:
   - Continuous IPC message dispatch from WebProcessProxy:
     `RemoteLayerTreeDrawingAreaProxy::commitLayerTree`
     `RemoteLayerTreeHost::updateLayerTree`
     `RemoteLayerTreeNode::applyBackingStore`
     `CAIOSurfaceCreate` / `CA::Render::Surface::Surface`
   - Active web pages continue streaming layer tree commits and allocating/releasing IOSurfaces even when the user is away, accumulating thousands of unmapped Mach VM / purgeable ledger entries.

3. **Tab lifecycle state**:
   - 11 tabs open across 2 windows.
   - 0 tabs were asleep after 44+ hours of runtime.
   - 8 separate WebContent processes remained fully active and unsuspended in memory.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter TabSleepMemoryTests`
Red:
```
error: type 'Browser' has no member 'forceSleepAfter'
error: extra argument 'force' in call
```
Green: compiles and passes all tests; idle tabs pause regardless of form fields, and tabs past `forceSleepAfter` (1 hour) force-sleep and discard their web view.

## Review against upstream, 2026-10-20
The user requested a fresh upstream-versus-fork review before retaining patches. No implementation is authorized merely because an earlier fork branch has it.

- Upstream b2048a0 has configurable sleep at 10 minutes, 30 minutes or 2 hours, with protections for drafts, active work, keep-awake sites and notification-enabled pins in parked spaces. It has no fork-style 2.5-minute suspension stage.
- The pending d99dc44 tests do not establish their advertised draft/time behavior. Both HTML fixtures contain only headings, with no typed fields or rich editors. The second test calls browser.sleep(tab) directly, with no one-hour idle advancement and no force argument. They do not prove a one-hour draft grace period, draft restoration or an overnight memory ceiling.
- The pending sleep shortcut `tab.paused && (force || tab.picture != nil)` bypasses unsaved checking even when force is false. Once pause accepts draft pages, a screenshot is not evidence that a paused page has no draft. This shortcut does not implement the stated draft grace policy.
- The added `kind === 'search'` check is unreachable after the preceding allowed-kind filter, which already excludes input type search. Excluding arbitrary text inputs solely by names q/search/query risks ignoring non-search content.
- Earlier footprint measurements show the reported resource problem, but do not establish an IOSurface leak's cause or a verified 1-2 GB ceiling after the patch. Keep the issue fixing until the chosen policy is implemented and actual behavior measured.

## Implemented Policy and Verification, 2026-10-20
The approved policy was implemented in `Sources/Search/Sleep.swift`:
1. Early 2.5-minute suspension stage is omitted (user decision: "Upstream only").
2. Configurable sleep timing is retained: Sooner (10m), Normal (30m), Later (2h).
3. Draft tabs are protected from sleeping until idle age reaches `max(sleepAfter, 3600s)` (one hour for Normal and Sooner; two hours for Later). After this threshold, sleep proceeds to reclaim WebContent memory.
4. Active tabs, pinned tabs with notification permissions, and kept-awake sites remain exempt from sleep.
5. All 8 tests in `Tests/SearchTests/DraftSleepTests.swift` pass, covering draft protection before 1 hour, discard after 1 hour, Later pace 2-hour threshold, active/kept-awake exemptions, normal non-draft sleep, and memory pressure.

Status remains `fixing` pending real-world multi-hour overnight memory measurement to confirm overall physical footprint reduction on complex sites.
1. **Tabs never sleep when input forms or contenteditable elements exist (`unsaved()` check):**
   - In `TabPause.swift:40` and `Sleep.swift:110`, before pausing or sleeping an idle tab, `tab.unsaved` evaluates `window.__officeForms.unsaved()`.
   - In `Forms.swift:188-190`, `unsaved()` checked `el.isContentEditable` and returned `true` if any `textContent` existed. Modern web apps (Slack, Telegram, Discord, Google Docs, Notion, email, rich text inputs) keep text in `contenteditable` elements.
   - If `unsaved()` returned `true`, the tab was neither paused nor put to sleep. It remained fully active in memory forever, running background scripts, websockets, and animations.
2. **Tab pausing was unnecessarily gated on `unsaved()`:**
   - `pause(_ tab: Tab)` checked `!typed` before calling `_suspendPage:`. Suspending a page in WebKit does not discard form state or DOM; it merely freezes background execution. Skipping pause for any tab with text kept background layer trees streaming all night.
3. **IOSurface & CoreAnimation backing store leak under background rendering:**
   - Active background tabs continuously committed layer trees via `RemoteLayerTreeDrawingAreaProxy::commitLayerTree`.
   - The UI process received `IOSurface` frame buffers. As layers were replaced, XNU kernel accounting retained them under `Owned physical footprint (unmapped)` until memory pressure triggered aggressive reclamation, allowing the main process footprint to balloon to 3 GB.
4. **No upper limit or periodic cache trim on WebKit memory cache:**
   - Search/Brauz did not have a force-sleep threshold for extended idle tabs, and did not call `_close` on discarded web views, leaving process proxies alive until dealloc.

## Fix
1. In `Sources/Search/Forms.swift`:
   - Excluded search inputs (`kind === 'search'`, `el.name === 'q'`, `el.name === 'search'`, `el.name === 'query'`, or inputs within `form[role="search"]`) from being classified as unsaved drafts.
2. In `Sources/Search/TabPause.swift`:
   - Removed the `!typed` gate from `pause(_ tab: Tab)`. Background tabs pause after 2.5 minutes regardless of typed text, immediately halting background layer tree updates and timer execution.
3. In `Sources/Search/Sleep.swift`:
   - Added `Browser.forceSleepAfter` (1 hour).
   - In `sleepIdle(within:)`, tabs untouched for over 1 hour are passed `force: true`.
   - In `sleep(_:force:done:)`, if `force` is true or the tab is paused with an existing snapshot, the tab sleeps and discards its web view without blocking on `unsaved()`.
4. In `Sources/Search/Tab.swift`:
   - Added `touch(at date: Date = Date())` for backdating and time calculations.
   - In `discard()`, invoke WebKit's private `_close` selector on `web` when supported so WebKit immediately tears down `WebProcessProxy` layer host resources.
5. In `Tests/SearchTests/TabSleepMemoryTests.swift`:
   - Added unit tests for idle background tab pausing and extended idle force-sleep.

## Decisions (from Grill)
1. Extended idle force-sleep: Yes. If an idle background tab has been untouched for 1 hour (`forceSleepAfter`), take a snapshot, save `interactionState`, and put the tab to sleep even if form inputs or rich text editors contain text.
2. Background rendering suspension: Inactive background tabs must pause after 2.5 minutes without being blocked by `unsaved()`. Pausing suspends JS timers and animations without discarding form text.

## Guarded by
`Tests/SearchTests/TabSleepMemoryTests.swift`:
- `testIdleTabWithTypedContentStillPauses`
- `testExtendedIdleTabWithTypedContentForceSleeps`

## Acceptance
- Background tabs pause when idle (`pauseAfter`, 2.5 min) without being blocked by `unsaved()` form content.
- Pausing a background tab stops `RemoteLayerTreeDrawingAreaProxy` layer streaming.
- Tabs idle for over 1 hour (`forceSleepAfter`) force-sleep and discard their web view.
- Discarding a web view calls `_close` if supported to immediately release `WebProcessProxy` layer host resources.
- Search inputs are not classified as unsaved drafts in `Forms.swift`.

## Files
- `Sources/Search/Forms.swift`
- `Sources/Search/TabPause.swift`
- `Sources/Search/Sleep.swift`
- `Sources/Search/Tab.swift`
- `Tests/SearchTests/TabSleepMemoryTests.swift`

## PR
https://github.com/hnnsly/brauz/pull/4

## Test by hand
Start the built test app:
```bash
./build.sh && open build/Brauz.app
```
(Do not touch `/Applications/Brauz.app`).

Checks:
1. Open a search page (e.g. YouTube, Google, or GitHub), type a query into the search box, and navigate to results. Open a second tab so the first tab is in the background. Leave it for 2.5 minutes.
   - Expect: The background tab pauses (CPU drops to 0%, animations halt) instead of running continuously.
2. Open a chat app (e.g. Telegram Web, Discord, or Slack) in a tab and type draft text into the message box. Switch to another tab and leave it idle.
   - Expect: The tab pauses after 2.5 minutes. When you switch back, your typed draft text is still intact.
3. Leave Brauz running overnight with multiple tabs open across spaces.
   - Expect: Tabs not looked at for over 15 minutes (or 1 hour if holding drafts) transition to sleep, their WebContent processes are reclaimed by WebKit, and overall memory footprint remains bounded under 1-2 GB rather than swelling to 7 GB.
4. Switch back to a sleeping tab.
   - Expect: The tab displays its saved picture cover and wakes smoothly without crashing.

What no automated check covered:
- Real-world 8-hour overnight idle retention under macOS system memory management.
- Live DOM and interaction state restoration on third-party rich text editors (Notion, Telegram, Google Docs) after extended-idle force sleep.

Risks:
- Tabs left idle for over 1 hour with unsaved drafts will discard their live DOM. While WebKit interaction state restores standard form inputs, complex custom in-memory editor states (e.g. custom canvas-based editors) may reload to their last autosaved state.

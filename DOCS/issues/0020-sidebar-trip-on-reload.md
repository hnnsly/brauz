---
status: open
found: 2026-10-23
---
# Sidebar layout trips and mispositions or hides pinned tabs after offloaded page reloads

## Symptom
When an offloaded page reloads, the sidebar sometimes mispositions horizontally (e.g. 10-20% too far left) or jumps, and pinned tabs temporarily vanish from the screen.

## Loop
`python3 Tests/sidebar_reload_layout.py`

## Cause
When a sleeping tab wakes, `tab.loading` becomes true, causing `PinSquare` in `Sources/Search/Side.swift:624` to replace the pinned tab icon with a loading `Ring`, which unmounts the icon view. In addition, entering unloaded spaces in `Sources/Search/Spaces.swift:218` calls `showRow([], active: nil)`, clearing tabs and dropping `pinnedCount` to zero before session restore repopulates them.
- Ruled out / wrong in the first draft: The issue assumed layout measurement in `SideBar` races with geometry updates; `SideBar` has a fixed width (`prefs.sideWidth`) with no dynamic horizontal measurement.

## Decisions (2026-10-24)
- The user has seen it both with the sidebar folded and with it always visible, or is not sure which.
- Build a red loop first, then show the user ranked hypotheses before any fix. No fix is chosen yet: keeping the old space's tabs until the new ones are ready, and laying the loading ring over the pin icon, were options from the triage, not decisions.
- It happened with hands off the trackpad, so a half-finished space swipe is ruled out.
- Keep this issue open until the user can describe the steps or send a screen recording.

## Probe, 2026-10-24
A probe (branch `probe/0020-sidebar-wake`, `Tests/sidebar_wake_layout.py` and a `sidebar-sample` bench command) slept, woke and reloaded pinned and unpinned tabs with the sidebar visible, folded and peeking, and across a space switch. It stayed green in all 20 checks. The only thing that reproduced "about 20% left, pins gone" was a space swipe held partway (dx = -46 pt), which the user has ruled out.

The probe cannot see this bug, so it is not merged:
- It samples only after each bench command returns, so a transient shift during the wake is already over.
- It counts pinned tabs from the model (`pinnedCount`), not from what is drawn, so a pin that disappears from the screen still counts.
- It assumes the sidebar is on the left.

## Fix
None yet. Waiting for steps or a recording.

## Guarded by
Automated split view / sidebar layout python bench probes.

## Acceptance
- Waking or reloading an offloaded tab keeps the sidebar correctly positioned without shifting or hiding pinned tabs.

## Files
- `Sources/Search/Side.swift`
- `Sources/Search/Spaces.swift`
- `Sources/Search/Tab.swift`

## Test by hand
Offload a tab, switch back or reload it, observe sidebar position and pinned tabs.

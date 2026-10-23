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
- Build a red loop first using a Python bench probe that sleeps and wakes a tab with the sidebar folded and unfolded, sampling sidebar x position and pinned cell count.
- Show the user ranked hypotheses before any fix.
- Retain previous space tabs and swap atomically when new tabs are ready rather than clearing tabs to an empty array.
- Overlay the loading indicator ring on top of the icon instead of replacing it, avoiding unmounting pinned glyphs during reload.

## Fix
(Pending implementation after user agrees on ranked hypotheses)

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

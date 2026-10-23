---
status: open
found: 2026-10-23
---
# Sidebar layout trips and mispositions or hides pinned tabs after offloaded page reloads

## Symptom
When an offloaded page reloads, the sidebar sometimes mispositions horizontally (e.g. 10-20% too far left) or jumps, and pinned tabs temporarily vanish from the screen.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter Sidebar`

## Cause
Layout measurement or state restoration upon waking an offloaded tab races with sidebar offset or view geometry updates in `SideBar` / `Fold.swift`.

## Fix
Synchronize sidebar layout updates and frame measurements when waking or reloading offloaded tabs.

## Guarded by
Automated split view / sidebar layout tests.

## Acceptance
- Waking or reloading an offloaded tab keeps the sidebar correctly positioned without shifting or hiding pinned tabs.

## Files
- `Sources/Search/Side.swift`
- `Sources/Search/Fold.swift`
- `Sources/Search/Tab.swift`

## Test by hand
Offload a tab, switch back or reload it, observe sidebar position and pinned tabs.

---
status: open
found: 2026-10-23
---
# Fix visual appearance of offloaded Arc-like pinned tabs (transparently darkened artifact)

## Symptom
Pinned tabs look strange and transparently darkened when offloaded or put to rest, differing from active pinned tabs.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter Pin`

## Cause
Opacity or overlay styling applied to sleeping/offloaded pin cells in `Side.swift` / `TabBar.swift` over-darkens or creates unwanted transparency effects.

## Fix
Adjust CSS/SwiftUI opacity and background modifiers for offloaded pin cells.

## Guarded by
Pin visual representation tests.

## Acceptance
- Offloaded pinned tabs maintain a clean, consistent appearance without weird transparent darkening.

## Files
- `Sources/Search/Side.swift`
- `Sources/Search/TabBar.swift`

## Test by hand
Pin tabs, let them offload/sleep, check their visual styling in the sidebar/strip.

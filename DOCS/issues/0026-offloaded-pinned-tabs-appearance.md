---
status: open
found: 2026-10-23
---
# Sleeping pinned tabs keep full opacity and desaturate instead of dimming

## Symptom
Sleeping pinned tabs appear muddy and semi-transparent in dark mode because upstream applies 45% opacity over a dark background tile.

## Loop
`python3 Tests/pin_appearance.py` (manual inspection of Brauz.app screenshot via bench socket)

## Cause
When `tab.asleep` is true, `PinSquare` (`Sources/Search/Side.swift:628`) and `TabPill` (`Sources/Search/TabBar.swift:582`) pass `dim: true` to `Mark` (`Sources/Search/Icons.swift:349`), applying 45% opacity to the favicon or letter. Over dark sidebar tiles (`Palette.sideTile`, `Sources/Search/Design.swift:56`), this transparency lets the dark background bleed through. Listed pin rows (`SideRow`, `Sources/Search/Side.swift:715`) do not dim, creating visual inconsistency.
Ranked hypotheses:
1. Upstream opacity reduction causes dark background bleed-through on favicons. (Confirmed by code inspection and grep).
2. Inconsistency with listed sidebar rows makes the dimming look like a rendering artifact. (Confirmed).
Ruled out / wrong in the first draft:
- Adjusting CSS or background overlays (there is no CSS, app is SwiftUI).
- Running XCTest filters for pin appearance (no visual tests exist).

## Decisions (2026-10-24)
A sleeping pinned tab keeps full opacity and is desaturated (greyscale icon or letter) instead of upstream's 45% opacity (`Icons.swift:349`, `Side.swift:632`, `TabBar.swift:588`, upstream commit c3b3c66).
Not chosen: no dimming, lighter dim, leaving upstream.

## Fix
Update `Mark` in `Sources/Search/Icons.swift` (or the call sites in `Side.swift` and `TabBar.swift`) to apply a greyscale/desaturation filter instead of 45% opacity when sleeping, preserving 100% icon opacity.

## Guarded by
Manual visual inspection of sleeping pinned tabs.

## Acceptance
- Sleeping pinned tabs remain fully opaque and desaturated in both light and dark modes.

## Files
- `Sources/Search/Icons.swift`
- `Sources/Search/Side.swift`
- `Sources/Search/TabBar.swift`

## Test by hand
Pin a tab, let it sleep, verify the icon is desaturated and fully opaque without muddy background bleed-through.

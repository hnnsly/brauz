---
status: fixing
found: 2026-10-23
---
# Sleeping pinned tabs keep full opacity and desaturate instead of dimming

## Symptom
Sleeping pinned tabs appear muddy and semi-transparent in dark mode because upstream applies 45% opacity over a dark background tile.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter PinStyleTests`

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
A sleeping pinned tab keeps full opacity (1.0) and is desaturated (saturation 0.0, greyscale) instead of 0.45 opacity. Added `PinStyle.swift` defining `PinGlyphStyle` and `.pinGlyphStyle(asleep:)`, and hooked it into `Side.swift` and `TabBar.swift` while keeping full opacity on the glyphs. Other callers of `Mark(dim:)` (`SplitTabItem` and horizontal tab bar loose tabs) retain their existing dim behavior.
Files:
- `Sources/Search/PinStyle.swift`
- `Sources/Search/Side.swift`
- `Sources/Search/TabBar.swift`
- `Tests/SearchTests/PinStyleTests.swift`

## Guarded by
`Tests/SearchTests/PinStyleTests.swift` (`PinStyleTests.testSleepingPinGlyphHasFullOpacityAndZeroSaturation` and `testAwakePinGlyphHasFullOpacityAndFullSaturation`) covers only the style values (full opacity and saturation values). The look itself is checked by hand.

## Acceptance
- Sleeping pinned tabs remain fully opaque and desaturated in both light and dark modes.

## Files
- `Sources/Search/PinStyle.swift`
- `Sources/Search/Side.swift`
- `Sources/Search/TabBar.swift`
- `Tests/SearchTests/PinStyleTests.swift`

## Test by hand
Start Brauz (`./build.sh`, then `open build/Brauz.app`).
1. Pin a tab with a colorful favicon (e.g. YouTube, GitHub) and another tab with a text monogram.
2. Put the pinned tab to sleep (switch to another space or let it sleep via memory management).
3. Expect: The sleeping pinned tab icon is desaturated to greyscale and text stays crisp at full opacity, with no transparent darkening or background tile bleed-through.
4. Click the sleeping pinned tab to wake it. Expect: Full colors return immediately.
What no test covers: exact visual blending of CoreGraphics image saturation and SwiftUI greyscale over different OS theme backgrounds (light and dark mode).

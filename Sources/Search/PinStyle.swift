import SwiftUI

/// Styling for pinned tabs (#0026).
///
/// A sleeping pinned tab keeps full opacity and is desaturated (greyscale)
/// instead of 0.45 opacity, keeping its presence clean without transparent
/// darkening over the background tile.
struct PinGlyphStyle: Equatable {
    let opacity: Double
    let saturation: Double

    init(asleep: Bool) {
        self.opacity = PinGlyphStyle.opacity(asleep: asleep)
        self.saturation = PinGlyphStyle.saturation(asleep: asleep)
    }

    static func opacity(asleep: Bool) -> Double {
        1.0
    }

    static func saturation(asleep: Bool) -> Double {
        asleep ? 0.0 : 1.0
    }
}

extension View {
    /// A sleeping pinned tab keeps full opacity and is desaturated (greyscale).
    func pinGlyphStyle(asleep: Bool) -> some View {
        self
            .opacity(PinGlyphStyle.opacity(asleep: asleep))
            .saturation(PinGlyphStyle.saturation(asleep: asleep))
    }
}

import XCTest
@testable import Search

/// Pinned tab appearance (#0026): a sleeping pinned tab keeps full opacity (1.0)
/// and is desaturated (saturation 0.0, greyscale) instead of 0.45 opacity.
final class PinStyleTests: XCTestCase {
    func testSleepingPinGlyphHasFullOpacityAndZeroSaturation() {
        let style = PinGlyphStyle(asleep: true)
        XCTAssertEqual(style.opacity, 1.0, "Sleeping pin must keep full opacity (1.0) instead of 0.45")
        XCTAssertEqual(style.saturation, 0.0, "Sleeping pin must be desaturated (0.0)")
    }

    func testAwakePinGlyphHasFullOpacityAndFullSaturation() {
        let style = PinGlyphStyle(asleep: false)
        XCTAssertEqual(style.opacity, 1.0, "Awake pin has full opacity")
        XCTAssertEqual(style.saturation, 1.0, "Awake pin is fully saturated")
    }
}

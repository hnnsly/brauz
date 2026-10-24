import XCTest
@testable import Search

/// A test suite that never sets SEARCH_PROBE must still be isolated from the
/// user's real browser profile, settings, and keychain.
final class StoreIsolationTests: XCTestCase {
    func testTestRunIsIsolatedWithoutSearchProbe() {
        XCTAssertTrue(Store.testing)
        XCTAssertNotNil(Store.world)
        XCTAssertNotEqual(Store.folder.lastPathComponent, ForkIdentity.folderName)
        XCTAssertTrue(Store.folder.lastPathComponent.hasPrefix("Search ("))
        XCTAssertTrue(Store.settings !== UserDefaults.standard)
    }
}

import XCTest
@testable import Search

final class BrauzVersionTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "brauz-version-\(getpid())", 1)
        super.setUp()
    }

    func testVersionWithoutBrauzVersionKeyFallsBackToUpdaterVersion() {
        XCTAssertEqual(BrauzAbout.version, Updater.version)
        XCTAssertEqual(BrauzAbout.version(from: nil), Updater.version)
        XCTAssertEqual(BrauzAbout.version(from: [:]), Updater.version)
        XCTAssertEqual(BrauzAbout.version(from: ["BrauzVersion": ""]), Updater.version)
    }

    func testVersionWithBrauzVersionKey() {
        let releaseDict: [String: Any] = ["BrauzVersion": "1.0.5.b2"]
        XCTAssertEqual(BrauzAbout.version(from: releaseDict), "1.0.5.b2")

        let devDict: [String: Any] = ["BrauzVersion": "1.0.5.b2+14"]
        XCTAssertEqual(BrauzAbout.version(from: devDict), "1.0.5.b2+14")
    }
}

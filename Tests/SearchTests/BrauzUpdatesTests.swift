import XCTest
@testable import Search

final class BrauzUpdatesTests: XCTestCase {
    func testAcceptedReleaseTitles() {
        let cases: [(title: String, expectedVersion: String, expectedBuild: Int)] = [
            ("Brauz 1.0.4 (build 202610071500)", "1.0.4", 202610071500),
            ("Brauz 1.0.5 (build 202610201200)", "1.0.5", 202610201200),
            ("Brauz 2.0 (build 202701010000)", "2.0", 202701010000),
            ("Brauz 1.0.5-beta (build 202610201200)", "1.0.5-beta", 202610201200),
            ("Brauz 1.0.4 (build 202610071500) - Hotfix", "1.0.4", 202610071500),
        ]
        for c in cases {
            guard let parsed = BrauzUpdates.parse(title: c.title) else {
                XCTFail("Expected valid release title for: \(c.title)")
                continue
            }
            XCTAssertEqual(parsed.version, c.expectedVersion, "Version mismatch for \(c.title)")
            XCTAssertEqual(parsed.build, c.expectedBuild, "Build mismatch for \(c.title)")
        }
    }

    func testRejectedReleaseTitles() {
        let rejected = [
            "",
            "Search 1.0.5 (build 202610201200)",
            "Brauz",
            "Brauz ",
            "Brauz (build 202610071500)",
            "Brauz   (build 202610071500)",
            "Brauz 1.0.4",
            "Brauz 1.0.4 build 202610071500",
            "Brauz 1.0.4 (build )",
            "Brauz 1.0.4 (build 123)",
            "Brauz 1.0.4 (build 20261007)",
            "Brauz 1.0.4 (build 2026100715001)",
            "Brauz 1.0.4 (build abcdefghijkl)",
            "Draft: Brauz 1.0.4 (build 202610071500)",
            "brauz 1.0.4 (build 202610071500)",
        ]
        for title in rejected {
            XCTAssertNil(BrauzUpdates.parse(title: title), "Expected rejection for title: \(title)")
        }
    }
}

import XCTest
@testable import Search

final class CleanLinkTests: XCTestCase {
    func testUtmParametersDropped() {
        let input = "https://example.com/article?utm_source=twitter&utm_medium=social&utm_campaign=summer2026&utm_term=browser&utm_content=headline"
        let expected = "https://example.com/article"
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)
    }

    func testClickIdParametersDropped() {
        let clickIDs = [
            "fbclid": "IwAR123456789",
            "gclid": "EAIaIQobChMI12345",
            "dclid": "CK312345",
            "gbraid": "0AAAA1234",
            "wbraid": "0AAAA5678",
            "msclkid": "abcd1234efgh",
            "yclid": "987654321",
            "ysclid": "123456789",
            "mc_eid": "abc12345",
            "mc_cid": "def67890",
            "igshid": "xyz98765",
            "_hsenc": "p2ANqzt-test",
            "_hsmi": "1234567"
        ]

        for (key, val) in clickIDs {
            let input = "https://example.com/landing?id=42&\(key)=\(val)&active=true"
            let expected = "https://example.com/landing?id=42&active=true"
            XCTAssertEqual(
                CleanLink.clean(URL(string: input)!).absoluteString,
                expected,
                "Failed to drop tracking parameter: \(key)"
            )
        }
    }

    func testPreservesLegitimateParametersAndEncoding() {
        let input = "https://example.com/search?query=hello+world&filter=tag%2Fsubtag&name=John%20Doe&utm_source=ad&safe=1"
        let expected = "https://example.com/search?query=hello+world&filter=tag%2Fsubtag&name=John%20Doe&safe=1"
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)
    }

    func testRepeatedParametersPreservedInOrder() {
        let input = "https://example.com/shop?cat=shoes&utm_source=promo&cat=boots&sort=asc&cat=sneakers"
        let expected = "https://example.com/shop?cat=shoes&cat=boots&sort=asc&cat=sneakers"
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)
    }

    func testFragmentPreserved() {
        let input = "https://example.com/docs?utm_source=newsletter&section=quickstart#step-3"
        let expected = "https://example.com/docs?section=quickstart#step-3"
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)

        let inputOnlyTracking = "https://example.com/docs?utm_source=newsletter#step-3"
        let expectedOnlyTracking = "https://example.com/docs#step-3"
        XCTAssertEqual(CleanLink.clean(URL(string: inputOnlyTracking)!).absoluteString, expectedOnlyTracking)
    }

    func testAllTrackingParametersRemovesQueryPrefix() {
        let input = "https://example.com/page?utm_source=mail&fbclid=12345"
        let expected = "https://example.com/page"
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)
    }

    func testEmptyAndFlagParametersPreserved() {
        let input = "https://example.com/test?flag&utm_campaign=spring&empty="
        let expected = "https://example.com/test?flag&empty="
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)
    }

    func testYouTubeAndSpotifyShareIdentifiers() {
        // YouTube desktop
        let yt1 = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=trackingID123"
        XCTAssertEqual(
            CleanLink.clean(URL(string: yt1)!).absoluteString,
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )

        // YouTube short domain
        let yt2 = "https://youtu.be/dQw4w9WgXcQ?si=trackingID123&t=42"
        XCTAssertEqual(
            CleanLink.clean(URL(string: yt2)!).absoluteString,
            "https://youtu.be/dQw4w9WgXcQ?t=42"
        )

        // Spotify
        let sp = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc123def456&context=spotify%3Aalbum"
        XCTAssertEqual(
            CleanLink.clean(URL(string: sp)!).absoluteString,
            "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?context=spotify%3Aalbum"
        )

        // Other domain: si is NOT dropped
        let other = "https://example.com/api?si=system_identifier&user=alice"
        XCTAssertEqual(
            CleanLink.clean(URL(string: other)!).absoluteString,
            "https://example.com/api?si=system_identifier&user=alice"
        )
    }

    func testCaseInsensitiveMatching() {
        let input = "https://example.com/test?UTM_SOURCE=ad&FbClid=xyz&GCLID=123&keep=ok"
        let expected = "https://example.com/test?keep=ok"
        XCTAssertEqual(CleanLink.clean(URL(string: input)!).absoluteString, expected)
    }

    func testCleanIfEnabledToggle() {
        let dirty = URL(string: "https://example.com/page?utm_source=twitter&keep=1")!
        let clean = "https://example.com/page?keep=1"

        // Default: enabled
        Store.settings.removeObject(forKey: CleanLink.key)
        XCTAssertEqual(CleanLink.cleanIfEnabled(dirty).absoluteString, clean)

        // Disabled via settings
        Store.settings.set(false, forKey: CleanLink.key)
        XCTAssertEqual(CleanLink.cleanIfEnabled(dirty).absoluteString, dirty.absoluteString)

        // Re-enabled
        Store.settings.set(true, forKey: CleanLink.key)
        XCTAssertEqual(CleanLink.cleanIfEnabled(dirty).absoluteString, clean)

        Store.settings.removeObject(forKey: CleanLink.key)
    }

    func testCleanString() {
        let input = "https://example.com/item?id=99&utm_source=newsletter"
        XCTAssertEqual(CleanLink.clean(input), "https://example.com/item?id=99")
        XCTAssertEqual(CleanLink.clean("not a valid url but text"), "not a valid url but text")
    }

    func testCleanPasteboardIfEnabled() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString("https://example.com/test?utm_source=ad&q=target", forType: .string)

        Store.settings.removeObject(forKey: CleanLink.key)
        CleanLink.cleanPasteboardIfEnabled()
        XCTAssertEqual(board.string(forType: .string), "https://example.com/test?q=target")

        // When disabled
        board.clearContents()
        let dirty = "https://example.com/test?utm_source=ad&q=target"
        board.setString(dirty, forType: .string)
        Store.settings.set(false, forKey: CleanLink.key)
        CleanLink.cleanPasteboardIfEnabled()
        XCTAssertEqual(board.string(forType: .string), dirty)

        Store.settings.removeObject(forKey: CleanLink.key)
    }
}

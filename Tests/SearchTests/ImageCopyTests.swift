import AppKit
import Foundation
import XCTest
@testable import Search

@MainActor
final class ImageCopyTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "image-copy-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    func testALargePictureArrivesQuickly() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("image-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data((0..<20_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let file = folder.appendingPathComponent("photo.jpg")
        try bytes.write(to: file)
        let browser = Browser(record: WindowRecord())
        let tab = Search.Tab(shy: true)

        let started = Date()
        let copied = await browser.imageData(at: file, in: tab)
        let seconds = Date().timeIntervalSince(started)

        XCTAssertEqual(copied, bytes)
        XCTAssertLessThan(seconds, 2, "a 20 MB picture took \(seconds) seconds to copy")
    }

    func testHTTP20MBExactRead() async throws {
        let server = try LocalDownloadServer(size: 20 * 1024 * 1024)
        defer { server.stop() }
        let browser = Browser(record: WindowRecord())
        let tab = Search.Tab(shy: true)

        let started = Date()
        let copied = await browser.imageData(at: server.url("/image-fast.bin"), in: tab)
        let seconds = Date().timeIntervalSince(started)

        XCTAssertEqual(copied, server.expectedBytes())
        XCTAssertLessThan(seconds, 5, "a 20 MB HTTP picture took \(seconds) seconds to copy")
    }

    func testOversizedHeaderIsRejectedWithoutWaitingForBody() async throws {
        let server = try LocalDownloadServer(size: 1024)
        defer { server.stop() }
        let browser = Browser(record: WindowRecord())
        let tab = Search.Tab(shy: true)

        let started = Date()
        let copied = await browser.imageData(at: server.url("/image-oversized.bin"), in: tab)

        XCTAssertNil(copied)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(server.count("/image-oversized.bin"), 1)
        XCTAssertEqual(server.bytesSent("/image-oversized.bin"), 1)
    }

    func testUnknownLengthStopsAtSizeLimit() async throws {
        let server = try LocalDownloadServer(size: 60 * 1024 * 1024)
        defer { server.stop() }
        let browser = Browser(record: WindowRecord())
        let tab = Search.Tab(shy: true)

        let copied = await browser.imageData(at: server.url("/image-unbounded.bin"), in: tab)
        let sent = server.bytesSent("/image-unbounded.bin")

        XCTAssertNil(copied)
        XCTAssertGreaterThanOrEqual(sent, 50_000_000, "the transfer must reach the limit, not fail before it")
        XCTAssertLessThan(sent, server.expectedBytes().count)
        XCTAssertEqual(server.completed("/image-unbounded.bin"), 0)
    }

    func testCookieIsolation() async throws {
        let server = try LocalDownloadServer(size: 1024)
        defer { server.stop() }
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: "image-fixture-\(UUID().uuidString)",
            .value: "fixture-only"
        ]))
        let storage = try XCTUnwrap(URLSession.shared.configuration.httpCookieStorage)
        storage.setCookie(cookie)
        defer { storage.deleteCookie(cookie) }

        var control = URLRequest(url: server.url("/image-cookie-control.bin"))
        control.cachePolicy = .reloadIgnoringLocalCacheData
        _ = try await URLSession.shared.data(for: control)
        XCTAssertTrue(server.cookies("/image-cookie-control.bin").contains { $0?.contains(cookie.name) == true },
                      "the control request must actually send the cookie")

        let browser = Browser(record: WindowRecord())
        let tab = Search.Tab(shy: true)
        let copied = await browser.imageData(at: server.url("/image-fast.bin"), in: tab)
        XCTAssertEqual(copied, server.expectedBytes())
        XCTAssertEqual(server.count("/image-fast.bin"), 1)
        XCTAssertTrue(server.cookies("/image-fast.bin").allSatisfy { $0 == nil })
    }

    func testCancellationStopsAnActiveTransfer() async throws {
        let server = try LocalDownloadServer(size: 8 * 1024 * 1024)
        defer { server.stop() }
        let browser = Browser(record: WindowRecord())
        let tab = Search.Tab(shy: true)
        let transfer = Task { await browser.imageData(at: server.url("/image-unbounded.bin"), in: tab) }
        let deadline = Date().addingTimeInterval(5)
        while server.bytesSent("/image-unbounded.bin") < 128 * 1024 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(server.bytesSent("/image-unbounded.bin"), 128 * 1024)
        transfer.cancel()

        let copied = await transfer.value
        XCTAssertNil(copied)
        XCTAssertLessThan(server.bytesSent("/image-unbounded.bin"), server.expectedBytes().count)
        XCTAssertEqual(server.completed("/image-unbounded.bin"), 0)
    }
}

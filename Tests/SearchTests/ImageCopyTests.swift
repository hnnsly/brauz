import AppKit
import Foundation
import WebKit
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

    private func evaluate(_ web: PageView, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            web.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }

    private func loadTab(at url: URL) async throws -> (Browser, Search.Tab) {
        let browser = Browser(record: WindowRecord())
        let tab = browser.open(url, foreground: true)
        let deadline = Date().addingTimeInterval(10)
        var ready = false
        while Date() < deadline {
            if let web = tab.built,
               !tab.loading,
               web.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
                let js = """
                (() => {
                    const img = document.getElementById('p');
                    if (!img) return true;
                    return Boolean(img.complete && img.naturalWidth > 0);
                })()
                """
                if (await evaluate(web, js) as? Bool) == true {
                    ready = true
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        if !ready {
            XCTFail("Timed out waiting for tab to load \(url)")
        }
        try await Task.sleep(for: .milliseconds(500))
        return (browser, tab)
    }

    func testPageLoadedPictureIsNotDownloadedTwice() async throws {
        let server = try LocalDownloadServer(size: 1024)
        defer { server.stop() }
        let (browser, tab) = try await loadTab(at: server.url("/pic-page"))
        XCTAssertEqual(server.count("/pic-cacheable.png"), 1)
        let copied = await browser.imageData(at: server.url("/pic-cacheable.png"), in: tab)
        XCTAssertEqual(copied, server.picture)
        XCTAssertEqual(server.count("/pic-cacheable.png"), 1, "copying re-downloaded a picture the page already had")
    }

    func testNoStorePictureStillCopies() async throws {
        let server = try LocalDownloadServer(size: 1024)
        defer { server.stop() }
        let (browser, tab) = try await loadTab(at: server.url("/pic-page-nostore"))
        let copied = await browser.imageData(at: server.url("/pic-nostore.png"), in: tab)
        XCTAssertEqual(copied, server.picture)
    }

    func testCrossOriginPictureWithoutCORSFallsBack() async throws {
        let serverA = try LocalDownloadServer(size: 1024)
        defer { serverA.stop() }
        let serverB = try LocalDownloadServer(size: 1024)
        defer { serverB.stop() }

        serverA.crossOriginPicture = serverB.url("/pic-cacheable.png")
        let (browser, tab) = try await loadTab(at: serverA.url("/pic-page-cross"))
        let copied = await browser.imageData(at: serverB.url("/pic-cacheable.png"), in: tab)
        XCTAssertEqual(copied, serverB.picture)
        XCTAssertEqual(serverB.count("/pic-cacheable.png"), 2)
    }

    func testOversizedPictureIsRefusedQuicklyThroughThePage() async throws {
        let server = try LocalDownloadServer(size: 1024)
        defer { server.stop() }
        let (browser, tab) = try await loadTab(at: server.url("/pic-page"))

        let started = Date()
        let copied = await browser.imageData(at: server.url("/image-oversized.bin"), in: tab)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNil(copied)
        XCTAssertLessThan(elapsed, 3)
    }

    /// Recorded, not asserted: how long a copy takes through the page and
    /// over the network at a few sizes, and how many requests the server saw.
    /// One request is the page's own warm-up, one the network copy; a third
    /// means the page read was not served from WebKit's cache.
    func testPictureTimingsBySize() async throws {
        for megabytes in [2, 5, 10, 20] {
            let server = try LocalDownloadServer(size: megabytes * 1024 * 1024)
            defer { server.stop() }
            let (browser, tab) = try await loadTab(at: server.url("/pic-page"))
            let web = try XCTUnwrap(tab.built)
            _ = try await web.callAsyncJavaScript(
                "return await fetch('/pic-big.bin').then(r => r.arrayBuffer()).then(b => b.byteLength);",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            try await Task.sleep(for: .milliseconds(500))

            let url = server.url("/pic-big.bin")

            let pageStart = Date()
            let pageCopied = await browser.imageData(at: url, in: tab)
            let pageSeconds = Date().timeIntervalSince(pageStart)
            let afterPage = server.count("/pic-big.bin")

            let networkTab = Search.Tab(shy: true)
            let networkStart = Date()
            let networkCopied = await browser.imageData(at: url, in: networkTab)
            let networkSeconds = Date().timeIntervalSince(networkStart)

            XCTAssertEqual(pageCopied, server.expectedBytes(), "\(megabytes) MB through the page")
            XCTAssertEqual(networkCopied, server.expectedBytes(), "\(megabytes) MB over the network")

            print("IMAGECOPY-TIMING size=\(megabytes)MB page=\(String(format: "%.3f", pageSeconds)) network=\(String(format: "%.3f", networkSeconds)) requestsAfterPageCopy=\(afterPage) (1 means served from cache)")
        }
    }
}

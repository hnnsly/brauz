import AppKit
import Foundation
import XCTest
@testable import Search

private typealias BrowserTab = Search.Tab

/// Copy Image used to read a picture one byte at a time, so a large one took
/// tens of seconds to arrive while a small one was instant.
@MainActor
final class ImageCopyTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "image-copy-\(getpid())", 1)
        super.setUp()
    }

    override class func tearDown() {
        Disk.drain()
        if let world = Store.world {
            let suite = "com.officecommun.search.test.\(world)"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: Store.folder)
        }
        super.tearDown()
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
        let tab = BrowserTab(shy: true)

        let started = Date()
        let copied = await browser.imageData(at: file, in: tab)
        let seconds = Date().timeIntervalSince(started)

        XCTAssertEqual(copied, bytes)
        XCTAssertLessThan(seconds, 2, "a 20 MB picture took \(seconds) seconds to copy")
    }
}

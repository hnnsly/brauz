import AppKit
import XCTest
@testable import Search

@MainActor
final class WindowRestoreTests: XCTestCase {
    private var primary: Browser!
    private var primaryWindow: NSWindow!

    override class func setUp() {
        setenv("SEARCH_PROBE", "window-restore-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        if let existing = Browsers.primary {
            primary = existing
        } else {
            primary = Browser(record: WindowRecord())
            Browsers.register(primary)
        }
        if primary.window == nil {
            primaryWindow = NSWindow(
                contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            primary.window = primaryWindow
        }
        let file = Store.file("windows.json")
        try? FileManager.default.removeItem(at: file)
    }

    override func tearDown() {
        for browser in Browsers.all where browser !== primary {
            if let window = browser.window {
                window.orderOut(nil)
                window.close()
                Browsers.closing(window)
            } else {
                browser.closeAll()
            }
        }
        let file = Store.file("windows.json")
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    func testWindowRecordIsEmpty() {
        let emptyNoRows = WindowRecord()
        XCTAssertTrue(emptyNoRows.isEmpty)

        var emptyRowsEmptyShape = WindowRecord()
        emptyRowsEmptyShape.rows[Space.firstID.uuidString] = Session.Shape(tabs: [], active: 0)
        XCTAssertTrue(emptyRowsEmptyShape.isEmpty)

        var populated = WindowRecord()
        let entry = Session.Entry(url: "https://example.com", title: "Example")
        populated.rows[Space.firstID.uuidString] = Session.Shape(tabs: [entry], active: 0)
        XCTAssertFalse(populated.isEmpty)
    }

    func testRestorableDropsFirstRecordAndEmptyRecords() {
        var record0 = WindowRecord()
        record0.frame = NSStringFromRect(NSRect(x: 100, y: 100, width: 800, height: 600))

        let empty1 = WindowRecord()
        var empty2 = WindowRecord()
        empty2.rows[Space.firstID.uuidString] = Session.Shape(tabs: [], active: 0)

        var populated = WindowRecord()
        let entry = Session.Entry(url: "https://example.com", title: "Example")
        populated.rows[Space.firstID.uuidString] = Session.Shape(tabs: [entry], active: 0)

        let result = Browsers.restorable([record0, empty1, populated, empty2])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, populated.id)
    }

    func testRestoreSkipsEmptyRecordsOpensExactlyOneExtraWindow() throws {
        var record0 = WindowRecord()
        record0.frame = NSStringFromRect(NSRect(x: 100, y: 100, width: 800, height: 600))

        let empty1 = WindowRecord()
        var empty2 = WindowRecord()
        empty2.rows[Space.firstID.uuidString] = Session.Shape(tabs: [], active: 0)

        var populated = WindowRecord()
        let entry = Session.Entry(url: "https://example.com", title: "Example")
        populated.rows[Space.firstID.uuidString] = Session.Shape(tabs: [entry], active: 0)

        let records = [record0, empty1, empty2, populated]
        let file = Store.file("windows.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: file, options: .atomic)

        let beforeCount = Browsers.all.count
        Browsers.restore()

        XCTAssertEqual(Browsers.all.count, beforeCount + 1, "restore must open exactly one extra window")
        XCTAssertEqual(Browsers.all.last?.record.id, populated.id)
    }

    func testSaveWithRestoredFalseDoesNotCarryEmptyRecordsForward() throws {
        var record0 = WindowRecord()
        record0.frame = NSStringFromRect(NSRect(x: 100, y: 100, width: 800, height: 600))

        let empty1 = WindowRecord()
        var empty2 = WindowRecord()
        empty2.rows[Space.firstID.uuidString] = Session.Shape(tabs: [], active: 0)

        var populated = WindowRecord()
        let entry = Session.Entry(url: "https://example.com", title: "Example")
        populated.rows[Space.firstID.uuidString] = Session.Shape(tabs: [entry], active: 0)

        let fileRecords = [record0, empty1, empty2, populated]
        let file = Store.file("windows.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(fileRecords).write(to: file, options: .atomic)

        let openCount = Browsers.saved.count
        Browsers.save(now: true)

        let saved = Browsers.read()
        // Open windows are written first; only non-empty records from disk are carried forward.
        XCTAssertEqual(saved.count, openCount + 1, "only the populated record from disk should be carried forward")
        XCTAssertEqual(saved.last?.id, populated.id)
        XCTAssertFalse(saved.contains { $0.id == empty1.id }, "empty record with no rows must not be carried forward")
        XCTAssertFalse(saved.contains { $0.id == empty2.id }, "empty record with empty space row must not be carried forward")
        XCTAssertFalse(saved.dropFirst().contains { $0.id == record0.id }, "record 0 from disk must not be carried forward")
    }
}

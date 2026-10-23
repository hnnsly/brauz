import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class WakeCoverTests: XCTestCase {
    private var browser: Browser!
    private var window: NSWindow!

    override class func setUp() {
        setenv("SEARCH_PROBE", "wake-cover-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    private func makeMouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 100, y: 100),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    func testMouseDownWhileUnpaintedDoesNotTriggerOnTouch() {
        let config = WKWebViewConfiguration()
        let page = PageView(frame: NSRect(x: 0, y: 0, width: 500, height: 500), configuration: config)
        page.holdForFirstFrame()
        XCTAssertTrue(page.unpainted)

        var touched = false
        page.onTouch = { touched = true }

        page.mouseDown(with: makeMouseEvent())
        XCTAssertFalse(touched, "mouseDown while unpainted must not trigger onTouch")

        page.showFirstFrame()
        XCTAssertFalse(page.unpainted)

        page.mouseDown(with: makeMouseEvent())
        XCTAssertTrue(touched, "mouseDown after firstFrame has rendered triggers onTouch")
    }

    func testWakingTabCoverDoesNotDropOnMouseDownWhileUnpainted() {
        let tab = browser.open(URL(string: "about:blank")!, foreground: true)
        window.contentView = tab.web
        tab.setAddressOptimistically(URL(string: "https://example.com")!)

        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        image.unlockFocus()
        let tiff = image.tiffRepresentation!

        tab.sleep(picture: tiff)
        XCTAssertTrue(tab.asleep)

        tab.wake()
        XCTAssertNotNil(tab.cover, "Waking tab must show snapshot cover")
        XCTAssertTrue(tab.web.unpainted, "Waking tab web view must start unpainted")

        tab.web.mouseDown(with: makeMouseEvent())
        XCTAssertNotNil(tab.cover, "Clicking a waking tab before first paint must not drop the cover")

        tab.web.showFirstFrame()
        tab.uncover()
        XCTAssertNil(tab.cover, "Cover uncovers once firstFrame has rendered")
    }
}

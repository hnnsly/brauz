import AppKit
import WebKit
import XCTest
@testable import Search

private final class NavDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    var finished = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
    }
}

@MainActor
final class TabSleepMemoryTests: XCTestCase {
    private var window: NSWindow!
    private var navDelegate: NavDelegate!

    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-sleep-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 680),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        navDelegate = NavDelegate()
    }

    override func tearDown() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        navDelegate = nil
        super.tearDown()
    }

    func testIdleTabWithTypedContentStillPauses() throws {
        let browser = Browser(record: WindowRecord())
        let tab = try XCTUnwrap(browser.open(URL(string: "data:text/html,<h1>Test</h1>")!, foreground: true))
        tab.delegate = navDelegate
        window.contentView = tab.web
        try waitUntil { self.navDelegate.finished }

        // Open a second tab so the first tab is not the one on screen
        _ = browser.open(URL(string: "data:text/html,<h1>Test 2</h1>")!, foreground: true)

        XCTAssertNotNil(tab.built)
        XCTAssertFalse(tab.paused)

        // Directly invoke pause(tab)
        browser.pause(tab)
        try waitUntil { tab.paused }

        XCTAssertTrue(tab.paused, "A background tab must pause to stop layer rendering and JS execution")
    }

    func testExtendedIdleTabWithTypedContentForceSleeps() throws {
        let browser = Browser(record: WindowRecord())
        let tab = try XCTUnwrap(browser.open(URL(string: "data:text/html,<h1>Test</h1>")!, foreground: true))
        tab.delegate = navDelegate
        window.contentView = tab.web
        try waitUntil { self.navDelegate.finished }

        // Open a second tab so the first tab is not the one on screen
        _ = browser.open(URL(string: "data:text/html,<h1>Test 2</h1>")!, foreground: true)

        XCTAssertNotNil(tab.built)

        // Pause the tab first, then sleep it
        browser.pause(tab)
        try waitUntil { tab.paused }

        browser.sleep(tab)
        try waitUntil { tab.asleep && tab.built == nil }

        XCTAssertTrue(tab.asleep, "Extended idle tab must sleep to free WebContent memory")
        XCTAssertNil(tab.built, "Sleeping tab must discard its web view")
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTFail("Timed out waiting for condition")
        throw WaitError.timedOut
    }

    private enum WaitError: Error { case timedOut }
}

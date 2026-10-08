import AppKit
import Darwin
import Foundation
import WebKit
import XCTest
@testable import Search

private typealias BrowserTab = Search.Tab

private final class NavDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    var finished = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
    }
}

/// A paused tab's view is suspended, and WebKit raises on stopLoading, load,
/// reload and the rest while it is. Putting such a tab to sleep or closing it
/// took the app down with "The WKWebView is suspended".
///
/// Synchronous on purpose: XCTest reports an Objective-C exception from a
/// synchronous test as a failure, while one unwinding through an async test
/// kills the process with no word of what was thrown.
@MainActor
final class PausedTabDiscardTests: XCTestCase {
    private var window: NSWindow!
    private var navDelegate: NavDelegate!

    override class func setUp() {
        setenv("SEARCH_PROBE", "paused-tab-\(getpid())", 1)
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

    func testSleepingPausedTabDoesNotThrow() throws {
        let tab = try pausedTab()
        tab.sleep(picture: nil)
        XCTAssertNil(tab.built)
    }

    func testClosingPausedTabDoesNotThrow() throws {
        let tab = try pausedTab()
        tab.close()
        XCTAssertNil(tab.built)
    }

    func testReloadingPausedTabResumesIt() throws {
        let tab = try pausedTab()
        tab.reload()
        XCTAssertFalse(tab.paused)
    }

    private func pausedTab() throws -> BrowserTab {
        let tab = BrowserTab()
        tab.delegate = navDelegate
        window.contentView = tab.web
        tab.go(to: URL(string: "data:text/html,<h1>Test</h1>")!)
        try waitUntil { self.navDelegate.finished }
        tab.pause()
        XCTAssertTrue(tab.paused, "the page must really be suspended, or these tests prove nothing")
        return tab
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

import AppKit
import Darwin
import Foundation
import SwiftUI
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

/// Typing in a page puts each edit on the window's undo stack, aimed at an
/// object the page's view owns. WebKit takes them off only as the view
/// leaves its window; a page let go without that left ⌘Z aimed at freed
/// memory, and the app crashed in -[NSUndoManager undoNestedGroup].
@MainActor
final class PageUndoTests: XCTestCase {
    private var window: NSWindow!
    private var navDelegate: NavDelegate!

    override class func setUp() {
        setenv("SEARCH_PROBE", "page-undo-\(getpid())", 1)
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
            styleMask: [.titled, .closable, .resizable],
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

    /// The crash: an extension's popup, built as ExtensionPopup.show builds
    /// it and closed through its delegate. A popover's window hands out the
    /// browser window's undo manager, so what is typed in the popup lands
    /// on the browser's stack.
    @available(macOS 15.4, *)
    func testClosedExtensionPopupLeavesNothingToUndo() throws {
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 680))
        window.contentView = anchor
        window.makeKeyAndOrderFront(nil)
        let browserUndo = try XCTUnwrap(window.undoManager)

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        web.navigationDelegate = navDelegate
        let stage = NSView(frame: web.frame)
        stage.addSubview(web)
        let host = NSViewController()
        host.view = stage
        let popover = NSPopover()
        popover.contentViewController = host
        popover.contentSize = stage.frame.size
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = ExtensionPopup.shared
        popover.show(relativeTo: NSRect(x: 100, y: 100, width: 1, height: 1), of: anchor, preferredEdge: .maxY)

        try type(into: web, "<textarea id=t autofocus></textarea>")
        XCTAssertTrue(browserUndo.canUndo, "the popup's typing must land on the browser's stack, or this proves nothing")

        popover.performClose(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(browserUndo.canUndo, "⌘Z in the browser would be aimed at the closed popup's page")
    }

    func testClosingATabLeavesNothingToUndo() throws {
        try leaves("close") { tab in tab.close() }
    }

    func testSleepingATabLeavesNothingToUndo() throws {
        try leaves("sleep") { tab in tab.sleep(picture: nil) }
    }

    func testATabOffStageThenClosedLeavesNothingToUndo() throws {
        try leaves("off stage, then close") { [self] tab in
            (window.contentView as? NSHostingView<AnyView>)?.rootView = AnyView(WebStage(page: nil))
            window.contentView?.layoutSubtreeIfNeeded()
            tab.close()
        }
    }

    func testATabTypedIntoAndClosedAtOnceLeavesNothingToUndo() throws {
        try leaves("typed, closed in the same turn") { tab in
            tab.web.evaluateJavaScript("document.execCommand('insertText', false, ' again')")
            tab.close()
        }
    }

    func testAStageDroppedBySwiftUILeavesNothingToUndo() throws {
        try leaves("stage dropped by SwiftUI") { [self] _ in
            (window.contentView as? NSHostingView<AnyView>)?.rootView = AnyView(Color.clear)
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    func testAClosedWindowLeavesNothingToUndo() throws {
        try leaves("window closed, then tab closed") { [self] tab in
            window.close()
            tab.close()
        }
    }

    // MARK: -

    /// A tab on the stage, typed into; `leave` takes it away; nothing may be
    /// left on the undo stack it typed into.
    private func leaves(_ name: String, _ leave: (BrowserTab) -> Void) throws {
        let tab = BrowserTab()
        tab.delegate = navDelegate
        let host = NSHostingView(rootView: AnyView(WebStage(page: tab.web)))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(tab.web.window === window, "the page must be on the stage")
        tab.go(to: URL(string: "data:text/html,<textarea id=t autofocus></textarea>")!)
        try type(into: tab.web, nil)
        let undo = try XCTUnwrap(tab.web.undoManager)
        XCTAssertTrue(undo.canUndo, "typing must register an undo, or this proves nothing")

        leave(tab)
        window.contentView = nil
        // Anything late from the page's process lands now.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(undo.canUndo, "\(name): ⌘Z would be aimed at the page that went")
    }

    /// Waits for the page, loading `html` first if given, then types into
    /// its textarea and waits for the edit to reach the undo stack.
    private func type(into web: WKWebView, _ html: String?) throws {
        if let html { web.loadHTMLString(html, baseURL: nil) }
        try waitUntil { self.navDelegate.finished }
        web.window?.makeFirstResponder(web)
        web.evaluateJavaScript("const t = document.getElementById('t'); t.focus(); document.execCommand('insertText', false, 'hello')")
        try waitUntil { web.undoManager?.canUndo == true }
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

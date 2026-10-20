import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class PageLengthTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "page-length-\(getpid())", 1)
        super.setUp()
    }

    private func makeHarness(width: CGFloat = 800, height: CGFloat = 600) -> (Tab, NSWindow) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let tab = Tab(bench: true)
        let web = tab.web
        web.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.orderFrontRegardless()
        return (tab, window)
    }

    private func waitForCondition(timeout: TimeInterval = 5, condition: () -> Bool) -> Bool {
        let limit = Date().addingTimeInterval(timeout)
        while Date() < limit {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    func testInitialPageLengthReport() throws {
        let (tab, window) = makeHarness(width: 800, height: 600)
        defer {
            window.close()
            tab.close()
        }

        let html = """
        <!doctype html>
        <html>
        <head><style>body { margin: 0; }</style></head>
        <body>
          <div id="content" style="height: 1800px;">Initial</div>
        </body>
        </html>
        """
        tab.web.loadHTMLString(html, baseURL: nil)

        let reported = waitForCondition {
            tab.screens != nil
        }
        XCTAssertTrue(reported, "Initial page length should be reported")
        if let screens = tab.screens {
            XCTAssertEqual(screens, 3.0, accuracy: 0.2)
        }
    }

    func testChangedDocumentHeightUpdatesPageLength() throws {
        let (tab, window) = makeHarness(width: 800, height: 600)
        defer {
            window.close()
            tab.close()
        }

        let html = """
        <!doctype html>
        <html>
        <head><style>body { margin: 0; }</style></head>
        <body>
          <div id="content" style="height: 1800px;">Initial</div>
        </body>
        </html>
        """
        tab.web.loadHTMLString(html, baseURL: nil)

        XCTAssertTrue(waitForCondition { tab.screens != nil })
        let initialScreens = tab.screens

        tab.web.evaluateJavaScript("document.getElementById('content').style.height = '3600px';")

        let updated = waitForCondition {
            tab.screens != initialScreens && tab.screens != nil
        }
        XCTAssertTrue(updated, "Page length should update when document height changes")
        if let screens = tab.screens {
            XCTAssertEqual(screens, 6.0, accuracy: 0.2)
        }
    }

    func testReadingProgressPerScrollPathAbsent() throws {
        let (tab, window) = makeHarness(width: 800, height: 600)
        defer {
            window.close()
            tab.close()
        }

        let html = """
        <!doctype html>
        <html>
        <head><style>body { margin: 0; }</style></head>
        <body>
          <div id="content" style="height: 2400px;">Long Content</div>
        </body>
        </html>
        """
        tab.web.loadHTMLString(html, baseURL: nil)

        XCTAssertTrue(waitForCondition { tab.screens != nil })
        let screensBeforeScroll = tab.screens

        XCTAssertFalse(
            ScrollRelay.script.contains("addEventListener('scroll'"),
            "ScrollRelay.script must not attach scroll listeners"
        )
        XCTAssertFalse(
            ScrollRelay.script.contains("scrollY"),
            "ScrollRelay.script must not inspect scroll position"
        )

        tab.web.evaluateJavaScript("window.scrollTo(0, 1000);")

        _ = waitForCondition(timeout: 0.3) { false }

        XCTAssertEqual(tab.screens, screensBeforeScroll)
    }
}

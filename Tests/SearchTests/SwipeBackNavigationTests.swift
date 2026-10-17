import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class SwipeBackNavigationTests: XCTestCase {
    private var window: NSWindow!

    override class func setUp() {
        setenv("SEARCH_PROBE", "swipe-back-\(getpid())", 1)
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
    }

    override func tearDown() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        super.tearDown()
    }

    func testBackForwardNavigationDoesNotTearDownUserScripts() throws {
        let browser = Browser(record: WindowRecord())
        let tab = try XCTUnwrap(browser.open(URL(string: "https://example.com/page1")!, foreground: true))
        window.contentView = tab.web

        let controller = tab.web.configuration.userContentController
        let customScript = WKUserScript(source: "console.log('test')", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(customScript)
        let initialScriptCount = controller.userScripts.count
        XCTAssertTrue(initialScriptCount > 0)

        // Simulate back/forward navigation action
        class BackForwardActionStub: WKNavigationAction {
            let req: URLRequest
            init(url: URL) {
                self.req = URLRequest(url: url)
                super.init()
            }
            override var request: URLRequest { req }
            override var targetFrame: WKFrameInfo? { nil }
            override var navigationType: WKNavigationType { .backForward }
        }

        let action = BackForwardActionStub(url: URL(string: "https://example.com/page2")!)
        var allowed = false

        browser.webView(
            tab.web,
            decidePolicyFor: action,
            preferences: WKWebpagePreferences()
        ) { policy, _ in
            allowed = policy == .allow
        }

        XCTAssertTrue(allowed)
        // On a .backForward swipe navigation, the controller's scripts must not be wiped out and re-added,
        // which invalidates WebKit's Back-Forward Cache (Page Cache) and causes 1-2s freezes.
        XCTAssertEqual(
            controller.userScripts.count,
            initialScriptCount,
            "Back/forward navigation must not re-arm and wipe user scripts on the controller"
        )
    }

    func testProcessPoolAndPreferencesEnableWebProcessCacheAndFastBackForwardLoading() throws {
        let pool = Web.pool
        if let poolConfig = pool.value(forKey: "_configuration") as? NSObject {
            let usesWebProcessCache = poolConfig.value(forKey: "usesWebProcessCache") as? Bool
            XCTAssertEqual(usesWebProcessCache, true, "WebKit must keep Web Process Cache enabled like Safari")
            let pageCacheEnabled = poolConfig.value(forKey: "pageCacheEnabled") as? Bool
            XCTAssertEqual(pageCacheEnabled, true, "WebKit must keep Page Cache enabled")
        }

        let config = Web.configuration()
        let uiLoading = config.preferences.value(forKey: "_useUIProcessForBackForwardItemLoading") as? Bool
        XCTAssertEqual(uiLoading, true, "UI process back forward item loading must be enabled")
    }
}

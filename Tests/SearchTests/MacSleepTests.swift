import AppKit
import WebKit
import XCTest
@testable import Search

/// When the Mac goes to sleep (NSWorkspace.willSleepNotification), background
/// tabs sleep immediately regardless of idle age. Tabs visible on screen (active
/// tab, split partner), tabs with active drafts under 1 hour, and exempt tabs
/// (audio, keep-awake, pins) remain awake.
@MainActor
final class MacSleepTests: XCTestCase {
    private var browser: Browser!
    private var secondBrowser: Browser?
    private var window: NSWindow!
    private let siteURL = URL(string: "https://macsleep.example.com/page")!

    private let formHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Mac Sleep Form</title></head>
    <body>
      <form>
        <input id="note" type="text" value="">
      </form>
    </body>
    </html>
    """

    override class func setUp() {
        setenv("SEARCH_PROBE", "macsleep-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        browser.prefs.sleepsTabs = true
        Store.settings.removeObject(forKey: SleepPace.key)
        Store.settings.removeObject(forKey: "sleep.after")
        Store.settings.removeObject(forKey: "tabs.keepAwake")
        Store.settings.removeObject(forKey: "sites.awake")
        browser.prefs.keepsSitesAwake = false
        browser.prefs.awakeSites = []
        window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        Store.settings.removeObject(forKey: SleepPace.key)
        Store.settings.removeObject(forKey: "sleep.after")
        Store.settings.removeObject(forKey: "tabs.keepAwake")
        Store.settings.removeObject(forKey: "sites.awake")
        window?.orderOut(nil)
        window?.close()
        window = nil
        secondBrowser?.parked = [:]
        secondBrowser?.closeAll()
        secondBrowser = nil
        browser?.parked = [:]
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    private func makePage(in b: Browser? = nil, html: String = "", foreground: Bool = false) throws -> Tab {
        let target = b ?? browser!
        let tab = target.open(URL(string: "about:blank")!, foreground: foreground)
        tab.setAddressOptimistically(siteURL)
        window.contentView = tab.web
        tab.web.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        let marker = UUID().uuidString
        let pageHTML = (html.isEmpty ? formHTML : html)
            + "<script>window.macSleepFixtureReady = '\(marker)'</script>"
        tab.web.loadHTMLString(pageHTML, baseURL: siteURL)
        var documentReady = false
        try waitUntil {
            guard !tab.web.isLoading else { return false }
            tab.web.evaluateJavaScript("window.macSleepFixtureReady === '\(marker)'") { value, _ in
                documentReady = value as? Bool == true
            }
            return documentReady
        }
        tab.setAddressOptimistically(siteURL)
        var formsReady = false
        tab.web.evaluateInSearch("!!window.__officeForms") { result in
            formsReady = result as? Bool == true
        }
        try waitUntil { formsReady && !tab.loading }
        return tab
    }

    private func typeInput(in tab: Tab, id: String = "note", text: String = "saved draft text") throws {
        window.makeFirstResponder(tab.web)
        var typedDone = false
        tab.web.evaluateJavaScript("""
        (function() {
            var el = document.getElementById('\(id)');
            el.focus();
            document.execCommand('insertText', false, '\(text)');
            return true;
        })()
        """) { _, _ in
            typedDone = true
        }
        try waitUntil { typedDone }

        var isUnsaved = false
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && !isUnsaved {
            tab.unsaved { isUnsaved = $0 }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        if !isUnsaved {
            for char in text {
                if let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: String(char),
                    charactersIgnoringModifiers: String(char),
                    isARepeat: false,
                    keyCode: 0
                ) {
                    window.sendEvent(event)
                }
            }
            try waitUntil(timeout: 5) {
                var checked = false
                tab.unsaved { isUnsaved = $0; checked = true }
                while !checked {
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
                }
                return isUnsaved
            }
        }
        XCTAssertTrue(isUnsaved, "FormRelay must track the typed draft as unsaved")
    }

    private func pump(duration: TimeInterval = 0.3) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        XCTFail("Timed out waiting for condition")
        throw WaitError.timedOut
    }

    private enum WaitError: Error { case timedOut }

    func testMacSleepPutsBackgroundTabsToSleepImmediately() throws {
        let bgTab = try makePage()
        let activeTab = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        XCTAssertFalse(bgTab.asleep)
        XCTAssertNotNil(bgTab.built)
        XCTAssertFalse(activeTab.asleep)
        XCTAssertNotNil(activeTab.built)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try waitUntil { bgTab.asleep }

        XCTAssertTrue(bgTab.asleep, "Background tab must be put to sleep on Mac sleep notification")
        XCTAssertNil(bgTab.built, "Sleeping tab must discard its web view")
        XCTAssertFalse(activeTab.asleep, "Active tab on screen must stay awake")
        XCTAssertNotNil(activeTab.built)
    }

    func testMacSleepPreservesVisibleSplitPartner() throws {
        browser.prefs.splitView = true
        let leftTab = try makePage()
        let rightTab = try makePage()
        let bgTab = try makePage()

        browser.showRow(browser.tabs, active: leftTab.id, splits: [
            TabSplit(tabs: [leftTab.id, rightTab.id], focused: leftTab.id)
        ])

        XCTAssertEqual(browser.visibleTabIDs, Set([leftTab.id, rightTab.id]))
        XCTAssertFalse(bgTab.asleep)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try waitUntil { bgTab.asleep }

        XCTAssertTrue(bgTab.asleep, "Background tab must sleep")
        XCTAssertNil(bgTab.built)
        XCTAssertFalse(leftTab.asleep, "Left tab of visible split must stay awake")
        XCTAssertNotNil(leftTab.built)
        XCTAssertFalse(rightTab.asleep, "Right tab of visible split must stay awake")
        XCTAssertNotNil(rightTab.built)
    }

    func testMacSleepProtectsDraftBeforeThreshold() throws {
        let plainBgTab = try makePage()
        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "note", text: "Protected draft text")
        let activeTab = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        let base = Date()
        // 5 minutes idle: under 1h draft threshold
        draftTab.touch(at: base.addingTimeInterval(-300))

        XCTAssertFalse(plainBgTab.asleep)
        XCTAssertFalse(draftTab.asleep)
        XCTAssertFalse(activeTab.asleep)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try waitUntil { plainBgTab.asleep }

        XCTAssertTrue(plainBgTab.asleep, "Plain background tab must sleep on Mac sleep notification")
        XCTAssertNil(plainBgTab.built)
        XCTAssertFalse(draftTab.asleep, "Draft tab under 1 hour must stay awake on Mac sleep")
        XCTAssertNotNil(draftTab.built)
        XCTAssertFalse(activeTab.asleep)
    }

    func testMacSleepDiscardsDraftAfterThreshold() throws {
        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "note", text: "Stale draft text")
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        let base = Date()
        // Over 1 hour idle (3660 seconds)
        draftTab.touch(at: base.addingTimeInterval(-3660))

        XCTAssertFalse(draftTab.asleep)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try waitUntil { draftTab.asleep }

        XCTAssertTrue(draftTab.asleep, "Draft tab past 1 hour threshold must sleep on Mac sleep")
        XCTAssertNil(draftTab.built)
    }

    func testMacSleepPreservesExemptions() throws {
        let noisyTab = try makePage()
        noisyTab.noisy = true

        let activePin = try makePage()
        activePin.pin = "P"

        let keepAwakeURL = URL(string: "https://keepawake.example.com/page")!
        let keepAwakeTab = try makePage()
        keepAwakeTab.setAddressOptimistically(keepAwakeURL)
        browser.prefs.keepsSitesAwake = true
        browser.keepAwake(true, for: keepAwakeTab)

        let bgTab = try makePage()
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try waitUntil { bgTab.asleep }

        XCTAssertTrue(bgTab.asleep, "Background tab must sleep")
        XCTAssertFalse(noisyTab.asleep, "Audio playing tab must stay awake")
        XCTAssertNotNil(noisyTab.built)
        XCTAssertFalse(activePin.asleep, "Pin in active space must stay awake")
        XCTAssertNotNil(activePin.built)
        XCTAssertFalse(keepAwakeTab.asleep, "Kept awake tab must stay awake")
        XCTAssertNotNil(keepAwakeTab.built)
    }

    func testMacSleepAcrossMultipleWindows() throws {
        secondBrowser = Browser(record: WindowRecord())
        secondBrowser?.prefs.sleepsTabs = true

        let bg1 = try makePage(in: browser)
        let active1 = try makePage(in: browser, html: "<html><body><h1>Window 1 Active</h1></body></html>", foreground: true)

        let bg2 = try makePage(in: secondBrowser!)
        let active2 = try makePage(in: secondBrowser!, html: "<html><body><h1>Window 2 Active</h1></body></html>", foreground: true)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try waitUntil { bg1.asleep && bg2.asleep }

        XCTAssertTrue(bg1.asleep, "Window 1 background tab must sleep")
        XCTAssertTrue(bg2.asleep, "Window 2 background tab must sleep")
        XCTAssertNil(bg1.built)
        XCTAssertNil(bg2.built)
        XCTAssertFalse(active1.asleep, "Window 1 active tab must stay awake")
        XCTAssertFalse(active2.asleep, "Window 2 active tab must stay awake")
    }
}

import AppKit
import WebKit
import XCTest
@testable import Search

/// Automatic draft discard permission applies only when idle age is at least
/// max(Browser.sleepAfter, 3600 seconds). Until that threshold, detected typed
/// drafts block sleep. Pinned, on-screen, and kept-awake tabs remain awake.
@MainActor
final class DraftSleepTests: XCTestCase {
    private var browser: Browser!
    private var window: NSWindow!
    private let siteURL = URL(string: "https://drafts.example.com/page")!

    private let formHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Draft Form</title></head>
    <body>
      <form>
        <input id="note" type="text" value="">
        <textarea id="comment"></textarea>
      </form>
    </body>
    </html>
    """

    override class func setUp() {
        setenv("SEARCH_PROBE", "gh-draftsleep-\(getpid())", 1)
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
        browser?.parked = [:]
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    private func makePage(html: String = "", foreground: Bool = false) throws -> Tab {
        let tab = browser.open(URL(string: "about:blank")!, foreground: foreground)
        tab.setAddressOptimistically(siteURL)
        window.contentView = tab.web
        tab.web.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        let marker = UUID().uuidString
        let pageHTML = (html.isEmpty ? formHTML : html)
            + "<script>window.draftFixtureReady = '\(marker)'</script>"
        tab.web.loadHTMLString(pageHTML, baseURL: siteURL)
        var documentReady = false
        try waitUntil {
            guard !tab.web.isLoading else { return false }
            tab.web.evaluateJavaScript("window.draftFixtureReady === '\(marker)'") { value, _ in
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

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        XCTFail("Timed out waiting for condition")
        throw WaitError.timedOut
    }

    private enum WaitError: Error { case timedOut }

    func testTypedDraftProtectedBeforeThreshold() throws {
        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "note", text: "Important unsaved note")
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        let base = Date()
        // 59 minutes idle (3540 seconds): past normal 30m wait, but under 1h draft threshold
        draftTab.touch(at: base.addingTimeInterval(-3540))

        XCTAssertFalse(draftTab.asleep)
        XCTAssertNotNil(draftTab.built)

        browser.sleepIdle(now: base)
        pump(duration: 0.3)

        XCTAssertFalse(draftTab.asleep, "Typed draft must be protected before 1 hour threshold")
        XCTAssertNotNil(draftTab.built, "Web view must not be discarded before threshold")
    }

    func testTypedDraftDiscardedAfterThreshold() throws {
        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "note", text: "Stale draft to discard")
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        let base = Date()
        // At or past 1 hour threshold (3600 seconds)
        draftTab.touch(at: base.addingTimeInterval(-3605))

        XCTAssertFalse(draftTab.asleep)

        browser.sleepIdle(now: base)
        try waitUntil { draftTab.asleep }

        XCTAssertTrue(draftTab.asleep, "Typed draft must be discarded after 1 hour idle threshold")
        XCTAssertNil(draftTab.built, "Sleeping tab must discard its web view")
    }

    func testLaterPacePreservesDraftThroughOneHourAndAllowsAfterTwoHours() throws {
        Store.settings.set(SleepPace.later.rawValue, forKey: SleepPace.key)
        XCTAssertEqual(Browser.sleepAfter, 7200)
        XCTAssertEqual(Browser.draftSleepAfter, 7200)

        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "comment", text: "Later pace draft")
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        let base = Date()

        // At 1 hour (3600 seconds): Later pace must still preserve the draft
        draftTab.touch(at: base.addingTimeInterval(-3600))
        browser.sleepIdle(now: base)
        pump(duration: 0.3)
        XCTAssertFalse(draftTab.asleep, "Later pace must preserve draft through 1 hour")
        XCTAssertNotNil(draftTab.built)

        // At 1 hour 50 minutes (6600 seconds): still preserved
        draftTab.touch(at: base.addingTimeInterval(-6600))
        browser.sleepIdle(now: base)
        pump(duration: 0.3)
        XCTAssertFalse(draftTab.asleep, "Later pace must preserve draft until 2 hours")

        // At 2 hours (7200 seconds): threshold reached, allowed to sleep
        draftTab.touch(at: base.addingTimeInterval(-7205))
        browser.sleepIdle(now: base)
        try waitUntil { draftTab.asleep }
        XCTAssertTrue(draftTab.asleep, "Later pace allows sleep after 2 hours")
        XCTAssertNil(draftTab.built)
    }

    func testActiveTabWithDraftRemainsAwakeEvenAfterThreshold() throws {
        let tab = try makePage(foreground: true)
        try typeInput(in: tab, id: "note", text: "Active tab content")

        let base = Date()
        // Touched 2 hours ago, but is currently active on screen
        tab.touch(at: base.addingTimeInterval(-7200))

        browser.sleepIdle(now: base)
        pump(duration: 0.3)

        XCTAssertFalse(tab.asleep, "Active tab on screen must remain awake even after threshold")
        XCTAssertNotNil(tab.built)
    }

    func testKeptAwakeTabWithDraftRemainsAwakeEvenAfterThreshold() throws {
        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "note", text: "Kept awake draft")
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        browser.prefs.keepsSitesAwake = true
        browser.keepAwake(true, for: draftTab)
        XCTAssertEqual(browser.busy(draftTab), "kept awake for this site")

        let base = Date()
        draftTab.touch(at: base.addingTimeInterval(-7200))

        browser.sleepIdle(now: base)
        pump(duration: 0.3)

        XCTAssertFalse(draftTab.asleep, "Kept-awake tab must remain awake even after threshold")
        XCTAssertNotNil(draftTab.built)
    }

    func testNonDraftNormalSleepUnchanged() throws {
        let normalTab = try makePage()
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        var isUnsaved: Bool?
        normalTab.unsaved { isUnsaved = $0 }
        try waitUntil { isUnsaved != nil }
        XCTAssertEqual(isUnsaved, false, "Untouched field must not report unsaved")

        let base = Date()
        // 15 minutes idle: under normal 30m wait, tab stays awake
        normalTab.touch(at: base.addingTimeInterval(-900))
        browser.sleepIdle(now: base)
        pump(duration: 0.3)
        XCTAssertFalse(normalTab.asleep, "Normal tab must stay awake before 30m wait")

        // 30 minutes idle: normal sleep delay reached, tab sleeps without waiting 1 hour
        normalTab.touch(at: base.addingTimeInterval(-1805))
        browser.sleepIdle(now: base)
        try waitUntil { normalTab.asleep }
        XCTAssertTrue(normalTab.asleep, "Normal non-draft tab sleeps at normal wait")
        XCTAssertNil(normalTab.built)
    }

    func testTabUsedAgainDuringSleepCheckStaysAwake() throws {
        let tab = try makePage()
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)
        let now = Date()
        tab.touch(at: now.addingTimeInterval(-7205))

        browser.sleepIdle(now: now)
        browser.select(tab)
        pump(duration: 0.5)

        XCTAssertFalse(tab.asleep, "A pending sleep check must not discard a tab used again")
        XCTAssertNotNil(tab.built)
    }

    func testMemoryPressureDiscardsNonDraftImmediatelyButProtectsDraft() throws {
        let draftTab = try makePage()
        try typeInput(in: draftTab, id: "note", text: "Protected draft under memory pressure")

        let normalTab = try makePage()
        _ = try makePage(html: "<html><body><h1>Active</h1></body></html>", foreground: true)

        let base = Date()
        // Both tabs idle for 5 minutes (300 seconds)
        draftTab.touch(at: base.addingTimeInterval(-300))
        normalTab.touch(at: base.addingTimeInterval(-300))

        // Critical memory pressure
        browser.sleepIdle(within: 0, now: base)

        // Non-draft tab sleeps immediately under memory pressure
        try waitUntil { normalTab.asleep }
        XCTAssertTrue(normalTab.asleep, "Non-draft tab must sleep under memory pressure")

        // Draft tab stays protected because idle age is under 1 hour
        pump(duration: 0.3)
        XCTAssertFalse(draftTab.asleep, "Draft tab must remain protected under memory pressure")
        XCTAssertNotNil(draftTab.built)
    }
}

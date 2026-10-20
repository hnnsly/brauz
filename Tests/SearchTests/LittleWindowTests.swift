import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class LittleWindowTests: XCTestCase {
    private var browser: Browser!
    private var fixture: LocalDownloadServer!
    private var savedUsesSpaces = false

    override class func setUp() {
        setenv("SEARCH_PROBE", "little-window-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        savedUsesSpaces = Shared.prefs.usesSpaces
        Shared.prefs.usesSpaces = true

        browser = Browser(record: WindowRecord())
        browser.prefs.usesSpaces = true
        browser.prefs.popupSites = []

        do {
            fixture = try LocalDownloadServer()
        } catch {
            XCTFail("Failed to start LocalDownloadServer: \(error)")
        }
    }

    override func tearDown() {
        for little in LittleWindow.all {
            little.close()
        }

        browser?.closeAll()
        browser = nil

        fixture?.stop()
        fixture = nil

        Ask.testing = nil
        Shared.prefs.usesSpaces = savedUsesSpaces

        super.tearDown()
    }

    // MARK: - Synchronous RunLoop helpers

    private func pump(_ duration: TimeInterval = 0.05) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
    }

    private func waitUntil(timeout: TimeInterval = 10, condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        if condition() { return }
        XCTFail("Timed out waiting for condition")
        throw WaitError.timedOut
    }

    private enum WaitError: Error {
        case timedOut
    }

    private func evaluateJS(_ script: String, in web: WKWebView, timeout: TimeInterval = 5) -> Any? {
        var done = false
        var output: Any?
        web.evaluateJavaScript(script) { result, _ in
            output = result
            done = true
        }
        let limit = Date().addingTimeInterval(timeout)
        while !done && Date() < limit {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return output
    }

    private func waitForFixtureReady(_ tab: Tab, timeout: TimeInterval = 10) throws {
        try waitUntil(timeout: timeout) {
            guard !tab.web.isLoading else { return false }
            return (self.evaluateJS("window.fixtureReady === true", in: tab.web) as? Bool) == true
        }
    }

    // MARK: - Test Cases

    /// (1) Ordinary #next navigation commits history and actual back() returns.
    func testOrdinaryNextNavigationCommitsHistoryAndBackReturns() throws {
        let url = fixture.url("/little-one")
        LittleWindow.show(url, for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)
        XCTAssertEqual(little.tab.pageAddress?.path, "/little-one")

        _ = evaluateJS("document.getElementById('next').click()", in: little.tab.web)
        try waitUntil {
            little.tab.pageAddress?.path == "/little-two" &&
            (self.evaluateJS("window.fixtureReady === true", in: little.tab.web) as? Bool) == true &&
            little.tab.canGoBack
        }
        XCTAssertTrue(little.tab.canGoBack)

        little.tab.back()
        try waitUntil {
            little.tab.pageAddress?.path == "/little-one" &&
            (self.evaluateJS("window.fixtureReady === true", in: little.tab.web) as? Bool) == true
        }
        XCTAssertEqual(little.tab.pageAddress?.path, "/little-one")
    }

    /// (2) target_blank stays in Little and main tab count unchanged, with real WK source frame:
    /// record popupGesture origin for loopback then evaluate actual #blank.click;
    /// permit WK automatic-window gate if needed to reach Browser's blocker, never bypass Browser checks.
    func testTargetBlankStaysInLittleAndMainTabCountUnchanged() throws {
        let initialTabCount = browser.tabs.count
        let url = fixture.url("/little-one")
        LittleWindow.show(url, for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)

        little.tab.web.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let origin = PopupGesture.originKey(scheme: "http", host: "127.0.0.1", port: Int(fixture.port))
        little.tab.popupGesture.record(origin: origin, kind: "input")

        _ = evaluateJS("document.getElementById('blank').click()", in: little.tab.web)
        try waitUntil {
            little.tab.pageAddress?.path == "/little-two" &&
            (self.evaluateJS("window.fixtureReady === true", in: little.tab.web) as? Bool) == true
        }

        XCTAssertEqual(browser.tabs.count, initialTabCount, "Main tab count must remain unchanged")
        XCTAssertEqual(little.tab.pageAddress?.path, "/little-two", "target_blank must navigate within Little window")
    }

    /// (3) No-gesture popup rejected and real dimensioned JS popup returns separate
    /// main-browser context under recorded gesture, original Little remains.
    func testPopupRejectionWithoutGestureAndOpeningWithRecordedGesture() throws {
        let initialTabCount = browser.tabs.count
        let url = fixture.url("/little-one")
        LittleWindow.show(url, for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)

        little.tab.web.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Part A: No gesture popup rejected
        little.tab.popupGesture.clear()
        _ = evaluateJS("document.getElementById('popup').click()", in: little.tab.web)
        pump(0.3)
        XCTAssertEqual(browser.tabs.count, initialTabCount, "Main tab count must not increase for ungranted popup")
        XCTAssertFalse(little.tab.blockedPopups.isEmpty, "Opener tab must note blocked popup")

        // Part B: Recorded gesture popup opens dimensioned tab in main browser
        let origin = PopupGesture.originKey(scheme: "http", host: "127.0.0.1", port: Int(fixture.port))
        little.tab.popupGesture.record(origin: origin, kind: "input")
        _ = evaluateJS("document.getElementById('popup').click()", in: little.tab.web)

        try waitUntil { self.browser.tabs.count == initialTabCount + 1 }
        let popupTab = try XCTUnwrap(browser.tabs.first { $0.opener == little.tab.id })
        XCTAssertTrue(popupTab.popup, "Created tab must be marked as popup")
        XCTAssertTrue(popupTab.web !== little.tab.web)
        XCTAssertEqual(little.tab.pageAddress?.path, "/little-one")
        XCTAssertTrue(LittleWindow.all.contains(where: { $0 === little }), "Original Little window must remain")
    }

    /// (4) Two stores set distinct loopback cookies via httpCookieStore, switchSpace
    /// and verify new actual request Cookie + tab.store identity.
    func testTwoStoresSetDistinctCookiesAndSwitchSpacePreservesCookieAndStoreIdentity() throws {
        let space1 = Space(id: UUID(), name: "Space 1", colour: 0)
        let space2 = Space(id: UUID(), name: "Space 2", colour: 1)
        browser.spaces = [space1, space2]
        browser.spaceID = space1.id

        let store1 = Spaces.store(for: space1.id)
        let store2 = Spaces.store(for: space2.id)
        XCTAssertTrue(store1 !== store2, "Spaces must have distinct data stores")

        let cookie1 = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: "space_session",
            .value: "store_one_\(UUID().uuidString)",
        ]))
        let cookie2 = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: "space_session",
            .value: "store_two_\(UUID().uuidString)",
        ]))

        var set1 = false
        store1.httpCookieStore.setCookie(cookie1) { set1 = true }
        try waitUntil { set1 }

        var set2 = false
        store2.httpCookieStore.setCookie(cookie2) { set2 = true }
        try waitUntil { set2 }

        LittleWindow.show(fixture.url("/little-one"), for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)

        XCTAssertTrue(little.tab.store === store1)
        XCTAssertEqual(little.spaceID, space1.id)

        let initialCookies = fixture.cookies("/little-one")
        XCTAssertTrue(initialCookies.contains { $0?.contains(cookie1.value) == true })

        little.switchSpace(to: space2.id)
        try waitUntil { little.spaceID == space2.id && little.tab.store === store2 }
        try waitForFixtureReady(little.tab)

        XCTAssertTrue(little.tab.store === store2, "tab.store identity must match store2")
        let updatedCookies = fixture.cookies("/little-one")
        XCTAssertTrue(updatedCookies.last??.contains(cookie2.value) == true, "Latest request must contain cookie2 from store2")
    }

    /// (5) Real textarea input/execCommand makes tab.unsaved true, Ask.testing=false
    /// cancel keeps same selectedID/store/page. Ensure callback processed using
    /// subsequent JS completion barrier, not an immediate assertion before async work.
    func testUnsavedTextareaCancelsSpaceSwitchWithAskTestingFalse() throws {
        let space1 = Space(id: UUID(), name: "Space 1", colour: 0)
        let space2 = Space(id: UUID(), name: "Space 2", colour: 1)
        browser.spaces = [space1, space2]
        browser.spaceID = space1.id
        let store1 = Spaces.store(for: space1.id)

        LittleWindow.show(fixture.url("/little-one"), for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)
        var formsReady = false
        little.tab.web.evaluateInSearch("!!window.__officeForms") { formsReady = $0 as? Bool == true }
        try waitUntil { formsReady }

        _ = evaluateJS("""
        (function() {
            var el = document.getElementById('draft');
            el.focus();
            document.execCommand('insertText', false, 'unsaved form content');
            return true;
        })()
        """, in: little.tab.web)

        try waitUntil {
            var isUnsaved = false
            var checked = false
            little.tab.unsaved {
                isUnsaved = $0
                checked = true
            }
            while !checked {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            return isUnsaved
        }

        Ask.testing = false
        little.switchSpace(to: space2.id)

        var barrierDone = false
        little.tab.web.evaluateJavaScript("1 + 1") { _, _ in
            barrierDone = true
        }
        try waitUntil { barrierDone }
        pump(0.1)

        XCTAssertEqual(little.spaceID, space1.id, "Cancel must keep same selected space ID")
        XCTAssertTrue(little.tab.store === store1, "Cancel must keep same store")
        XCTAssertEqual(little.tab.pageAddress?.path, "/little-one", "Cancel must keep same page")
    }

    /// (6) Shared-signin target same store preserves DOM token/document.
    func testSharedSignInTargetSameStorePreservesDOMTokenAndDocument() throws {
        let space1 = Space(id: Space.firstID, name: "First", colour: 0)
        let sharedSpace = Space(id: UUID(), name: "Shared", colour: 1, sharesSignIns: true)
        browser.spaces = [space1, sharedSpace]
        browser.spaceID = space1.id

        LittleWindow.show(fixture.url("/little-one"), for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)

        _ = evaluateJS("window.__testDOMToken = 'dom-token-preserve-42'; document.title = 'DOM Preserved';", in: little.tab.web)
        XCTAssertEqual(evaluateJS("window.__testDOMToken", in: little.tab.web) as? String, "dom-token-preserve-42")

        little.switchSpace(to: sharedSpace.id)
        pump(0.1)

        XCTAssertEqual(little.spaceID, sharedSpace.id)
        XCTAssertTrue(little.tab.store === Spaces.store(for: sharedSpace.id))
        XCTAssertEqual(evaluateJS("window.__testDOMToken", in: little.tab.web) as? String, "dom-token-preserve-42")
        XCTAssertEqual(evaluateJS("document.title", in: little.tab.web) as? String, "DOM Preserved")
    }

    /// (7) keep(in:) switches destination browser to selected space and receives same tab.
    func testKeepInDestinationSwitchesSpaceAndReceivesSameTab() throws {
        let destBrowser = Browser(record: WindowRecord())
        let space1 = Space(id: UUID(), name: "Space 1", colour: 0)
        let space2 = Space(id: UUID(), name: "Space 2", colour: 1)
        destBrowser.spaces = [space1, space2]
        destBrowser.prefs.usesSpaces = true
        destBrowser.spaceID = space1.id

        LittleWindow.show(fixture.url("/little-one"), for: destBrowser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        little.switchSpace(to: space2.id)
        try waitForFixtureReady(little.tab)
        XCTAssertEqual(little.spaceID, space2.id)

        let littleTab = little.tab
        little.keep(in: destBrowser)
        pump(0.1)

        XCTAssertEqual(destBrowser.spaceID, space2.id, "Destination browser must switch to selected space")
        XCTAssertTrue(destBrowser.tabs.contains(where: { $0 === littleTab }), "Destination browser must receive the same tab")
        XCTAssertFalse(LittleWindow.all.contains(where: { $0 === little }), "Little window must close after keep")

        destBrowser.closeAll()
    }

    /// (8) Notification Spaces.changed removing current selection MUST NOT silently change LittleAddress.spaceID.
    /// Intentionally catches primary review finding still present in LittleExtras.swift.
    func testSpacesChangedRemovingCurrentSelectionMustNotSilentlyChangeSpaceID() throws {
        let selectedID = UUID()
        let otherSpace = Space(id: UUID(), name: "Other", colour: 0)
        let address = LittleAddress(spaceID: selectedID, spaces: [Space(id: selectedID, name: "Selected", colour: 1), otherSpace])
        XCTAssertEqual(address.spaceID, selectedID)

        NotificationCenter.default.post(name: Spaces.changed, object: [otherSpace])
        pump(0.1)

        XCTAssertEqual(address.spaceID, selectedID, "Spaces.changed removing current selection MUST NOT silently change LittleAddress.spaceID")
    }

    /// (9) keep with missing selected destination must leave Little open and not transfer into fallback space.
    /// Intentionally catches primary review finding still present in Little.swift.
    func testKeepWithMissingSelectedDestinationLeavesLittleOpenAndDoesNotTransferToFallback() throws {
        let destBrowser = Browser(record: WindowRecord())
        let destSpace = Space(id: UUID(), name: "Dest Space", colour: 0)
        destBrowser.spaces = [destSpace]
        destBrowser.prefs.usesSpaces = true
        destBrowser.spaceID = destSpace.id
        let initialTabCount = destBrowser.tabs.count

        LittleWindow.show(fixture.url("/little-one"), for: destBrowser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        try waitForFixtureReady(little.tab)

        let missingSpaceID = UUID()
        little.address.spaceID = missingSpaceID

        little.keep(in: destBrowser)
        pump(0.1)

        XCTAssertTrue(LittleWindow.all.contains(where: { $0 === little }), "Little window must remain open when selected destination space is missing")
        XCTAssertFalse(destBrowser.tabs.contains(where: { $0 === little.tab }), "Must not transfer into fallback space when selected destination space is missing")
        XCTAssertEqual(destBrowser.tabs.count, initialTabCount, "Destination browser tab count must remain unchanged")

        destBrowser.closeAll()
    }
}

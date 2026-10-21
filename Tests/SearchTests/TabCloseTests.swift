import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class TabCloseTests: XCTestCase {
    private var browser: Browser!
    private var oldSplitView: Bool!
    private var oldNewTabAfterLast: Bool!
    private var oldPins: [UUID: [PinDef]] = [:]
    private var oldSharedPins: [PinDef] = []

    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-close-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        Pins.load()
        oldPins = Pins.bySpace
        oldSharedPins = Pins.shared
        oldSplitView = browser.prefs.splitView
        oldNewTabAfterLast = browser.prefs.newTabAfterLast
        browser.prefs.splitView = false
        browser.prefs.newTabAfterLast = false
        browser.closeAll()
    }

    override func tearDown() {
        browser?.closeAll()
        if let browser {
            for space in Set(Pins.bySpace.keys).union(oldPins.keys) {
                Pins.set(space, oldPins[space] ?? [], from: browser)
            }
            Pins.setShared(oldSharedPins, from: browser)
        }
        if let oldSplitView { browser?.prefs.splitView = oldSplitView }
        if let oldNewTabAfterLast { browser?.prefs.newTabAfterLast = oldNewTabAfterLast }
        browser = nil
        super.tearDown()
    }

    private func makeFixture() -> (tabA: Tab, tabB: Tab, tabC: Tab) {
        let a = Tab(configuration: Web.configuration(space: browser.spaceID))
        a.restore(url: URL(string: "about:blank#A")!, title: "A")
        let b = Tab(configuration: Web.configuration(space: browser.spaceID))
        b.restore(url: URL(string: "about:blank#B")!, title: "B")
        let c = Tab(configuration: Web.configuration(space: browser.spaceID))
        c.restore(url: URL(string: "about:blank#C")!, title: "C")
        let row = [a, b, c]
        browser.showRow(row, active: c.id)
        return (a, b, c)
    }

    func testClosingCurrentReturnsToLastViewedNotNeighbour() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        browser.close(c)
        XCTAssertEqual(browser.activeID, a.id, "Expected A last viewed, B sidebar neighbour")
    }

    func testSwitcherAlreadyOrdersLastViewedBeforeNeighbour() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        let ordered = browser.tabSwitcher.ordered(row: browser.tabs.map(\.id), current: browser.activeID)
        XCTAssertEqual(ordered, [c.id, a.id, b.id])
    }

    func testClosingBackgroundLeavesCurrentSelected() {
        let (a, _, c) = makeFixture()
        browser.select(a)
        browser.select(c)
        browser.close(a)
        XCTAssertEqual(browser.activeID, c.id)
        XCTAssertFalse(browser.tabs.contains { $0.id == a.id })
    }

    func testRecencyCandidatesExcludeRemovedTabs() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        browser.close(a)
        let ordered = browser.tabSwitcher.ordered(row: browser.tabs.map(\.id), current: browser.activeID)
        XCTAssertEqual(ordered, [c.id, b.id])
        XCTAssertFalse(ordered.contains(a.id))
    }

    func testRecencyCandidatesExcludeTabsOutsideCurrentRow() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        let oldRow = browser.tabs
        browser.parked[UUID()] = Parked(tabs: oldRow, active: c.id)

        let d = Tab(configuration: Web.configuration(space: browser.spaceID))
        d.restore(url: URL(string: "about:blank#D")!, title: "D")
        let e = Tab(configuration: Web.configuration(space: browser.spaceID))
        e.restore(url: URL(string: "about:blank#E")!, title: "E")
        let f = Tab(configuration: Web.configuration(space: browser.spaceID))
        f.restore(url: URL(string: "about:blank#F")!, title: "F")
        let newRow = [d, e, f]
        browser.showRow(newRow, active: f.id)

        let ordered = browser.tabSwitcher.ordered(row: browser.tabs.map(\.id), current: browser.activeID)
        let oldIDs = Set(oldRow.map(\.id))
        let currentIDs = Set(newRow.map(\.id))
        XCTAssertTrue(ordered.allSatisfy { currentIDs.contains($0) })
        XCTAssertTrue(ordered.allSatisfy { !oldIDs.contains($0) })
    }

    func testClosingFocusedSplitKeepsOtherPane() {
        browser.prefs.splitView = true
        let (a, b, c) = makeFixture()
        browser.pair(b, with: a, onLeft: false)
        browser.select(c)
        browser.select(b)
        browser.close(b)
        XCTAssertEqual(browser.activeID, a.id)
        XCTAssertNil(browser.activeSplit)
    }

    func testClosingCurrentWakesSleepingReplacement() {
        let (_, b, c) = makeFixture()
        browser.select(c)
        XCTAssertTrue(b.asleep)
        browser.close(c)
        XCTAssertEqual(browser.activeID, b.id)
        XCTAssertFalse(b.asleep)
        XCTAssertNotNil(b.built)
    }

    func testSuccessiveClosesFollowViewingHistory() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        browser.close(c)
        XCTAssertEqual(browser.activeID, a.id)
        browser.close(a)
        XCTAssertEqual(browser.activeID, b.id)
        XCTAssertFalse(browser.tabs.contains { $0.id == c.id })
        XCTAssertFalse(browser.tabs.contains { $0.id == a.id })
    }

    func testClosingRecentTabInBackgroundBypassesItOnSubsequentClose() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        browser.close(a)
        XCTAssertEqual(browser.activeID, c.id)
        browser.close(c)
        XCTAssertEqual(browser.activeID, b.id)
        XCTAssertFalse(browser.tabs.contains { $0.id == a.id })
        XCTAssertFalse(browser.tabs.contains { $0.id == c.id })
    }

    func testMovingTabInRowPreservesRecencyOrderOnClose() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        browser.move(c, to: 1)
        XCTAssertEqual(browser.tabs.map(\.id), [a.id, c.id, b.id])
        browser.close(c)
        XCTAssertEqual(browser.activeID, a.id)
    }

    func testNoHistoryClosingMiddleTabSelectsRightNeighbour() {
        let (_, b, c) = makeFixture()
        browser.select(b)
        browser.tabSwitcher.reset()
        browser.close(b)
        XCTAssertEqual(browser.activeID, c.id)
    }

    func testNoHistoryClosingLastTabSelectsLeftNeighbour() {
        let (_, b, c) = makeFixture()
        browser.select(c)
        browser.tabSwitcher.reset()
        browser.close(c)
        XCTAssertEqual(browser.activeID, b.id)
    }

    func testClosingCurrentWakesSleepingMostRecentTab() {
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)
        a.rest()
        XCTAssertTrue(a.asleep)
        browser.close(c)
        XCTAssertEqual(browser.activeID, a.id)
        XCTAssertFalse(a.asleep)
        XCTAssertNotNil(a.built)
    }

    func testClosingCurrentAfterSpaceSwitchReturnsToSpaceMRU() {
        let oldUsesSpaces = browser.prefs.usesSpaces
        let oldSpaces = browser.spaces
        defer {
            browser.prefs.usesSpaces = oldUsesSpaces
            browser.spaces = oldSpaces
        }
        browser.prefs.usesSpaces = true
        let firstID = browser.spaceID
        let firstSpace = Space(id: firstID, name: "First", colour: 0)
        let secondID = UUID()
        let secondSpace = Space(id: secondID, name: "Second", colour: 1)
        browser.spaces = [firstSpace, secondSpace]

        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)

        browser.switchSpace(to: secondID)
        let d = Tab(configuration: Web.configuration(space: browser.spaceID))
        d.restore(url: URL(string: "about:blank#D")!, title: "D")
        let e = Tab(configuration: Web.configuration(space: browser.spaceID))
        e.restore(url: URL(string: "about:blank#E")!, title: "E")
        browser.showRow([d, e], active: d.id)
        browser.select(e)
        browser.select(d)

        browser.switchSpace(to: firstID)
        browser.close(c)
        XCTAssertEqual(browser.activeID, a.id)
        XCTAssertEqual(browser.spaceID, firstID)
    }

    func testClosingCurrentBypassesTabMovedToAnotherWindow() {
        let destination = Browser(record: WindowRecord(space: browser.spaceID))
        defer { destination.closeAll() }
        let (a, b, c) = makeFixture()
        browser.select(b)
        browser.select(a)
        browser.select(c)

        browser.moveToWindow(a, destination)
        browser.close(c)
        XCTAssertEqual(browser.activeID, b.id)
        XCTAssertTrue(destination.tabs.contains { $0.id == a.id })
        XCTAssertFalse(browser.tabs.contains { $0.id == a.id })
    }

    func testClosingPinnedTabPutsItDownAndSelectsPreviousTab() {
        let (a, b, _) = makeFixture()
        a.pin = "A"
        browser.select(a)
        browser.select(b)
        browser.select(a)
        browser.close(a)
        XCTAssertTrue(browser.tabs.contains { $0.id == a.id })
        XCTAssertTrue(a.asleep)
        XCTAssertEqual(browser.activeID, b.id)
    }

    func testClosingLastOrdinaryTabWithPinsAndNewTabAfterLastLeavesBlank() {
        let a = Tab(configuration: Web.configuration(space: browser.spaceID))
        a.restore(url: URL(string: "about:blank#A")!, title: "A")
        a.pin = "A"
        let b = Tab(configuration: Web.configuration(space: browser.spaceID))
        b.restore(url: URL(string: "about:blank#B")!, title: "B")
        browser.showRow([a, b], active: b.id)
        browser.select(b)
        browser.prefs.newTabAfterLast = true
        defer { browser.prefs.newTabAfterLast = false }

        browser.close(b)
        XCTAssertEqual(browser.active?.isBlank, true)
        XCTAssertTrue(browser.tabs.contains { $0.id == a.id })
        XCTAssertFalse(browser.tabs.contains { $0.id == b.id })
    }

    func testClosingSoleOrdinaryTabLeavesSingleBlankTab() {
        let c = Tab(configuration: Web.configuration(space: browser.spaceID))
        c.restore(url: URL(string: "about:blank#C")!, title: "C")
        let oldID = c.id
        browser.showRow([c], active: c.id)

        browser.close(c)
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertEqual(browser.active?.isBlank, true)
        XCTAssertFalse(browser.tabs.contains { $0.id == oldID })
    }

    func testTabSwitcherMostRecentDirectAccessAndCapacity() {
        let switcher = TabSwitcher()
        let tabs = (0..<12).map { i -> Tab in
            let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
            tab.restore(url: URL(string: "about:blank#\(i)")!, title: "\(i)")
            return tab
        }
        let allIDs = Set(tabs.map(\.id))
        for tab in tabs {
            switcher.left(tab, alive: allIDs)
        }
        let oldestID = tabs[0].id
        XCTAssertEqual(switcher.mostRecent(in: [oldestID]), oldestID)
        XCTAssertNil(switcher.mostRecent(in: [UUID()]))
        XCTAssertNil(switcher.mostRecent(in: []))
    }
}

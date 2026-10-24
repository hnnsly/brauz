import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class TabArmTests: XCTestCase {
    private func makeTab() -> Tab {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let tab = Tab(bench: true, configuration: config)
        _ = tab.web
        return tab
    }

    func testArmingTwiceWithSameInputsLeavesUserScriptsUntouched() throws {
        let tab = makeTab()
        guard let controller = tab.built?.configuration.userContentController else {
            XCTFail("Tab web view was not built")
            return
        }

        let url1 = URL(string: "https://example.com/page1")!
        let css = "p { color: red; }"

        // First arm call with url1 and css
        tab.arm(hiding: css, to: url1)
        let firstScripts = Array(controller.userScripts)
        XCTAssertFalse(firstScripts.isEmpty, "Controller should have user scripts installed")

        // Second arm call with identical inputs
        tab.arm(hiding: css, to: url1)
        let secondScripts = Array(controller.userScripts)

        XCTAssertEqual(firstScripts.count, secondScripts.count)
        for (index, (s1, s2)) in zip(firstScripts, secondScripts).enumerated() {
            XCTAssertTrue(
                s1 === s2,
                "Script at index \(index) was recreated despite identical inputs"
            )
        }
    }

    func testChangingAnyInputRebuildsUserScripts() throws {
        let tab = makeTab()
        guard let controller = tab.built?.configuration.userContentController else {
            XCTFail("Tab web view was not built")
            return
        }

        let url1 = URL(string: "https://example.com/page1")!
        let css1 = "p { color: red; }"

        // Establish baseline
        tab.arm(hiding: css1, to: url1)
        var lastFirstScript = controller.userScripts.first!

        // 1. Changing CSS rebuilds
        let css2 = "p { color: blue; }"
        tab.arm(hiding: css2, to: url1)
        var currentFirstScript = controller.userScripts.first!
        XCTAssertTrue(
            currentFirstScript !== lastFirstScript,
            "Expected user scripts to be rebuilt when CSS changed"
        )
        lastFirstScript = currentFirstScript

        // 2. Changing destination host rebuilds
        let host2 = "dusk-test-\(UUID().uuidString.prefix(8).lowercased()).org"
        let url2 = URL(string: "https://\(host2)/page1")!
        tab.arm(hiding: css2, to: url2)
        currentFirstScript = controller.userScripts.first!
        XCTAssertTrue(
            currentFirstScript !== lastFirstScript,
            "Expected user scripts to be rebuilt when destination host changed"
        )
        lastFirstScript = currentFirstScript

        // 3. Changing AutoScroll.on rebuilds
        let savedAutoScroll = AutoScroll.on
        defer { AutoScroll.on = savedAutoScroll }
        AutoScroll.on.toggle()
        tab.arm(hiding: css2, to: url2)
        currentFirstScript = controller.userScripts.first!
        XCTAssertTrue(
            currentFirstScript !== lastFirstScript,
            "Expected user scripts to be rebuilt when AutoScroll.on changed"
        )
        lastFirstScript = currentFirstScript

        // 4. Changing HoveredLink.on rebuilds
        let savedHoveredLink = HoveredLink.on
        defer { HoveredLink.on = savedHoveredLink }
        HoveredLink.on.toggle()
        tab.arm(hiding: css2, to: url2)
        currentFirstScript = controller.userScripts.first!
        XCTAssertTrue(
            currentFirstScript !== lastFirstScript,
            "Expected user scripts to be rebuilt when HoveredLink.on changed"
        )
        lastFirstScript = currentFirstScript

        // 5. Changing FormRelay.passkeysOffered rebuilds
        let savedPasskeys = FormRelay.passkeysOffered
        defer { FormRelay.passkeysOffered = savedPasskeys }
        FormRelay.passkeysOffered.toggle()
        tab.arm(hiding: css2, to: url2)
        currentFirstScript = controller.userScripts.first!
        XCTAssertTrue(
            currentFirstScript !== lastFirstScript,
            "Expected user scripts to be rebuilt when FormRelay.passkeysOffered changed"
        )
        lastFirstScript = currentFirstScript

        // 6. Changing Dusk state rebuilds
        let savedAppearance = NSApp.appearance
        let savedDuskOn = Dusk.shared.on
        defer {
            NSApp.appearance = savedAppearance
            Dusk.shared.on = savedDuskOn
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Dusk.shared.on = true
        Dusk.shared.saw(host2, dark: false)
        tab.arm(hiding: css2, to: url2)
        currentFirstScript = controller.userScripts.first!
        XCTAssertTrue(
            currentFirstScript !== lastFirstScript,
            "Expected user scripts to be rebuilt when Dusk state changed"
        )
    }

    func testArmInputsEquality() {
        let base = ArmInputs(
            css: "a",
            destinationHost: "example.com",
            autoScroll: false,
            hoveredLink: false,
            passkeysOffered: true,
            externalScript: nil,
            duskScript: nil,
            shy: false
        )
        let identical = ArmInputs(
            css: "a",
            destinationHost: "example.com",
            autoScroll: false,
            hoveredLink: false,
            passkeysOffered: true,
            externalScript: nil,
            duskScript: nil,
            shy: false
        )
        XCTAssertEqual(base, identical)

        XCTAssertNotEqual(base, ArmInputs(css: "b", destinationHost: "example.com", autoScroll: false, hoveredLink: false, passkeysOffered: true, externalScript: nil, duskScript: nil, shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "other.com", autoScroll: false, hoveredLink: false, passkeysOffered: true, externalScript: nil, duskScript: nil, shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "example.com", autoScroll: true, hoveredLink: false, passkeysOffered: true, externalScript: nil, duskScript: nil, shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "example.com", autoScroll: false, hoveredLink: true, passkeysOffered: true, externalScript: nil, duskScript: nil, shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "example.com", autoScroll: false, hoveredLink: false, passkeysOffered: false, externalScript: nil, duskScript: nil, shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "example.com", autoScroll: false, hoveredLink: false, passkeysOffered: true, externalScript: "ext", duskScript: nil, shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "example.com", autoScroll: false, hoveredLink: false, passkeysOffered: true, externalScript: nil, duskScript: "dusk", shy: false))
        XCTAssertNotEqual(base, ArmInputs(css: "a", destinationHost: "example.com", autoScroll: false, hoveredLink: false, passkeysOffered: true, externalScript: nil, duskScript: nil, shy: true))
    }

    func testTwoTabsSharingControllerRebuildsWhenInterleavedOrDiscarded() throws {
        let controller = WKUserContentController()
        let configA = WKWebViewConfiguration()
        configA.userContentController = controller
        configA.websiteDataStore = .nonPersistent()
        let tabA = Tab(bench: true, configuration: configA)
        _ = tabA.web

        let configB = WKWebViewConfiguration()
        configB.userContentController = controller
        configB.websiteDataStore = .nonPersistent()
        let tabB = Tab(bench: true, configuration: configB)
        _ = tabB.web

        let urlA = URL(string: "https://example-a.org/page1")!
        let urlB = URL(string: "https://example-b.org/page1")!
        let cssA = "p { color: red; }"
        let cssB = "p { color: blue; }"

        // 1. Arm A
        tabA.arm(hiding: cssA, to: urlA)
        let scriptsA1 = Array(controller.userScripts)
        XCTAssertFalse(scriptsA1.isEmpty)

        // 2. Arm B with other inputs
        tabB.arm(hiding: cssB, to: urlB)
        let scriptsB = Array(controller.userScripts)
        XCTAssertFalse(scriptsB.isEmpty)
        XCTAssertTrue(scriptsB.first !== scriptsA1.first, "Arming B with other inputs must rebuild")

        // 3. Arm A again with its old inputs -> must rebuild
        tabA.arm(hiding: cssA, to: urlA)
        let scriptsA2 = Array(controller.userScripts)
        XCTAssertFalse(scriptsA2.isEmpty)
        XCTAssertTrue(
            scriptsA2.first !== scriptsB.first,
            "Arming A again with its old inputs after B armed must rebuild"
        )

        // 4. Discard B -> A rebuilds on next arm
        if #available(macOS 15.4, *) {
            let savedPages = Extensions.pages
            defer { Extensions.pages = savedPages }
            Extensions.pages = controller
            tabB.discard()
            // Shared controller still has PopupGestureRelay installed
            XCTAssertEqual(controller.userScripts.count, 1)

            tabA.arm(hiding: cssA, to: urlA)
            let scriptsA3 = Array(controller.userScripts)
            XCTAssertTrue(
                scriptsA3.count > 1,
                "Arming A after B discarded must rebuild all user scripts"
            )
        } else {
            tabB.discard()
            tabA.arm(hiding: cssA, to: urlA)
            let scriptsA3 = Array(controller.userScripts)
            XCTAssertFalse(scriptsA3.isEmpty)
        }
    }
}

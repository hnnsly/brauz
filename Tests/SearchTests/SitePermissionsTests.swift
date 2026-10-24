import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class SitePermissionsTests: XCTestCase {
    private var coordinator: SitePermissionCoordinator!
    private let siteA = "https://telemost.yandex.ru"
    private let hostA = "telemost.yandex.ru"
    private let siteB = "https://meet.google.com"
    private let hostB = "meet.google.com"
    private let tabA = UUID()
    private let tabB = UUID()

    override class func setUp() {
        setenv("SEARCH_PROBE", "site-perms-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        coordinator = SitePermissionCoordinator()
        // Clean up any test keys
        for key in Store.settings.dictionaryRepresentation().keys where key.hasPrefix("capture.") {
            Store.settings.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Store.settings.dictionaryRepresentation().keys where key.hasPrefix("capture.") {
            Store.settings.removeObject(forKey: key)
        }
        super.tearDown()
    }

    /// A stored camera+microphone grant satisfies a single-device request.
    func testCompositeKeyStoredGrantSatisfiesSingleDevice() {
        // Store camera and microphone grant (rawValue 2)
        Store.settings.set(true, forKey: "capture.\(siteA)|2")

        // Single camera request (0) should be satisfied immediately without prompt
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera), .grant)

        // Single microphone request (1) should be satisfied immediately without prompt
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone), .grant)

        // Both camera and microphone request (2) should also be satisfied
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .cameraAndMicrophone), .grant)

        var cameraDecision: WKPermissionDecision?
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            cameraDecision = decision
        }
        XCTAssertEqual(cameraDecision, .grant)
        XCTAssertNil(coordinator.activePrompt)
    }

    /// When a second camera/microphone request from the same site arrives while that site's
    /// prompt is open, merge them into ONE prompt whose answer resolves every pending request.
    func testMergeSecondRequestFromSameSite() {
        var firstDecision: WKPermissionDecision?
        var secondDecision: WKPermissionDecision?

        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            firstDecision = decision
        }

        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.wants, "camera")

        // Second request arrives for microphone from same site and tab
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .microphone, shy: false) { decision in
            secondDecision = decision
        }

        // Must be merged into ONE prompt
        XCTAssertEqual(coordinator.activePrompt?.type, .cameraAndMicrophone)
        XCTAssertEqual(coordinator.activePrompt?.wants, "camera and microphone")
        XCTAssertTrue(coordinator.queue.isEmpty, "Second request from same site must merge, not queue")

        // Answering resolves every pending request
        coordinator.answer(decision: .grant, keep: true)

        XCTAssertEqual(firstDecision, .grant)
        XCTAssertEqual(secondDecision, .grant)
        XCTAssertNil(coordinator.activePrompt)

        // Single-device keys are stored individually, and composite kept in sync
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|0") as? Bool, true)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|1") as? Bool, true)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|2") as? Bool, true)
    }

    /// A request from a different site or tab waits in a queue and is shown after
    /// the current one is answered.
    func testQueueRequestFromDifferentSiteOrTab() {
        var firstDecision: WKPermissionDecision?
        var secondDecision: WKPermissionDecision?

        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            firstDecision = decision
        }

        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.site, siteA)

        // Request from different site arrives
        coordinator.request(tabID: tabB, site: siteB, host: hostB, type: .microphone, shy: false) { decision in
            secondDecision = decision
        }

        // Must wait in queue, not denied at once
        XCTAssertNil(secondDecision, "Queued request must not be denied immediately")
        XCTAssertEqual(coordinator.queue.count, 1)
        XCTAssertEqual(coordinator.activePrompt?.site, siteA)

        // Answer first prompt
        coordinator.answer(decision: .deny, keep: true)
        XCTAssertEqual(firstDecision, .deny)

        // Second prompt should now be shown as activePrompt
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.site, siteB)
        XCTAssertEqual(coordinator.activePrompt?.wants, "microphone")
        XCTAssertTrue(coordinator.queue.isEmpty)

        // Answer second prompt
        coordinator.answer(decision: .grant, keep: true)
        XCTAssertEqual(secondDecision, .grant)
        XCTAssertNil(coordinator.activePrompt)
    }

    /// A pending prompt and its decision handlers are answered .deny and cleared
    /// when its tab closes or navigates away.
    func testTabCleanupWhenTabClosesOrNavigatesAway() {
        var promptDecision1: WKPermissionDecision?
        var promptDecision2: WKPermissionDecision?
        var queuedDecision: WKPermissionDecision?

        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            promptDecision1 = decision
        }
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .microphone, shy: false) { decision in
            promptDecision2 = decision
        }
        coordinator.request(tabID: tabB, site: siteB, host: hostB, type: .camera, shy: false) { decision in
            queuedDecision = decision
        }

        // Tab A navigates away or closes
        coordinator.drop(tabID: tabA)

        // Both pending handlers for tab A must be answered .deny
        XCTAssertEqual(promptDecision1, .deny)
        XCTAssertEqual(promptDecision2, .deny)

        // Tab B's queued request should now become active
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.tabID, tabB)
        XCTAssertNil(queuedDecision)

        // Now tab B closes while queued/active
        coordinator.drop(tabID: tabB)
        XCTAssertEqual(queuedDecision, .deny)
        XCTAssertNil(coordinator.activePrompt)
        XCTAssertTrue(coordinator.queue.isEmpty)
    }

    /// Settings › Privacy per-site list and removal: lists Camera and Microphone
    /// as separate removable rows even when granted together.
    func testSettingsSitePermissionsListAndRemoval() {
        Store.settings.set(true, forKey: "capture.\(siteA)|2")
        Store.settings.set(true, forKey: "capture.\(siteB)|0")
        Store.settings.set(true, forKey: "capture.\(siteB)|location")

        let allowed = SitePermissions.allowed
        // siteA has camera and microphone as separate rows; siteB has camera and location
        XCTAssertEqual(allowed.count, 4)

        let entryACam = allowed.first(where: { $0.site == siteA && $0.kind == .camera })
        XCTAssertNotNil(entryACam)
        XCTAssertEqual(entryACam?.description, "Can use camera")

        let entryAMic = allowed.first(where: { $0.site == siteA && $0.kind == .microphone })
        XCTAssertNotNil(entryAMic)
        XCTAssertEqual(entryAMic?.description, "Can use microphone")

        let entryBCam = allowed.first(where: { $0.site == siteB && $0.kind == .camera })
        XCTAssertNotNil(entryBCam)
        XCTAssertEqual(entryBCam?.description, "Can use camera")

        let entryBLoc = allowed.first(where: { $0.site == siteB && $0.kind == .location })
        XCTAssertNotNil(entryBLoc)
        XCTAssertEqual(entryBLoc?.description, "Can use location")

        // Remove camera for site A; microphone must remain
        if let entryACam {
            SitePermissions.forget(entryACam)
        }
        XCTAssertNil(Store.settings.object(forKey: "capture.\(siteA)|0"))
        XCTAssertNil(Store.settings.object(forKey: "capture.\(siteA)|2"))
        XCTAssertFalse(SitePermissions.allowed.contains(where: { $0.site == siteA && $0.kind == .camera }))
        XCTAssertTrue(SitePermissions.allowed.contains(where: { $0.site == siteA && $0.kind == .microphone }))
    }

    /// Removing Camera keeps Microphone working and vice versa.
    func testRemovingCameraKeepsMicrophoneWorkingAndViceVersa() {
        // 1. Answer merged prompt for siteA: granted
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { _ in }
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .microphone, shy: false) { _ in }
        coordinator.answer(decision: .grant, keep: true)

        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|0") as? Bool, true)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|1") as? Bool, true)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|2") as? Bool, true)

        let camEntryA = SitePermissions.allowed.first(where: { $0.site == siteA && $0.kind == .camera })
        XCTAssertNotNil(camEntryA)
        // Remove Camera
        SitePermissions.forget(camEntryA!)

        // Camera is removed, Microphone still works
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera))
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone), .grant)

        // 2. Answer merged prompt for siteB: granted
        coordinator.request(tabID: tabB, site: siteB, host: hostB, type: .camera, shy: false) { _ in }
        coordinator.request(tabID: tabB, site: siteB, host: hostB, type: .microphone, shy: false) { _ in }
        coordinator.answer(decision: .grant, keep: true)

        let micEntryB = SitePermissions.allowed.first(where: { $0.site == siteB && $0.kind == .microphone })
        XCTAssertNotNil(micEntryB)
        // Remove Microphone
        SitePermissions.forget(micEntryB!)

        // Microphone is removed, Camera still works
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteB, type: .microphone))
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteB, type: .camera), .grant)
    }

    /// Merging microphone first, then camera from same site and tab.
    func testMergeMicrophoneThenCamera() {
        var firstDecision: WKPermissionDecision?
        var secondDecision: WKPermissionDecision?

        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .microphone, shy: false) { decision in
            firstDecision = decision
        }
        XCTAssertEqual(coordinator.activePrompt?.wants, "microphone")

        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            secondDecision = decision
        }
        XCTAssertEqual(coordinator.activePrompt?.type, .cameraAndMicrophone)
        XCTAssertEqual(coordinator.activePrompt?.wants, "camera and microphone")

        coordinator.answer(decision: .grant, keep: true)
        XCTAssertEqual(firstDecision, .grant)
        XCTAssertEqual(secondDecision, .grant)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|0") as? Bool, true)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|1") as? Bool, true)
        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|2") as? Bool, true)
    }

    /// Shy (private) tab does not read remembered permissions and never stores anything.
    func testShyTabDoesNotReadOrStorePermissions() {
        Store.settings.set(true, forKey: "capture.\(siteA)|2")

        var decision: WKPermissionDecision?
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: true) { dec in
            decision = dec
        }
        // Should prompt even though persistent settings had a grant
        XCTAssertNil(decision)
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertTrue(coordinator.activePrompt?.shy == true)

        // Clear stored settings before answering
        Store.settings.removeObject(forKey: "capture.\(siteA)|2")

        coordinator.answer(decision: .grant, keep: true)
        XCTAssertEqual(decision, .grant)

        // Must NOT have written to Store.settings because it was shy
        XCTAssertNil(Store.settings.object(forKey: "capture.\(siteA)|2"))
        XCTAssertNil(Store.settings.object(forKey: "capture.\(siteA)|0"))
    }

    /// Test remembered decision combinations (deny individual, deny both, grant individual).
    func testRememberedDecisionCombinations() {
        // Individual camera grant and mic grant satisfies both
        Store.settings.set(true, forKey: "capture.\(siteA)|0")
        Store.settings.set(true, forKey: "capture.\(siteA)|1")
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera), .grant)
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone), .grant)
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .cameraAndMicrophone), .grant)

        // Denied camera
        Store.settings.set(false, forKey: "capture.\(siteA)|0")
        Store.settings.removeObject(forKey: "capture.\(siteA)|1")
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera), .deny)
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone))
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .cameraAndMicrophone), "Composite request with one denied and other unknown must prompt")

        // Composite deny stored: single-device fallback applies to composite grant only
        Store.settings.removeObject(forKey: "capture.\(siteA)|0")
        Store.settings.set(false, forKey: "capture.\(siteA)|2")
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera), "Composite deny must not deny single camera request")
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone), "Composite deny must not deny single microphone request")
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .cameraAndMicrophone), .deny)

        // Denied both devices explicitly
        Store.settings.set(false, forKey: "capture.\(siteA)|0")
        Store.settings.set(false, forKey: "capture.\(siteA)|1")
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera), .deny)
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone), .deny)
        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .cameraAndMicrophone), .deny)
    }

    /// Browser hook: closing a tab denies and clears its pending capture request.
    func testTabCloseClearsPendingCaptureRequest() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }

        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: siteA)!, title: "Telemost")
        browser.prepare(tab)
        browser.showRow([tab], active: tab.id)

        var decision: WKPermissionDecision?
        browser.sitePermissions.request(tabID: tab.id, site: siteA, host: hostA, type: .camera, shy: false) { dec in
            decision = dec
        }

        XCTAssertNotNil(browser.sitePermissions.activePrompt)
        XCTAssertNil(decision)

        browser.close(tab)

        XCTAssertEqual(decision, .deny)
        XCTAssertNil(browser.sitePermissions.activePrompt)
    }

    /// Browser hook: starting provisional navigation clears pending capture request.
    func testProvisionalNavigationClearsPendingCaptureRequest() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }

        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: siteA)!, title: "Telemost")
        browser.prepare(tab)
        browser.showRow([tab], active: tab.id)

        var decision: WKPermissionDecision?
        browser.sitePermissions.request(tabID: tab.id, site: siteA, host: hostA, type: .camera, shy: false) { dec in
            decision = dec
        }

        XCTAssertNotNil(browser.sitePermissions.activePrompt)
        XCTAssertNil(decision)

        let webView = tab.web
        guard let nav = webView.loadHTMLString("<html></html>", baseURL: URL(string: siteA)!) else {
            XCTFail("Failed to start navigation")
            return
        }
        browser.webView(webView, didStartProvisionalNavigation: nav)

        XCTAssertEqual(decision, .deny)
        XCTAssertNil(browser.sitePermissions.activePrompt)
    }

    /// Browser hook: toggling Split View off in Settings does NOT drop capture requests on ordinary tabs.
    func testSplitViewToggleDoesNotClearPendingCaptureRequest() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        defer {
            browser.closeAll()
            browser.prefs.splitView = false
        }

        browser.prefs.splitView = true

        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: siteA)!, title: "Telemost")
        browser.prepare(tab)
        browser.showRow([tab], active: tab.id)

        var decision: WKPermissionDecision?
        browser.sitePermissions.request(tabID: tab.id, site: siteA, host: hostA, type: .camera, shy: false) { dec in
            decision = dec
        }

        XCTAssertNotNil(browser.sitePermissions.activePrompt)
        XCTAssertNil(decision)

        // Toggle Split View off
        browser.prefs.splitView = false

        // Prompt must remain active, handler must not be denied
        XCTAssertNil(decision, "Toggling Split View off must not deny pending capture request")
        XCTAssertNotNil(browser.sitePermissions.activePrompt, "Toggling Split View off must not clear activePrompt")
    }

    /// Denying camera then asking for microphone prompts instead of being denied.
    func testDenyCameraThenAskMicrophonePrompts() {
        // Deny camera for siteA
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { _ in }
        coordinator.answer(decision: .deny, keep: true)

        XCTAssertEqual(Store.settings.object(forKey: "capture.\(siteA)|0") as? Bool, false)
        XCTAssertNil(Store.settings.object(forKey: "capture.\(siteA)|1"))
        XCTAssertNil(Store.settings.object(forKey: "capture.\(siteA)|2"), "syncComposite must not write composite deny unless both devices are denied")

        XCTAssertEqual(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .camera), .deny)
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .microphone), "Microphone must not be denied when only camera was denied")
        XCTAssertNil(SitePermissionCoordinator.rememberedDecision(for: siteA, type: .cameraAndMicrophone), "Composite request must prompt when one device denied and other unknown")

        // Now ask for microphone: must prompt, not be denied
        var micDecision: WKPermissionDecision?
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .microphone, shy: false) { decision in
            micDecision = decision
        }

        XCTAssertNil(micDecision, "Microphone request must prompt, not be answered immediately")
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.wants, "microphone")

        // Clear active prompt without storing
        coordinator.answer(decision: .grant, keep: false)

        // Composite request with one denied and other unknown must prompt
        var compositeDecision: WKPermissionDecision?
        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .cameraAndMicrophone, shy: false) { decision in
            compositeDecision = decision
        }
        XCTAssertNil(compositeDecision, "Composite request with one denied and one unknown must prompt")
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.wants, "camera and microphone")
    }

    /// When dequeuing, answer every queued request that rememberedDecision now resolves
    /// without prompting, and merge only the still-undecided ones into the next prompt.
    func testAdvanceQueueResolvesGrantedDeviceWithoutPromptAndAsksUndecided() {
        var tab1CamDecision: WKPermissionDecision?
        var tab2MicDecision: WKPermissionDecision?
        var tab2CamDecision: WKPermissionDecision?

        coordinator.request(tabID: tabA, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            tab1CamDecision = decision
        }
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.tabID, tabA)
        XCTAssertEqual(coordinator.activePrompt?.wants, "camera")
        XCTAssertNil(tab1CamDecision)

        coordinator.request(tabID: tabB, site: siteA, host: hostA, type: .microphone, shy: false) { decision in
            tab2MicDecision = decision
        }
        XCTAssertNil(tab2MicDecision)

        coordinator.request(tabID: tabB, site: siteA, host: hostA, type: .camera, shy: false) { decision in
            tab2CamDecision = decision
        }
        XCTAssertNil(tab2CamDecision)
        XCTAssertEqual(coordinator.queue.count, 2)

        // User allows tab 1's camera
        coordinator.answer(decision: .grant, keep: true)

        XCTAssertEqual(tab1CamDecision, .grant)
        XCTAssertEqual(tab2CamDecision, .grant, "Tab 2 camera must be granted without prompt")
        XCTAssertNotNil(coordinator.activePrompt)
        XCTAssertEqual(coordinator.activePrompt?.tabID, tabB)
        XCTAssertEqual(coordinator.activePrompt?.wants, "microphone")
        XCTAssertNil(tab2MicDecision)
        XCTAssertTrue(coordinator.queue.isEmpty)
    }

    /// Extension popup web view (not a browser tab): first request prompts,
    /// a camera+microphone pair does not turn into a deny of the first request,
    /// and remembered decisions apply as upstream did.
    func testExtensionPopupWebViewPromptsInsteadOfBeingDenied() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }

        let popupWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNil(browser.tab(for: popupWebView), "Extension popup web view is not in browser tabs")

        var cameraDecision: WKPermissionDecision?
        browser.askedForCapture(
            popupWebView,
            site: siteA,
            host: hostA,
            type: .camera,
            shy: false
        ) { dec in
            cameraDecision = dec
        }

        // Upstream behaviour: first request prompts, coordinator not used
        XCTAssertNil(cameraDecision, "Extension popup first capture request must prompt, not be denied immediately")
        XCTAssertNil(browser.sitePermissions.activePrompt, "activePrompt must be nil for non-tab web view")
        XCTAssertNotNil(browser.asking, "browser.asking card must be shown")
        XCTAssertEqual(browser.asking?.host, hostA)
        XCTAssertEqual(browser.asking?.wants, "camera")

        // Second request for microphone from the same popup while first is waiting
        var micDecision: WKPermissionDecision?
        browser.askedForCapture(
            popupWebView,
            site: siteA,
            host: hostA,
            type: .microphone,
            shy: false
        ) { dec in
            micDecision = dec
        }

        // Second request is refused immediately, but first request is not turned into a deny
        XCTAssertEqual(micDecision, .deny, "Second request while first is waiting is refused")
        XCTAssertNil(cameraDecision, "First request must still be waiting, not turned into a deny")
        XCTAssertNotNil(browser.asking, "browser.asking card must still be shown for first request")
        XCTAssertEqual(browser.asking?.wants, "camera")

        // Remembered decision applies to popup as upstream did
        Store.settings.set(true, forKey: "capture.\(siteB)|0")
        var rememberedDecision: WKPermissionDecision?
        browser.askedForCapture(
            popupWebView,
            site: siteB,
            host: hostB,
            type: .camera,
            shy: false
        ) { dec in
            rememberedDecision = dec
        }
        XCTAssertEqual(rememberedDecision, .grant, "Remembered per-site decision applies to popup")
    }
}

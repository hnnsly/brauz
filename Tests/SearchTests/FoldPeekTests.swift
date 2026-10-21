import XCTest
@testable import Search

@MainActor
final class FoldPeekTests: XCTestCase {

    private func wait(timeout: TimeInterval = 1.0, condition: @escaping @MainActor () -> Bool) {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                break
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private func drain(after delay: TimeInterval = 0.03) {
        var drained = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            drained = true
        }
        wait { drained }
    }

    func testSidebarHidesOnlyOnItsOwnWindow() {
        XCTAssertTrue(FoldHiding.allowsHide(sidebar: true, inWindow: true, onWindow: true))
        XCTAssertFalse(FoldHiding.allowsHide(sidebar: true, inWindow: false, onWindow: true))
        XCTAssertFalse(FoldHiding.allowsHide(sidebar: true, inWindow: true, onWindow: false))
        XCTAssertFalse(FoldHiding.allowsHide(sidebar: true, inWindow: false, onWindow: false))
    }

    func testTopStripKeepsOutsideHidePolicy() {
        XCTAssertTrue(FoldHiding.allowsHide(sidebar: false, inWindow: true, onWindow: true))
        XCTAssertTrue(FoldHiding.allowsHide(sidebar: false, inWindow: false, onWindow: true))
        XCTAssertTrue(FoldHiding.allowsHide(sidebar: false, inWindow: true, onWindow: false))
        XCTAssertTrue(FoldHiding.allowsHide(sidebar: false, inWindow: false, onWindow: false))
    }

    func testEligiblePageHidesAfterDelay() {
        let hiding = FoldHiding()
        var hideCount = 0
        hiding.schedule(after: 0.01, canHide: { true }, hide: { hideCount += 1 })
        XCTAssertEqual(hideCount, 0, "Should not hide synchronously")
        wait { hideCount == 1 }
        XCTAssertEqual(hideCount, 1)
        hiding.cancel()
    }

    func testQueuedHideRechecksWindowExit() {
        let hiding = FoldHiding()
        var hideCalled = false
        var evalCount = 0
        var currentInWindow = true

        hiding.schedule(after: 0.01, canHide: {
            evalCount += 1
            return FoldHiding.allowsHide(sidebar: true, inWindow: currentInWindow, onWindow: true)
        }, hide: { hideCalled = true })

        currentInWindow = false

        wait { evalCount > 0 }

        XCTAssertFalse(hideCalled, "Should not hide when inWindow became false")
        XCTAssertGreaterThan(evalCount, 0, "canHide must have evaluated")
        hiding.cancel()
    }

    func testQueuedHideRechecksOverlappingWindow() {
        let hiding = FoldHiding()
        var hideCalled = false
        var evalCount = 0
        var currentOnWindow = true

        hiding.schedule(after: 0.01, canHide: {
            evalCount += 1
            return FoldHiding.allowsHide(sidebar: true, inWindow: true, onWindow: currentOnWindow)
        }, hide: { hideCalled = true })

        currentOnWindow = false

        wait { evalCount > 0 }

        XCTAssertFalse(hideCalled, "Should not hide when onWindow is false")
        XCTAssertGreaterThan(evalCount, 0)
        hiding.cancel()
    }

    func testReturningToPageCanScheduleAfterBlockedHide() {
        let hiding = FoldHiding()
        var hideCount = 0
        var evalCount = 0
        var eligible = false

        hiding.schedule(after: 0.01, canHide: {
            evalCount += 1
            return FoldHiding.allowsHide(sidebar: true, inWindow: eligible, onWindow: eligible)
        }, hide: { hideCount += 1 })

        wait { evalCount > 0 }
        XCTAssertEqual(hideCount, 0, "First attempt blocked")

        eligible = true
        evalCount = 0
        hiding.schedule(after: 0.01, canHide: {
            evalCount += 1
            return FoldHiding.allowsHide(sidebar: true, inWindow: eligible, onWindow: eligible)
        }, hide: { hideCount += 1 })

        wait { hideCount == 1 }
        XCTAssertEqual(hideCount, 1, "Second attempt succeeds")
        hiding.cancel()
    }

    func testReturningToSidebarCancelsPendingHide() {
        let hiding = FoldHiding()
        var hideCalled = false
        var evalCount = 0

        hiding.schedule(after: 0.01, canHide: {
            evalCount += 1
            return true
        }, hide: { hideCalled = true })

        hiding.cancel()
        drain(after: 0.03)

        XCTAssertFalse(hideCalled)
        XCTAssertEqual(evalCount, 0)
    }

    func testCancellationWithoutPendingWorkAllowsNextHide() {
        let hiding = FoldHiding()
        hiding.cancel()
        hiding.cancel()

        var hideCount = 0
        hiding.schedule(after: 0.01, canHide: { true }, hide: { hideCount += 1 })
        wait { hideCount == 1 }
        XCTAssertEqual(hideCount, 1)
        hiding.cancel()
    }

    func testRepeatedRequestsKeepFirstAction() {
        let hiding = FoldHiding()
        var firstCount = 0
        var secondCount = 0

        hiding.schedule(after: 0.01, canHide: { true }, hide: { firstCount += 1 })
        hiding.schedule(after: 0.0, canHide: { true }, hide: { secondCount += 1 })

        wait { firstCount > 0 || secondCount > 0 }
        drain(after: 0.03)

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)
        hiding.cancel()
    }

    func testQueuedHideRechecksEditorAndMenuProtection() {
        do {
            let hiding = FoldHiding()
            var hideCalled = false
            var evalCount = 0
            var isEditing = false

            hiding.schedule(after: 0.02, canHide: {
                evalCount += 1
                return !isEditing && FoldHiding.allowsHide(sidebar: true, inWindow: true, onWindow: true)
            }, hide: { hideCalled = true })

            isEditing = true

            wait { evalCount > 0 }

            XCTAssertFalse(hideCalled, "Should not hide when editing became true")
            XCTAssertGreaterThan(evalCount, 0)
            hiding.cancel()
        }

        do {
            let hiding = FoldHiding()
            var hideCalled = false
            var evalCount = 0
            var isHolding = false

            hiding.schedule(after: 0.02, canHide: {
                evalCount += 1
                return !isHolding && FoldHiding.allowsHide(sidebar: true, inWindow: true, onWindow: true)
            }, hide: { hideCalled = true })

            isHolding = true

            wait { evalCount > 0 }

            XCTAssertFalse(hideCalled, "Should not hide when holding became true")
            XCTAssertGreaterThan(evalCount, 0)
            hiding.cancel()
        }
    }
}

import XCTest
@testable import Search

final class ExtensionWarningsTests: XCTestCase {
    func testFormatContextErrorSimple() {
        let error = NSError(domain: "WKWebExtensionErrorDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid manifest format"
        ])
        let formatted = ExtensionWarnings.formatContextError(error)
        XCTAssertEqual(formatted, "Invalid manifest format")
    }

    func testFormatContextErrorWithUnderlyingError() {
        let underlying = NSError(domain: "WKWebExtensionErrorDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Key 'permissions' is invalid"
        ])
        let error = NSError(domain: "WKWebExtensionErrorDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid manifest format",
            NSUnderlyingErrorKey: underlying
        ])
        let formatted = ExtensionWarnings.formatContextError(error)
        XCTAssertEqual(formatted, "Invalid manifest format: Key 'permissions' is invalid")
    }

    func testCombineOnlyContextErrors() {
        let err1 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Warning 1"])
        let err2 = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Warning 2"])
        let combined = ExtensionWarnings.combine(contextErrors: [err1, err2], runtimeErrors: [])
        XCTAssertEqual(combined, ["Warning 1", "Warning 2"])
    }

    func testCombineOnlyRuntimeErrors() {
        let runtime = ["Uncaught TypeError at content.js:12", "Network error on background.js:45"]
        let combined = ExtensionWarnings.combine(contextErrors: [], runtimeErrors: runtime)
        XCTAssertEqual(combined, runtime)
    }

    func testCombineBothSourcesPreservesOrderNewestLast() {
        let contextErr = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manifest warning"])
        let runtime1 = "Worker started with warning"
        let runtime2 = "Latest exception (newest)"
        let combined = ExtensionWarnings.combine(contextErrors: [contextErr], runtimeErrors: [runtime1, runtime2])
        XCTAssertEqual(combined, [
            "Manifest warning",
            "Worker started with warning",
            "Latest exception (newest)"
        ])
        XCTAssertEqual(combined.last, runtime2, "Newest runtime error must be last")
    }

    func testTotalCountMatchesCombined() {
        let contextErr = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manifest warning"])
        let runtime = ["Runtime error 1", "Runtime error 2"]
        let combined = ExtensionWarnings.combine(contextErrors: [contextErr], runtimeErrors: runtime)
        let total = ExtensionWarnings.totalCount(contextCount: 1, runtimeCount: runtime.count)
        XCTAssertEqual(total, 3)
        XCTAssertEqual(total, combined.count)
    }

    func testCopyTextJoinsWithNewlines() {
        let errors = ["Error 1", "Error 2", "Error 3"]
        let text = ExtensionWarnings.copyText(errors: errors)
        XCTAssertEqual(text, "Error 1\nError 2\nError 3")
    }

    func testCopyTextEmpty() {
        let text = ExtensionWarnings.copyText(errors: [])
        XCTAssertEqual(text, "")
    }

    func testCombineBothEmpty() {
        let combined = ExtensionWarnings.combine(contextErrors: [], runtimeErrors: [])
        XCTAssertEqual(combined, [])
        let total = ExtensionWarnings.totalCount(contextCount: 0, runtimeCount: 0)
        XCTAssertEqual(total, 0)
    }
}

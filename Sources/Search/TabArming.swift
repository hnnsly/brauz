import Foundation
import WebKit

// What gets injected into a tab's page (Tab.arm) depends on a handful of
// inputs: stylesheets, destination host, preferences, and loaded extensions.
// When none of them have changed since the last arming on this content controller,
// rebuilding all user scripts is skipped.

struct ArmInputs: Equatable {
    let css: String
    let destinationHost: String?
    let autoScroll: Bool
    let hoveredLink: Bool
    let passkeysOffered: Bool
    let externalScript: String?
    let duskScript: String?
    let shy: Bool

    @MainActor
    static func current(for tab: Tab, hiding css: String, to url: URL?) -> ArmInputs {
        let host = Dusk.host(of: url ?? tab.pageAddress)
        return ArmInputs(
            css: css,
            destinationHost: host,
            autoScroll: AutoScroll.on,
            hoveredLink: HoveredLink.on,
            passkeysOffered: FormRelay.passkeysOffered,
            externalScript: ExtensionExternal.script,
            duskScript: Dusk.shared.script(for: host),
            shy: tab.shy
        )
    }
}

private final class ArmedInputsBox {
    let inputs: ArmInputs
    init(_ inputs: ArmInputs) { self.inputs = inputs }
}

enum TabArming {
    private static let remembered = NSMapTable<WKUserContentController, ArmedInputsBox>.weakToStrongObjects()

    @MainActor
    static func inputs(for controller: WKUserContentController) -> ArmInputs? {
        remembered.object(forKey: controller)?.inputs
    }

    @MainActor
    static func record(_ inputs: ArmInputs, for controller: WKUserContentController) {
        remembered.setObject(ArmedInputsBox(inputs), forKey: controller)
    }

    @MainActor
    static func forget(for controller: WKUserContentController) {
        remembered.removeObject(forKey: controller)
    }
}

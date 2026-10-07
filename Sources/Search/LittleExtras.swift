import SwiftUI

// The small window (Little.swift), with more of a browser in it: an address
// to type over the page, the usual keys kept to itself, and a place on the
// screen it comes back to.
//
// ⌘L, or a click on the site, turns the site into a field: an address or a
// search goes there, Escape gives the site back. Reload, zoom, back and
// forward work as in the browser, and no other ⌘ key gets through to the
// browser's window behind it. A new one opens where the last was left, its
// size too, or a step down from one still open; always on a screen.

/// What is being typed over the page, for as long as it is.
@MainActor
final class LittleAddress: ObservableObject {
    @Published var editing = false
    @Published var typed = ""
    /// Raised to put the caret in the field.
    @Published var focusRequest = 0
}

extension LittleWindow {
    // MARK: - The address

    func startEditing() {
        address.typed = tab.address?.absoluteString ?? ""
        address.editing = true
        address.focusRequest += 1
    }

    func cancelEditing() {
        address.editing = false
        address.typed = ""
        backToPage()
    }

    func submit() {
        let text = address.typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return cancelEditing() }
        if let destination = destination(for: text) { tab.go(to: destination) }
        address.editing = false
        address.typed = ""
        backToPage()
    }

    private func backToPage() {
        if let web = tab.built, let window = web.window { window.makeFirstResponder(web) }
    }

    /// As the browser reads what is typed in its own field; with no browser
    /// left, an address, or the search engine Settings names.
    private func destination(for text: String) -> URL? {
        if let browser { return browser.destination(for: text) }
        if let url = Address.url(from: text) { return url }
        let custom = Store.settings.string(forKey: "search.custom") ?? ""
        let engine = Store.settings.string(forKey: "search.engine").flatMap(Engine.init) ?? .standard
        return Engine.url(for: text, template: engine.template(custom: custom))
    }

    private func copyAddress() {
        guard let url = tab.pageAddress ?? tab.address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        browser?.announce("Copied address")
    }

    // MARK: - Keys

    /// Asked first by `take`. Matched by key code as well, so they work on
    /// any keyboard layout (see ShortcutKey.swift).
    func keys(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.shortcutKey
        let code = event.keyCode
        // Select all, copy, paste, cut, undo (with ⇧, redo) and the arrows
        // are the page's or the field's.
        let editing = ["a", "c", "v", "x", "z"].contains(key) || [0, 8, 9, 7, 6].contains(code)
        let typing = address.editing || event.window?.firstResponder is NSTextView
        let arrow = (123...126).contains(code)

        if code == 53 && flags.isEmpty {
            if address.editing { cancelEditing() } else { window.performClose(nil) }
            return true
        }
        switch flags {
        case .command:
            switch true {
            case key == "w" || code == 13: window.performClose(nil)
            case key == "o" || code == 31: keep()
            case key == "l" || code == 37: startEditing()
            case key == "r" || code == 15: tab.web.reload()
            case key == "=" || key == "+" || code == 24: tab.magnify(to: min(3, tab.web.pageZoom + 0.1))
            case key == "-" || code == 27: tab.magnify(to: max(0.4, tab.web.pageZoom - 0.1))
            case key == "0" || code == 29: tab.magnify(to: 1.0)
            case key == "." || code == 47: tab.stop()
            // Back and forward, unless the arrows are moving a caret.
            case !typing && (key == "[" || code == 33 || code == 123): tab.back()
            case !typing && (key == "]" || code == 30 || code == 124): tab.forward()
            default: return stops(event, editing: editing || typing && arrow)
            }
            return true
        case [.command, .option] where key == "r" || code == 15:
            tab.web.reloadFromOrigin()
            return true
        case [.command, .shift] where key == "r" || code == 15:
            tab.toggleReader { _ in }
            return true
        case [.command, .shift] where key == "c" || code == 8:
            copyAddress()
            return true
        default:
            return flags.contains(.command) && stops(event, editing: editing || typing && arrow)
        }
    }

    /// Any other ⌘ key stops here rather than reach the browser's window
    /// behind, except the ones for editing text.
    private func stops(_ event: NSEvent, editing: Bool) -> Bool {
        !editing && event.window === window
    }

    // MARK: - Where it opens

    /// A step down from the newest one still open; otherwise where the last
    /// one was left, at its size; the first time, in the middle.
    func position() {
        if let last = LittleWindow.all.dropLast().last, last.window.isVisible {
            window.setFrame(last.window.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.window.frame.minX, y: last.window.frame.maxY)))
            window.setFrame(LittleWindow.fitOnScreen(window.frame), display: false)
        } else if let saved = Store.settings.string(forKey: LittleWindow.frameKey),
                  case let rect = NSRectFromString(saved),
                  rect.width >= window.minSize.width, rect.height >= window.minSize.height {
            window.setFrame(LittleWindow.fitOnScreen(rect), display: false)
        } else {
            window.center()
        }
    }

    private static let frameKey = "little.frame"

    /// Wholly on the screen it is mostly on, or the main one if none: a
    /// frame kept from a screen since unplugged would open out of reach.
    static func fitOnScreen(_ rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(rect) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return rect }
        var fitted = rect
        fitted.size.width = min(rect.width, visible.width)
        fitted.size.height = min(rect.height, visible.height)
        fitted.origin.x = max(visible.minX, min(rect.minX, visible.maxX - fitted.width))
        fitted.origin.y = max(visible.minY, min(rect.minY, visible.maxY - fitted.height))
        return fitted
    }

    func saveFrame() {
        guard window.isVisible, !window.isMiniaturized, !Store.testing else { return }
        Store.settings.set(NSStringFromRect(window.frame), forKey: LittleWindow.frameKey)
    }

    @objc func windowDidMove(_ notification: Notification) { saveFrame() }
    @objc func windowDidResize(_ notification: Notification) { saveFrame() }
}

/// The site over the page, and in the small window the field it turns into.
struct LittleTitle: View {
    weak var little: LittleWindow?
    let site: String
    @ObservedObject private var address: LittleAddress

    init(little: LittleWindow?, site: String) {
        self.little = little
        self.site = site
        address = little?.address ?? LittleAddress()
    }

    var body: some View {
        if address.editing, let little {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                LittleAddressField(little: little, address: address)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .frame(maxWidth: 440)
        } else if let little {
            Button(action: { little.startEditing() }) {
                name
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search or enter address   ⌘L")
        } else {
            name
        }
    }

    private var name: some View {
        Text(site)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
    }
}

/// The field itself, in AppKit, for the caret put in it on ⌘L and Return
/// and Escape read as the field's.
private struct LittleAddressField: NSViewRepresentable {
    weak var little: LittleWindow?
    @ObservedObject var address: LittleAddress

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.textColor = Palette.NS.ink
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(
            string: "Search or enter address",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: NSColor(Palette.ink.opacity(0.35)),
            ]
        )
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.little = little
        if field.stringValue != address.typed { field.stringValue = address.typed }
        if context.coordinator.answered != address.focusRequest {
            context.coordinator.answered = address.focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var little: LittleWindow?
        var answered = -1

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            MainActor.assumeIsolated { little?.address.typed = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            MainActor.assumeIsolated {
                switch command {
                case #selector(NSResponder.insertNewline(_:)): little?.submit(); return true
                case #selector(NSResponder.cancelOperation(_:)): little?.cancelEditing(); return true
                default: return false
                }
            }
        }
    }
}

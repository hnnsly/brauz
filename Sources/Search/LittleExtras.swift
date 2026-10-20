import SwiftUI

// The small window (Little.swift), with address and search entry,
// space selection, and saved placement fitted and cascaded to the screen.

/// What is being typed over the page, and the space selection state.
@MainActor
final class LittleAddress: ObservableObject {
    @Published var editing = false
    @Published var typed = ""
    @Published var focusRequest = 0
    @Published var spaceID: UUID
    @Published var spaces: [Space]

    private var observer: Any?

    init(spaceID: UUID = Space.firstID, spaces: [Space] = []) {
        self.spaceID = spaceID
        self.spaces = spaces.isEmpty ? Spaces.read() : spaces
        observer = NotificationCenter.default.addObserver(
            forName: Spaces.changed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                if let updated = note.object as? [Space] {
                    self?.updateSpaces(updated)
                } else {
                    self?.updateSpaces(Spaces.read())
                }
            }
        }
    }

    private func updateSpaces(_ newSpaces: [Space]) {
        spaces = newSpaces
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
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
        if let destination = destination(for: text) { navigate(to: destination) }
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

    // MARK: - Where it opens

    static let frameKey = "little.frame"

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
}

/// The site over the page, and in the small window the field it turns into.
struct LittleTitle: View {
    weak var little: LittleWindow?
    let site: String
    @ObservedObject var address: LittleAddress

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
        Text(site.isEmpty ? "Search or enter address" : site)
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
        context.coordinator.address = address
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
        weak var address: LittleAddress?
        var answered = -1

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            MainActor.assumeIsolated {
                if let address = self.address {
                    address.typed = field.stringValue
                } else {
                    self.little?.address.typed = field.stringValue
                }
            }
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

/// The space menu in the header, choosing the browsing space and keep destination.
struct LittleSpaceMenu: View {
    weak var little: LittleWindow?
    @ObservedObject var address: LittleAddress
    @State private var hovering = false

    private var currentSpace: Space? {
        address.spaces.first { $0.id == address.spaceID }
    }

    var body: some View {
        Menu {
            ForEach(address.spaces) { space in
                Button {
                    little?.switchSpace(to: space.id)
                } label: {
                    if space.id == address.spaceID {
                        Label(space.name, systemImage: "checkmark")
                    } else {
                        Label(space.name, systemImage: space.symbol)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: currentSpace?.symbol ?? "briefcase")
                    .font(.system(size: 11, weight: .medium))
                Text(currentSpace?.name ?? "Choose space")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Palette.hover : Palette.wash)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Space")
    }
}

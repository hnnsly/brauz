import AppKit
import SwiftUI

// The address field takes the keyboard when it is asked to, every time.
//
// Asked with makeFirstResponder from SwiftUI's update, focus was lost when
// the field wasn't in a window yet (⌘T opening a blank tab) or the window
// wasn't key yet. The request is kept here until it can be answered: when
// the field reaches a window, and again whenever that window becomes key.

final class OmniboxTextField: NSTextField {
    weak var coordinator: AddressField.Coordinator?
    var pendingFocusRequest: Int?
    private var windowKeyObserver: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            setupWindowObserver(window)
            if pendingFocusRequest != nil {
                claimFocus()
            }
        } else {
            removeWindowObserver()
        }
    }

    private func setupWindowObserver(_ window: NSWindow) {
        removeWindowObserver()
        windowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let browser = self.coordinator?.browser,
                      browser.fieldShowing else { return }
                self.claimFocus()
            }
        }
    }

    private func removeWindowObserver() {
        if let windowKeyObserver {
            NotificationCenter.default.removeObserver(windowKeyObserver)
            self.windowKeyObserver = nil
        }
    }

    func requestAppKitFocus(_ request: Int) {
        pendingFocusRequest = request
        claimFocus()
    }

    func claimFocus() {
        guard let window else { return }
        guard let request = pendingFocusRequest else { return }

        if let editor = currentEditor() as? NSTextView, window.firstResponder === editor {
            coordinator?.answered = request
            pendingFocusRequest = nil
            applyTextSelection()
            return
        }

        if window.makeFirstResponder(self) {
            coordinator?.answered = request
            pendingFocusRequest = nil
            applyTextSelection()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingFocusRequest == request else { return }
                if self.window?.makeFirstResponder(self) == true {
                    self.coordinator?.answered = request
                    self.pendingFocusRequest = nil
                    self.applyTextSelection()
                }
            }
        }
    }

    private func applyTextSelection() {
        guard let coordinator, let editor = currentEditor() as? NSTextView else { return }
        // The system paints selected text as a block of accent colour,
        // which over this pale field is the loudest thing in the
        // window. A tenth of the ink says "selected" quietly enough.
        editor.selectedTextAttributes = [
            .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
            .foregroundColor: Palette.NS.ink,
        ]
        // A draft come back to its blank tab is carried on, not typed
        // over: the caret after it. An address ⌘L raises is selected whole.
        if coordinator.browser.active?.isBlank == true, !coordinator.browser.typed.isEmpty {
            coordinator.select(from: coordinator.browser.typed.count, in: self)
        } else {
            editor.selectAll(nil)
        }
    }

    deinit {
        removeWindowObserver()
    }
}

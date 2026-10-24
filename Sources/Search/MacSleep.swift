import AppKit

// When the Mac goes to sleep, put background tabs to sleep at once regardless
// of idle age, while keeping visible tabs, drafts under their threshold, and
// exempt tabs awake.

@MainActor
enum MacSleep {
    private static let browsers = NSHashTable<Browser>.weakObjects()
    private static var started = false

    /// Registers a browser to sleep its background tabs on system sleep.
    static func watch(_ browser: Browser) {
        browsers.add(browser)
        startIfNeeded()
    }

    private static func startIfNeeded() {
        guard !started else { return }
        started = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                sleepAll()
            }
        }
    }

    /// Puts background tabs across all windows to sleep at once.
    static func sleepAll() {
        for browser in browsers.allObjects {
            browser.sleepIdle(within: 0)
        }
    }
}

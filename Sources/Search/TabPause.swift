import WebKit

// A tab left alone a few minutes is paused before it is put to sleep.
//
// Sleep (Sleep.swift) drops the page's view to give its memory back, and
// coming back means loading it again. Pausing keeps the page as it is and
// stops it running: WebKit suspends its scripts, timers and animations, so
// a tab out of sight costs no CPU, and showing it again is instant. A tab is
// paused after two and a half minutes and put to sleep after fifteen. A
// pinned tab is paused but never put to sleep.
//
// A paused page can't run JavaScript (WebKit throws), so nothing of Search's
// or an extension's is asked to while it is paused: see `isSuspended`, and
// the `paused` checks in Extensions.swift.

extension Browser {
    /// How long a tab goes without being looked at before it is paused.
    /// Two and a half minutes, or `pause.after` in seconds.
    static var pauseAfter: TimeInterval {
        let set = Store.settings.double(forKey: "pause.after")
        return set > 0 ? set : 2.5 * 60
    }

    /// Every tab idle long enough, paused. Run with `sleepIdle`, under the
    /// same setting; memory running short brings it forward the same way.
    func pauseIdle(within given: TimeInterval?) {
        let wait = given.map { min($0, Browser.pauseAfter) } ?? Browser.pauseAfter
        let now = Date()
        let idle = (tabs + parkedTabs).filter {
            !$0.paused && $0.built != nil
                && now.timeIntervalSince($0.touched) >= wait
                && awake(because: $0, forSleep: false) == nil
        }
        for tab in idle { pause(tab) }
    }

    /// Pictured first, for when it is put to sleep later, and never with
    /// something typed in it. Looked at again at each step, as sleep is.
    func pause(_ tab: Tab) {
        tab.unsaved { [weak self, weak tab] typed in
            guard let self, let tab, !typed, self.awake(because: tab, forSleep: false) == nil else { return }
            tab.snapshot { [weak self, weak tab] picture in
                guard let self, let tab, self.awake(because: tab, forSleep: false) == nil else { return }
                tab.picture = picture
                tab.pause()
            }
        }
    }
}

extension Tab {
    /// Suspended in place through WebKit's `_suspendPage:`, outside the
    /// public framework, so asked first. The page and its process stay.
    func pause() {
        guard !paused, let web = built else { return }
        let set = NSSelectorFromString("_suspendPage:")
        guard web.responds(to: set) else { return }
        typealias Suspend = @convention(c) (AnyObject, Selector, @convention(block) () -> Void) -> Void
        unsafeBitCast(web.method(for: set), to: Suspend.self)(web, set, {})
        paused = true
    }

    /// Running again, as it was, with nothing loaded.
    func resume() {
        guard paused, let web = built else { return }
        let set = NSSelectorFromString("_resumePage:")
        guard web.responds(to: set) else { return }
        typealias Resume = @convention(c) (AnyObject, Selector, @convention(block) () -> Void) -> Void
        unsafeBitCast(web.method(for: set), to: Resume.self)(web, set, {})
        paused = false
    }
}

extension WKWebView {
    /// Whether the page is suspended, when nothing may run in it.
    var isSuspended: Bool {
        let get = NSSelectorFromString("_isSuspended")
        guard responds(to: get) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method(for: get), to: Getter.self)(self, get)
    }
}

import WebKit

// Pages at 120 Hz, on a screen that can go that fast, like a MacBook Pro's,
// and hardware acceleration for scrolling on heavy pages.
//
// WebKit holds a page's animations, and the scrolling it draws itself, to
// about 60 frames a second even on a 120 Hz screen. That's Safari's default
// too, and it is the cheaper one: a page that animates at 120 draws twice as
// often, and in a short test on a 120 Hz MacBook Pro, a page with one CSS
// animation took about half again as much energy (Activity Monitor's 10 → 15).
// A page that is standing still costs nothing either way. So 60 unless
// asked for, in Settings › General.
//
// Fast pages also enable hardware-accelerated fixed/sticky element layers,
// off-screen tile retention during fast scrolling, GPU-accelerated CSS filters,
// layer-based SVG rendering, and CSS scroll anchoring on dynamic pages.

enum FrameRate {
    /// Settings › General › Pages at 120 Hz.
    ///
    /// Told to every open page at once, but WebKit reads the flags as a page
    /// is made: an open tab is sure to follow only once it is reloaded
    /// (going up, it often does at the next switch to it). Reloading them
    /// all here would lose whatever is typed in them, so it is left.
    @MainActor static var fast = false {
        didSet {
            guard fast != oldValue else { return }
            if fast {
                for page in Web.pages.allObjects { apply(to: page.configuration.preferences) }
            } else {
                // Only the pages this changed are given WebKit's own defaults
                // back; the rest were never touched.
                for preferences in changed.allObjects { revert(in: preferences) }
                changed.removeAllObjects()
            }
        }
    }

    /// The preferences this has modified, so switching off can undo
    /// exactly those and nothing else.
    @MainActor private static let changed = NSHashTable<WKPreferences>.weakObjects()

    /// Before a page's view is made, which is when WebKit reads the flags:
    /// a new tab, one opened by a site, and one woken from sleep.
    @MainActor static func apply(to preferences: WKPreferences) {
        guard fast else { return }
        set(false, for: near60, in: preferences)
        set(true, for: fixedCompositing, in: preferences)
        set(true, for: tileRetention, in: preferences)
        set(true, for: acceleratedFilters, in: preferences)
        set(true, for: scrollAnchoring, in: preferences)
        set(true, for: layerBasedSVG, in: preferences)
        changed.add(preferences)
    }

    private static func revert(in preferences: WKPreferences) {
        set(true, for: near60, in: preferences)
        set(false, for: fixedCompositing, in: preferences)
        set(false, for: tileRetention, in: preferences)
        set(false, for: acceleratedFilters, in: preferences)
        set(false, for: scrollAnchoring, in: preferences)
        set(false, for: layerBasedSVG, in: preferences)
    }

    /// Whether the page holds itself near 60, as its WebKit has it — nil
    /// where this WebKit has no such flag. For the bench.
    static func prefersNear60(_ preferences: WKPreferences) -> Bool? {
        let get = NSSelectorFromString("_isEnabledForFeature:")
        guard let flag = near60, preferences.responds(to: get) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        return unsafeBitCast(preferences.method(for: get), to: Getter.self)(preferences, get, flag)
    }

    // MARK: - WebKit's switches

    /// The switches are WebKit feature flags, from the list Safari shows
    /// under Develop › Feature Flags. They are looked up once: walking a list
    /// of hundreds of features for every tab would be wasteful.
    private static let features: [NSObject]? = {
        let list = NSSelectorFromString("_features")
        let type: AnyObject = WKPreferences.self
        guard type.responds(to: list),
              let all = type.perform(list)?.takeUnretainedValue() as? [NSObject]
        else { return nil }
        return all
    }()

    private static func feature(_ key: String) -> NSObject? {
        features?.first { $0.value(forKey: "key") as? String == key }
    }

    private static let near60 = feature("PreferPageRenderingUpdatesNear60FPSEnabled")
    private static let fixedCompositing = feature("AcceleratedCompositingForFixedPositionEnabled")
    private static let tileRetention = feature("AggressiveTileRetentionEnabled")
    private static let acceleratedFilters = feature("AcceleratedFiltersEnabled")
    private static let scrollAnchoring = feature("CSSScrollAnchoringEnabled")
    private static let layerBasedSVG = feature("LayerBasedSVGEngineEnabled")

    private static func set(_ on: Bool, for flag: NSObject?, in preferences: WKPreferences) {
        guard let flag else { return }
        let set = NSSelectorFromString("_setEnabled:forFeature:")
        guard preferences.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, on, flag)
    }
}

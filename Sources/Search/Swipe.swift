import Foundation
import WebKit

// Two fingers sideways means back, or forward.
//
// WebKit has a swipe of its own, and it drags the whole page across the window
// with a picture of the last one behind it. This is the other kind: a disc
// comes in from the edge you are pulling from, and past a certain point it is
// armed. Let go then, and the page simply goes back. Let go before, and it
// slips out again. Nothing slides, nothing is kept in memory to slide.
//
// The one hard question is whether a sideways swipe belongs to the page — a
// carousel, a wide table, a map, a canvas — or is free to mean something. The
// page is asked, on every sideways wheel event, whether anything under the
// pointer could scroll that way, or whether the page took the event for
// itself. The answer arrives a frame or two after the gesture starts, which
// is before there is anything to show.

enum Swipe {
    /// Native WebKit rubber-banding on all edges is kept, matching Safari and
    /// Tauri, so trackpad deceleration and small scrolls retain natural elasticity.
    static func calm(_ web: WKWebView) {}

    static let watch = ""
}

/// Where a sideways swipe has got to, for the disc that shows it.
struct Pull: Equatable {
    /// Pulling from the left edge, to go back; otherwise from the right.
    var back: Bool
    /// How far the fingers have come, in points, before any damping.
    var travel: CGFloat
    /// Far enough that letting go will do it.
    var armed: Bool
    /// Let go while armed: the page is on its way, and the disc leaves.
    var going: Bool
    /// Held once armed: the pages that way, top to bottom, in place of the
    /// disc, and the one letting go would open (see PageView.openList).
    var stops: [Stop]? = nil
    var picked = 0
}

/// A page in the list a held swipe shows.
struct Stop: Equatable {
    var title: String
    var url: URL
}

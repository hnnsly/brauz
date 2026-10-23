import Foundation
import AppKit

/// Cleaning tracking parameters from copied and shared links.
enum CleanLink {
    static let key = "privacy.cleanLinks"

    static var isEnabled: Bool {
        Store.settings.object(forKey: key) as? Bool ?? true
    }

    private static let blockedExact: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid",
        "msclkid", "yclid", "ysclid", "mc_eid", "mc_cid",
        "igshid", "_hsenc", "_hsmi"
    ]

    static func isTrackingParameter(_ name: String, host: String?) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix("utm_") { return true }
        if blockedExact.contains(lower) { return true }
        if lower == "si", let host = host?.lowercased() {
            if host == "youtu.be"
                || host == "youtube.com" || host.hasSuffix(".youtube.com")
                || host == "spotify.com" || host.hasSuffix(".spotify.com") {
                return true
            }
        }
        return false
    }

    static func clean(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let items = components.percentEncodedQueryItems,
              !items.isEmpty else {
            return url
        }
        let host = components.host
        let filtered = items.filter { !isTrackingParameter($0.name, host: host) }
        if filtered.count == items.count {
            return url
        }
        components.percentEncodedQueryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }

    static func clean(_ string: String) -> String {
        guard let url = URL(string: string), url.scheme != nil else { return string }
        let cleaned = clean(url)
        return cleaned == url ? string : cleaned.absoluteString
    }

    static func cleanIfEnabled(_ url: URL) -> URL {
        guard isEnabled else { return url }
        return clean(url)
    }

    static func cleanIfEnabled(_ string: String) -> String {
        guard isEnabled else { return string }
        return clean(string)
    }

    static func cleanPasteboardIfEnabled() {
        guard isEnabled else { return }
        let board = NSPasteboard.general
        guard let text = board.string(forType: .string),
              let url = URL(string: text),
              url.scheme != nil else { return }
        let cleaned = clean(url)
        if cleaned != url {
            board.clearContents()
            board.setString(cleaned.absoluteString, forType: .string)
        }
    }
}

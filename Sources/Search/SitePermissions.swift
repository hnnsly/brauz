import Foundation
import WebKit
import SwiftUI

/// Coordinates media capture permission prompts: merging requests from the same site,
/// queueing requests from different sites/tabs, cleaning up on tab navigation/close,
/// and satisfying single-device requests from a stored camera+microphone grant.
@MainActor
final class SitePermissionCoordinator {
    struct Prompt: Equatable {
        let tabID: UUID
        let site: String
        let host: String
        var type: WKMediaCaptureType
        let shy: Bool

        var wants: String {
            switch type {
            case .camera: return "camera"
            case .microphone: return "microphone"
            case .cameraAndMicrophone: return "camera and microphone"
            @unknown default: return "camera and microphone"
            }
        }

        var key: String {
            "\(site)|\(type.rawValue)"
        }
    }

    struct PendingRequest {
        let tabID: UUID
        let site: String
        let host: String
        let type: WKMediaCaptureType
        let shy: Bool
        let decisionHandler: (WKPermissionDecision) -> Void
    }

    private(set) var activePrompt: Prompt?
    private var activeHandlers: [(WKPermissionDecision) -> Void] = []
    private(set) var queue: [PendingRequest] = []

    var onPromptChanged: ((Prompt?) -> Void)?
    var isExternalPromptActive: () -> Bool = { false }

    /// Check if an origin already has a remembered permission decision.
    /// Single-device keys are the truth; a stored composite grant satisfies single devices as fallback.
    static func rememberedDecision(for site: String, type: WKMediaCaptureType) -> WKPermissionDecision? {
        let camera = Store.settings.object(forKey: "capture.\(site)|0") as? Bool
        let mic = Store.settings.object(forKey: "capture.\(site)|1") as? Bool
        let both = Store.settings.object(forKey: "capture.\(site)|2") as? Bool

        switch type {
        case .camera:
            if let camera { return camera ? .grant : .deny }
            if both == true { return .grant }
            return nil
        case .microphone:
            if let mic { return mic ? .grant : .deny }
            if both == true { return .grant }
            return nil
        case .cameraAndMicrophone:
            if camera == true && mic == true { return .grant }
            if camera == false && mic == false { return .deny }
            if camera == nil && mic == nil, let both { return both ? .grant : .deny }
            return nil
        @unknown default:
            if both == true { return .grant }
            return nil
        }
    }

    /// Handles a media capture permission request.
    func request(
        tabID: UUID,
        site: String,
        host: String,
        type: WKMediaCaptureType,
        shy: Bool,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        if !shy, let remembered = Self.rememberedDecision(for: site, type: type) {
            decisionHandler(remembered)
            return
        }

        if let current = activePrompt {
            if current.site == site && current.tabID == tabID {
                // Merge second camera/microphone request from same site into ONE prompt
                let mergedType: WKMediaCaptureType
                if current.type == type {
                    mergedType = current.type
                } else {
                    mergedType = .cameraAndMicrophone
                }
                activePrompt?.type = mergedType
                activeHandlers.append(decisionHandler)
                onPromptChanged?(activePrompt)
                return
            } else {
                // Request from different site or tab waits in queue
                queue.append(PendingRequest(
                    tabID: tabID,
                    site: site,
                    host: host,
                    type: type,
                    shy: shy,
                    decisionHandler: decisionHandler
                ))
                return
            }
        }

        if isExternalPromptActive() {
            queue.append(PendingRequest(
                tabID: tabID,
                site: site,
                host: host,
                type: type,
                shy: shy,
                decisionHandler: decisionHandler
            ))
            return
        }

        let prompt = Prompt(tabID: tabID, site: site, host: host, type: type, shy: shy)
        activePrompt = prompt
        activeHandlers = [decisionHandler]
        onPromptChanged?(activePrompt)
    }

    /// Answers the currently active prompt with a user decision.
    func answer(decision: WKPermissionDecision, keep: Bool = true) {
        guard let prompt = activePrompt else { return }
        let handlers = activeHandlers
        activePrompt = nil
        activeHandlers = []

        if keep, !prompt.shy {
            Self.store(decision: decision, for: prompt.site, type: prompt.type)
            SitePermissions.shared.objectWillChange.send()
        }

        for handler in handlers {
            handler(decision)
        }

        advanceQueue()
    }

    static func store(decision: WKPermissionDecision, for site: String, type: WKMediaCaptureType) {
        let granted = decision == .grant
        switch type {
        case .camera:
            Store.settings.set(granted, forKey: "capture.\(site)|0")
            syncComposite(for: site)
        case .microphone:
            Store.settings.set(granted, forKey: "capture.\(site)|1")
            syncComposite(for: site)
        case .cameraAndMicrophone:
            Store.settings.set(granted, forKey: "capture.\(site)|0")
            Store.settings.set(granted, forKey: "capture.\(site)|1")
            Store.settings.set(granted, forKey: "capture.\(site)|2")
        @unknown default:
            Store.settings.set(granted, forKey: "capture.\(site)|\(type.rawValue)")
        }
    }

    static func syncComposite(for site: String) {
        let cam = Store.settings.object(forKey: "capture.\(site)|0") as? Bool
        let mic = Store.settings.object(forKey: "capture.\(site)|1") as? Bool
        if cam == true && mic == true {
            Store.settings.set(true, forKey: "capture.\(site)|2")
        } else if cam == false && mic == false {
            Store.settings.set(false, forKey: "capture.\(site)|2")
        } else {
            Store.settings.removeObject(forKey: "capture.\(site)|2")
        }
    }

    func advanceQueue() {
        if isExternalPromptActive() { return }

        // Answer every queued request that rememberedDecision now resolves
        var unresolved: [PendingRequest] = []
        var resolved: [(PendingRequest, WKPermissionDecision)] = []
        for req in queue {
            if !req.shy, let remembered = Self.rememberedDecision(for: req.site, type: req.type) {
                resolved.append((req, remembered))
            } else {
                unresolved.append(req)
            }
        }
        queue = unresolved
        for (req, decision) in resolved {
            req.decisionHandler(decision)
        }

        while !queue.isEmpty && activePrompt == nil {
            let next = queue.removeFirst()

            var prompt = Prompt(
                tabID: next.tabID,
                site: next.site,
                host: next.host,
                type: next.type,
                shy: next.shy
            )
            var handlers = [next.decisionHandler]

            // Merge any other still-undecided requests in queue for this same site and tab
            var remaining: [PendingRequest] = []
            for req in queue {
                if req.site == prompt.site && req.tabID == prompt.tabID {
                    if req.type != prompt.type {
                        prompt.type = .cameraAndMicrophone
                    }
                    handlers.append(req.decisionHandler)
                } else {
                    remaining.append(req)
                }
            }
            queue = remaining

            activePrompt = prompt
            activeHandlers = handlers
            onPromptChanged?(activePrompt)
            return
        }

        if activePrompt == nil {
            onPromptChanged?(nil)
        }
    }

    /// Clears any active prompt and queued requests for a tab when it closes or navigates away.
    func drop(tabID: UUID) {
        var droppedActive = false
        if let prompt = activePrompt, prompt.tabID == tabID {
            let handlers = activeHandlers
            activePrompt = nil
            activeHandlers = []
            droppedActive = true
            for handler in handlers {
                handler(.deny)
            }
        }

        var remaining: [PendingRequest] = []
        for req in queue {
            if req.tabID == tabID {
                req.decisionHandler(.deny)
            } else {
                remaining.append(req)
            }
        }
        queue = remaining

        if droppedActive {
            advanceQueue()
        }
    }
}

/// Settings › Privacy: per-site camera, microphone, and location permissions.
final class SitePermissions: ObservableObject {
    static let shared = SitePermissions()

    enum Kind: String, CaseIterable, Comparable {
        case camera
        case microphone
        case location

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Entry: Identifiable, Equatable {
        let site: String
        let kind: Kind
        var id: String { "\(site)|\(kind.rawValue)" }
        var displayName: String { URL(string: site).map(SiteCard.site) ?? site }
        var description: String {
            switch kind {
            case .camera: return "Can use camera"
            case .microphone: return "Can use microphone"
            case .location: return "Can use location"
            }
        }
    }

    static var allowed: [Entry] {
        var entries: [Entry] = []
        let dict = Store.settings.dictionaryRepresentation()

        var sites: Set<String> = []
        for key in dict.keys where key.hasPrefix("capture.") {
            let rest = String(key.dropFirst("capture.".count))
            guard let pipe = rest.lastIndex(of: "|") else { continue }
            sites.insert(String(rest[..<pipe]))
        }

        for site in sites.sorted() {
            let camDirect = dict["capture.\(site)|0"] as? Bool
            let micDirect = dict["capture.\(site)|1"] as? Bool
            let both = dict["capture.\(site)|2"] as? Bool
            let loc = dict["capture.\(site)|location"] as? Bool == true

            let cam = camDirect == true || (both == true && camDirect != false)
            let mic = micDirect == true || (both == true && micDirect != false)

            if cam { entries.append(Entry(site: site, kind: .camera)) }
            if mic { entries.append(Entry(site: site, kind: .microphone)) }
            if loc { entries.append(Entry(site: site, kind: .location)) }
        }
        return entries
    }

    static func forget(_ entry: Entry) {
        switch entry.kind {
        case .camera:
            if Store.settings.object(forKey: "capture.\(entry.site)|1") == nil,
               Store.settings.object(forKey: "capture.\(entry.site)|2") as? Bool == true {
                Store.settings.set(true, forKey: "capture.\(entry.site)|1")
            }
            Store.settings.removeObject(forKey: "capture.\(entry.site)|0")
            Store.settings.removeObject(forKey: "capture.\(entry.site)|2")
        case .microphone:
            if Store.settings.object(forKey: "capture.\(entry.site)|0") == nil,
               Store.settings.object(forKey: "capture.\(entry.site)|2") as? Bool == true {
                Store.settings.set(true, forKey: "capture.\(entry.site)|0")
            }
            Store.settings.removeObject(forKey: "capture.\(entry.site)|1")
            Store.settings.removeObject(forKey: "capture.\(entry.site)|2")
        case .location:
            Store.settings.removeObject(forKey: "capture.\(entry.site)|location")
        }
        shared.objectWillChange.send()
    }
}

/// Settings › Privacy: the sites allowed to use camera, microphone, or location, each with a Remove button.
struct SitePermissionsList: View {
    @ObservedObject private var permissions = SitePermissions.shared

    var body: some View {
        let entries = SitePermissions.allowed
        if !entries.isEmpty {
            ForEach(entries) { entry in
                Rule()
                Line(entry.displayName, entry.description) {
                    Pill("Remove") { SitePermissions.forget(entry) }
                }
            }
        }
    }
}


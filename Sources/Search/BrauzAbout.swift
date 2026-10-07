import SwiftUI

// Settings › About, as Brauz: its own mark and name, the credit to Search it
// is built from, and where updates and reports go now that they don't go to
// Office Commun (see ForkIdentity.swift, BrauzUpdates.swift and Updater's `looks`).

enum BrauzAbout {
    static let repository = URL(string: "https://github.com/hnnsly/Search")!

    /// A new issue on the fork, with the version already in it. Settings and
    /// Help › Send Feedback both come here (Links.writeFeedback).
    static func writeFeedback() {
        var issue = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        issue?.queryItems = [
            URLQueryItem(name: "body", value: "\n\n—\nBrauz \(Updater.version), build \(Updater.build), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
        ]
        guard let url = issue?.url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The mark, the name, and what it is built on.
struct BrauzAboutHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            BrauzMark()
                .fill(Palette.ink)
                .aspectRatio(BrauzMark.size.width / BrauzMark.size.height, contentMode: .fit)
                .frame(height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Brauz")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("based on Search by Office Commun · version \(Updater.version)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

/// Settings › About: whether a newer release is out on GitHub.
struct BrauzUpdatesLine: View {
    @ObservedObject private var updates = BrauzUpdates.shared

    var body: some View {
        if let newer = updates.newer {
            Line("Brauz \(newer.version) is out", "Build \(newer.build), on GitHub") {
                Pill("Download", filled: true) {
                    NSWorkspace.shared.open(newer.page)
                }
            }
        } else {
            Line("Updates", detail) {
                Pill(updates.checking ? "Checking…" : "Check now") {
                    updates.checkByHand()
                }
                .disabled(updates.checking)
            }
        }
    }

    private var detail: String {
        if let last = updates.lastChecked {
            return "Checked \(last.formatted(.relative(presentation: .named))) — Brauz looks on GitHub once a day"
        }
        return "Brauz looks on GitHub once a day"
    }
}

/// The б of the app's icon, the same shape as Icon/icon.swift draws: one
/// stroke, 72 units wide, in that drawing's 1024-unit coordinates.
struct BrauzMark: Shape {
    /// The stroke's own bounds, nothing outside it.
    static let bounds = CGRect(x: 336, y: 256, width: 352, height: 540)
    static var size: CGSize { bounds.size }

    func path(in rect: CGRect) -> Path {
        var line = Path()
        line.move(to: CGPoint(x: 644, y: 292))
        line.addLine(to: CGPoint(x: 515, y: 292))
        line.addCurve(to: CGPoint(x: 372, y: 410), control1: CGPoint(x: 429.2, y: 292), control2: CGPoint(x: 372, y: 339.2))
        line.addLine(to: CGPoint(x: 372, y: 620))
        line.addEllipse(in: CGRect(x: 372, y: 480, width: 280, height: 280))
        let stroke = line.strokedPath(StrokeStyle(lineWidth: 72, lineCap: .round, lineJoin: .round))
        // Fit to the frame, centred, as an SVG viewBox's "meet".
        let bounds = BrauzMark.bounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let fit = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return stroke.applying(fit)
    }
}

import AppKit
import SwiftUI
import WebKit

// Extension warnings inspector and diagnostic log sheet.
//
// Manifest warnings from WebKit (WKWebExtensionContext.errors) and runtime
// errors collected while running (Extensions.errors) are shown together,
// newest last, with a button to copy the list as text.

public enum ExtensionWarnings {
    public static func formatContextError(_ error: Error) -> String {
        let e = error as NSError
        if let under = e.userInfo[NSUnderlyingErrorKey] as? NSError {
            let underDesc = under.localizedDescription
            if !underDesc.isEmpty && underDesc != e.localizedDescription {
                return "\(e.localizedDescription): \(underDesc)"
            }
        }
        if let reason = e.localizedFailureReason, !reason.isEmpty && reason != e.localizedDescription {
            return "\(e.localizedDescription): \(reason)"
        }
        return e.localizedDescription
    }

    public static func combine(contextErrors: [Error], runtimeErrors: [String]) -> [String] {
        contextErrors.map(formatContextError) + runtimeErrors
    }

    public static func totalCount(contextCount: Int, runtimeCount: Int) -> Int {
        contextCount + runtimeCount
    }

    public static func copyText(errors: [String]) -> String {
        errors.joined(separator: "\n")
    }

    public static func copyToPasteboard(errors: [String]) {
        let text = copyText(errors: errors)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@available(macOS 15.4, *)
struct ExtensionRowDetail: View {
    let item: Installed
    @ObservedObject var extensions: Extensions
    let context: WKWebExtensionContext?
    let folder: String

    @State private var showingSheet = false
    @State private var hovering = false

    private var runtimeErrors: [String] {
        extensions.errors[item.id] ?? []
    }

    private var contextErrors: [Error] {
        context?.errors ?? []
    }

    private var count: Int {
        ExtensionWarnings.totalCount(contextCount: contextErrors.count, runtimeCount: runtimeErrors.count)
    }

    var body: some View {
        var parts = ["Version \(item.version)", item.fromStore ? "Chrome Web Store" : folder]
        if item.enabled, context == nil { parts.append("couldn't start") }
        if extensions.newTabPageID == item.id {
            parts.append("shows in new tabs")
        }

        return HStack(spacing: 0) {
            Text(parts.joined(separator: " · "))
            if count > 0 {
                Text(" · ")
                    .fixedSize()
                Button {
                    showingSheet = true
                } label: {
                    Text("\(count) warning\(count == 1 ? "" : "s")")
                        .underline(hovering)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.unsafe)
                .onHover { hovering = $0 }
                .fixedSize()
            }
        }
        .sheet(isPresented: $showingSheet) {
            ExtensionWarningsSheet(item: item, extensions: extensions, context: context)
        }
    }
}

@available(macOS 15.4, *)
struct ExtensionWarningsSheet: View {
    let item: Installed
    @ObservedObject var extensions: Extensions
    let context: WKWebExtensionContext?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var errorList: [String] {
        ExtensionWarnings.combine(
            contextErrors: context?.errors ?? [],
            runtimeErrors: extensions.errors[item.id] ?? []
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let icon = context?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("\(errorList.count) warning\(errorList.count == 1 ? "" : "s")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Pill(copied ? "Copied" : "Copy") {
                    ExtensionWarnings.copyToPasteboard(errors: errorList)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }
                Pill("Done", filled: true) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if errorList.isEmpty {
                        Text("No warnings or errors.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else {
                        ForEach(Array(errorList.enumerated()), id: \.offset) { _, text in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.unsafe)
                                    .padding(.top, 3)
                                Text(text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Palette.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 480, idealWidth: 540, maxWidth: 640, minHeight: 260, idealHeight: 340, maxHeight: 480)
        }
        .background(Palette.ground)
        .onExitCommand { dismiss() }
    }
}

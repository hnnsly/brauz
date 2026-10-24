---
status: fixed
found: 2026-10-23
---
# Clickable warning count on extension row opens diagnostics sheet with WebKit and runtime error logs

## Symptom
The extensions row in Settings > Extensions displays a warning count subtitle, but provides no way to view the actual warning or error details.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter ExtensionWarningsTests`

## Cause
`ExtensionsUI.swift:223` formats the warning count using `context?.errors.count`, but the subtitle is rendered as plain text without any click interaction. Furthermore, `Extensions.shared.errors` (holding runtime script crashes and shims) and WebKit's `WKWebExtensionContext.errors` are maintained in separate structures, so runtime errors do not contribute to the row warning indicator.
Ranked hypotheses:
1. Missing UI interactivity: Subtitle warning text is plain unclickable Text. (Confirmed)
2. Data source split: WKWebExtensionContext errors and runtime script errors in `Extensions.errors` are not unified in the warning count. (Confirmed)

Ruled out / wrong in the first draft:
- Tooltips (`.help`) were considered, but tooltips cannot display multiline stack traces or support text selection and copying.

## Decisions (2026-10-24)
- The "N warnings" text on the extension row in Settings > Extensions becomes clickable and opens a sheet listing both WebKit's context errors and the runtime errors `Extensions.swift` already collects, with a Copy button.
- New UI in a fork-only file, with one hook in `ExtensionsUI.swift`.
- Not chosen: an "Errors & Warnings…" item in the row menu, or both entry points.
- New UI in a fork-only file (`Sources/Search/ExtensionWarnings.swift`), with one hook in `ExtensionsUI.swift`.
- Not chosen: tooltips or context menu items alone, because users need to easily inspect and copy multi-line error traces.

## Fix
In `Sources/Search/ExtensionsUI.swift` (`Row.detail`), replace static warning text with an interactive button that opens an extension warnings sheet. Move the UI and combining logic into fork-only `Sources/Search/ExtensionWarnings.swift`. The warning button uses `.fixedSize()` so long folder paths truncate instead of the warning label. The sheet presentation modifier is attached to the root view rather than the conditional button so an open sheet survives warning count changes or dropping to zero while open. The count and sheet combine `WKWebExtensionContext.errors` and `Extensions.errors` (newest last). The sheet includes an error list with monospaced text selection and a Copy button that copies all errors separated by newlines to the clipboard.

## Guarded by
`Tests/SearchTests/ExtensionWarningsTests.swift` (covers error formatting, underlying error descriptions, unified error combination newest last, total count computation, and newline-separated clipboard text). Two layout points are checked by hand rather than asserting on SwiftUI internal type strings: attaching `.sheet` to the root view rather than the conditional button so an open sheet survives count dropping to zero, and `.fixedSize()` on the warning button so long folder paths truncate instead of the warning label.

## Acceptance
- Users can click or inspect extension warnings/errors to view detailed diagnostic messages.
- The warning count includes both context errors and runtime errors.
- Users can copy the combined error list to the clipboard.

## Files
- `Sources/Search/ExtensionWarnings.swift`
- `Sources/Search/ExtensionsUI.swift`
- `Tests/SearchTests/ExtensionWarningsTests.swift`

## Test by hand
Start: Run `./build.sh` and open `build/Brauz.app`. Go to Settings › Extensions (⌘, › Extensions).
1. Load or run an extension that produces warnings or errors (such as an unpacked extension with unrecognized manifest keys or script errors). Expect the extension row in Settings › Extensions to show "N warning(s)" as a clickable button in warning amber.
2. Click the warning count button. Expect a sheet to open displaying the extension's icon, name, warning count, and all diagnostic messages (newest last).
3. Click the "Copy" button in the sheet header. Expect the button to briefly show "Copied" and the full list of errors to be copied to the clipboard. Paste into a text editor to verify the newline-separated messages.
4. Press "Done" or the Escape key. Expect the sheet to close smoothly.
5. Layout check 1 (fixed size): With an extension loaded from a very long folder path, narrow the window. Verify that the folder path truncates with an ellipsis while the warning count button remains fully visible.
6. Layout check 2 (sheet root attachment): Open the warnings sheet for an extension, then clear its runtime errors in the background so the warning count drops to zero. Verify the open sheet remains presented and dismissable without disappearing abruptly or crashing.

What no test covers: AppKit pasteboard write verification, SwiftUI modal sheet presentation animation in the live window, sheet attachment to the root view surviving count dropping to zero, and fixedSize button preventing warning label truncation over folder path (both layout points checked by hand).

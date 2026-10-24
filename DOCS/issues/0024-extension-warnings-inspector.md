---
status: open
found: 2026-10-23
---
# Clickable warning count on extension row opens diagnostics sheet with WebKit and runtime error logs

## Symptom
The extensions row in Settings > Extensions displays a warning count subtitle, but provides no way to view the actual warning or error details.

## Loop
`python3 Tests/extension_warnings.py` driving build/Brauz.app via the bench socket.

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

## Fix
Make the warning text clickable in `ExtensionsUI.swift`, presenting a sheet powered by a new fork-only `ExtensionDiagnostics.swift` view that displays unified WebKit context errors and runtime script logs along with a Copy button.

## Guarded by
`Tests/extension_warnings.py` bench probe.

## Acceptance
- The warning count on the extension row is clickable.
- Clicking it opens a diagnostic sheet listing both WebKit context errors and runtime errors.
- A Copy button allows copying the diagnostics to the clipboard.

## Files
- `Sources/Search/ExtensionsUI.swift`
- `Sources/Search/ExtensionDiagnostics.swift`

## Test by hand
Load an extension with errors, open Settings > Extensions, click the warning count text, and verify the diagnostic sheet and Copy button function correctly.

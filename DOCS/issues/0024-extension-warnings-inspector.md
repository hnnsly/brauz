---
status: open
found: 2026-10-23
---
# Expose extension warning and error details in the extensions panel

## Symptom
The extensions tab or panel sometimes displays a vague "1 warning" indicator, but provides no way to view the actual warning, error messages, or logs from the extension.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter Extension`

## Cause
Extension error/warning reporting delegates or storage in `Extensions.swift` do not expose diagnostic logs to the UI view.

## Fix
Capture and display extension console/diagnostic warnings and errors in the extension settings sheet or inspector.

## Guarded by
Extension diagnostics tests.

## Acceptance
- Users can click or inspect extension warnings/errors to view detailed diagnostic messages.

## Files
- `Sources/Search/ExtensionShims.swift`
- `Sources/Search/Settings.swift`

## Test by hand
Load an extension with a warning/error, inspect the extensions panel/settings to view details.

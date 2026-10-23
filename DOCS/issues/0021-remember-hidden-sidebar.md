---
status: open
found: 2026-10-23
---
# Remember hidden sidebar state across launches and space switches

## Symptom
The sidebar folding state (when folded away) does not always persist correctly or reset as expected across window launches and space switches.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter Window`

## Cause
Preference or session persistence for `folded` state is either not saved or overwritten by default launch configurations.

## Fix
Persist and restore `browser.folded` state reliably in session shape and preferences.

## Guarded by
Session restoration tests.

## Acceptance
- Launching Brauz or switching spaces remembers whether the sidebar was folded/hidden.

## Files
- `Sources/Search/Browser.swift`
- `Sources/Search/Session.swift`
- `Sources/Search/Prefs.swift`

## Test by hand
Fold the sidebar with `⌘S`, restart or switch spaces, verify it stays folded.

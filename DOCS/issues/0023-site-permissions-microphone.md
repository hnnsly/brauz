---
status: open
found: 2026-10-23
---
# Provide site permissions settings and inspection (e.g., microphone requests like Yandex Telemost)

## Symptom
Websites requesting microphone or media permissions (such as Yandex Telemost) do not always prompt correctly or get stuck without clear rejection/acceptance options, and there is no UI to inspect or reset current site permissions.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test`

## Cause
`WKUIDelegate` permission request methods (`runOpenPanel`, media capture permissions) lack explicit handlers or persistent site permission storage and inspection settings.

## Fix
Implement media capture permission delegates and add a site permissions management interface in Settings.

## Guarded by
Media permission delegation tests.

## Acceptance
- Sites requesting microphone/camera permissions prompt correctly.
- Settings provides a way to view and revoke current site permissions.

## Files
- `Sources/Search/Web.swift`
- `Sources/Search/Settings.swift`
- `Sources/Search/Prefs.swift`

## Test by hand
Visit a video/audio conferencing site, verify permission prompt and settings inspection.

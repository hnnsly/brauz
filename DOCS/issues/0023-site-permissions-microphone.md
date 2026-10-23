---
status: open
found: 2026-10-23
---
# Provide site permissions settings and inspection for camera, microphone, and location

## Symptom
Websites requesting microphone or camera access (such as Yandex Telemost) fail or stall because concurrent media capture requests are immediately rejected by the browser delegate, and closing a tab with a prompt active locks out future requests. Settings lacks per-site inspection and revocation for camera, microphone, or location permissions.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter SitePermissionsTests`

## Cause
Brauz implements media capture delegation (`webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` in `/Users/daniil/Dev/Search/Sources/Search/Browser.swift:5436`), but rejects concurrent media capture requests immediately if a prompt is already waiting (`Sources/Search/Browser.swift:5482`), and fails to clear active prompt decision handlers when a tab is closed (`Sources/Search/Browser.swift:2981`). Separate key storage for individual types (`.camera=0`, `.microphone=1`, `.cameraAndMicrophone=2`) prevents composite grants from satisfying single-device requests.
Ranked hypotheses:
1. Concurrent media capture requests hit guard decide == nil and get denied.
2. Separate key storage for individual types prevents composite grants from satisfying single-device requests.
3. Tab closure fails to cancel pending decision handlers, deadlocking future prompts.
Ruled out / wrong in the first draft:
- WKUIDelegate media capture delegate methods were assumed missing, but are fully implemented in Browser.swift:5436.
- Sources/Search/Web.swift was assumed to exist, but does not exist in the repository.
- Prefs.swift was assumed to manage site permissions, but per-site permissions reside in Store.settings.

## Decisions (2026-10-24)
Fix the request bugs and add a per-site list in Settings under Privacy (Camera, Microphone, and Location per site, each removable) in a fork-only file with short hooks. When a page asks for the microphone and then the camera while the first prompt is still open, show one merged prompt ("site wants your camera and microphone") whose answer covers both requests. Clear the pending prompt when its tab closes or navigates away, and let a stored camera plus microphone grant satisfy a single-device request. Not chosen: keeping bulk reset only without per-site list, or ignoring concurrent media requests.

## Fix
Implement request queueing and merging in `Sources/Search/Browser.swift` for concurrent media capture requests, add a composite permission check, ensure active prompt cleanup on tab close and navigation, and introduce a fork-only `Sources/Search/SitePermissions.swift` file for per-site inspection and revocation hooked into `Sources/Search/Settings.swift`.

## Guarded by
`SitePermissionsTests` in `Tests/SearchTests/`.

## Acceptance
- Concurrent camera and microphone requests show a merged prompt and succeed.
- Closing a tab with a pending prompt clears the prompt state without blocking other tabs.
- Settings provides a per-site inspection and removal interface for camera, microphone, and location permissions.

## Files
- `Sources/Search/Browser.swift`
- `Sources/Search/SitePermissions.swift`
- `Sources/Search/Settings.swift`

## Test by hand
Visit a WebRTC conferencing site requesting both camera and microphone, check the merged prompt, and verify site permissions appear in Settings under Privacy.

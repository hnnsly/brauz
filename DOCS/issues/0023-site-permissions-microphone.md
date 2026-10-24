---
status: fixed
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
Extracted media capture permission management into `SitePermissionCoordinator` in fork-only `Sources/Search/SitePermissions.swift`:
- Merges concurrent camera and microphone requests from the same site into a single prompt ("camera and microphone") resolving all handlers on answer.
- Queues requests from different sites or tabs until the current prompt resolves. When dequeuing in `advanceQueue`, answers any queued request resolved by remembered decisions without prompting, merging only still-undecided requests into the next prompt.
- Automatically denies and cleans up pending prompts and handlers when their tab closes or navigates away. Single cleanup hook via `dropQuestions(for:)` in `Dialogs.swift`. Coordinator handles tabs only (keyed by tab UUID).
- Requests from web views that are not tabs (extension popups, side panels, offscreen documents) route through upstream's original `askedForCapture` path unchanged, prompting on the first request and refusing concurrent requests without denying the active prompt. Remembered decisions apply to popups as upstream did.
- Satisfies single-device requests when a composite camera+microphone grant is already stored, without letting a composite deny suppress single-device requests. A composite request with one device denied and the other unknown prompts. Composite deny is only written when both devices are denied.
- Added `SitePermissionsList` in Settings › Privacy listing per-site camera, microphone, and location permissions with Remove buttons.
- Hooked coordinator into `Browser.swift`, `Dialogs.swift`, and `Settings.swift`.
- Removed dead `dropAll`.

Files touched:
- `Sources/Search/SitePermissions.swift`
- `Sources/Search/Browser.swift`
- `Sources/Search/Dialogs.swift`
- `Sources/Search/Settings.swift`
- `Tests/SearchTests/SitePermissionsTests.swift`

## Guarded by
`SitePermissionsTests` in `Tests/SearchTests/SitePermissionsTests.swift` (`testAdvanceQueueResolvesGrantedDeviceWithoutPromptAndAsksUndecided`, `testExtensionPopupWebViewPromptsInsteadOfBeingDenied`, `testDenyCameraThenAskMicrophonePrompts`, `testTabCloseClearsPendingCaptureRequest`, and combinations).

## Acceptance
- Concurrent camera and microphone requests show a merged prompt and succeed.
- Closing a tab with a pending prompt clears the prompt state without blocking other tabs.
- Settings provides a per-site inspection and removal interface for camera, microphone, and location permissions.
- Denying camera still allows microphone to prompt without being denied.
- Extension popup web views prompt for media capture rather than being denied.

## Files
- `Sources/Search/SitePermissions.swift`
- `Sources/Search/Browser.swift`
- `Sources/Search/Dialogs.swift`
- `Sources/Search/Settings.swift`
- `Tests/SearchTests/SitePermissionsTests.swift`

## Test by hand
Start with `DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer ./build.sh` then `open build/Brauz.app`.
1. Open a conferencing site (e.g. Yandex Telemost or Google Meet): expect a single merged prompt asking for camera and microphone rather than microphone failing.
2. Click Allow: expect both media streams to connect.
3. Open Settings › Privacy: expect to see the site with separate "Can use camera" and "Can use microphone" rows, each with a Remove pill.
4. Click Remove on Camera: reload the page and expect the prompt to ask for camera again while microphone remains granted.
5. Open two tabs on the same site; have tab 1 request camera and tab 2 request microphone then camera; allow tab 1's camera: expect tab 2's camera granted without a prompt and only microphone asked.
6. Open an extension popup requesting media: expect prompt to appear, subsequent request refused without canceling the prompt, and Allow to grant capture.
What no automated test covers: live AVFoundation hardware access and WebKit media hardware stream acquisition.

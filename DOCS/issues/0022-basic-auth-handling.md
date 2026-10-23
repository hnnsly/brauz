---
status: open
found: 2026-10-23
---
# Improve handling and prompting for HTTP Basic Authentication websites

## Symptom
Websites requiring HTTP Basic Authentication are handled poorly or fail to prompt reliably, making it difficult to determine if it is a site config issue or a browser limitation.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test`

## Cause
`WKNavigationDelegate` methods (`didReceiveAuthenticationChallenge`) may not be fully implemented or delegate the authentication challenge properly to UI dialogs.

## Fix
Implement robust handling of `didReceiveAuthenticationChallenge` to present credential sheets for HTTP Basic Auth.

## Guarded by
Authentication delegation tests.

## Acceptance
- Visiting a Basic Auth protected site presents a clean credential prompt and authenticates successfully.

## Files
- `Sources/Search/Web.swift`
- `Sources/Search/Browser.swift`

## Test by hand
Visit a local or public basic auth test URL, verify authentication prompt appears.

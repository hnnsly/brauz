---
status: fixing
found: 2026-10-23
---
# HTTP Basic, Digest, and NTLM credentials should be remembered in browser passwords and filled on repeat visits

## Symptom
The browser prompts for HTTP sign-in via its sheet in Dialogs.swift, but credentials are session-only and never saved to the browser's own passwords vault or auto-filled on repeat visits. Furthermore, the 2-failure cutoff permanently aborts authentication on typos.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter BasicAuthTests`

## Cause
`Browser` implements `didReceiveAuthenticationChallenge` in `/Users/daniil/Dev/Search/Sources/Search/Dialogs.swift:228`. When Basic, Digest, or NTLM challenges arrive, `signIn()` imposes a hard failure count cutoff at `previousFailureCount >= 2` (/Users/daniil/Dev/Search/Sources/Search/Dialogs.swift:305) and builds an `NSAlert` sheet with `askSignIn()` (/Users/daniil/Dev/Search/Sources/Search/Dialogs.swift:317). Credentials are created with `.forSession` persistence only (/Users/daniil/Dev/Search/Sources/Search/Dialogs.swift:350), with zero integration with Vault or stored passwords.

Ruled out / wrong in the first draft:
- Assuming authentication delegation was unimplemented (`didReceiveAuthenticationChallenge` is fully implemented in `Dialogs.swift`).
- Assuming `Web.swift` owns the challenge handling (it does not exist; challenge handling lives in `Dialogs.swift`).

## Decisions (2026-10-24)
- Brauz should save Basic/Digest/NTLM passwords in its own passwords vault, fill them the next time the same site asks, and let the user remove ("drop") them.
- The existing prompt works; its 2-failure cutoff and session-only credentials are the current behavior.
- Saving: the sign-in box gets a "Remember in Brauz" checkbox under the password field, on by default. The password is saved to the Vault only once the site accepts it. Not chosen: a "Save password?" offer after sign-in, saving always.
- Filling: when the same site asks again, the box still appears, with name and password filled in; the user presses Sign In. Not chosen: signing in silently.
- Removing: a saved sign-in shows in Settings › Passwords and is removed there like any other password.

## Fix
Added `BasicAuth.swift` to handle credential storage, lookup by protection space (host, port, realm, method), and staged acceptance:
- Added a "Remember in Brauz" checkbox under the password field in `askSignIn`, checked by default.
- Staged credentials save to the Vault only after the site accepts them (main-frame response status != 401).
- Rejected credentials (401 response or challenge with previous failure count > 0) are discarded immediately and never saved.
- Subsequent challenges for the same protection space open with name and password prefilled, requiring the user to press Sign In.
- Saved HTTP sign-in entries appear in Settings › Passwords like any other password (no separate badge) and can be removed there. Form autofill on web pages ignores them.
- Avoided macOS `errSecParam` by querying Keychain attributes with `kSecMatchLimitAll` and reading secrets with `kSecMatchLimitOne`.
- Added `kSecAttrAuthenticationType: kSecAttrAuthenticationTypeHTMLForm` to the `Vault.save` update identity so saving a form login does not overwrite a BasicAuth sign-in for the same host and user.
- Added `kSecAttrAuthenticationTypeHTMLForm` to form-login queries in `Vault.swift` (`secret` when `isSignIn == false`, `rows(where:)`, and `forget`) to keep Keychain queries for form logins apart from HTTP sign-ins.
- Injectable `BasicAuthStore` protocol with thread-safe `MemoryBasicAuthStore` and default `KeychainBasicAuthStore`.
- Port and realm included in `Kept.id` to prevent collision and allow selective removal. Host casing normalized to lowercase.

Files:
- `Sources/Search/BasicAuth.swift`
- `Sources/Search/Vault.swift`
- `Sources/Search/Dialogs.swift`
- `Sources/Search/Browser.swift`
- `Tests/SearchTests/BasicAuthTests.swift`

## Guarded by
`BasicAuthTests` in `Tests/SearchTests/BasicAuthTests.swift`, including:
- `testSaveSignInFirstThenFormLoginBothSurviveWithOwnPasswords`: verifies a saved sign-in and a form login for the same host and user both survive with their own passwords.
- `testBasicAuthSecretWithNilPortAndRealmReadsFromKeychain`: verifies `BasicAuth.secret` reads through the Keychain path with nil port and realm without `errSecParam`.

## Acceptance
- The sign-in box has a "Remember in Brauz" checkbox, on by default.
- Submitting wrong credentials discards them and saves nothing.
- Submitting valid credentials authenticates and saves to the Vault only after acceptance.
- Re-visiting the protection space opens the prompt with name and password prefilled.
- Saved credentials appear in Settings › Passwords and can be removed.

## Files
- `Sources/Search/BasicAuth.swift`
- `Sources/Search/Vault.swift`
- `Sources/Search/Dialogs.swift`
- `Sources/Search/Browser.swift`
- `Tests/SearchTests/BasicAuthTests.swift`

## Test by hand
How to start: Run `./build.sh` and open `build/Brauz.app`.
1. Navigate to a Basic Auth test URL (such as `http://httpbin.org/basic-auth/user/passwd`). Expect a prompt with Name, Password, and a checked "Remember in Brauz" checkbox.
2. Enter invalid credentials. Expect the prompt to say that was not accepted, and no credential stored in Settings › Passwords.
3. Enter valid credentials and click Sign In. Expect the page to authenticate and the credential to appear under the site in Settings › Passwords.
4. Open the test URL again in a new session. Expect the prompt to appear with name and password prefilled.
5. In Settings › Passwords, click Remove on the entry. Expect the credential to be forgotten.
What no test covers: Visual alignment of the AppKit checkbox inside the sheet and Touch ID prompt when revealing the password.

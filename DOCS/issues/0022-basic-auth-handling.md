---
status: open
found: 2026-10-23
---
# HTTP Basic, Digest, and NTLM credentials should be remembered in browser passwords and filled on repeat visits

## Symptom
The browser prompts for HTTP sign-in via its sheet in Dialogs.swift, but credentials are session-only and never saved to the browser's own passwords vault or auto-filled on repeat visits. Furthermore, the 2-failure cutoff permanently aborts authentication on typos.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test`

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
To be implemented per the decisions. Hook in `Sources/Search/Dialogs.swift` (`askSignIn`, `signIn`), storage through `Sources/Search/Vault.swift`.

## Guarded by
Authentication delegation tests.

## Acceptance
- The sign-in box has a "Remember in Brauz" checkbox, on by default.
- After an accepted sign-in with the box checked, the same site's next challenge opens the box prefilled.
- A rejected password is not saved.
- The saved sign-in appears in Settings › Passwords and can be removed there.

## Files
- `Sources/Search/Dialogs.swift`
- `Sources/Search/Vault.swift`

## Test by hand
Visit a basic auth test URL, enter credentials, verify saving and repeat-visit fill.

# This fork

`hnnsly/Search` is Brauz, a fork of [driceroland/Search](https://github.com/driceroland/Search). Its `main` is upstream's `main` with a short stack of the fork's commits on top. There is no mirror branch; `upstream/main`, which `git fetch upstream` keeps current, is the base.

To see exactly what the fork adds:

```bash
git log --oneline upstream/main..main
```

## Remotes

```bash
git remote add upstream git@github.com:driceroland/Search.git
git config rerere.enabled true
```

`origin` is this fork, `upstream` is the original. `rerere` makes git remember how a conflict was resolved and reuse that the next time the same conflict comes up.

## Syncing with upstream

```bash
./sync.sh
git push --force-with-lease origin main
```

`sync.sh` fetches upstream and replays the fork's commits on top of it, keeping `CHANGELOG.md` as upstream has it at every commit. Then it runs the tests and the build, and prints the push command; it never pushes itself. Before rebasing it tags the old `main` as `pre-sync-backup`, so `git reset --hard pre-sync-backup` undoes a sync that went wrong.

When a commit doesn't apply, `sync.sh` stops and names the commit and its files. Resolve them, `git add` them, `git rebase --continue`, and run `./sync.sh` again; it picks up at the tests. Each commit covers one area, so a conflict points at what it was for. When resolving, keep the rules below.

Sync often: a week of upstream rarely conflicts, a month can. Every Monday the Upstream workflow (`.github/workflows/upstream.yml`) counts the commits Search has that Brauz hasn't, tries the rebase, and keeps one issue labelled `upstream-sync` up to date with the count and whether the rebase is clean. It closes the issue once `main` has caught up.

Don't use GitHub's "Sync fork" button. Because `main` carries commits upstream doesn't have, it offers to discard them.

The fork's code goes in files of its own where it can, with only a short hook in upstream's files: upstream changing a file the fork barely touches rarely conflicts. When upstream takes one of the fork's changes, drop the fork's commit for it.

The fork's own files:

- `ForkIdentity.swift`: the Brauz bundle id and data folder, and the one-time copy from Search. Hooks: three lines in `Store.swift`.
- `BrauzAbout.swift`: Settings › About as Brauz, and feedback going to the fork's GitHub issues. Hooks: two in `Settings.swift`, `writeFeedback` in `Links.swift`.
- `TabPause.swift`: pausing idle tabs. Hooks: `pauseIdle` in `Sleep.swift`, `paused` in `Tab.swift`, `resume()` in `Browser.swift`.
- `ShortcutKey.swift`: shortcuts on any keyboard layout (`NSEvent.shortcutKey`).
- `OmniboxField.swift`: the address field that takes focus reliably. Hook: `AddressField` in `Omnibox.swift`.
- `LittleExtras.swift`: the small window's address field, keys and placement. Hooks: a few lines in `Little.swift`.
- `CLAUDE.md`: how work on the fork is done with Claude Code, and the local issue list it keeps in `issues/` (gitignored).
- `DOCS/BRAUZ-CHANGES.md`: what changed in Brauz itself, by release.
- `sync.sh` and `.github/workflows/upstream.yml`: syncing with upstream, by hand and the weekly check.
- `.github/workflows/release.yml`: building and publishing a release.

The rest are edits and deletions inside upstream's files and can't move: the scrolling changes in `Tab.swift`, `Stage.swift`, `Swipe.swift` and `StatusLine.swift`, and the removed reading fill.

## Rules the fork's changes depend on

1. `PageView` never overrides `scrollWheel(with:)`. Trackpad events go straight to WebKit's scrolling thread; catching them on the main thread delays and bunches them.
2. Back and forward swipes are WebKit's own: `allowsBackForwardNavigationGestures = true`. No injected `wheel` listeners for gestures.
3. Injected page scripts add no `wheel` listeners, and nothing reports scroll position to the app on every frame. `HoveredLink.script` ignores `mouseover` while the page scrolls.
4. A suspended tab (`tab.paused`, `WKWebView.isSuspended`) is never asked to run JavaScript or take a snapshot. WebKit throws if it is. `Extensions.swift` and `Tab.swift` guard this.
5. Shortcuts match the physical key code as well as the character (`NSEvent.shortcutKey`), so they work on Russian and other non-Latin layouts.
6. `Updater` never checks Office Commun's feed. Brauz looks at its own GitHub releases instead (`BrauzUpdates.swift`), and finds the build number in the release title, so the title keeps the form `Brauz 1.0.4 (build 202610071500)`.
7. The app is Brauz, `dev.aabc.brauz`, with its data in `Application Support/Brauz`, so it never shares settings, cookies or files with Search. `ForkIdentity.swift` copies Search's once, on Brauz's first run. The icon is drawn in `Icon/icon.swift`; its Dark and Tinted versions need Xcode installed somewhere (build.sh finds it with Spotlight), and without it the Dock darkens the light icon to black on black. Names that only exist inside the code (the Swift package, `Search.sdef`, the keychain label in `Vault.swift`, the test suites) stay Search, which keeps saved passwords readable and syncs with upstream simple.
8. The fork's commits never change `CHANGELOG.md`, which is upstream's and conflicted on almost every sync while they did. Brauz's own changes go in `DOCS/BRAUZ-CHANGES.md`, under `## Unreleased`.

## Releasing

A tag starting with `v` builds and publishes a release (`.github/workflows/release.yml`). First rename `## Unreleased` in `DOCS/BRAUZ-CHANGES.md` to the tag, add a fresh empty `## Unreleased` above it, and commit. The workflow puts that section at the top of the release notes, and stops before building when the tag has no section.

```bash
git tag v1.0.4-brauz.4 && git push origin main v1.0.4-brauz.4
```

GitHub builds `Brauz.dmg` for Apple Silicon on a `macos-26` runner, signs it, and publishes the release with install steps. There is no Intel build since `v1.0.4-brauz.4`, because it doubled the run. `SEARCH_ARCH=x86_64 ./build.sh release dmg` still makes one by hand. No build cache either: Brauz is one module with no dependencies, so a release compiles it whole every time, and GitHub doesn't share a cache made under one tag with the next tag. Brauz on your friends' Macs sees it within a day. Use the upstream version from `VERSION`, then `-brauz.` and a number that goes up.

The signature is a self-signed certificate, "Brauz Signing", not Apple's. macOS asks once per new version (System Settings › Privacy & Security › Open Anyway), but because every release carries the same certificate, it keeps each Mac's passwords and permissions across updates. It lives in two repository secrets, `BRAUZ_CERT_P12` (the .p12, base64) and `BRAUZ_CERT_PASSWORD`, and in your login keychain, where `build.sh` finds it for local builds. Keep the .p12 and its password somewhere safe: a release signed with a new certificate is a different app to macOS, and everyone is asked for their passwords and permissions again.

## What was measured

Scrolling was compared in three windows on the same pages: Search, a plain `WKWebView` with WebKit's default configuration and nothing of ours in it, and Safari. After these changes Search scrolls like the plain web view. Any difference left between that and Safari comes from how Safari configures WebKit for itself, not from Search's code.

The stage keeps no `.offset` at rest and only resizes the page when its frame changes. That removes redundant work, but there is no measurement showing it changes how frames reach the screen.

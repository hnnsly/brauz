# This fork

`hnnsly/brauz` is Brauz, a fork of [driceroland/Search](https://github.com/driceroland/Search). Its `main` is upstream's `main` with a short stack of the fork's commits on top. There is no mirror branch; `upstream/main`, which `git fetch upstream` keeps current, is the base.

To see exactly what the fork adds:

```bash
git log --oneline upstream/main..HEAD
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
```

`sync.sh` fetches upstream and replays the fork's commits on top of it, keeping `CHANGELOG.md` as upstream has it at every commit. Then it runs the tests and the build, and prints the push command; it never pushes itself.

When a commit doesn't apply, `sync.sh` stops and names the commit and its files. Resolve them, `git add` them, `git rebase --continue`, and run `./sync.sh` again; it picks up at the tests. Each commit covers one area, so a conflict points at what it was for. When resolving, keep the rules below.

Sync often: a week of upstream rarely conflicts, a month can.

Don't use GitHub's "Sync fork" button. Because `main` carries commits upstream doesn't have, it offers to discard them.

The fork's code goes in files of its own where it can, with only a short hook in upstream's files: upstream changing a file the fork barely touches rarely conflicts. When upstream takes one of the fork's changes, drop the fork's commit for it.

The fork's own files:

- `ForkIdentity.swift`: the Brauz bundle id and data folder. Hooks: three lines in `Store.swift`.
- `BrauzAbout.swift`: Settings › About as Brauz, and feedback going to the fork's GitHub issues. Hooks: two in `Settings.swift`, `writeFeedback` in `Links.swift`.
- `BrauzUpdates.swift`: Brauz looks at its GitHub releases once a day to say when a new one is out.
- `LittleExtras.swift`: Little Window address field, Back button, placement, and spaces/extensions.
- `CLAUDE.md`: how work on the fork is done with Claude Code, and the local issue list it keeps in `issues/` (gitignored).
- `DOCS/BRAUZ-CHANGES.md`: what changed in Brauz itself, by release.
- `sync.sh`: syncing with upstream, by hand.
- `.github/workflows/release.yml`: building and publishing a release.

The rest are edits and deletions inside upstream's files and can't move: the scrolling changes, and the removed reading progress.

## Rules the fork's changes depend on

1. `PageView` never overrides `scrollWheel(with:)`. Trackpad events go straight to WebKit's scrolling thread. Arrow keys and natural vertical bounce apply. No reading progress reporting.
2. Back and forward swipes are WebKit's own: `allowsBackForwardNavigationGestures = true`. No injected `wheel` listeners for gestures.
3. Injected page scripts add no `wheel` listeners, and nothing reports scroll position to the app on every frame.
4. A suspended tab (`tab.paused`, `WKWebView.isSuspended`) is never asked to run JavaScript or take a snapshot. WebKit throws if it is. No early pause; draft max(delay, 1h). Sleep and suspension exemptions survive.
5. Shortcuts match the physical key code as well as the character (`NSEvent.shortcutKey`), so they work on non-Latin layouts.
6. `Updater` never checks Office Commun's feed. Brauz looks at its own GitHub releases instead (`BrauzUpdates.swift`), keeping release title format for parsing: `Brauz 1.0.4 (build 202610071500)`.
7. The app is Brauz, `dev.aabc.brauz`, with its data in `Application Support/Brauz`, so it never shares settings, cookies or files with Search. No automatic profile copy. The icon is drawn in `Icon/icon.swift`. Names that only exist inside the code stay Search, which keeps saved passwords readable and syncs with upstream simple.
8. The fork's commits never change `CHANGELOG.md`, which is upstream's. Brauz's own changes go in `DOCS/BRAUZ-CHANGES.md`, under `## Unreleased`.
9. Little Window ordinary target blank vs JavaScript popups and blocker.
10. Closing the current ordinary tab selects its surviving split partner first, otherwise the last-viewed surviving tab in the current window and space, then the existing positional neighbor fallback if no history survives. Uses TabSwitcher departure history and Browser.select so sleeping tabs wake. Pinned put-down and last-tab settings stay upstream.
11. An already open vertical sidebar stays open when the pointer is outside its actual window or over another app; normal auto-hide resumes on return to the page; pending hides recheck eligibility; existing opening/overshoot, explicit controls and horizontal strip are unchanged.

## Fork-only Tests

- `PageLengthTests.swift`
- `DraftSleepTests.swift`
- `LittleWindowTests.swift`
- `ImageCopyTests.swift`
- `PageUndoTests.swift`
- `BrauzUpdatesTests.swift`
- `TabCloseTests.swift`
- `FoldPeekTests.swift`
- `Tests/sidebar_window_exit.py`
- `Tests/little_extensions.py`
- `DOCS/FORK.md`

## Releasing

A tag starting with `v` builds and publishes a release (`.github/workflows/release.yml`). First rename `## Unreleased` in `DOCS/BRAUZ-CHANGES.md` to the tag, add a fresh empty `## Unreleased` above it, and commit.

```bash
git tag v1.0.4-brauz.4 && git push origin main v1.0.4-brauz.4
```

GitHub builds `Brauz.dmg` for Apple Silicon on a `macos-26` runner, signs it, and publishes the release with install steps. Apple Silicon release only.

The signature is a self-signed certificate, "Brauz Signing", not Apple's. It lives in two repository secrets, `BRAUZ_CERT_P12` and `BRAUZ_CERT_PASSWORD`.

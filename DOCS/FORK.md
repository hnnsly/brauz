# This fork

`hnnsly/Search` is a fork of [driceroland/Search](https://github.com/driceroland/Search). Its `main` is upstream's `main` with a short stack of the fork's commits on top. There is no mirror branch; `upstream/main`, which `git fetch upstream` keeps current, is the base.

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
git fetch upstream
git rebase upstream/main
./build.sh
git push --force-with-lease origin main
```

The rebase replays the fork's commits on top of the new upstream. Each commit covers one area, so a conflict points at what it was for. When resolving, keep the rules below.

Don't use GitHub's "Sync fork" button. Because `main` carries commits upstream doesn't have, it offers to discard them.

The fork's code goes in files of its own where it can, with only a short hook in upstream's files: upstream changing a file the fork barely touches rarely conflicts. When upstream takes one of the fork's changes, drop the fork's commit for it.

The fork's own files:

- `TabPause.swift`: pausing idle tabs. Hooks: `pauseIdle` in `Sleep.swift`, `paused` in `Tab.swift`, `resume()` in `Browser.swift`.
- `ShortcutKey.swift`: shortcuts on any keyboard layout (`NSEvent.shortcutKey`).
- `OmniboxField.swift`: the address field that takes focus reliably. Hook: `AddressField` in `Omnibox.swift`.
- `LittleExtras.swift`: the small window's address field, keys and placement. Hooks: a few lines in `Little.swift`.

The rest are edits and deletions inside upstream's files and can't move: the scrolling changes in `Tab.swift`, `Stage.swift`, `Swipe.swift` and `StatusLine.swift`, and the removed reading fill.

## Rules the fork's changes depend on

1. `PageView` never overrides `scrollWheel(with:)`. Trackpad events go straight to WebKit's scrolling thread; catching them on the main thread delays and bunches them.
2. Back and forward swipes are WebKit's own: `allowsBackForwardNavigationGestures = true`. No injected `wheel` listeners for gestures.
3. Injected page scripts add no `wheel` listeners, and nothing reports scroll position to the app on every frame. `HoveredLink.script` ignores `mouseover` while the page scrolls.
4. A suspended tab (`tab.paused`, `WKWebView.isSuspended`) is never asked to run JavaScript or take a snapshot. WebKit throws if it is. `Extensions.swift` and `Tab.swift` guard this.
5. Shortcuts match the physical key code as well as the character (`NSEvent.shortcutKey`), so they work on Russian and other non-Latin layouts.
6. `Updater` never checks Office Commun's feed. Their release has the same bundle id and would replace this build.

## What was measured

Scrolling was compared in three windows on the same pages: Search, a plain `WKWebView` with WebKit's default configuration and nothing of ours in it, and Safari. After these changes Search scrolls like the plain web view. Any difference left between that and Safari comes from how Safari configures WebKit for itself, not from Search's code.

The stage keeps no `.offset` at rest and only resizes the page when its frame changes. That removes redundant work, but there is no measurement showing it changes how frames reach the screen.

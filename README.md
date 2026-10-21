# Brauz

Brauz is a small, fast, quiet web browser for the Mac. It is a fork of [Search](https://github.com/driceroland/Search), the WebKit browser by Office Commun, and it is kept up to date with it.

**[Download for macOS (Apple Silicon)](https://github.com/hnnsly/brauz/releases)** · macOS 14 or later · free · open source

What the browser does, its shortcuts and its privacy model are in [Search's readme](https://github.com/driceroland/Search#readme), and they all hold here unless this page says otherwise.

## What Brauz changes

- **Its own identity.** Bundle id `dev.aabc.brauz`, data in `Application Support/Brauz`. It shares nothing with Search and never copies Search's data.
- **Scrolling.** Trackpad scrolling keeps WebKit's natural bounce at the top and bottom of a page. There is no reading-progress indicator and nothing reports the scroll position on every frame.
- **Tabs.** Closing the current tab returns to the tab you looked at before it, within the current space, unless it is half of a split view, in which case the other half stays. A tab with an unsent draft is not put to sleep until it has been idle for at least an hour, or for the chosen sleep delay if that is longer.
- **Sidebar.** An open sidebar stays open while the pointer is outside the window or over another app, and goes back in when the pointer returns to the page.
- **Little Window.** It has an address and search field, a Back button and a space selector that switches the space and its sign-ins at once. It remembers where it was, opens ordinary links in the same window, and shows extensions its page as a tab.
- **Copy Image.** The picture is read from the page when possible, instead of being downloaded a second time.
- **Updates.** Once a day Brauz looks at its own [releases](https://github.com/hnnsly/brauz/releases) and says when a new one is out. It never downloads or installs anything itself.

Each release's changes are in [DOCS/BRAUZ-CHANGES.md](DOCS/BRAUZ-CHANGES.md). Search's own changes are in `CHANGELOG.md`, which stays exactly as Search has it.

## Installing

Open `Brauz.dmg` from the [releases page](https://github.com/hnnsly/brauz/releases) and drag Brauz to Applications. It needs macOS 14 or later, and Chrome extensions need 15.4. There is no Intel build.

Brauz is signed with a certificate of its own, not Apple's, so macOS stops it the first time. Open it once, go to System Settings › Privacy & Security, press Open Anyway next to Brauz, and confirm. This is needed again after each new version.

## Building

Run `./build.sh`. It writes `build/Brauz.app`, ad-hoc signed, and needs Xcode with Swift 6. Without Xcode the Dock icon goes black on black in dark mode.

- `swift build -c release` checks the release build.
- `swift test` runs the XCTest suite in `Tests/SearchTests`.
- `python3 Tests/<name>.py` drives a hidden Brauz from `build/` through the bench socket, so build first. Search's readme describes `./bench`.

A build of your own keeps its passwords apart from a release's, because the keychain tells them apart by signature.

## Working on it

[DOCS/FORK.md](DOCS/FORK.md) holds the rules the fork's changes depend on, the list of files that are Brauz's own, and how to bring in new work from Search.

MIT, as upstream. See [LICENSE](LICENSE).

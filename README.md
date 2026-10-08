### Brauz

A fork of [Search](https://github.com/driceroland/Search), the small WebKit browser for the Mac. What the browser does, its shortcuts and its privacy model are in [Search's readme](https://github.com/driceroland/Search#readme), and they all hold here unless this page says otherwise.

What Brauz changes:

- It has its own identity: bundle id `dev.aabc.brauz`, data in `Application Support/Brauz`. It shares nothing with Search and copies Search's data once on first run.
- Idle tabs pause before they sleep, and a paused tab closes and reloads.
- Scrolling is WebKit's. The app no longer intercepts trackpad events, so scrolling matches a plain web view.
- Shortcuts work on any keyboard layout, Cyrillic included.
- Little Window has its own address field and shortcuts, remembers its position, and shows extensions its page as a tab.

Get `Brauz.dmg` (Apple Silicon) or `Brauz-Intel.dmg` from the [releases page](https://github.com/hnnsly/Search/releases). It needs macOS 14 or later, and Chrome extensions need 15.4.

To build it, run `./build.sh`. It writes `build/Brauz.app`, ad-hoc signed, and needs Xcode 16 (Swift 6). Without Xcode the Dock icon goes black on black in dark mode. `swift build` runs the app from the SwiftPM binary, `swift build -c release` checks the release build, and `swift test` runs the XCTest suite in `Tests/SearchTests`. `python3 Tests/<name>.py` drives a hidden Brauz from `build/` through the bench socket, so build first. Search's readme describes `./bench`. A build of your own keeps its passwords apart from a release's, because the keychain tells them apart by signature.

MIT, as upstream. See [LICENSE](LICENSE).

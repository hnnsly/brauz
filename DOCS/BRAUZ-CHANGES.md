# What changed in Brauz

Brauz's own changes, newest first. What comes from Search is in `CHANGELOG.md`, which stays exactly as Search has it.

Each section is headed by the tag it ships in, and the release workflow puts that section at the top of the release notes. Write a change under `## Unreleased` when it lands, and rename the heading to the tag (`## v1.0.4-brauz.4`) in the commit you tag.

## Unreleased

- Copy Image reads the picture from the page when it can, instead of downloading it a second time; a picture the page cannot read is fetched as before.

## v1.0.5.b1

- Up to date with Search v1.0.5 and subsequent upstream commits through b2048a0.
- Upstream arrow-disc navigation gesture and natural vertical bounce.
- Removed reading-progress indicator and per-scroll tracking.
- Little Window: space selector to switch browsing space and cookie store immediately, address and search entry, Back button, and remembered placement.
- Little Window: ordinary target=_blank links navigate in the same window while preserving popup protections and extensions.
- Tabs: drafts protected until one hour idle before sleep.
- Popups: fixed undo memory crash after typing in extension popovers.
- Images: fast bounded streaming for image copying.
- Packaging: disk image background updated to Brauz. Release titles include the tag name. Apple Silicon release builds.

## v1.0.4-brauz.3

- Coming back to a tab that was paused no longer crashes Brauz. Switching to it, switching spaces with it in view, putting it in Split View, or changing between light and dark could ask the paused page to run a script, and WebKit stopped the app with "The WKWebView is suspended". The tab now wakes before anything asks it something, and its icon is checked again once it is awake.
- Up to date with Search as of 13 October: Arc's folders and pinned tabs come over in the shape Arc had them, Download Linked File in the right-click menu saves the file, Open Link in New Tab leaves you on the page you were on, websites an extension lists can message it as in Chrome, and more. Search's `CHANGELOG.md` has the full list.

## v1.0.4-brauz.2

- Copy Image takes a moment instead of over a minute on a large picture: it read the picture a byte at a time.
- A paused tab sleeps, closes and reloads without crashing.
- Extensions see the small window's page as a tab, so a password manager fills it.
- Closing an extension's popup leaves nothing behind for ⌘Z to undo.

## v1.0.4-brauz.1

The first release of Brauz.

- Its own name, icon, and data folder, so it runs next to Search without sharing settings, cookies or passwords. On first launch it copies Search's once.
- Settings › About and Help › Send Feedback point at Brauz's GitHub, and Brauz looks at its GitHub releases once a day to say when a new one is out.
- Scrolling is WebKit's own, as smooth as in a plain web view.
- Tabs left alone for a few minutes are paused, so they cost no CPU and come back at once.
- Shortcuts work with a Russian or any other non-Latin keyboard layout on.
- The address field takes focus every time on ⌘T and a new blank tab.
- The small window has an address field and shortcuts of its own, and opens where it was last.

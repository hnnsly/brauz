---
status: fixing
found: 2026-10-23
---
# Copy Clean Link: drop tracking query parameters on copied and shared links

## Symptom
When copying a link via Command-Shift-C or menus, the URL includes tracking parameters like utm_source, utm_medium, fbclid, gclid, yclid, and mc_eid, cluttering shared links.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter CleanLinkTests`

## Cause
Browser.copyAddress in Sources/Search/Browser.swift:1522 copies url.absoluteString directly without filtering query parameters.

## Ruled out / wrong in the first draft
- Assuming remote Supabase search_ideas database was needed (ROADMAP.md contains the exported backlog locally).
- Assuming a full browser extension was required for link cleaning.

## Decisions (2026-10-24)
- User chose Copy Clean Link (ROADMAP.md).
- Every copy of a page address (Command-Shift-C, Copy Link items in menus, Share) drops tracking parameters such as utm_*, fbclid, gclid, yclid, mc_eid; the address bar still shows the full URL.
- A Settings switch turns cleaning off; it is on by default.

## Fix
Added fork-only `CleanLink.swift` that strips tracking query parameters (`utm_*` prefix, `fbclid`, `gclid`, `dclid`, `gbraid`, `wbraid`, `msclkid`, `yclid`, `ysclid`, `mc_eid`, `mc_cid`, `igshid`, `_hsenc`, `_hsmi`, and `si` on YouTube and Spotify hosts) while keeping other parameters, encoded values, order, and fragments. Hooked `Browser.copyAddress`, `Browser.copyMarkdownLink`, `Browser.selectedTabLinks`, `Sharing.share`, `Little.copy`, `ImageMenu`, and WebKit's context menu `Copy Link`. Added a toggle switch in Settings › Privacy (`cleanLinks`, on by default).

## Guarded by
`Tests/SearchTests/CleanLinkTests.swift`

## Acceptance
- Command-Shift-C drops tracking parameters and keeps legitimate parameters and fragments.
- Copy as Markdown Link formats a clean URL.
- File › Share… sends a clean URL.
- Little Window Command-Shift-C and Markdown copy produce clean URLs.
- Copy Link in page context menu places a clean URL on the clipboard.
- Settings › Privacy toggle turns cleaning off when switched off.
- Address bar and navigation URLs remain untouched.

## Files
- `Sources/Search/CleanLink.swift`
- `Sources/Search/Browser.swift`
- `Sources/Search/ImageMenu.swift`
- `Sources/Search/Little.swift`
- `Sources/Search/Prefs.swift`
- `Sources/Search/Settings.swift`
- `Sources/Search/Sharing.swift`
- `Sources/Search/Tab.swift`
- `Tests/SearchTests/CleanLinkTests.swift`

## Test by hand
1. Run `./build.sh` and open `build/Brauz.app`.
2. Navigate to `https://example.com/test?utm_source=twitter&foo=bar#section1`.
3. Press Command-Shift-C and paste into TextEdit; expect `https://example.com/test?foo=bar#section1`.
4. Right-click the tab and choose Copy as Markdown Link; expect `[test](https://example.com/test?foo=bar#section1)`.
5. Open Settings › Privacy, turn off "Copy clean links", press Command-Shift-C again; expect the original URL with `utm_source` intact.

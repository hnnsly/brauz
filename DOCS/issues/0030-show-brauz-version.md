---
status: open
found: 2026-10-24
---
# Settings › About shows Search's version (1.0.5), not Brauz's (1.0.5.b2)

## Symptom
"I think we should show b* version in Brauz info, not only search base version (e.g. 1.0.5)."

Settings › About reads "based on Search by Office Commun · version 1.0.5". The feedback issue body says "Brauz 1.0.5, build …". Neither names the Brauz release, such as `v1.0.5.b2`.

## Cause
The app's only version is upstream's:
- `build.sh` writes `VERSION` (`1.0.5`) into `CFBundleShortVersionString`.
- `Updater.version` reads that.
- The Brauz tag lives only in the GitHub release title, "Brauz v1.0.5.b2 (build 202610211427)". `release.yml` builds that title from `$GITHUB_REF_NAME`.

`CFBundleShortVersionString` must stay upstream's version:
- `WhatsNew.current` (`WhatsNew.swift:84`) matches it against `CHANGELOG.md`'s releases.
- Update checks compare `CFBundleVersion` (`BrauzUpdates.swift:85`), not the version string.

## Decisions (2026-10-24)
- Credit line reads "version 1.0.5.b2 · based on Search 1.0.5 by Office Commun".
- Builds between releases show `<tag>+<commits>`.
- No release cut now.

## Fix
- `build.sh`: writes `BrauzVersion` key into Info.plist, parsed from `$GITHUB_REF_NAME` or `git describe --tags --match 'v*'`.
- `Sources/Search/BrauzAbout.swift`: adds `BrauzAbout.version` reading Info.plist's `BrauzVersion` with fallback to `Updater.version`, updates `BrauzAboutHeader`, and includes `BrauzAbout.version` in `writeFeedback`.
- `Tests/SearchTests/BrauzVersionTests.swift`: tests fallback and version extraction.
- `DOCS/BRAUZ-CHANGES.md` and `DOCS/FORK.md`: release note, rule 6 update, and test registration.

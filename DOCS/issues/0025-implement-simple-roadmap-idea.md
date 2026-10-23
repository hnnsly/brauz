---
status: open
found: 2026-10-23
---
# Copy Clean Link

## Symptom
When copying a link via Command-Shift-C or menus, the URL includes tracking parameters like utm_source, utm_medium, fbclid, gclid, yclid, and mc_eid, cluttering shared links.

## Loop
DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter AddressTests

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
Implement URL parameter cleaning in copyAddress (Sources/Search/Browser.swift:1522) to strip tracking query parameters when enabled.

## Guarded by
AddressTests verifying clean URL generation.

## Acceptance
- Command-Shift-C copies URL without tracking query parameters.
- Address bar retains the full original URL.
- Settings toggle turns cleaning on and off.

## Files
- Sources/Search/Browser.swift
- Sources/Search/Settings.swift
- Sources/Search/Prefs.swift

## Test by hand
Open a URL with utm_source=twitter, press Command-Shift-C, paste into text editor and verify utm parameters are stripped.

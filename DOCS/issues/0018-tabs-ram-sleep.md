---
status: open
found: 2026-10-23
---
# Tabs offloaded during Mac sleep still retain RAM footprint or reload unexpectedly

## Symptom
Tabs that have been put to sleep or offloaded while the Mac sleeps appear to reload when opened, but their underlying memory footprint does not seem fully reclaimed or they wake up prematurely.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter DraftSleepTests`

## Cause
Investigation needed into whether WKWebView termination/discard (`_close`) and memory pressure handlers release backing processes effectively during system sleep.

## Fix
Ensure process suspension and webview termination fully release associated memory and IOSurface resources on system sleep notifications.

## Guarded by
Automated memory / sleep tests.

## Acceptance
- Sleeping or offloaded tabs release their WebContent process memory completely during system sleep.
- Opening an offloaded tab restores state correctly without lingering stale footprint.

## Files
- `Sources/Search/Sleep.swift`
- `Sources/Search/Tab.swift`

## Test by hand
Put tabs to sleep, put Mac to sleep, check Activity Monitor / memory footprint.

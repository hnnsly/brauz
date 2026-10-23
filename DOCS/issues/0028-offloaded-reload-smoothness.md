---
status: open
found: 2026-10-23
---
# Optimize and smooth out reloading experience when restoring offloaded pages

## Symptom
Reloading and waking up offloaded pages feels ugly and noticeably slow, showing flash of white or rough transition states.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter Sleep`

## Cause
Snapshot cover removal timing, webview re-initialization, and document readiness synchronization during `wake()` / `revive()`.

## Fix
Smooth out snapshot cover transition and DOM restoration when waking sleeping tabs.

## Guarded by
Tab wake/revive tests.

## Acceptance
- Waking an offloaded tab transitions smoothly from its snapshot cover to the live page without visual stutter or perceived slowness.

## Files
- `Sources/Search/Tab.swift`
- `Sources/Search/Sleep.swift`

## Test by hand
Let tabs sleep/offload, click them to wake, observe transition smoothness.

---
status: open
found: 2026-10-23
---
# Pause inactive tabs after configurable duration (5, 10, or 20 minutes)

## Symptom
Users want inactive tabs to pause automatically after adjustable durations (e.g. 5, 10, or 20 minutes) respecting tab sleep settings.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test --filter DraftSleepTests`

## Cause
Current pause/sleep timers use fixed intervals or upstream defaults without direct UI/pref bindings for 5/10/20 minute thresholds.

## Fix
Wire configurable idle duration settings into `Sleep.swift` and `Preferences.swift`.

## Guarded by
`Tests/SearchTests/DraftSleepTests.swift`

## Acceptance
- Tabs pause after the configured duration (5, 10, or 20 minutes).
- Settings correctly persist and apply the selected idle timeout.

## Files
- `Sources/Search/Sleep.swift`
- `Sources/Search/Prefs.swift`
- `Sources/Search/Settings.swift`

## Test by hand
Set sleep preference to 5 minutes, leave a tab idle, verify it pauses.

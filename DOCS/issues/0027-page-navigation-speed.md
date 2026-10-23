---
status: open
found: 2026-10-23
---
# Investigate and eliminate page navigation delays and slow initial open times

## Symptom
Pages sometimes fail to open or open significantly slower in Brauz compared to Safari or Chrome running in adjacent windows.

## Loop
`DEVELOPER_DIR=/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer swift test`

## Cause
Potential overhead in navigation policy decisions, resource preloading, script message relay initialization, or process pool allocation.

## Fix
Audit navigation delegates, process pool configuration, and network interception bottlenecks.

## Guarded by
Performance benchmark tests.

## Acceptance
- Page navigation initiation and load times match Safari/Chrome responsiveness.

## Files
- `Sources/Search/Web.swift`
- `Sources/Search/Browser.swift`

## Test by hand
Open heavy websites side-by-side with Safari, compare initial load and navigation speed.

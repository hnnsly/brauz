---
status: open
found: 2026-10-20
---
# YouTube sometimes downloads HTML instead of opening the page

## Symptom
Historical user report from earlier work: sometimes youtube.com downloads an HTML file instead of opening the page. Recorded during the all-issues inventory on 2026-10-20. Original report date and exact URL are not available in the retained context.

## Loop
No reproduction yet. A successful YouTube navigation does not disprove an intermittent download. Need the exact response URL, status, Content-Type, Content-Disposition and navigation/download decision when it happens. Redact cookies, tokens and authentication headers as <REDACTED>.

## Cause
Unknown. Do not change download policy based on the hostname without a reproduction.

## Fix
None yet. Keep this issue open unless the actual failure is reproduced and checked after a fix.

## Guarded by
No regression test yet.

## Acceptance
- A reproduction distinguishes an ordinary HTML navigation from an intentional download.
- The reproduced navigation opens as a page after the fix.
- Intentional HTML downloads still work.

## Files
Pending reproduction. Navigation and download policy are in Sources/Search/Browser.swift.

## Test by hand
Not performed during upstream integration yet. No claim that the issue is fixed.

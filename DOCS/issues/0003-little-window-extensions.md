---
status: fixed
found: 2026-10-08
---
# A password manager doesn't fill in a little window

## Symptom
The user: "in little windows extensions are like not working", then "password manager doesn't fill". The same page in a normal tab fills. Extension buttons in little windows are not wanted (the user's decision).

## Loop
`./build.sh && python3 Tests/little_extensions.py`. A test extension fills the way password managers do: the page's script asks the worker, the worker answers `tabs.sendMessage(sender.tab.id)`. Red: "a little window's page is filled" fails with `no answer` (the reply arrives empty, no `lastError`).

## Cause
The little window's tab is in no browser's row, so `Extensions.follow` never told WebKit about it (`didOpenTab`). Content scripts still ran (the page has the controller from `Tab.swift`), but WebKit had no tab to route the worker's answer to. Proved by the loop: the same tab and view, kept into the row with Open in Search, fills.

## Fix
A little window is a window of its own to extensions, type popup, with its one tab (`ExtensionWindow.little`, `Extensions.opened/closed/keeping`, hooks in `Little.swift`). It is the focused window while in front. Open in Search is a move (`inTransit` → `didMoveTab`), and the emptied window is closed after; it is emptied first, since WebKit closes every tab a closing window still lists (tried without: the kept tab was closed, red).

## Guarded by
`Tests/little_extensions.py`: a normal tab, a little window, one kept into the row, and a tab opened after a little window closed, all filled.

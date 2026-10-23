---
status: open
found: 2026-10-23
---
# Page navigation speed: skip redundant user script re-arming on main frame navigation

## Symptom
Pages sometimes open slower in Brauz compared to Safari or Chrome.

## Loop
`python3 Tests/navigation_speed.py` using the bench socket.

## Cause
`Browser.decide()` in `/Users/daniil/Dev/Search/Sources/Search/Browser.swift:5005` runs `tab.arm(hiding:)` on every main frame navigation, which calls `controller.removeAllUserScripts()` and re-adds all 12-16 user scripts (`/Users/daniil/Dev/Search/Sources/Search/Tab.swift:813`). 

Ruled out / wrong in the first draft:
- WebKit private process cache and WebProcessPool configuration.
- Measuring first without profiling navigation delegates.

## Decisions (2026-10-24)
- User chose to go straight to the top suspect: `tab.arm(hiding:to:)` runs on every main-frame navigation (`Browser.swift:5005`) and removes and re-adds all 12-16 user scripts (`Tab.swift:813`).
- Skip that rebuild when its inputs have not changed, then measure Return to load start to first paint with the bench socket before and after.
- Not chosen: measuring first, WebKit private process cache.

## Fix
Skip user script re-arming when the destination host and curtain CSS have not changed.

## Guarded by
`Tests/navigation_speed.py` bench performance assertions.

## Acceptance
- Navigation initiation and load times match standard browser responsiveness.

## Files
- `/Users/daniil/Dev/Search/Sources/Search/Browser.swift`
- `/Users/daniil/Dev/Search/Sources/Search/Tab.swift`

## Test by hand
Launch build/Brauz.app, trigger page navigations via Omnibox Return, and verify responsiveness.

---
status: fixed
found: 2026-10-08
---
# ⌘Z on a page crashes Brauz after typing in an extension's popup

## Symptom
Crash report 2026-10-07 20:02, build 202610071423: `EXC_BAD_ACCESS` in `objc_msgSend` from `-[_NSUndoStack popAndInvoke]` under `-[NSUndoManager undoNestedGroup]`, reached from ⌘Z that the focused page didn't handle. `x1` held `undoEditing:`.

## Loop
`swift test --filter PageUndoTests/testClosedExtensionPopupLeavesNothingToUndo`. Red: "⌘Z in the browser would be aimed at the closed popup's page" (the browser window's undo manager still `canUndo` after the popup closed).

## Cause
`undoEditing:` is WebKit's: `WebViewImpl::registerEditCommand` puts each edit typed in a page on `[webView undoManager]`, aimed at a `WKEditorUndoTarget` the view owns, and removes them only in `viewWillMoveToWindow:`. An extension's popup is a page in an `NSPopover`; a popover's window hands out the browser window's undo manager, so typing in the popup landed on the browser's stack. `ExtensionPopup` let go of the popup's page still inside the popover, and once a popover starts closing its window answers with an undo manager of its own, so WebKit's clear missed. After the page was freed, ⌘Z in the browser went to freed memory.

Ruled out by the loop: closing, sleeping, taking off stage, closing the window, SwiftUI dropping the stage — all clear correctly. Replacing a window's `contentView` with a page inside also leaks, but only the bench does that.

## Fix
`ExtensionPopup.popoverShouldClose` takes the page out of its view before any close begins (ours or a click outside), while the popover's window still hands out the browser's undo manager. Side effect: the page leaves at the start of the popover's fade, about 0.15 s of empty popover. `popoverDidClose` is too late (tried: red).

## Guarded by
`Tests/SearchTests/PageUndoTests.swift`: the popover as `ExtensionPopup.show` builds it, with the real delegate; plus six tab paths that must stay clear. The test builds the popover itself: in the test process an extension's page never loads, so the real `show` can't be typed into.

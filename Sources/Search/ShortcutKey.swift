import AppKit

// Shortcuts on any keyboard layout.
//
// With a Russian layout on, ⌘W types ⌘Ц: the event's characters are the
// layout's, and a shortcut matched by character never fires. The key's
// position doesn't change with the layout, so a letter that isn't Latin is
// read back from the key code as the US layout has it, and ⌘Ц is ⌘W again.

extension NSEvent {
    /// The physical keys of the US (ANSI) layout, by key code.
    static let ansiKeyCodes: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".",
        50: "`"
    ]

    /// The key a shortcut is matched by: the character typed when it is a
    /// Latin letter, a digit or a symbol, and otherwise the US layout's key
    /// in the same place.
    var shortcutKey: String {
        if let chars = charactersIgnoringModifiers?.lowercased(),
           let first = chars.first,
           first.isASCII && (first.isLetter || first.isNumber || "-=[]\\;',./`".contains(first)) {
            return String(first)
        }
        return NSEvent.ansiKeyCodes[keyCode] ?? charactersIgnoringModifiers?.lowercased() ?? ""
    }
}

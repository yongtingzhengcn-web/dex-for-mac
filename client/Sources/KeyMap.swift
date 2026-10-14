import Cocoa

/// macOS hardware keyCode → Android KEYCODE_*, plus meta-state tracking.
enum KeyMap {

    /// Android keycodes for keys we handle as real key events (letters, digits,
    /// navigation, common punctuation). Everything else falls back to INJECT_TEXT.
    static let keyCodeTable: [UInt16: Int32] = [
        // letters
        0: 29, 11: 30, 8: 31, 2: 32, 14: 33, 3: 34, 5: 35, 4: 36, 34: 37,
        38: 38, 40: 39, 37: 40, 46: 41, 45: 42, 31: 43, 35: 44, 12: 45,
        15: 46, 1: 47, 17: 48, 32: 49, 9: 50, 13: 51, 7: 52, 16: 53, 6: 54,
        // digits row
        18: 8, 19: 9, 20: 10, 21: 11, 23: 12, 22: 13, 26: 14, 28: 15, 25: 16, 29: 7,
        // whitespace / editing
        36: 66, 76: 160, 48: 61, 49: 62, 51: 67, 117: 112, 53: 111,
        // arrows
        123: 21, 124: 22, 125: 20, 126: 19,
        // navigation cluster
        115: 122, 119: 123, 116: 92, 121: 93,
        // punctuation
        27: 69, 24: 70, 33: 71, 30: 72, 42: 73, 41: 74, 39: 75, 43: 56,
        47: 57, 44: 76, 50: 68,
        // function keys
        122: 131, 120: 132, 99: 133, 118: 134, 96: 135, 97: 136, 98: 137,
        100: 138, 101: 139, 109: 140, 103: 141, 111: 142,
    ]

    /// Current meta state from modifier flags.
    static func metaState(from flags: NSEvent.ModifierFlags) -> Int32 {
        var meta: Int32 = 0
        if flags.contains(.shift) { meta |= ControlMessages.META_SHIFT }
        if flags.contains(.option) { meta |= ControlMessages.META_ALT }
        if flags.contains(.control) { meta |= ControlMessages.META_CTRL }
        if flags.contains(.command) { meta |= ControlMessages.META_META }
        return meta
    }
}

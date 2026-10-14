import Foundation

/// Serialization of scrcpy control messages (client → device), protocol of
/// scrcpy-server 5.0.x. All integers big-endian.
enum ControlMessages {

    // Message types (server ControlMessage.java)
    static let TYPE_INJECT_KEYCODE: UInt8 = 0
    static let TYPE_INJECT_TEXT: UInt8 = 1
    static let TYPE_INJECT_TOUCH_EVENT: UInt8 = 2
    static let TYPE_INJECT_SCROLL_EVENT: UInt8 = 3
    static let TYPE_BACK_OR_SCREEN_ON: UInt8 = 4
    static let TYPE_GET_CLIPBOARD: UInt8 = 8
    static let TYPE_SET_CLIPBOARD: UInt8 = 9
    static let TYPE_SET_DISPLAY_POWER: UInt8 = 10
    static let TYPE_ROTATE_DEVICE: UInt8 = 11

    // MotionEvent actions
    static let ACTION_DOWN: UInt8 = 0
    static let ACTION_UP: UInt8 = 1
    static let ACTION_MOVE: UInt8 = 2
    static let ACTION_HOVER_MOVE: UInt8 = 7

    // MotionEvent buttons
    static let BUTTON_PRIMARY: UInt32 = 1
    static let BUTTON_SECONDARY: UInt32 = 2
    static let BUTTON_TERTIARY: UInt32 = 4

    // Pointer ids (control_msg.h)
    static let POINTER_ID_MOUSE: Int64 = -1

    // KeyEvent meta states
    static let META_SHIFT: Int32 = 1
    static let META_ALT: Int32 = 2
    static let META_CTRL: Int32 = 0x1000
    static let META_META: Int32 = 0x10000

    private static func appendBE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var v = value.bigEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    /// type(1) action(1) keycode(4) repeat(4) metaState(4)
    static func injectKeycode(action: UInt8, keycode: Int32, meta: Int32) -> Data {
        var d = Data(capacity: 14)
        d.append(TYPE_INJECT_KEYCODE)
        d.append(action)
        appendBE(&d, keycode)
        appendBE(&d, Int32(0)) // repeat
        appendBE(&d, meta)
        return d
    }

    /// type(1) length(4) utf8
    static func injectText(_ text: String) -> Data? {
        guard let bytes = text.data(using: .utf8), bytes.count <= 300 else { return nil }
        var d = Data(capacity: 5 + bytes.count)
        d.append(TYPE_INJECT_TEXT)
        appendBE(&d, Int32(bytes.count))
        d.append(bytes)
        return d
    }

    private static func appendPosition(_ d: inout Data, x: Int32, y: Int32, w: Int, h: Int) {
        appendBE(&d, x)
        appendBE(&d, y)
        appendBE(&d, UInt16(clamping: w))
        appendBE(&d, UInt16(clamping: h))
    }

    /// type(1) action(1) pointerId(8) position(12) pressure(2) actionButton(4) buttons(4)
    static func injectTouch(action: UInt8, pointerId: Int64 = POINTER_ID_MOUSE,
                            x: Int32, y: Int32, displayW: Int, displayH: Int,
                            pressure: UInt16, actionButton: UInt32, buttons: UInt32) -> Data {
        var d = Data(capacity: 32)
        d.append(TYPE_INJECT_TOUCH_EVENT)
        d.append(action)
        appendBE(&d, pointerId)
        appendPosition(&d, x: x, y: y, w: displayW, h: displayH)
        appendBE(&d, pressure)
        appendBE(&d, actionButton)
        appendBE(&d, buttons)
        return d
    }

    /// type(1) position(12) hScroll(2) vScroll(2) buttons(4)
    /// Scroll values are i16 fixed point where 1.0 == 16 "ticks" on the device side.
    static func injectScroll(x: Int32, y: Int32, displayW: Int, displayH: Int,
                             hScroll: Float, vScroll: Float, buttons: UInt32) -> Data {
        func fixed(_ f: Float) -> Int16 {
            let clamped = max(-16, min(16, f))
            return Int16(clamping: Int(clamped / 16 * 32767))
        }
        var d = Data(capacity: 21)
        d.append(TYPE_INJECT_SCROLL_EVENT)
        appendPosition(&d, x: x, y: y, w: displayW, h: displayH)
        appendBE(&d, fixed(hScroll))
        appendBE(&d, fixed(vScroll))
        appendBE(&d, buttons)
        return d
    }

    /// type(1) sequence(8) paste(1) length(4) utf8
    static func setClipboard(_ text: String, paste: Bool) -> Data? {
        guard let bytes = text.data(using: .utf8), bytes.count <= (1 << 18) - 14 else { return nil }
        var d = Data(capacity: 14 + bytes.count)
        d.append(TYPE_SET_CLIPBOARD)
        appendBE(&d, Int64(0)) // SEQUENCE_INVALID
        d.append(paste ? 1 : 0)
        appendBE(&d, Int32(bytes.count))
        d.append(bytes)
        return d
    }

    static func backOrScreenOn(action: UInt8) -> Data {
        Data([TYPE_BACK_OR_SCREEN_ON, action])
    }

    /// Pressure as u16 fixed point (1.0 = 0x8000); 0 when not pressed.
    static func pressure(pressed: Bool) -> UInt16 { pressed ? 0x8000 : 0 }
}

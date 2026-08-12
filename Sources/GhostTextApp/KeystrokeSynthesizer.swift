import CoreGraphics
import Foundation

/// Types text into whatever app is focused by posting synthetic key events.
///
/// This is the output half of the design. Completions are never written into the
/// text field through Accessibility — that breaks on Electron and browser fields.
/// Synthetic keystrokes work everywhere, and the target app needs no awareness of
/// Ghost Text at all.
enum KeystrokeSynthesizer {
    /// Long unicode payloads in a single event are handled inconsistently across
    /// apps. Chunking keeps each event small enough to be reliable.
    private static let chunkSize = 16

    /// `marked` stamps the events so our own tap ignores them. The self-test posts
    /// unmarked events on purpose, to imitate a real person typing.
    static func type(_ text: String, marked: Bool = true, at location: CGEventTapLocation = .cgAnnotatedSessionEventTap) {
        guard !text.isEmpty else { return }
        guard let source = CGEventSource(stateID: .privateState) else {
            FileLog.app("synthesize FAILED: could not create event source")
            return
        }

        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let end = min(index + chunkSize, units.count)
            post(Array(units[index..<end]), source: source, marked: marked, at: location)
            index = end
        }
    }

    /// For keys that carry no text — Tab, Escape, Return.
    static func pressKey(_ virtualKey: CGKeyCode, marked: Bool = true, at location: CGEventTapLocation = .cgAnnotatedSessionEventTap) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }

        down.flags = []
        up.flags = []
        if marked {
            down.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticMarker)
            up.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticMarker)
        }
        down.post(tap: location)
        up.post(tap: location)
    }

    private static func post(_ chunk: [UniChar], source: CGEventSource, marked: Bool, at location: CGEventTapLocation) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }

        var buffer = chunk
        down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
        up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)

        // Ambient modifier state would otherwise leak into the synthetic event —
        // the user may still be holding Shift from whatever triggered the accept.
        down.flags = []
        up.flags = []

        // Let our own tap recognise these and skip re-buffering them.
        if marked {
            down.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticMarker)
            up.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticMarker)
        }

        down.post(tap: location)
        up.post(tap: location)
    }
}

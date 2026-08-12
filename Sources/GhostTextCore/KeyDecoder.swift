import Carbon
import Foundation

/// The modifier keys active on a keydown, decoupled from `NSEvent.ModifierFlags`
/// so this layer stays testable without AppKit.
public struct ModifierSet: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = ModifierSet(rawValue: 1 << 0)
    public static let control = ModifierSet(rawValue: 1 << 1)
    public static let option = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
    public static let capsLock = ModifierSet(rawValue: 1 << 4)
    public static let fn = ModifierSet(rawValue: 1 << 5)
}

/// The result of decoding one raw keydown into something the rest of Ghost
/// Text can reason about. Deliberately does NOT special-case `~` -- that's
/// an accept-key decision, not a keyboard-layout decision, and belongs in
/// `AcceptPolicy` (see DESIGN.md, "Accept keys").
public enum DecodedKey: Sendable, Equatable {
    case tab
    case escape
    case commit
    case backspace
    case caretMove
    case ignored
    case text(Character)
}

/// Translates a raw key code + modifiers into a `Character`, the one seam
/// that needs the real macOS keyboard layout (dead keys, non-US layouts,
/// etc). Abstracted behind a protocol so tests can supply a fake layout
/// instead of touching Carbon.
public protocol KeyboardLayoutTranslating: Sendable {
    func character(keyCode: UInt16, modifiers: ModifierSet) -> Character?
}

/// The real, system keyboard-layout-aware translator. This is the one
/// allowed Carbon dependency (see task spec, item 2) -- `UCKeyTranslate`
/// has no AppKit/CoreGraphics-event equivalent that respects the user's
/// active input source, dead keys included.
public final class SystemKeyboardLayout: KeyboardLayoutTranslating, @unchecked Sendable {
    private let lock = NSLock()
    private var deadKeyState: UInt32 = 0

    public init() {}

    public func character(keyCode: UInt16, modifiers: ModifierSet) -> Character? {
        lock.lock()
        defer { lock.unlock() }

        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0

        let carbonModifiers = carbonModifierFlags(from: modifiers)

        let status: OSStatus = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let keyboardLayoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return errSecParam
            }
            return UCKeyTranslate(
                keyboardLayoutPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                carbonModifiers,
                UInt32(LMGetKbdType()),
                OptionBits(0), // 0 == dead-key composition enabled (normal typing behavior)
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )
        }

        guard status == noErr, actualLength > 0 else { return nil }

        let scalars = chars[0..<actualLength].compactMap { Unicode.Scalar($0) }
        guard !scalars.isEmpty else { return nil }
        let str = String(String.UnicodeScalarView(scalars))
        return str.first
    }

    /// Maps our `ModifierSet` to the Carbon modifier bits `UCKeyTranslate`
    /// expects (the high byte of `EventRecord.modifiers`, shifted into
    /// `UCKeyTranslate`'s `modifierKeyState` param). Only Shift, Option, and
    /// CapsLock affect character translation; Control/Command are handled
    /// earlier in `KeyDecoder.decode` (they force `.caretMove`) and are
    /// intentionally not passed through here.
    private func carbonModifierFlags(from modifiers: ModifierSet) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.shift) {
            flags |= UInt32(shiftKey >> 8)
        }
        if modifiers.contains(.option) {
            flags |= UInt32(optionKey >> 8)
        }
        if modifiers.contains(.capsLock) {
            flags |= UInt32(alphaLock >> 8)
        }
        return flags
    }
}

/// Decodes raw key codes into `DecodedKey`, the layout-pure representation
/// the rest of Ghost Text works with.
public struct KeyDecoder: Sendable {
    private let layout: KeyboardLayoutTranslating

    private static let tabCode: UInt16 = 48
    private static let returnCode: UInt16 = 36
    private static let keypadEnterCode: UInt16 = 76
    private static let escapeCode: UInt16 = 53
    private static let backspaceCode: UInt16 = 51
    private static let forwardDeleteCode: UInt16 = 117
    private static let leftCode: UInt16 = 123
    private static let rightCode: UInt16 = 124
    private static let downCode: UInt16 = 125
    private static let upCode: UInt16 = 126
    private static let homeCode: UInt16 = 115
    private static let endCode: UInt16 = 119
    private static let pageUpCode: UInt16 = 116
    private static let pageDownCode: UInt16 = 121

    private static let caretMoveCodes: Set<UInt16> = [
        leftCode, rightCode, downCode, upCode, homeCode, endCode, pageUpCode, pageDownCode,
    ]

    public init(layout: KeyboardLayoutTranslating) {
        self.layout = layout
    }

    public func decode(keyCode: UInt16, modifiers: ModifierSet) -> DecodedKey {
        // A command or control chord may have moved the caret or replaced a
        // selection (select-all + type, cmd-left, etc). We don't know which,
        // so the safe read is to treat it as caret movement and invalidate
        // the buffer -- see DESIGN.md's emphasis on never trusting a buffer
        // we can't be sure is in sync. Option is a genuine text modifier
        // (dead keys, alt-layouts) and is passed through to the layout.
        if modifiers.contains(.command) || modifiers.contains(.control) {
            return .caretMove
        }

        switch keyCode {
        case Self.tabCode:
            return .tab
        case Self.escapeCode:
            return .escape
        case Self.returnCode, Self.keypadEnterCode:
            return .commit
        case Self.backspaceCode:
            return .backspace
        case Self.forwardDeleteCode:
            // Forward-delete removes text ahead of the caret. We can't
            // represent that as a buffer edit (our buffer only tracks what
            // precedes the caret), so treat it like any other caret-region
            // mutation we can't reconstruct: invalidate.
            return .caretMove
        case _ where Self.caretMoveCodes.contains(keyCode):
            return .caretMove
        default:
            if let character = layout.character(keyCode: keyCode, modifiers: modifiers), !character.isNewline {
                return .text(character)
            }
            return .ignored
        }
    }
}

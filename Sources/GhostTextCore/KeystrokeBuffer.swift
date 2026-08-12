import Foundation

/// Everything that can happen to the in-memory text buffer that Ghost Text
/// maintains as the source of truth for "what has the user typed."
///
/// This buffer exists because AX reads are unreliable across Electron apps
/// (see DESIGN.md, "The central flip"). It is reconstructed purely from
/// keystrokes we observe in the event tap, so every event that could change
/// what's in the real text field -- including ones we don't fully
/// understand, like an arbitrary cmd/ctrl chord -- has to be modeled here.
public enum BufferEvent: Sendable, Equatable {
    case character(Character)
    case backspace
    case commit                       // Return / Enter
    case dismiss                      // Escape
    case caretMoved                   // arrows, Home/End, Page keys, cmd/ctrl chords
    case mouseDown
    case focusChanged(bundleID: String?)
    case idleTimeout
    case secureInputEngaged
    case acceptedCompletion(String)   // text WE synthesized
}

/// What happened to the buffer as a result of applying one event, expressed
/// as instructions for the caller (the overlay controller / scheduler) so
/// this type never has to know about `NSPanel` or debounce timers.
public struct BufferChange: Sendable, Equatable {
    public let cleared: Bool
    public let textChanged: Bool
    public let shouldDismissSuggestion: Bool
    public let shouldRequestSuggestion: Bool

    public init(
        cleared: Bool,
        textChanged: Bool,
        shouldDismissSuggestion: Bool,
        shouldRequestSuggestion: Bool
    ) {
        self.cleared = cleared
        self.textChanged = textChanged
        self.shouldDismissSuggestion = shouldDismissSuggestion
        self.shouldRequestSuggestion = shouldRequestSuggestion
    }
}

/// The in-memory reconstruction of "what's in the focused text field right
/// now, as far as we can tell." Never touches AX; it is built exclusively
/// from the keystrokes the event tap observes (see DESIGN.md).
public struct KeystrokeBuffer: Sendable, Equatable {
    public private(set) var text: String

    /// False when we know we've lost sync with the real field -- e.g. a
    /// backspace was applied to an already-empty buffer, meaning the user
    /// deleted past whatever we thought the field's contents were. While
    /// desynced we still track characters (best effort) but never offer
    /// suggestions against a buffer we can't trust.
    public private(set) var isSuggestable: Bool

    public static let maxLength = 512

    public init() {
        self.text = ""
        self.isSuggestable = true
    }

    @discardableResult
    public mutating func apply(_ event: BufferEvent) -> BufferChange {
        switch event {
        case .character(let c):
            text.append(c)
            trimFrontIfNeeded()
            return BufferChange(
                cleared: false,
                textChanged: true,
                shouldDismissSuggestion: true,
                shouldRequestSuggestion: shouldRequestSuggestionNow()
            )

        case .backspace:
            if text.isEmpty {
                // Deleted past our known origin: we no longer know what's
                // in the field. Desync, and stay desynced until something
                // resets us (commit/dismiss/caretMoved/focus/etc.).
                isSuggestable = false
                return BufferChange(
                    cleared: false,
                    textChanged: false,
                    shouldDismissSuggestion: true,
                    shouldRequestSuggestion: false
                )
            }
            text.removeLast()
            return BufferChange(
                cleared: false,
                textChanged: true,
                shouldDismissSuggestion: true,
                shouldRequestSuggestion: shouldRequestSuggestionNow()
            )

        case .commit, .dismiss, .caretMoved, .mouseDown, .idleTimeout, .secureInputEngaged:
            return clearAndReset()

        case .focusChanged:
            // Always clears, even if the bundleID is unchanged -- a focus
            // event means the field itself may have changed under us even
            // if the owning app didn't.
            return clearAndReset()

        case .acceptedCompletion(let accepted):
            // We synthesized this text ourselves, so it does not touch
            // desync state -- it's exactly as trustworthy as what preceded
            // it in the buffer.
            text.append(accepted)
            trimFrontIfNeeded()
            return BufferChange(
                cleared: false,
                textChanged: true,
                shouldDismissSuggestion: false,
                shouldRequestSuggestion: shouldRequestSuggestionNow()
            )
        }
    }

    private mutating func clearAndReset() -> BufferChange {
        let hadText = !text.isEmpty
        text = ""
        isSuggestable = true
        return BufferChange(
            cleared: true,
            textChanged: hadText,
            shouldDismissSuggestion: true,
            shouldRequestSuggestion: false
        )
    }

    private mutating func trimFrontIfNeeded() {
        guard text.count > Self.maxLength else { return }
        let overflow = text.count - Self.maxLength
        text.removeFirst(overflow)
    }

    private func shouldRequestSuggestionNow() -> Bool {
        guard isSuggestable else { return false }
        let nonWhitespaceCount = text.reduce(0) { count, ch in
            ch.isWhitespace ? count : count + 1
        }
        return nonWhitespaceCount >= 3
    }
}

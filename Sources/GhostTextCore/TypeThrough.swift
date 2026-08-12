import Foundation

/// Lets the user type along a suggestion that is already correct.
///
/// Without this, every keystroke dismisses the suggestion and waits for the model
/// to produce a new one, so typing the very words being suggested still costs a
/// full round trip per character and the ghost text flickers the whole way. When
/// the typed character is the one the suggestion predicted, there is nothing to
/// ask the model: shrink the suggestion and carry on. That path costs no
/// inference at all, which is the difference between "fast" and "instant".
public enum TypeThrough {
    public enum Outcome: Sendable, Equatable {
        /// The character matched. Show what is left.
        case consumed(remaining: String)
        /// The character matched and the suggestion is now used up.
        case exhausted
        /// The user typed something else. The suggestion is wrong now.
        case diverged
    }

    public static func apply(character: Character, to completion: String) -> Outcome {
        guard let expected = completion.first else { return .diverged }
        guard character == expected else { return .diverged }

        let remaining = String(completion.dropFirst())
        // Whitespace alone is not worth showing, and leaving it up would park a
        // stray blank overlay next to the caret.
        return remaining.allSatisfy(\.isWhitespace) ? .exhausted : .consumed(remaining: remaining)
    }
}

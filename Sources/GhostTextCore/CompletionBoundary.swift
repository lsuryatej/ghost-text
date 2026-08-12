import Foundation

/// Decides when a completion has reached a natural stopping point, so generation
/// can end before the token cap. Decode dominates end-to-end latency, so stopping
/// early is most of the speed win.
public enum CompletionBoundary {
    /// `~` accepts three words and Tab accepts one, so eight is already generous
    /// headroom over anything a single accept shows.
    public static let defaultWordLimit = 8

    private static let terminators: Set<Character> = [".", "!", "?"]

    /// `text` is the completion generated so far, never the user's buffer.
    /// Called after every streamed token, so it stays a cheap single pass.
    public static func isAtBoundary(_ text: String, wordLimit: Int = defaultWordLimit) -> Bool {
        guard !text.isEmpty else { return false }

        // Completions are single-line by design; a newline means the model has
        // wandered into a new paragraph or a list.
        if text.contains(where: { $0.isNewline }) { return true }

        let words = text.split(whereSeparator: { $0.isWhitespace })
        if words.count >= wordLimit { return true }

        // Require at least one real word before any sentence-terminator stop.
        // Without this a completion that opens with an ellipsis ends before it
        // has said anything: the 1.5B model emitted a bare "..." for a third of
        // the quality prompts and every one of them was cut to nothing.
        guard words.contains(where: { $0.contains(where: { !terminators.contains($0) }) }) else {
            return false
        }

        // Only a terminator *confirmed* by following whitespace ends generation,
        // and never one inside a run like "..." or "?!". Waiting for the next
        // token to confirm costs about one decode step, which is far cheaper
        // than truncating a good completion.
        let characters = Array(text)
        for index in characters.indices.dropLast() {
            guard terminators.contains(characters[index]), characters[index + 1].isWhitespace else { continue }
            if index > 0, terminators.contains(characters[index - 1]) { continue }
            return true
        }
        return false
    }
}

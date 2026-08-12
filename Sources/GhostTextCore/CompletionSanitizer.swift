import Foundation

/// Cleans up raw model output before it's shown as ghost text or synthesized
/// as keystrokes. Small on-device models reliably do a handful of annoying
/// things: wrap the answer in quotes/backticks, echo back a chunk of the
/// prompt they were just given, ramble past a sentence, or emit multiple
/// lines. This is the seam that turns "raw model text" into "safe to type
/// into any app."
public struct CompletionSanitizer: Sendable {
    public var maxWords: Int

    public init(maxWords: Int = 6) {
        self.maxWords = maxWords
    }

    /// Runs the full cleanup pipeline. Returns `nil` when nothing usable
    /// survives (empty, whitespace-only, or pure punctuation) -- callers
    /// should treat `nil` exactly like "no suggestion."
    public func sanitize(raw: String, buffer: String) -> String? {
        var work = Self.truncateAtNewline(raw)
        work = Self.stripWrappingArtifacts(work)
        work = Self.dropEchoedContext(work, buffer: buffer)
        work = Self.normalizeWhitespace(work, bufferEndsInWhitespace: buffer.last?.isWhitespace ?? false)
        work = Self.capWords(work, maxWords: maxWords)

        guard Self.isMeaningful(work) else { return nil }
        return work
    }

    /// The leading whitespace (if any) plus the next non-whitespace run, so
    /// it can be appended directly to whatever's already been typed. Used
    /// for the `Tab` (accept-one-word) accept key.
    public static func firstWord(of completion: String) -> String {
        var idx = completion.startIndex
        var leading = ""
        while idx < completion.endIndex, completion[idx].isWhitespace {
            leading.append(completion[idx])
            idx = completion.index(after: idx)
        }
        var word = ""
        while idx < completion.endIndex, !completion[idx].isWhitespace {
            word.append(completion[idx])
            idx = completion.index(after: idx)
        }
        return leading + word
    }

    /// The leading whitespace (if any) plus up to `maxWords` words. Used for
    /// the `~` (accept-phrase) accept key, which the caller invokes with
    /// `maxWords: 3`.
    public static func phrase(of completion: String, maxWords: Int) -> String {
        var idx = completion.startIndex
        var leading = ""
        while idx < completion.endIndex, completion[idx].isWhitespace {
            leading.append(completion[idx])
            idx = completion.index(after: idx)
        }
        let rest = completion[idx...]
        let words = rest.split(whereSeparator: { $0.isWhitespace }).prefix(maxWords)
        return leading + words.joined(separator: " ")
    }

    // MARK: - Pipeline stages

    private static func truncateAtNewline(_ raw: String) -> String {
        if let newlineIndex = raw.firstIndex(where: { $0.isNewline }) {
            return String(raw[raw.startIndex..<newlineIndex])
        }
        return raw
    }

    /// Strips matching wrapping quotes / markdown emphasis markers
    /// (`"..."`, `'...'`, `` `...` ``, `**...**`, `*...*`) from around the
    /// non-whitespace core of the string, repeating until nothing more
    /// unwraps (handles nested cases like `` **`word`** ``). Whitespace at
    /// the very edges is preserved untouched for the whitespace-normalize
    /// stage to reason about.
    private static func stripWrappingArtifacts(_ s: String) -> String {
        guard let firstNonWS = s.firstIndex(where: { !$0.isWhitespace }) else { return s }
        let lastNonWS = s.lastIndex(where: { !$0.isWhitespace })!
        let leading = String(s[s.startIndex..<firstNonWS])
        let trailing = String(s[s.index(after: lastNonWS)...])
        var core = String(s[firstNonWS...lastNonWS])

        var changed = true
        while changed {
            changed = false
            if core.count >= 4, core.hasPrefix("**"), core.hasSuffix("**") {
                core = String(core.dropFirst(2).dropLast(2))
                changed = true
            } else if core.count >= 2, core.hasPrefix("`"), core.hasSuffix("`") {
                core = String(core.dropFirst().dropLast())
                changed = true
            } else if core.count >= 2, core.hasPrefix("\""), core.hasSuffix("\"") {
                core = String(core.dropFirst().dropLast())
                changed = true
            } else if core.count >= 2, core.hasPrefix("'"), core.hasSuffix("'") {
                core = String(core.dropFirst().dropLast())
                changed = true
            } else if core.count >= 2, core.hasPrefix("*"), core.hasSuffix("*") {
                core = String(core.dropFirst().dropLast())
                changed = true
            }
        }
        return leading + core + trailing
    }

    /// Finds the longest suffix of `buffer` (looking back at most 40
    /// characters) that is a case-insensitive prefix of `completion`, and
    /// removes it. Small models frequently echo back the tail of the prompt
    /// before continuing it.
    ///
    /// Only suffixes that *begin at a word boundary* are considered. Matching any
    /// suffix would mangle completions on a coincidental one-character overlap:
    /// a buffer ending in "e" against the completion "elephant" would strip the
    /// "e" and emit "lephant". Requiring a boundary still catches both real echo
    /// shapes — a whole repeated word ("The quick brown" + "brown fox" → " fox")
    /// and a repeated partial word ("The quick brow" + "brown fox" → "n fox").
    private static func dropEchoedContext(_ completion: String, buffer: String) -> String {
        let bufferTail = String(buffer.suffix(40))
        guard !bufferTail.isEmpty else { return completion }

        let characters = Array(bufferTail)
        let isWholeBuffer = buffer.count <= 40
        let lowerCompletion = completion.lowercased()

        // Longest match first, so iterate candidate start offsets ascending.
        for start in 0..<characters.count {
            // A truncated tail's first character is mid-word, so it only counts
            // as a boundary when the tail really is the whole buffer.
            let atBoundary = start == 0 ? isWholeBuffer : characters[start - 1].isWhitespace
            guard atBoundary else { continue }

            let candidate = String(characters[start...]).lowercased()
            guard !candidate.isEmpty, lowerCompletion.hasPrefix(candidate) else { continue }
            return String(completion.dropFirst(candidate.count))
        }
        return completion
    }

    /// Collapses internal whitespace runs to a single space, and enforces
    /// the leading-space rule: at most one leading space survives, and even
    /// that one is dropped if `buffer` already ends in whitespace (since the
    /// separation is already there).
    private static func normalizeWhitespace(_ s: String, bufferEndsInWhitespace: Bool) -> String {
        let hasLeadingWhitespace = s.first?.isWhitespace ?? false
        let words = s.split(whereSeparator: { $0.isWhitespace })
        let collapsed = words.joined(separator: " ")

        if hasLeadingWhitespace, !bufferEndsInWhitespace, !collapsed.isEmpty {
            return " " + collapsed
        }
        return collapsed
    }

    /// Caps to `maxWords` words, preserving a single leading space marker
    /// (if present) without counting it as a word.
    private static func capWords(_ s: String, maxWords: Int) -> String {
        let hasLeadingSpace = s.hasPrefix(" ")
        let core = hasLeadingSpace ? String(s.dropFirst()) : s
        let words = core.split(separator: " ").prefix(maxWords)
        let capped = words.joined(separator: " ")
        return hasLeadingSpace ? " " + capped : capped
    }

    private static func isMeaningful(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains { $0.isLetter || $0.isNumber }
    }
}

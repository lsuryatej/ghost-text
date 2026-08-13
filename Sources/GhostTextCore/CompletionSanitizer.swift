import Foundation

/// Cleans up raw model output before it's shown as ghost text or synthesized
/// as keystrokes. Small on-device models reliably do a handful of annoying
/// things: wrap the answer in quotes/backticks, echo back a chunk of the
/// prompt they were just given, ramble past a sentence, or emit multiple
/// lines. This is the seam that turns "raw model text" into "safe to type
/// into any app."
public struct CompletionSanitizer: Sendable {
    public var maxWords: Int

    /// Whether a fragment is itself a complete word, not one still being
    /// typed. Defaults to "yes" (i.e. no rejection) so callers that don't
    /// care about this — most tests — see the old, permissive behavior;
    /// the app wires in a real dictionary lookup. See `rejectAbandonedFragment`
    /// and `normalizeWhitespace`.
    public var isCompleteWord: @Sendable (String) -> Bool

    public init(maxWords: Int = 6, isCompleteWord: @escaping @Sendable (String) -> Bool = { _ in true }) {
        self.maxWords = maxWords
        self.isCompleteWord = isCompleteWord
    }

    /// Runs the full cleanup pipeline. Returns `nil` when nothing usable
    /// survives (empty, whitespace-only, or pure punctuation) -- callers
    /// should treat `nil` exactly like "no suggestion."
    public func sanitize(raw: String, buffer: String) -> String? {
        var work = Self.truncateAtSpecialToken(raw)
        work = Self.truncateAtNewline(work)
        work = Self.stripWrappingArtifacts(work)
        work = Self.stripLeadingEllipsis(work)
        work = Self.dropEchoedContext(work, buffer: buffer)
        work = Self.dropRestartedWord(work, buffer: buffer)
        work = Self.rejectAbandonedFragment(work, buffer: buffer, isCompleteWord: isCompleteWord)
        work = Self.normalizeWhitespace(work, buffer: buffer, isCompleteWord: isCompleteWord)
        work = Self.truncateAtDegenerateRepetition(work)
        work = Self.capWords(work, maxWords: maxWords)

        guard Self.isMeaningful(work) else { return nil }
        return work
    }

    /// Cuts at a chat-template terminator that leaked into the output.
    ///
    /// Registering them as stop tokens is the real fix, but a model can still
    /// emit a terminator the loader did not know about, and the failure is ugly:
    /// Gemma produced "ing.<end_of_turn>" followed by tokens from several other
    /// scripts. Belt and braces, since the cost is one substring scan.
    static func truncateAtSpecialToken(_ raw: String) -> String {
        var cut = raw.endIndex
        for marker in ["<end_of_turn>", "<start_of_turn>", "<|im_end|>", "<|im_start|>", "<|endoftext|>", "<eos>", "<bos>", "<think>"] {
            if let range = raw.range(of: marker), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        return String(raw[raw.startIndex..<cut])
    }

    /// Removes a leading ellipsis.
    ///
    /// Larger instruct models have a tic of opening a continuation with "..." to
    /// signal "carrying on from here" - Qwen2.5-1.5B did it on a third of the
    /// quality prompts. As inline ghost text it is noise, and it pushes the real
    /// words along by three characters.
    static func stripLeadingEllipsis(_ s: String) -> String {
        let hadSpaceBefore = s.first?.isWhitespace ?? false
        var work = String(s.drop(while: { $0.isWhitespace }))

        var changed = false
        while work.hasPrefix("...") || work.hasPrefix("\u{2026}") {
            work = work.hasPrefix("...") ? String(work.dropFirst(3)) : String(work.dropFirst())
            changed = true
        }
        guard changed else { return s }

        // Whitespace on either side of the ellipsis was the word separator. Drop
        // it and "we could" + "organize" concatenates into "couldorganize"; the
        // later whitespace pass removes it again if the buffer already ends in a
        // space, so keeping it here is always safe.
        let hadSpaceAfter = work.first?.isWhitespace ?? false
        work = String(work.drop(while: { $0.isWhitespace }))
        guard !work.isEmpty else { return "" }
        return (hadSpaceBefore || hadSpaceAfter) ? " " + work : work
    }

    /// Cuts a completion short at the point it starts looping.
    ///
    /// Small models fall into degenerate repetition on short prompts — "The quick "
    /// produced "mouse mouse mouse mouse mouse mouse". A repetition penalty during
    /// sampling makes this rare but not impossible, and showing a visible loop
    /// reads as broken, so it is also caught here where it can be tested.
    ///
    /// Genuine English repeats a word twice ("had had", "that that"), so only a
    /// third consecutive occurrence counts as a loop.
    static func truncateAtDegenerateRepetition(_ s: String) -> String {
        let leading = s.hasPrefix(" ") ? " " : ""
        let words = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 3 else { return s }

        var kept: [String] = []
        var runLength = 0
        var previous: String?

        for word in words {
            let normalized = word.lowercased()
            if normalized == previous {
                runLength += 1
            } else {
                runLength = 1
                previous = normalized
            }
            guard runLength < 3 else { break }
            kept.append(word)
        }

        guard kept.count < words.count else { return s }
        return leading + kept.joined(separator: " ")
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

    /// Drops leading newlines, then keeps only the first line.
    ///
    /// Small models often open with a stray newline or two before saying anything
    /// useful. Truncating at the *first* newline turned those into empty strings
    /// and threw the completion away - one real example was a leading "\n\n"
    /// discarding an otherwise complete sentence. Leading newlines are formatting
    /// noise, not content, so skip past them before cutting.
    private static func truncateAtNewline(_ raw: String) -> String {
        var start = raw.startIndex
        while start < raw.endIndex, raw[start].isNewline {
            start = raw.index(after: start)
        }
        let body = raw[start...]
        if let newlineIndex = body.firstIndex(where: { $0.isNewline }) {
            return String(body[body.startIndex..<newlineIndex])
        }
        return String(body)
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

            // The match must end a word. If a letter follows, the completion is
            // continuing a word the user is midway through rather than repeating
            // one, which is `dropRestartedWord`'s job and has its own minimum
            // length. Without this, buffer "an a" against "apple pie" strips the
            // "a" and yields "pple pie".
            let remainder = completion.dropFirst(candidate.count)
            if let next = remainder.first, next.isLetter { continue }
            return String(remainder)
        }
        return completion
    }

    /// Handles a model that restarts the word the user is midway through typing.
    ///
    /// Asked to continue "Can you send me the quarterly rep", models often answer
    /// " report?" - the whole word, with a leading space - which would render as
    /// "quarterly rep report?". Detect that the completion's first word begins
    /// with the fragment still being typed, and drop the duplicated fragment.
    ///
    /// Only fires when the buffer really does end mid-word, so a completion that
    /// legitimately repeats a just-finished word is left alone.
    static func dropRestartedWord(_ completion: String, buffer: String) -> String {
        guard let lastCharacter = buffer.last, !lastCharacter.isWhitespace else { return completion }

        let fragment = String(buffer.reversed().prefix(while: { $0.isLetter }).reversed())
        guard fragment.count >= 2 else { return completion }

        let trimmed = completion.drop(while: { $0.isWhitespace })
        guard trimmed.count > fragment.count else { return completion }

        let candidate = String(trimmed)
        guard candidate.lowercased().hasPrefix(fragment.lowercased()) else { return completion }

        // The next character must continue the word rather than end it, otherwise
        // the model simply repeated a complete word and dropping it would be wrong.
        let remainder = String(candidate.dropFirst(fragment.count))
        guard let next = remainder.first, next.isLetter else { return completion }
        return remainder
    }

    /// Rejects a completion that ignores the word the user is still typing.
    ///
    /// `dropRestartedWord` handles a model that echoes the in-progress fragment
    /// back before continuing it. This handles the other failure: the model
    /// answers with an unrelated word instead, e.g. buffer "...quarterly rep" and
    /// completion " deadline". Typed through, that stitches into "quarterly rep
    /// deadline" — a stray word landing inside one you hadn't finished, which
    /// reads as a spurious space breaking the word apart.
    ///
    /// Only fires when the fragment is not itself a complete word: "the cat" +
    /// " sat on the mat" is the model correctly starting a new word after a
    /// finished one, and must not be rejected just because "cat" ends in a
    /// letter. Whether the fragment is "finished" can't be known from keystrokes
    /// alone, so `isCompleteWord` (a real dictionary lookup in the app) is the
    /// signal: an unfinished fragment is essentially never a real word.
    static func rejectAbandonedFragment(_ completion: String, buffer: String, isCompleteWord: (String) -> Bool) -> String {
        guard let lastCharacter = buffer.last, lastCharacter.isLetter else { return completion }
        let fragment = String(buffer.reversed().prefix(while: { $0.isLetter }).reversed())
        guard fragment.count >= 2, !isCompleteWord(fragment) else { return completion }

        // A direct continuation has no whitespace before the next letter — the
        // model is still writing the same token. Anything else abandons it.
        guard let first = completion.first else { return completion }
        return first.isWhitespace ? "" : completion
    }

    /// Collapses internal whitespace runs to a single space, and enforces the
    /// leading-space rule against the actual buffer rather than trusting
    /// whatever the model happened to emit:
    ///
    /// - Buffer ends in whitespace: no leading space — the separation is
    ///   already there, so even one the model added is dropped.
    /// - Buffer ends in a letter or digit: genuinely ambiguous (mid-token
    ///   continuation vs. a fresh word after one that just finished), so the
    ///   model's own choice is preserved as-is. `rejectAbandonedFragment`
    ///   already rejects the cases where that choice is wrong.
    /// - Buffer ends in punctuation: a new word is starting and always needs
    ///   a separator, model or not. Small local models drop it
    ///   disproportionately often right after a sentence-ending "." —
    ///   unnoticed here, that glues into "sentence.Next".
    private static func normalizeWhitespace(_ s: String, buffer: String, isCompleteWord: (String) -> Bool) -> String {
        let hasLeadingWhitespace = s.first?.isWhitespace ?? false
        let words = s.split(whereSeparator: { $0.isWhitespace })
        let collapsed = words.joined(separator: " ")
        guard !collapsed.isEmpty else { return collapsed }

        guard let lastBufferCharacter = buffer.last else {
            // Nothing typed yet: ambiguous, so defer to the model's own choice.
            return hasLeadingWhitespace ? " " + collapsed : collapsed
        }
        if lastBufferCharacter.isWhitespace { return collapsed }

        if lastBufferCharacter.isLetter || lastBufferCharacter.isNumber {
            let fragment = String(buffer.reversed().prefix(while: { $0.isLetter || $0.isNumber }).reversed())
            guard !fragment.isEmpty, isCompleteWord(fragment), !hasLeadingWhitespace else {
                // Fragment still in progress (or the model already
                // supplied its own separator): ambiguous either way, so
                // defer to the model's own choice, same as always.
                return hasLeadingWhitespace ? " " + collapsed : collapsed
            }
            // The fragment is already a finished word and the model glued
            // straight onto it with no space. That's only legitimate if the
            // glued result is itself a real word ("the" + "n" -> "then");
            // check the actual join rather than just the fragment, because
            // `dropRestartedWord` already turns a genuine restart-and-continue
            // ("rep" + "report?") into a clean continuation ("ort?") upstream,
            // and re-deciding purely from the fragment there would insert a
            // space back into the middle of a real word. Observed live: "the"
            // + model output "ghost text in this chat." glued into
            // "theghost" — "the" + "ghost" isn't a word, so this forces the
            // separator back in.
            let firstRun = String(collapsed.prefix(while: { $0.isLetter || $0.isNumber }))
            if !firstRun.isEmpty, isCompleteWord(fragment + firstRun) {
                return collapsed
            }
            return " " + collapsed
        }
        return " " + collapsed
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

import XCTest

@testable import GhostTextCore

final class CompletionSanitizerTests: XCTestCase {

    // MARK: - Basic pass-through

    func testSimpleCompletionPassesThrough() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "world", buffer: "hello "), "world")
    }

    // MARK: - Newline truncation

    func testTruncatesAtFirstNewline() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "world\nsome extra rambling", buffer: "hello "), "world")
    }

    func testTruncatesAtCarriageReturn() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "world\rmore junk", buffer: "hello "), "world")
    }

    // MARK: - Wrapping quotes / markdown artifacts

    func testStripsWrappingDoubleQuotes() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "\"world\"", buffer: "hello "), "world")
    }

    func testStripsWrappingSingleQuotes() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "'world'", buffer: "hello "), "world")
    }

    func testStripsWrappingBackticks() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "`world`", buffer: "hello "), "world")
    }

    func testStripsWrappingDoubleAsteriskBold() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "**world**", buffer: "hello "), "world")
    }

    func testStripsWrappingSingleAsteriskItalic() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "*world*", buffer: "hello "), "world")
    }

    func testStripsNestedMarkdownAndQuotes() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "**`world`**", buffer: "hello "), "world")
    }

    func testDoesNotStripInternalPunctuationThatIsntWrapping() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "don't stop", buffer: "please "), "don't stop")
    }

    // MARK: - Echoed context

    func testDropsFullyEchoedBuffer() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "I like to eat pizza", buffer: "I like to eat"), " pizza")
    }

    func testDropsPartialSuffixEcho() {
        let sanitizer = CompletionSanitizer()
        // buffer's suffix "to eat" echoed at the start of raw.
        XCTAssertEqual(sanitizer.sanitize(raw: "to eat pizza", buffer: "I like to eat"), " pizza")
    }

    func testEchoMatchIsCaseInsensitive() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "TO EAT pizza", buffer: "I like to eat"), " pizza")
    }

    func testMidWordContinuationYieldsNoLeadingSpace() {
        // The exact scenario from the spec: buffer ends mid-word, completion
        // continues it with no separating space.
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "n fox jumps", buffer: "The quick brow"), "n fox jumps")
    }

    func testNoEchoWhenNoOverlapExists() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "completely unrelated", buffer: "xyz123"), "completely unrelated")
    }

    // MARK: - Whitespace normalization

    func testCollapsesInternalWhitespaceRuns() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "hello    world", buffer: "say "), "hello world")
    }

    func testPreservesOneLeadingSpaceWhenBufferHasNoTrailingWhitespace() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: " world", buffer: "hello"), " world")
    }

    func testDropsLeadingSpaceWhenBufferEndsInWhitespace() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: " world", buffer: "hello "), "world")
    }

    func testCollapsesMultipleLeadingSpacesToOne() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "   world", buffer: "hello"), " world")
    }

    // MARK: - Word capping

    func testCapsToDefaultSixWords() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(
            sanitizer.sanitize(raw: "one two three four five six seven eight", buffer: "start "),
            "one two three four five six"
        )
    }

    func testCapsToCustomMaxWords() {
        let sanitizer = CompletionSanitizer(maxWords: 2)
        XCTAssertEqual(sanitizer.sanitize(raw: "one two three four", buffer: "start "), "one two")
    }

    func testCappingPreservesLeadingSpace() {
        let sanitizer = CompletionSanitizer(maxWords: 2)
        XCTAssertEqual(sanitizer.sanitize(raw: " one two three", buffer: "start"), " one two")
    }

    func testUnderMaxWordsPassesThroughUnchanged() {
        let sanitizer = CompletionSanitizer(maxWords: 6)
        XCTAssertEqual(sanitizer.sanitize(raw: "one two", buffer: "start "), "one two")
    }

    // MARK: - Rejections

    func testNilForEmptyString() {
        let sanitizer = CompletionSanitizer()
        XCTAssertNil(sanitizer.sanitize(raw: "", buffer: "hello "))
    }

    func testNilForWhitespaceOnly() {
        let sanitizer = CompletionSanitizer()
        XCTAssertNil(sanitizer.sanitize(raw: "   ", buffer: "hello "))
    }

    func testNilForPurePunctuation() {
        let sanitizer = CompletionSanitizer()
        XCTAssertNil(sanitizer.sanitize(raw: "...", buffer: "hello "))
    }

    func testNilForPunctuationAfterQuoteStrip() {
        let sanitizer = CompletionSanitizer()
        XCTAssertNil(sanitizer.sanitize(raw: "\"---\"", buffer: "hello "))
    }

    func testNilWhenOnlyEchoedContentRemains() {
        let sanitizer = CompletionSanitizer()
        XCTAssertNil(sanitizer.sanitize(raw: "I like to eat", buffer: "I like to eat"))
    }

    // MARK: - firstWord

    func testFirstWordBasic() {
        XCTAssertEqual(CompletionSanitizer.firstWord(of: "world peace"), "world")
    }

    func testFirstWordPreservesLeadingSpace() {
        XCTAssertEqual(CompletionSanitizer.firstWord(of: " fox jumps"), " fox")
    }

    func testFirstWordOfSingleWord() {
        XCTAssertEqual(CompletionSanitizer.firstWord(of: "solo"), "solo")
    }

    func testFirstWordOfEmptyStringIsEmpty() {
        XCTAssertEqual(CompletionSanitizer.firstWord(of: ""), "")
    }

    // MARK: - phrase

    func testPhraseCapsToThreeWords() {
        XCTAssertEqual(CompletionSanitizer.phrase(of: "one two three four five", maxWords: 3), "one two three")
    }

    func testPhrasePreservesLeadingSpace() {
        XCTAssertEqual(CompletionSanitizer.phrase(of: " one two three four", maxWords: 3), " one two three")
    }

    func testPhraseWithFewerWordsThanMax() {
        XCTAssertEqual(CompletionSanitizer.phrase(of: "one two", maxWords: 3), "one two")
    }

    func testPhraseWithMaxWordsOne() {
        XCTAssertEqual(CompletionSanitizer.phrase(of: "one two three", maxWords: 1), "one")
    }

    // MARK: - Echo drop only fires on word boundaries

    /// The regression this rule exists for: a coincidental one-character overlap
    /// between the end of the buffer and the start of the completion must not
    /// eat a character. "e" + "elephant" previously produced "lephant".
    func testCoincidentalTrailingCharacterIsNotTreatedAsEcho() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "elephant in the room", buffer: "I saw the"), "elephant in the room")
    }

    func testMidWordCoincidenceIsNotTreatedAsEcho() {
        let sanitizer = CompletionSanitizer()
        // "st" ends "breakfast" but is not a word start, so "stopped" survives whole.
        XCTAssertEqual(sanitizer.sanitize(raw: "stopped by", buffer: "we had breakfast"), "stopped by")
    }

    func testWholeRepeatedWordIsStillDropped() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "brown fox jumps", buffer: "The quick brown"), " fox jumps")
    }

    func testRepeatedPartialWordIsStillDropped() {
        let sanitizer = CompletionSanitizer()
        // Mid-word completion: no space is introduced.
        XCTAssertEqual(sanitizer.sanitize(raw: "brown fox jumps", buffer: "The quick brow"), "n fox jumps")
    }

    func testSingleLetterWordEchoIsDropped() {
        let sanitizer = CompletionSanitizer()
        // "a" is a real word here and does start at a boundary, so it is an echo.
        XCTAssertEqual(sanitizer.sanitize(raw: "a great day", buffer: "This is a"), " great day")
    }

    func testMultiWordEchoDropsTheLongestBoundaryMatch() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "quick brown fox", buffer: "The quick brown"), " fox")
    }

    // MARK: - Degenerate repetition

    /// The exact output the 0.5B model produced for the buffer "The quick ".
    func testTruncatesObservedDegenerateLoop() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(
            sanitizer.sanitize(raw: "mouse mouse mouse mouse mouse mouse", buffer: "The quick "),
            "mouse mouse"
        )
    }

    func testLoopLaterInTheCompletionIsCutAtTheLoop() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(
            sanitizer.sanitize(raw: "over the lazy dog dog dog dog", buffer: "jumps "),
            "over the lazy dog dog"
        )
    }

    /// Genuine English doubles words; only a third occurrence is a loop.
    func testLegitimateDoubledWordSurvives() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(sanitizer.sanitize(raw: "had had enough", buffer: "he "), "had had enough")
    }

    func testRepetitionCheckIsCaseInsensitive() {
        XCTAssertEqual(
            CompletionSanitizer.truncateAtDegenerateRepetition("No no NO no"),
            "No no"
        )
    }

    func testNonRepeatingCompletionIsUntouched() {
        XCTAssertEqual(
            CompletionSanitizer.truncateAtDegenerateRepetition(" brown fox jumps over"),
            " brown fox jumps over"
        )
    }

    // MARK: - Leading newlines

    /// Observed live: a leading "\n\n" made the whole completion vanish.
    func testLeadingNewlinesAreSkippedNotTruncatedAt() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(
            sanitizer.sanitize(raw: "\n\nThe sun set behind", buffer: "he wrote "),
            "The sun set behind"
        )
    }

    func testStillTruncatesAtNewlineAfterContent() {
        let sanitizer = CompletionSanitizer()
        XCTAssertEqual(
            sanitizer.sanitize(raw: "\nfirst line\nsecond line", buffer: "he wrote "),
            "first line"
        )
    }

    func testAllNewlinesIsStillRejected() {
        let sanitizer = CompletionSanitizer()
        XCTAssertNil(sanitizer.sanitize(raw: "\n\n\n", buffer: "he wrote "))
    }
}

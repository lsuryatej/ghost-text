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
}

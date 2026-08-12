import XCTest

@testable import GhostTextCore

final class KeystrokeBufferTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsEmptyAndSuggestable() {
        let buffer = KeystrokeBuffer()
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
    }

    // MARK: - .character

    func testCharacterAppends() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("h"))
        _ = buffer.apply(.character("i"))
        XCTAssertEqual(buffer.text, "hi")
    }

    func testCharacterTrimsFromFrontPastMaxLength() {
        var buffer = KeystrokeBuffer()
        for _ in 0..<(KeystrokeBuffer.maxLength) {
            _ = buffer.apply(.character("a"))
        }
        XCTAssertEqual(buffer.text.count, KeystrokeBuffer.maxLength)
        _ = buffer.apply(.character("b"))
        XCTAssertEqual(buffer.text.count, KeystrokeBuffer.maxLength)
        XCTAssertTrue(buffer.text.hasSuffix("b"))
    }

    func testCharacterDismissesCurrentSuggestion() {
        var buffer = KeystrokeBuffer()
        let change = buffer.apply(.character("a"))
        XCTAssertTrue(change.shouldDismissSuggestion)
    }

    func testCharacterRequestsSuggestionAtThreeNonWhitespaceChars() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.character("b"))
        let change = buffer.apply(.character("c"))
        XCTAssertTrue(change.shouldRequestSuggestion)
    }

    func testCharacterDoesNotRequestSuggestionBelowThreeChars() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        let change = buffer.apply(.character("b"))
        XCTAssertFalse(change.shouldRequestSuggestion)
    }

    func testCharacterRequestsSuggestionWithTrailingSpace() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.character("b"))
        _ = buffer.apply(.character("c"))
        let change = buffer.apply(.character(" "))
        XCTAssertTrue(change.shouldRequestSuggestion, "trailing space after 3 real chars should still suggest")
    }

    func testCharacterCountsOnlyNonWhitespace() {
        var buffer = KeystrokeBuffer()
        // "a b" -> only 2 non-whitespace chars, should not suggest yet.
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.character(" "))
        let change = buffer.apply(.character("b"))
        XCTAssertFalse(change.shouldRequestSuggestion)
    }

    func testCharacterMarksTextChanged() {
        var buffer = KeystrokeBuffer()
        let change = buffer.apply(.character("a"))
        XCTAssertTrue(change.textChanged)
        XCTAssertFalse(change.cleared)
    }

    // MARK: - .backspace

    func testBackspaceRemovesLastCharacter() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("h"))
        _ = buffer.apply(.character("i"))
        _ = buffer.apply(.backspace)
        XCTAssertEqual(buffer.text, "h")
    }

    func testBackspaceOnEmptyBufferDesyncs() {
        var buffer = KeystrokeBuffer()
        XCTAssertTrue(buffer.isSuggestable)
        _ = buffer.apply(.backspace)
        XCTAssertFalse(buffer.isSuggestable)
    }

    func testBackspaceOnEmptyBufferNeverRequestsSuggestion() {
        var buffer = KeystrokeBuffer()
        let change = buffer.apply(.backspace)
        XCTAssertFalse(change.shouldRequestSuggestion)
    }

    func testWhileDesyncedCharactersDoNotRequestSuggestions() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.backspace)  // desync
        XCTAssertFalse(buffer.isSuggestable)
        let change = buffer.apply(.character("a"))
        _ = buffer.apply(.character("b"))
        let change2 = buffer.apply(.character("c"))
        XCTAssertFalse(change.shouldRequestSuggestion)
        XCTAssertFalse(change2.shouldRequestSuggestion, "desync must persist across further typing")
    }

    func testDesyncPersistsUntilResettingEvent() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.backspace)
        XCTAssertFalse(buffer.isSuggestable)
        _ = buffer.apply(.character("a"))
        XCTAssertFalse(buffer.isSuggestable, "appending characters must not clear desync on its own")
    }

    func testBackspaceDismissesSuggestionEvenWhenGoingEmpty() {
        var buffer = KeystrokeBuffer()
        let change = buffer.apply(.backspace)
        XCTAssertTrue(change.shouldDismissSuggestion)
    }

    func testBackspaceOnNonEmptyDoesNotDesync() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.character("b"))
        _ = buffer.apply(.backspace)
        XCTAssertTrue(buffer.isSuggestable)
    }

    // MARK: - Clearing events

    func testCommitClearsBufferAndResetsSuggestability() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.backspace)  // desync first
        _ = buffer.apply(.character("a"))
        let change = buffer.apply(.commit)
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
        XCTAssertTrue(change.cleared)
        XCTAssertTrue(change.shouldDismissSuggestion)
        XCTAssertFalse(change.shouldRequestSuggestion)
    }

    func testDismissClearsBuffer() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.dismiss)
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
    }

    func testCaretMovedClearsBuffer() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.caretMoved)
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
    }

    func testMouseDownClearsBuffer() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.mouseDown)
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
    }

    func testIdleTimeoutClearsBuffer() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.idleTimeout)
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
    }

    func testSecureInputEngagedClearsBuffer() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.secureInputEngaged)
        XCTAssertEqual(buffer.text, "")
        XCTAssertTrue(buffer.isSuggestable)
    }

    func testFocusChangedClearsBufferWithDifferentBundleID() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.focusChanged(bundleID: "com.other.app"))
        XCTAssertEqual(buffer.text, "")
    }

    func testFocusChangedAlwaysClearsEvenWithSameBundleID() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("a"))
        _ = buffer.apply(.focusChanged(bundleID: "com.same.app"))
        let change = buffer.apply(.focusChanged(bundleID: "com.same.app"))
        XCTAssertTrue(change.cleared)
    }

    func testFocusChangedResetsIsSuggestableAfterDesync() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.backspace)  // desync
        XCTAssertFalse(buffer.isSuggestable)
        _ = buffer.apply(.focusChanged(bundleID: nil))
        XCTAssertTrue(buffer.isSuggestable)
    }

    func testClearingEventOnAlreadyEmptyBufferReportsClearedButNotTextChanged() {
        var buffer = KeystrokeBuffer()
        let change = buffer.apply(.commit)
        XCTAssertTrue(change.cleared)
        XCTAssertFalse(change.textChanged)
    }

    // MARK: - .acceptedCompletion

    func testAcceptedCompletionAppends() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("h"))
        _ = buffer.apply(.acceptedCompletion("ello"))
        XCTAssertEqual(buffer.text, "hello")
    }

    func testAcceptedCompletionDoesNotTouchDesyncState() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.backspace)  // desync
        XCTAssertFalse(buffer.isSuggestable)
        _ = buffer.apply(.acceptedCompletion("hello"))
        XCTAssertFalse(buffer.isSuggestable, "accepted completion must not silently re-sync the buffer")
    }

    func testAcceptedCompletionRequestsNewSuggestion() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("h"))
        _ = buffer.apply(.character("i"))
        let change = buffer.apply(.acceptedCompletion(" there"))
        XCTAssertTrue(change.shouldRequestSuggestion)
    }

    func testAcceptedCompletionDoesNotForceDismiss() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.character("h"))
        _ = buffer.apply(.character("i"))
        _ = buffer.apply(.character("!"))
        let change = buffer.apply(.acceptedCompletion(" there"))
        XCTAssertFalse(change.shouldDismissSuggestion, "accepting text is not the same as invalidating it")
    }

    func testAcceptedCompletionRespectsDesyncForSuggestionRequest() {
        var buffer = KeystrokeBuffer()
        _ = buffer.apply(.backspace)  // desync
        let change = buffer.apply(.acceptedCompletion("hello world"))
        XCTAssertFalse(change.shouldRequestSuggestion, "still desynced, should never request")
    }

    // MARK: - Equatable / value semantics

    func testEquality() {
        var a = KeystrokeBuffer()
        var b = KeystrokeBuffer()
        _ = a.apply(.character("x"))
        _ = b.apply(.character("x"))
        XCTAssertEqual(a, b)
        _ = a.apply(.character("y"))
        XCTAssertNotEqual(a, b)
    }
}

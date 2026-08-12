import XCTest

@testable import GhostTextCore

final class CompletionBoundaryTests: XCTestCase {

    // MARK: - The ellipsis regression

    /// The bug this rule exists for. A completion opening with an ellipsis was
    /// cut at the first dot, so the 1.5B model returned a bare "..." for a third
    /// of the quality prompts.
    func testBareEllipsisIsNotABoundary() {
        XCTAssertFalse(CompletionBoundary.isAtBoundary("..."))
        XCTAssertFalse(CompletionBoundary.isAtBoundary("."))
        XCTAssertFalse(CompletionBoundary.isAtBoundary(".."))
    }

    func testEllipsisMidCompletionIsNotABoundary() {
        XCTAssertFalse(CompletionBoundary.isAtBoundary("well... maybe"))
    }

    func testInterrobangRunIsNotABoundary() {
        XCTAssertFalse(CompletionBoundary.isAtBoundary("really?! "))
    }

    // MARK: - Genuine sentence ends

    func testConfirmedSentenceEndIsABoundary() {
        XCTAssertTrue(CompletionBoundary.isAtBoundary("the meeting is over. "))
    }

    /// An unconfirmed trailing terminator waits one more token rather than
    /// guessing, because it might be the start of an ellipsis.
    func testUnconfirmedTrailingTerminatorIsNotYetABoundary() {
        XCTAssertFalse(CompletionBoundary.isAtBoundary("the meeting is over."))
    }

    func testExclamationAndQuestionAlsoTerminate() {
        XCTAssertTrue(CompletionBoundary.isAtBoundary("that is great! "))
        XCTAssertTrue(CompletionBoundary.isAtBoundary("are you sure? "))
    }

    // MARK: - Other stops

    func testNewlineIsAlwaysABoundary() {
        XCTAssertTrue(CompletionBoundary.isAtBoundary("first line\n"))
        XCTAssertTrue(CompletionBoundary.isAtBoundary("\n"))
    }

    func testWordLimitStops() {
        XCTAssertTrue(CompletionBoundary.isAtBoundary("one two three four five six seven eight"))
        XCTAssertFalse(CompletionBoundary.isAtBoundary("one two three"))
    }

    func testCustomWordLimit() {
        XCTAssertTrue(CompletionBoundary.isAtBoundary("one two three", wordLimit: 3))
    }

    func testEmptyIsNotABoundary() {
        XCTAssertFalse(CompletionBoundary.isAtBoundary(""))
    }

    /// A decimal is not a sentence end, because the dot is not followed by space.
    func testDecimalNumberIsNotABoundary() {
        XCTAssertFalse(CompletionBoundary.isAtBoundary("costs 3.14 dollars"))
    }
}

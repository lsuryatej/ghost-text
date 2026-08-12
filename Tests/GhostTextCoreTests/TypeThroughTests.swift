import XCTest

@testable import GhostTextCore

final class TypeThroughTests: XCTestCase {
    func testMatchingCharacterShrinksTheSuggestion() {
        XCTAssertEqual(TypeThrough.apply(character: "b", to: "brown fox"), .consumed(remaining: "rown fox"))
    }

    func testTypingThroughALeadingSpace() {
        XCTAssertEqual(TypeThrough.apply(character: " ", to: " brown fox"), .consumed(remaining: "brown fox"))
    }

    func testDivergingCharacterInvalidates() {
        XCTAssertEqual(TypeThrough.apply(character: "g", to: "brown fox"), .diverged)
    }

    /// Case matters: showing "rown" after the user typed "B" would leave ghost
    /// text that no longer matches what is on screen.
    func testCaseMismatchDiverges() {
        XCTAssertEqual(TypeThrough.apply(character: "B", to: "brown fox"), .diverged)
    }

    func testLastCharacterExhausts() {
        XCTAssertEqual(TypeThrough.apply(character: "x", to: "x"), .exhausted)
    }

    func testTrailingWhitespaceCountsAsExhausted() {
        XCTAssertEqual(TypeThrough.apply(character: "x", to: "x  "), .exhausted)
    }

    func testEmptySuggestionDiverges() {
        XCTAssertEqual(TypeThrough.apply(character: "a", to: ""), .diverged)
    }

    func testTypingAWholeSuggestionThroughNeverCallsTheModel() {
        var completion = " brown fox"
        var steps = 0
        for character in " brown fox" {
            switch TypeThrough.apply(character: character, to: completion) {
            case .consumed(let remaining):
                completion = remaining
                steps += 1
            case .exhausted:
                steps += 1
            case .diverged:
                XCTFail("unexpected divergence at step \(steps)")
                return
            }
        }
        XCTAssertEqual(steps, 10)
    }
}

import XCTest

@testable import GhostTextCore

final class InstantCompleterTests: XCTestCase {
    private let completer = InstantCompleter(dictionary: ["creative", "creature", "sincere"])

    // MARK: - Fragment detection

    func testFragmentIsTheTrailingPartialWord() {
        XCTAssertEqual(InstantCompleter.fragment(in: "I want to be creat"), "creat")
    }

    func testNoFragmentAfterWhitespace() {
        XCTAssertNil(InstantCompleter.fragment(in: "I want to be "))
    }

    func testNoFragmentAfterPunctuation() {
        XCTAssertNil(InstantCompleter.fragment(in: "done."))
    }

    func testShortFragmentIsIgnored() {
        // Two letters match far too many words to guess from.
        XCTAssertNil(InstantCompleter.fragment(in: "go to cr"))
    }

    // MARK: - Completing from the document

    func testCompletesFromAWordAlreadyOnThePage() {
        let context = "The deployment pipeline failed. The deployment needs a rerun."
        XCTAssertEqual(completer.complete(buffer: "check the deploy", context: context), "ment")
    }

    /// The whole point of preferring the document: names and jargon no
    /// dictionary contains.
    func testCompletesJargonTheDictionaryDoesNotKnow() {
        let context = "Ghost Text uses CGEventTap for input. CGEventTap is global."
        XCTAssertEqual(completer.complete(buffer: "the CGEven", context: context), "ttap")
    }

    func testMostUsedWordOnThePageWins() {
        let context = "kubernetes kubernetes kubernetes kubelet"
        XCTAssertEqual(completer.complete(buffer: "run kube", context: context), "rnetes")
    }

    func testTiesPreferTheShorterWord() {
        let context = "running runner"
        let result = completer.complete(buffer: "he was runn", context: context)
        XCTAssertEqual(result, "er")
    }

    func testFallsBackToDictionaryWhenContextHasNothing() {
        XCTAssertEqual(completer.complete(buffer: "be creat", context: "nothing relevant here"), "ive")
    }

    func testReturnsNilWhenNothingMatches() {
        XCTAssertNil(completer.complete(buffer: "xyzzyx", context: "no match"))
    }

    func testDoesNotSuggestTheFragmentItself() {
        // "deploy" is present but is not longer than the fragment.
        XCTAssertNil(completer.complete(buffer: "deploy", context: "deploy deploy"))
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(completer.complete(buffer: "the Deploy", context: "deployment ready"), "ment")
    }
}

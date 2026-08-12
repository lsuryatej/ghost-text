import XCTest

@testable import GhostTextCore

final class AcceptPolicyTests: XCTestCase {

    // MARK: - Defaults

    func testDeniedBundleIDsIsEmptyByDefault() {
        let policy = AcceptPolicy()
        XCTAssertTrue(policy.deniedBundleIDs.isEmpty)
    }

    // MARK: - Visible-only gating: the collision-safety cases

    func testTabWithNoSuggestionPassesThrough_TabToNextFieldSurvives() {
        let policy = AcceptPolicy()
        XCTAssertEqual(
            policy.decide(key: .tab, suggestionVisible: false, bundleID: "com.apple.Terminal"),
            .passThrough
        )
    }

    func testTildeWithNoSuggestionPassesThrough_TildePathsSurvive() {
        let policy = AcceptPolicy()
        XCTAssertEqual(
            policy.decide(key: .text("~"), suggestionVisible: false, bundleID: "com.apple.Terminal"),
            .passThrough
        )
    }

    func testEscapeWithNoSuggestionPassesThrough() {
        let policy = AcceptPolicy()
        XCTAssertEqual(
            policy.decide(key: .escape, suggestionVisible: false, bundleID: nil),
            .passThrough
        )
    }

    func testTabImmediatelyAfterDismissPassesThrough() {
        // Simulates the sequence: Escape dismisses (suggestionVisible flips
        // to false), then Tab arrives on the very next keydown.
        let policy = AcceptPolicy()
        let dismissDecision = policy.decide(key: .escape, suggestionVisible: true, bundleID: nil)
        XCTAssertEqual(dismissDecision, .swallowDismiss)
        let tabDecision = policy.decide(key: .tab, suggestionVisible: false, bundleID: nil)
        XCTAssertEqual(tabDecision, .passThrough)
    }

    // MARK: - Visible: swallow behavior

    func testTabWhileVisibleSwallowsAsAcceptWord() {
        let policy = AcceptPolicy()
        XCTAssertEqual(
            policy.decide(key: .tab, suggestionVisible: true, bundleID: nil),
            .swallowAcceptWord
        )
    }

    func testTildeWhileVisibleSwallowsAsAcceptPhrase() {
        let policy = AcceptPolicy()
        XCTAssertEqual(
            policy.decide(key: .text("~"), suggestionVisible: true, bundleID: nil),
            .swallowAcceptPhrase
        )
    }

    func testEscapeWhileVisibleSwallowsAsDismiss() {
        let policy = AcceptPolicy()
        XCTAssertEqual(
            policy.decide(key: .escape, suggestionVisible: true, bundleID: nil),
            .swallowDismiss
        )
    }

    func testOtherKeysWhileVisiblePassThrough() {
        let policy = AcceptPolicy()
        XCTAssertEqual(policy.decide(key: .commit, suggestionVisible: true, bundleID: nil), .passThrough)
        XCTAssertEqual(policy.decide(key: .backspace, suggestionVisible: true, bundleID: nil), .passThrough)
        XCTAssertEqual(policy.decide(key: .caretMove, suggestionVisible: true, bundleID: nil), .passThrough)
        XCTAssertEqual(policy.decide(key: .text("a"), suggestionVisible: true, bundleID: nil), .passThrough)
        XCTAssertEqual(policy.decide(key: .ignored, suggestionVisible: true, bundleID: nil), .passThrough)
    }

    func testOnlyExactTildePassesGating_OtherTextCharsPassThrough() {
        let policy = AcceptPolicy()
        XCTAssertEqual(policy.decide(key: .text("`"), suggestionVisible: true, bundleID: nil), .passThrough)
    }

    // MARK: - Denylist escape valve

    func testDeniedBundleIDShortCircuitsToPassThroughEvenWhenVisible() {
        var policy = AcceptPolicy()
        policy.deniedBundleIDs = ["com.problem.app"]
        XCTAssertEqual(
            policy.decide(key: .tab, suggestionVisible: true, bundleID: "com.problem.app"),
            .passThrough
        )
    }

    func testDeniedBundleIDDoesNotAffectOtherApps() {
        var policy = AcceptPolicy()
        policy.deniedBundleIDs = ["com.problem.app"]
        XCTAssertEqual(
            policy.decide(key: .tab, suggestionVisible: true, bundleID: "com.fine.app"),
            .swallowAcceptWord
        )
    }

    func testNilBundleIDWithNonEmptyDenylistDoesNotCrashAndBehavesNormally() {
        var policy = AcceptPolicy()
        policy.deniedBundleIDs = ["com.problem.app"]
        XCTAssertEqual(
            policy.decide(key: .tab, suggestionVisible: true, bundleID: nil),
            .swallowAcceptWord
        )
    }

    func testInitWithDeniedBundleIDs() {
        let policy = AcceptPolicy(deniedBundleIDs: ["com.problem.app"])
        XCTAssertEqual(policy.deniedBundleIDs, ["com.problem.app"])
    }
}

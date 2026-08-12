import XCTest

@testable import GhostTextCore

final class ContextAssemblerTests: XCTestCase {
    private let assembler = ContextAssembler()

    // MARK: - AX lag reconciliation

    func testAXFullyCaughtUpAppendsNothing() {
        let result = assembler.assemble(
            axTextBeforeCaret: "The meeting starts at",
            keystrokeBuffer: " starts at",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "The meeting starts at")
        XCTAssertTrue(result.usedAXContext)
    }

    func testAXLaggingByOneCharacterAppendsIt() {
        let result = assembler.assemble(
            axTextBeforeCaret: "hello worl",
            keystrokeBuffer: "hello world",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "hello world")
    }

    func testAXLaggingBySeveralCharacters() {
        let result = assembler.assemble(
            axTextBeforeCaret: "hello ",
            keystrokeBuffer: "hello world",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "hello world")
    }

    func testAXMissingTheBufferEntirelyAppendsAllOfIt() {
        // Clicked into existing prose, then typed: no overlap at all.
        let result = assembler.assemble(
            axTextBeforeCaret: "Dear Priya,\n\nThanks for ",
            keystrokeBuffer: "the quick",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "Dear Priya,\n\nThanks for the quick")
    }

    func testEmptyBufferUsesAXTextAlone() {
        let result = assembler.assemble(
            axTextBeforeCaret: "an existing paragraph",
            keystrokeBuffer: "",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "an existing paragraph")
        XCTAssertTrue(result.usedAXContext)
    }

    /// The regression risk: appending a tail that is already there duplicates text.
    func testNoDuplicationWhenBufferIsAlreadyPresent() {
        let result = assembler.assemble(
            axTextBeforeCaret: "I will send the report",
            keystrokeBuffer: "report",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "I will send the report")
    }

    // MARK: - Fallback when AX is unavailable

    func testNilAXFallsBackToBuffer() {
        let result = assembler.assemble(
            axTextBeforeCaret: nil,
            keystrokeBuffer: "typed so far",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "typed so far")
        XCTAssertFalse(result.usedAXContext)
    }

    func testEmptyAXFallsBackToBuffer() {
        let result = assembler.assemble(
            axTextBeforeCaret: "",
            keystrokeBuffer: "typed so far",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt, "typed so far")
        XCTAssertFalse(result.usedAXContext)
    }

    func testBothEmptyYieldsEmpty() {
        let result = assembler.assemble(axTextBeforeCaret: nil, keystrokeBuffer: "", bufferIsSuggestable: true)
        XCTAssertEqual(result.prompt, "")
    }

    /// A desynced buffer is no longer a reason to refuse when AX has the text.
    /// This is the fix for suggestions stopping after deleting past the origin.
    func testDesyncedBufferStillProducesAContextPrompt() {
        let result = assembler.assemble(
            axTextBeforeCaret: "the document already says this",
            keystrokeBuffer: "",
            bufferIsSuggestable: false
        )
        XCTAssertEqual(result.prompt, "the document already says this")
        XCTAssertTrue(result.usedAXContext)
    }

    // MARK: - Capping

    func testShortPromptIsNotCapped() {
        let assembler = ContextAssembler(maxPrefix: 100)
        let result = assembler.assemble(axTextBeforeCaret: "short", keystrokeBuffer: "", bufferIsSuggestable: true)
        XCTAssertEqual(result.prompt, "short")
    }

    func testLongPromptIsCappedFromTheFront() {
        let assembler = ContextAssembler(maxPrefix: 20)
        let text = String(repeating: "ab ", count: 50)  // 150 chars
        let result = assembler.assemble(axTextBeforeCaret: text, keystrokeBuffer: "", bufferIsSuggestable: true)
        XCTAssertLessThanOrEqual(result.prompt.count, 20)
        XCTAssertTrue(text.hasSuffix(result.prompt))
    }

    func testCappingPrefersAWordBoundary() {
        let assembler = ContextAssembler(maxPrefix: 12)
        // Last 12 chars would be "ghijk lmnop", severing a word; expect the cut
        // to move past the space.
        let result = assembler.assemble(
            axTextBeforeCaret: "abcdef ghijk lmnop",
            keystrokeBuffer: "",
            bufferIsSuggestable: true
        )
        XCTAssertFalse(result.prompt.hasPrefix("hijk"))
        XCTAssertTrue("abcdef ghijk lmnop".hasSuffix(result.prompt))
    }

    func testCapNeverDropsEverything() {
        let assembler = ContextAssembler(maxPrefix: 10)
        let result = assembler.assemble(
            axTextBeforeCaret: String(repeating: "x", count: 200),
            keystrokeBuffer: "",
            bufferIsSuggestable: true
        )
        XCTAssertEqual(result.prompt.count, 10)
    }
}

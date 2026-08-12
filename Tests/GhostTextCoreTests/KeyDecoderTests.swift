import XCTest

@testable import GhostTextCore

/// A deterministic stand-in for the real macOS keyboard layout, so these
/// tests never touch Carbon / TIS.
private struct FakeKeyboardLayout: KeyboardLayoutTranslating {
    /// Maps (keyCode, modifiers) -> character. Anything not in the table
    /// returns nil, simulating an unmapped key.
    var table: [KeyModPair: Character]

    struct KeyModPair: Hashable {
        let keyCode: UInt16
        let modifiers: ModifierSet
    }

    func character(keyCode: UInt16, modifiers: ModifierSet) -> Character? {
        table[KeyModPair(keyCode: keyCode, modifiers: modifiers)]
    }
}

final class KeyDecoderTests: XCTestCase {
    private let arbitraryLetterCode: UInt16 = 0  // 'a' on ANSI US layout

    private func makeDecoder(table: [FakeKeyboardLayout.KeyModPair: Character] = [:]) -> KeyDecoder {
        KeyDecoder(layout: FakeKeyboardLayout(table: table))
    }

    // MARK: - Fixed-function keys

    func testTab() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 48, modifiers: []), .tab)
    }

    func testEscape() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 53, modifiers: []), .escape)
    }

    func testReturnIsCommit() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 36, modifiers: []), .commit)
    }

    func testKeypadEnterIsCommit() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 76, modifiers: []), .commit)
    }

    func testBackspace() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 51, modifiers: []), .backspace)
    }

    func testForwardDeleteIsCaretMove() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 117, modifiers: []), .caretMove)
    }

    func testArrowAndNavigationKeysAreCaretMove() {
        let decoder = makeDecoder()
        let navCodes: [UInt16] = [123, 124, 125, 126, 115, 119, 116, 121]
        for code in navCodes {
            XCTAssertEqual(decoder.decode(keyCode: code, modifiers: []), .caretMove, "code \(code) should be caretMove")
        }
    }

    // MARK: - Modifier chords

    func testCommandChordForcesCaretMoveRegardlessOfKey() {
        let decoder = makeDecoder(table: [.init(keyCode: arbitraryLetterCode, modifiers: [.command]): "a"])
        XCTAssertEqual(decoder.decode(keyCode: arbitraryLetterCode, modifiers: [.command]), .caretMove)
    }

    func testControlChordForcesCaretMoveRegardlessOfKey() {
        let decoder = makeDecoder(table: [.init(keyCode: arbitraryLetterCode, modifiers: [.control]): "a"])
        XCTAssertEqual(decoder.decode(keyCode: arbitraryLetterCode, modifiers: [.control]), .caretMove)
    }

    func testCommandOverridesTabIntoCaretMove() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 48, modifiers: [.command]), .caretMove)
    }

    func testControlOverridesEscapeIntoCaretMove() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 53, modifiers: [.control]), .caretMove)
    }

    func testCommandOverridesBackspaceIntoCaretMove() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 51, modifiers: [.command]), .caretMove)
    }

    func testOptionModifierIsPassedToLayout() {
        let decoder = makeDecoder(table: [.init(keyCode: arbitraryLetterCode, modifiers: [.option]): "å"])
        XCTAssertEqual(decoder.decode(keyCode: arbitraryLetterCode, modifiers: [.option]), .text("å"))
    }

    func testShiftModifierIsPassedToLayout() {
        let decoder = makeDecoder(table: [.init(keyCode: arbitraryLetterCode, modifiers: [.shift]): "A"])
        XCTAssertEqual(decoder.decode(keyCode: arbitraryLetterCode, modifiers: [.shift]), .text("A"))
    }

    func testCommandAndOptionTogetherStillForcesCaretMove() {
        let decoder = makeDecoder(table: [.init(keyCode: arbitraryLetterCode, modifiers: [.command, .option]): "a"])
        XCTAssertEqual(decoder.decode(keyCode: arbitraryLetterCode, modifiers: [.command, .option]), .caretMove)
    }

    // MARK: - Plain text

    func testPlainLetterTranslatesToText() {
        let decoder = makeDecoder(table: [.init(keyCode: arbitraryLetterCode, modifiers: []): "a"])
        XCTAssertEqual(decoder.decode(keyCode: arbitraryLetterCode, modifiers: []), .text("a"))
    }

    func testTildeTranslatesToPlainText() {
        // KeyDecoder must NOT special-case '~' -- that belongs to AcceptPolicy.
        let decoder = makeDecoder(table: [.init(keyCode: 50, modifiers: [.shift]): "~"])
        XCTAssertEqual(decoder.decode(keyCode: 50, modifiers: [.shift]), .text("~"))
    }

    func testUnmappedKeyIsIgnored() {
        let decoder = makeDecoder()
        XCTAssertEqual(decoder.decode(keyCode: 999, modifiers: []), .ignored)
    }

    func testLayoutReturningNewlineIsIgnoredNotText() {
        let decoder = makeDecoder(table: [.init(keyCode: 999, modifiers: []): "\n"])
        XCTAssertEqual(decoder.decode(keyCode: 999, modifiers: []), .ignored)
    }

    // MARK: - ModifierSet

    func testModifierSetComposition() {
        let mods: ModifierSet = [.shift, .command]
        XCTAssertTrue(mods.contains(.shift))
        XCTAssertTrue(mods.contains(.command))
        XCTAssertFalse(mods.contains(.option))
    }

    func testModifierSetEmptyByDefault() {
        let mods: ModifierSet = []
        XCTAssertFalse(mods.contains(.capsLock))
        XCTAssertFalse(mods.contains(.fn))
    }
}

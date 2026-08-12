import Foundation

/// Builds the text the model actually sees.
///
/// Ghost Text buffers keystrokes rather than reading text fields, because AX text
/// reading breaks on Electron. That reasoning still holds — but it argues against
/// *depending* on AX, not against using it when it is there. Reading the document
/// around the caret as context, with the keystroke buffer as the fallback and as
/// the authority on the newest characters, keeps universal coverage while giving
/// the model something to work with when the user clicks into existing prose.
public struct ContextAssembler: Sendable {
    /// Enough to condition on, short enough to keep prefill cheap.
    public var maxPrefix: Int

    public struct Result: Sendable, Equatable {
        public let prompt: String
        public let usedAXContext: Bool

        public init(prompt: String, usedAXContext: Bool) {
            self.prompt = prompt
            self.usedAXContext = usedAXContext
        }
    }

    public init(maxPrefix: Int = 600) {
        self.maxPrefix = maxPrefix
    }

    public func assemble(
        axTextBeforeCaret: String?,
        keystrokeBuffer: String,
        bufferIsSuggestable: Bool
    ) -> Result {
        guard let axText = axTextBeforeCaret, !axText.isEmpty else {
            return Result(prompt: Self.cap(keystrokeBuffer, to: maxPrefix), usedAXContext: false)
        }

        let merged = Self.merge(axText: axText, buffer: keystrokeBuffer)
        return Result(prompt: Self.cap(merged, to: maxPrefix), usedAXContext: true)
    }

    /// Reconciles AX text that may lag the newest keystrokes.
    ///
    /// AX is sampled after a debounce, so the last character or two the user typed
    /// may not be reflected yet. Find the longest prefix of the buffer that the AX
    /// text already ends with, and append only what is missing. Getting this wrong
    /// in either direction is very visible: drop the character just typed and the
    /// model predicts from stale text, duplicate it and the completion is garbage.
    static func merge(axText: String, buffer: String) -> String {
        guard !buffer.isEmpty else { return axText }

        // Longest overlap first: if AX is fully caught up, k == buffer.count and
        // nothing is appended.
        var k = buffer.count
        while k > 0 {
            if axText.hasSuffix(String(buffer.prefix(k))) {
                return axText + String(buffer.dropFirst(k))
            }
            k -= 1
        }
        return axText + buffer
    }

    /// Trims from the front, preferring a word boundary so the model never opens
    /// on a severed word.
    static func cap(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }

        let tail = String(text.suffix(limit))
        // Only skip to a boundary if one is reasonably near the start; otherwise
        // a long unbroken run would throw most of the context away.
        let searchWindow = tail.prefix(limit / 4)
        if let space = searchWindow.firstIndex(where: { $0.isWhitespace }) {
            return String(tail[tail.index(after: space)...])
        }
        return tail
    }
}

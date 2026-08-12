import AppKit
import ApplicationServices

/// Samples the Accessibility tree for everything needed to place the overlay.
///
/// This gathers raw candidates only; deciding which one to trust is the job of
/// `CaretResolver`, which is pure and unit-tested. Keeping the two apart means the
/// fallback ladder can be tested without an app, a caret, or permissions.
///
/// See PROBE.md for what these attributes actually return in real apps.
@MainActor
final class CaretTracker {
    struct Candidates {
        /// Caret rect in AX coordinates (top-left origin).
        var axRangeBounds: CGRect?
        var focusedElementFrame: CGRect?
        var focusedWindowFrame: CGRect?
        var bundleID: String?
        /// The real font of the text at the caret, read from Accessibility.
        /// Guessing this is what made ghost text render like a superscript:
        /// wrong typeface and a size derived from caret height.
        var font: NSFont?
        var lineHeight: CGFloat?
    }

    private let systemWide = AX.systemWide()

    func sample() -> Candidates {
        var candidates = Candidates()

        let app = NSWorkspace.shared.frontmostApplication
        candidates.bundleID = app?.bundleIdentifier

        guard AXIsProcessTrusted() else { return candidates }
        guard let focused = AX.child(systemWide, kAXFocusedUIElementAttribute as String) else {
            candidates.focusedWindowFrame = windowFrame(for: app)
            return candidates
        }

        candidates.focusedElementFrame = AX.frame(focused)
        candidates.focusedWindowFrame = windowFrame(for: app)

        if let selected = AX.range(focused, kAXSelectedTextRangeAttribute as String) {
            // Anchor on the END of the selection, not the start. Notes reports a
            // whole-document selection (loc 0, len 8829) when it activates, and
            // using the start would park the overlay at the top of the document.
            let caretLocation = selected.location + selected.length

            var rect = AX.boundsForRange(focused, location: caretLocation, length: 0)
            if rect == nil || !AX.isPlausibleCaretRect(rect!) {
                // Some apps return an empty rect for a zero-length range but a
                // real one for the character just before the caret.
                rect = AX.boundsForRange(focused, location: max(0, caretLocation - 1), length: 1)
            }
            if let rect, AX.isPlausibleCaretRect(rect) {
                candidates.axRangeBounds = rect
                candidates.lineHeight = rect.height
                candidates.font = Self.font(for: focused, at: caretLocation)
                    ?? Self.derivedFont(caretHeight: rect.height)
            }
        }

        return candidates
    }

    /// The actual font at the caret, via `AXAttributedStringForRange` over the
    /// character just before it. TextEdit, Safari, Notes and Terminal all vend
    /// this (see PROBE.md); apps that do not fall back to a derived size.
    static func font(for element: AXUIElement, at location: Int) -> NSFont? {
        var range = CFRange(location: max(0, location - 1), length: 1)
        guard location > 0, let argument = AXValueCreate(.cfRange, &range) else { return nil }

        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, "AXAttributedStringForRange" as CFString, argument, &value
        )
        guard status == .success, let attributed = value as? NSAttributedString, attributed.length > 0 else {
            return nil
        }

        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        // Two shapes in the wild: a real NSFont, or AX's own dictionary form.
        if let font = attributes[.font] as? NSFont { return font }
        if let descriptor = attributes[NSAttributedString.Key("AXFont")] as? [String: Any] {
            let size = (descriptor["AXFontSize"] as? CGFloat) ?? 13
            if let name = descriptor["AXFontName"] as? String, let font = NSFont(name: name, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size)
        }
        return nil
    }

    /// Last resort. A caret rect spans the full line box, so back out a plausible
    /// point size from it rather than using it directly.
    static func derivedFont(caretHeight: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: min(48, max(9, (caretHeight / 1.18).rounded())))
    }

    private func windowFrame(for app: NSRunningApplication?) -> CGRect? {
        guard let pid = app?.processIdentifier else { return nil }
        let appElement = AX.application(pid: pid)
        guard let window = AX.child(appElement, kAXFocusedWindowAttribute as String) else { return nil }
        return AX.frame(window)
    }
}

enum ScreenGeometry {
    /// AX reports a top-left origin measured from the primary screen; AppKit wants
    /// bottom-left. Everything crossing that boundary has to be flipped.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static var screenFrames: [CGRect] {
        NSScreen.screens.map(\.frame)
    }
}

/// Reads the document text around the caret, to give the model something to
/// condition on beyond what the user has typed since focus.
///
/// Falls back cleanly to nothing when unavailable (Electron), where the
/// keystroke buffer remains the only source. See PROBE.md for coverage.
@MainActor
final class ContextProvider {
    struct Context {
        var textBeforeCaret: String?
        var textAfterCaret: String?
        var caretLocation: Int?
        var available: Bool { textBeforeCaret != nil }
    }

    static let lookBehind = 600
    static let lookAhead = 200

    private let systemWide = AX.systemWide()

    func read() -> Context {
        var context = Context()
        guard AXIsProcessTrusted() else { return context }
        guard let focused = AX.child(systemWide, kAXFocusedUIElementAttribute as String) else { return context }
        guard let selected = AX.range(focused, kAXSelectedTextRangeAttribute as String) else { return context }

        let caret = selected.location + selected.length
        context.caretLocation = caret

        let start = max(0, caret - Self.lookBehind)
        if let before = AX.stringForRange(focused, location: start, length: caret - start) {
            context.textBeforeCaret = before
        } else if let whole = AX.string(focused, kAXValueAttribute as String) {
            // Some apps expose AXValue but not AXStringForRange.
            let characters = Array(whole)
            if caret <= characters.count {
                context.textBeforeCaret = String(characters[max(0, caret - Self.lookBehind)..<caret])
            }
        }

        if let total = AX.integer(focused, kAXNumberOfCharactersAttribute as String), total > caret {
            let length = min(Self.lookAhead, total - caret)
            context.textAfterCaret = AX.stringForRange(focused, location: caret, length: length)
        }

        return context
    }
}

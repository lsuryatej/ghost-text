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
        /// Derived from caret height — no app reliably exposes its font size, and
        /// the overlay needs a close match or the ghost text sits off the baseline.
        var fontSize: CGFloat?
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
                candidates.fontSize = min(48, max(9, rect.height * 0.72))
            }
        }

        return candidates
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

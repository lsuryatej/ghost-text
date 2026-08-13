import AppKit

/// Draws the ghost text itself. A plain custom `NSView` rather than
/// `NSTextField`, for direct control over the natural (unpadded) text size
/// that `GhostOverlayPanel` uses to size and position the panel.
final class GhostTextView: NSView {

    /// Flipped so `bounds` reads top-down, matching how the backdrop and text
    /// rects are reasoned about elsewhere in this file.
    override var isFlipped: Bool { true }

    /// On by default — see `backdropColor`/`textColor` below for why a bare,
    /// unbacked ghost text color can't be trusted to stay legible.
    var showsBackdrop = true

    /// Fixed rather than semantic (`NSColor.tertiaryLabelColor` and
    /// `.textBackgroundColor` were the previous choice). A semantic color
    /// resolves against *this app's* effective appearance — which tracks
    /// system-wide dark/light mode — not the actual background of whatever
    /// field the overlay is floating over. System in Dark Mode + a plain
    /// white Safari field produced light-gray-on-white: legible in
    /// isolation, invisible in practice, and it looked like an entirely
    /// different bug (mispositioning) until logs showed the geometry and
    /// visibility were both already correct. A fixed dark chip with fixed
    /// light text is self-contrasting regardless of what's underneath.
    static let backdropColor = NSColor(white: 0.08, alpha: 0.82)
    static let textColor = NSColor(white: 0.92, alpha: 1.0)

    private var attributedString = NSAttributedString()

    func configure(text: String, font: NSFont) {
        attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: Self.textColor,
            ]
        )
        needsDisplay = true
    }

    /// The string's own bounding size, ignoring `GhostOverlayPanel.padding`.
    /// Rounded up so hairline fractional glyph metrics never clip.
    var naturalTextSize: CGSize {
        let size = attributedString.size()
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)

        if showsBackdrop {
            let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
            Self.backdropColor.setFill()
            path.fill()
        }

        let textRect = bounds.insetBy(
            dx: GhostOverlayPanel.padding.width,
            dy: GhostOverlayPanel.padding.height
        )
        attributedString.draw(in: textRect)
    }
}

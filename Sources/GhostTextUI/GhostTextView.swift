import AppKit

/// Draws the ghost text itself. A plain custom `NSView` rather than
/// `NSTextField`, for direct control over the natural (unpadded) text size
/// that `GhostOverlayPanel` uses to size and position the panel.
final class GhostTextView: NSView {

    /// Flipped so `bounds` reads top-down, matching how the backdrop and text
    /// rects are reasoned about elsewhere in this file.
    override var isFlipped: Bool { true }

    var showsBackdrop = false

    private var attributedString = NSAttributedString()

    func configure(text: String, font: NSFont) {
        attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
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
            NSColor.textBackgroundColor.withAlphaComponent(0.72).setFill()
            path.fill()
        }

        let textRect = bounds.insetBy(
            dx: GhostOverlayPanel.padding.width,
            dy: GhostOverlayPanel.padding.height
        )
        attributedString.draw(in: textRect)
    }
}

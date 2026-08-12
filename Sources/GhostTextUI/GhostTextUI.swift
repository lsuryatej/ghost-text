import AppKit

/// A click-through, non-activating overlay panel that renders grey "ghost text"
/// near the caret. Never steals focus, never intercepts a click, never shows up
/// in the window list or the Cmd-` window cycle.
///
/// This type intentionally has no dependency on `GhostTextCore` — it is driven
/// entirely by the primitive values passed into `present`/`update`, so it can
/// be developed and eyeballed (via `ghost-panel-demo`) independent of the
/// event tap, AX geometry, or model work happening elsewhere.
///
/// All state is confined to the main actor, matching every other AppKit-backed
/// piece of Ghost Text.
@MainActor
public final class GhostOverlayPanel {

    // MARK: Init

    public init() {
        let panel = InertPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false

        let view = GhostTextView(frame: .zero)
        panel.contentView = view

        self.panel = panel
        self.view = view
    }

    // MARK: Public API

    /// Draws a subtle rounded translucent backing behind the text so it stays
    /// legible over busy backgrounds. Off by default: plain ghost text over
    /// whatever is underneath.
    public var showsBackdrop: Bool = false {
        didSet {
            guard showsBackdrop != oldValue else { return }
            view.showsBackdrop = showsBackdrop
            view.needsDisplay = true
        }
    }

    public private(set) var isPresented: Bool = false

    /// The panel's current screen frame (AppKit screen coordinates), after
    /// clamping. Exposed so callers/harnesses can log or reason about
    /// placement without reaching into AppKit themselves.
    public var panelFrame: CGRect { panel.frame }

    /// The frame of the screen the overlay was last resolved against.
    public private(set) var resolvedScreenFrame: CGRect?

    /// Shows ghost text so its natural (unpadded) bounding box sits with its
    /// bottom-left at `origin`, which reads as a continuation of the caret's
    /// text line because the rendered baseline falls exactly `descender`
    /// above that point.
    ///
    /// - Parameters:
    ///   - origin: AppKit screen coordinates for the bottom-left of the
    ///     caret's text line.
    ///   - lineHeight: The caret line's height. Not used in the baseline math
    ///     directly (the panel's own font metrics at `fontSize` drive that),
    ///     but kept on the anchor so callers/harnesses can reason about or
    ///     log the surrounding line band.
    ///   - fontSize: Size for the ghost text's system font. Pass the caret
    ///     line's actual font size so the baseline alignment reads true.
    public func present(text: String, at origin: CGPoint, lineHeight: CGFloat, font: NSFont) {
        anchorOrigin = origin
        anchorLineHeight = lineHeight
        anchorFont = font
        view.configure(text: text, font: font)
        relayout()
        if !isPresented {
            panel.orderFrontRegardless()
            isPresented = true
        }
    }

    /// Updates the visible text in place: resizes around the same anchor
    /// point with no flicker and, critically, no re-ordering in the window
    /// server's z-order (no `orderFrontRegardless` call here).
    public func update(text: String) {
        guard isPresented, let font = anchorFont else { return }
        view.configure(text: text, font: font)
        relayout()
    }

    public func dismiss() {
        guard isPresented else { return }
        panel.orderOut(nil)
        isPresented = false
    }

    // MARK: Layout

    /// Padding around the natural text bounding box. Present even with the
    /// backdrop off, so glyph edges (italics, overshoot) never clip against
    /// the panel bounds.
    /// No horizontal padding: ghost text must begin exactly at the caret, not
    /// a few points to its right. Vertical padding only guards glyph overshoot
    /// and is compensated for in the baseline maths below.
    static let padding = CGSize(width: 0, height: 1)

    private func relayout() {
        guard let origin = anchorOrigin else { return }
        let textSize = view.naturalTextSize
        var frame = CGRect(
            x: origin.x - Self.padding.width,
            y: origin.y - Self.padding.height,
            width: textSize.width + Self.padding.width * 2,
            height: textSize.height + Self.padding.height * 2
        )

        let screen = Self.screen(containing: origin)
        resolvedScreenFrame = screen?.frame
        if let bounds = screen?.frame {
            frame = Self.clamp(frame, to: bounds)
        }

        panel.setFrame(frame, display: true)
    }

    /// The screen containing `point`, falling back to the nearest screen by
    /// edge distance if `point` isn't inside any screen's frame (e.g. a
    /// slightly stale caret position right at a display boundary).
    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            distanceSquared(point, lhs.frame) < distanceSquared(point, rhs.frame)
        }
    }

    private static func distanceSquared(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Clamps `rect` to fully fit inside `bounds`, preferring to shift the
    /// origin over shrinking the size. Guarantees the result never renders
    /// partially outside the given bounds.
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        if result.maxX > bounds.maxX { result.origin.x = bounds.maxX - result.width }
        if result.minX < bounds.minX { result.origin.x = bounds.minX }
        if result.maxY > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        if result.minY < bounds.minY { result.origin.y = bounds.minY }
        return result
    }

    // MARK: State

    private let panel: InertPanel
    private let view: GhostTextView
    private var anchorOrigin: CGPoint?
    private var anchorLineHeight: CGFloat?
    private var anchorFont: NSFont?
}

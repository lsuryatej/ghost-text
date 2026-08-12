import CoreGraphics
import Foundation

/// Where the ghost-text overlay should be drawn, and how we found out.
///
/// All rects handled by `CaretResolver` (including this type's `origin` and
/// the `screens` passed into `resolve`) are expected to already live in a
/// single consistent coordinate space -- AppKit's screen space (origin at
/// the bottom-left of the primary display, y increasing upward). AX
/// reports its own rects top-left-origin/y-down; callers convert with
/// `AXCoordinates.flipToAppKit` before handing them to `resolve`, which
/// keeps this type free of AppKit and free of any specific screen height.
public struct CaretPlacement: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case axRange
        case axElement
        case window
        case lastKnownGood
    }

    /// Screen coords, bottom-left of the caret's text line.
    public let origin: CGPoint
    public let lineHeight: CGFloat
    public let source: Source

    public init(origin: CGPoint, lineHeight: CGFloat, source: Source) {
        self.origin = origin
        self.lineHeight = lineHeight
        self.source = source
    }
}

/// A cached placement, kept around so a momentary AX hiccup (rung 1-3 all
/// failing for one keystroke) doesn't flicker the overlay away and back.
public struct LastKnownGood: Sendable, Equatable {
    public let placement: CaretPlacement
    public let timestamp: TimeInterval
    public let bundleID: String?

    public init(placement: CaretPlacement, timestamp: TimeInterval, bundleID: String?) {
        self.placement = placement
        self.timestamp = timestamp
        self.bundleID = bundleID
    }
}

/// Converts AX's top-left-origin, y-down rects into AppKit's bottom-left-
/// origin, y-up screen space.
public enum AXCoordinates {
    public static func flipToAppKit(rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

/// The caret-position fallback ladder described in DESIGN.md: "a decision
/// function over `(axBounds?, elementFrame?, windowFrame?, lastKnownGood?,
/// age)`... fully tested without ever touching AX." AX is a soft dependency
/// for overlay geometry only -- being a few pixels off is cosmetic, so this
/// always prefers the most precise source that looks sane over a stale but
/// precise one, and only gives up (`nil`) when nothing usable is left.
public struct CaretResolver: Sendable {
    public var staleAfter: TimeInterval

    /// A single-line text caret is never taller than this in practice;
    /// above it, the rect is almost certainly a multi-line selection or
    /// garbage, not a caret bound.
    private static let axRangeMaxHeight: CGFloat = 200
    private static let axRangeMinHeight: CGFloat = 4

    /// An element frame can legitimately be a whole (short) text view;
    /// above this it's more likely a full-window-sized frame that slipped
    /// through as "the focused element."
    private static let elementFrameMaxHeight: CGFloat = 2000

    /// Inset applied to a window frame fallback so the overlay doesn't get
    /// drawn flush against the window's edge (title bar / resize handle).
    private static let windowInset: CGFloat = 12

    /// Used for rungs 2 and 3, where we know *where* to anchor the overlay
    /// but have no precise line-height signal to draw from.
    private static let fallbackLineHeight: CGFloat = 18

    public init(staleAfter: TimeInterval = 5) {
        self.staleAfter = staleAfter
    }

    public func resolve(
        axRangeBounds: CGRect?,
        focusedElementFrame: CGRect?,
        focusedWindowFrame: CGRect?,
        lastKnownGood: LastKnownGood?,
        currentBundleID: String?,
        now: TimeInterval,
        screens: [CGRect]
    ) -> CaretPlacement? {
        if let rect = axRangeBounds,
            Self.isSane(rect, minHeight: Self.axRangeMinHeight, maxHeight: Self.axRangeMaxHeight, screens: screens)
        {
            return CaretPlacement(
                origin: CGPoint(x: rect.minX, y: rect.minY),
                lineHeight: rect.height,
                source: .axRange
            )
        }

        if let rect = focusedElementFrame,
            rect.width > 0, rect.height > 0, rect.height < Self.elementFrameMaxHeight,
            screens.contains(where: { $0.intersects(rect) })
        {
            return CaretPlacement(
                origin: CGPoint(x: rect.minX, y: rect.minY),
                lineHeight: Self.fallbackLineHeight,
                source: .axElement
            )
        }

        if let rect = focusedWindowFrame, rect.width > 0, rect.height > 0,
            screens.contains(where: { $0.intersects(rect) })
        {
            let inset = rect.insetBy(dx: Self.windowInset, dy: Self.windowInset)
            let usable = (inset.width > 0 && inset.height > 0) ? inset : rect
            return CaretPlacement(
                origin: CGPoint(x: usable.minX, y: usable.minY),
                lineHeight: Self.fallbackLineHeight,
                source: .window
            )
        }

        if let lastKnownGood,
            lastKnownGood.bundleID == currentBundleID,
            now - lastKnownGood.timestamp < staleAfter
        {
            return lastKnownGood.placement
        }

        return nil
    }

    /// Non-zero size, height within `[minHeight, maxHeight]`, and
    /// intersects at least one known screen.
    private static func isSane(_ rect: CGRect, minHeight: CGFloat, maxHeight: CGFloat, screens: [CGRect]) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        guard rect.height >= minHeight, rect.height <= maxHeight else { return false }
        return screens.contains { $0.intersects(rect) }
    }
}

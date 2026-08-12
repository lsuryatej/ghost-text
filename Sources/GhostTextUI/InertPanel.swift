import AppKit

/// The concrete `NSPanel` subclass backing `GhostOverlayPanel`. Every override
/// here exists to make the panel behaviourally inert: it must never become
/// key or main, so it can never steal focus from whatever the user is typing
/// into underneath it.
///
/// Kept internal — `GhostOverlayPanel` is the only public surface, so all the
/// "never steals focus" configuration lives behind one API rather than being
/// something a consumer could accidentally misconfigure.
final class InertPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

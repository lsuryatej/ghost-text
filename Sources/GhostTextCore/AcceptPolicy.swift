import Foundation

/// Decides what a keydown means for the currently-showing suggestion (or
/// lack of one). This is the component that makes `Tab` and `~` safe to
/// hijack: see DESIGN.md, "Accept keys" -- both keys collide with
/// pre-existing meanings (tab-to-next-field / indent, and `~/` paths), and
/// the single rule that resolves both collisions is "visible-only gating":
/// a key is swallowed only while ghost text is actually on screen.
public struct AcceptPolicy: Sendable {
    /// Empty by design. DESIGN.md: the visible-only gating rule makes the
    /// collision window narrow enough that a denylist isn't needed; this
    /// set exists purely as a one-line escape valve if a specific app is
    /// later found to need one.
    public var deniedBundleIDs: Set<String>

    public enum Decision: Sendable, Equatable {
        case passThrough
        case swallowAcceptWord
        case swallowAcceptPhrase
        case swallowDismiss
    }

    public init(deniedBundleIDs: Set<String> = []) {
        self.deniedBundleIDs = deniedBundleIDs
    }

    public func decide(key: DecodedKey, suggestionVisible: Bool, bundleID: String?) -> Decision {
        // No suggestion on screen means Tab, ~, and Escape all mean exactly
        // what every other app already thinks they mean. This is the rule
        // that lets tab-to-next-field, indentation, `~/` paths, and a bare
        // Escape survive untouched.
        guard suggestionVisible else { return .passThrough }

        if let bundleID, deniedBundleIDs.contains(bundleID) {
            return .passThrough
        }

        switch key {
        case .tab:
            return .swallowAcceptWord
        case .text("~"):
            return .swallowAcceptPhrase
        case .escape:
            return .swallowDismiss
        default:
            return .passThrough
        }
    }
}

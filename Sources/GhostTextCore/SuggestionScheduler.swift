import Foundation

/// Deterministic debounce for suggestion requests. Deliberately has no
/// notion of a real clock -- the caller supplies `now` on every call -- so
/// it can be driven from `Task.sleep`, a `DispatchSourceTimer`, or a unit
/// test's fake timeline with identical logic. This is what lets the "type,
/// pause, get a suggestion" behavior be tested in microseconds instead of
/// real quiet-period waits.
public struct SuggestionScheduler: Sendable {
    public var quietPeriod: TimeInterval

    /// Instructions for the caller, which owns the actual timer / task.
    /// `SuggestionScheduler` never schedules anything itself -- it only
    /// decides what should happen and lets the caller do the scheduling.
    public enum Command: Sendable, Equatable {
        case cancelInFlight
        case scheduleFire(at: TimeInterval)
        case cancelAll
    }

    /// The target time of the most recently scheduled fire, if one is still
    /// outstanding. `fireDue` compares its `now` against this to tell a
    /// current callback from a stale one whose timer the caller failed (or
    /// raced) to actually cancel -- this struct treats real cancellation as
    /// best-effort and enforces correctness itself regardless.
    private var pendingFireTime: TimeInterval?

    /// Tolerance for matching a `fireDue(at:)` call against `pendingFireTime`.
    /// Guards against floating-point drift when a caller reconstructs `now`
    /// from `now + quietPeriod` arithmetic that doesn't round-trip exactly.
    private static let epsilon: TimeInterval = 1e-6

    public init(quietPeriod: TimeInterval = 0.25) {
        self.quietPeriod = quietPeriod
    }

    /// Call whenever a keystroke (or anything else that should reset the
    /// debounce window) occurs. Always cancels whatever was pending and
    /// schedules a new fire `quietPeriod` after `now`.
    public mutating func typingOccurred(at now: TimeInterval) -> [Command] {
        let target = now + quietPeriod
        pendingFireTime = target
        return [.cancelInFlight, .scheduleFire(at: target)]
    }

    /// Call when a previously scheduled fire's timer actually elapses.
    /// Returns `true` if this fire is still the most recently scheduled one
    /// (i.e. should actually trigger a suggestion request); `false` if it
    /// was superseded by a later `typingOccurred` call and should be
    /// ignored by the caller.
    public mutating func fireDue(at now: TimeInterval) -> Bool {
        guard let target = pendingFireTime, abs(now - target) < Self.epsilon else {
            return false
        }
        pendingFireTime = nil
        return true
    }

    /// Call when the suggestion currently on screen is dismissed (accepted,
    /// escaped, or invalidated by a buffer-clearing event). Cancels any
    /// pending scheduled fire so a stale debounce doesn't pop a suggestion
    /// back up after the user has moved on.
    public mutating func suggestionDismissed() -> [Command] {
        pendingFireTime = nil
        return [.cancelAll]
    }
}

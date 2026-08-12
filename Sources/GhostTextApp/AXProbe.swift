import AppKit
import ApplicationServices

/// Passive Accessibility capability probe.
///
/// Phase 2 hinges on one question: can we get usable caret bounds out of AX in
/// enough real apps to make AX-first positioning the primary design, or does the
/// fallback ladder need to be primary instead?
///
/// Rather than driving apps automatically — which would mean creating notes,
/// drafts and files in someone's real data — this watches passively. Type in your
/// apps normally for a couple of minutes and the log fills up on its own.
///
/// Results land in ~/Library/Logs/GhostText/ax-probe.log
@MainActor
final class AXProbe {
    struct Observation {
        var attempts = 0
        var usableCaretBounds = 0
        var hasSelectedRange = false
        var hasBoundsForRange = false
        var roles: Set<String> = []
    }

    private let systemWide = AX.systemWide()
    private var timer: Timer?
    private var lastSignature = ""
    private var warnedAboutTrust = false
    private(set) var observations: [String: Observation] = [:]

    func start() {
        FileLog.probe.banner("probe started \(Date())")
        FileLog.probe("watching for focus changes; type in your apps normally")

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { AXProbeHolder.shared?.sample(force: true) }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { AXProbeHolder.shared?.sample(force: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sample(force: Bool) {
        guard AXIsProcessTrusted() else {
            if !warnedAboutTrust {
                warnedAboutTrust = true
                FileLog.probe("NOT TRUSTED — grant Accessibility to Ghost Text in System Settings")
            }
            return
        }
        warnedAboutTrust = false

        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? "unknown"
        let appName = app?.localizedName ?? "unknown"

        guard let focused = AX.child(systemWide, kAXFocusedUIElementAttribute as String) else {
            record(bundleID: bundleID, usable: false, role: "none", selected: false, bounds: false)
            return
        }

        let role = AX.string(focused, kAXRoleAttribute as String) ?? "?"
        let subrole = AX.string(focused, kAXSubroleAttribute as String) ?? "-"
        let elementFrame = AX.frame(focused)

        // Dedupe: only write a full dump when something actually changed.
        let signature = "\(bundleID)|\(role)|\(subrole)|\(elementFrame?.debugDescription ?? "-")"
        let changed = signature != lastSignature
        guard force || changed else { return }
        lastSignature = signature

        let attributes = AX.attributeNames(focused)
        let parameterized = AX.parameterizedAttributeNames(focused)
        let selectedRange = AX.range(focused, kAXSelectedTextRangeAttribute as String)

        // Try the caret itself, then a one-character range — some apps return an
        // empty rect for a zero-length range but a real one for length 1.
        var caretRect: CGRect?
        if let selectedRange {
            caretRect = AX.boundsForRange(focused, location: selectedRange.location, length: 0)
            if caretRect == nil || !AX.isPlausibleCaretRect(caretRect!) {
                caretRect = AX.boundsForRange(focused, location: max(0, selectedRange.location - 1), length: 1)
            }
        }
        let usable = caretRect.map(AX.isPlausibleCaretRect) ?? false

        var window: CGRect?
        if let pid = app?.processIdentifier {
            let appElement = AX.application(pid: pid)
            if let focusedWindow = AX.child(appElement, kAXFocusedWindowAttribute as String) {
                window = AX.frame(focusedWindow)
            }
        }

        FileLog.probe.banner("\(appName) [\(bundleID)]")
        FileLog.probe("  role=\(role) subrole=\(subrole)")
        FileLog.probe("  elementFrame=\(describe(elementFrame))")
        FileLog.probe("  windowFrame=\(describe(window))")
        FileLog.probe("  selectedTextRange=\(selectedRange.map { "loc \($0.location) len \($0.length)" } ?? "UNAVAILABLE")")
        FileLog.probe("  boundsForRange=\(describe(caretRect)) usable=\(usable)")
        FileLog.probe("  hasAXBoundsForRange=\(parameterized.contains(kAXBoundsForRangeParameterizedAttribute as String))")
        FileLog.probe("  attributes=\(attributes.sorted().joined(separator: ","))")
        FileLog.probe("  parameterized=\(parameterized.sorted().joined(separator: ","))")

        record(
            bundleID: bundleID,
            usable: usable,
            role: role,
            selected: selectedRange != nil,
            bounds: parameterized.contains(kAXBoundsForRangeParameterizedAttribute as String)
        )
    }

    /// The actual Phase 2 gate: usable caret bounds in at least 3 of the target
    /// apps means AX-first positioning is viable. Below that, the fallback ladder
    /// has to become the primary design and the build order changes.
    func summary() -> String {
        var lines = ["", "=== PROBE SUMMARY ===", "app                                      samples  usable  role(s)"]
        var appsWithUsableBounds = 0

        for (bundleID, observation) in observations.sorted(by: { $0.key < $1.key }) {
            if observation.usableCaretBounds > 0 { appsWithUsableBounds += 1 }
            let name = bundleID.padding(toLength: 40, withPad: " ", startingAt: 0)
            let attempts = String(observation.attempts).padding(toLength: 8, withPad: " ", startingAt: 0)
            let usable = String(observation.usableCaretBounds).padding(toLength: 7, withPad: " ", startingAt: 0)
            lines.append("\(name) \(attempts) \(usable) \(observation.roles.sorted().joined(separator: ","))")
        }

        lines.append("")
        lines.append("apps with usable caret bounds: \(appsWithUsableBounds) of \(observations.count) seen")
        lines.append(appsWithUsableBounds >= 3
            ? "VERDICT: AX-first geometry is viable. Proceed with AX bounds, ladder as fallback."
            : "VERDICT: not enough AX coverage. Build the window-bounding-box fallback as primary.")
        return lines.joined(separator: "\n")
    }

    private func record(bundleID: String, usable: Bool, role: String, selected: Bool, bounds: Bool) {
        var observation = observations[bundleID] ?? Observation()
        observation.attempts += 1
        if usable { observation.usableCaretBounds += 1 }
        observation.hasSelectedRange = observation.hasSelectedRange || selected
        observation.hasBoundsForRange = observation.hasBoundsForRange || bounds
        observation.roles.insert(role)
        observations[bundleID] = observation
    }

    private func describe(_ rect: CGRect?) -> String {
        guard let rect else { return "UNAVAILABLE" }
        return String(format: "(%.0f,%.0f %.0fx%.0f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}

/// The Timer and notification closures need a stable reference that does not
/// capture `self` before it is fully initialised.
@MainActor
enum AXProbeHolder {
    static var shared: AXProbe?
}

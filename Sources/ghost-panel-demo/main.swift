import AppKit
import GhostTextUI

// Draws the ghost overlay at hardcoded coordinates so panel work can be
// eyeballed with no event tap, no Accessibility permission, and no model.
//
// `--once` runs a single pass through every case and exits; the default
// loops the cases forever on a ~2 second timer.

/// One step in the demo cycle. `isUpdateOnly` cases call `update(text:)` on
/// the already-visible panel (instead of `present`) so flicker/re-order
/// behaviour on an in-place resize can be checked from the log alone.
private struct DemoCase {
    let label: String
    let text: String
    let origin: CGPoint
    let lineHeight: CGFloat
    let fontSize: CGFloat
    let isUpdateOnly: Bool
}

@MainActor
private final class DemoRunner {
    private let panel = GhostOverlayPanel()
    private var cases: [DemoCase] = []
    private var index = 0
    private var once = false
    private var timer: Timer?

    func start(once: Bool) {
        self.once = once
        cases = Self.buildCases()

        guard !cases.isEmpty else {
            print("ghost-panel-demo: no NSScreen available, nothing to show")
            NSApp.terminate(nil)
            return
        }

        runNext()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runNext()
            }
        }
    }

    private func runNext() {
        if index >= cases.count {
            if once {
                print("ghost-panel-demo: cycle complete")
                timer?.invalidate()
                NSApp.terminate(nil)
                return
            }
            index = 0
        }

        let c = cases[index]
        if c.isUpdateOnly {
            panel.update(text: c.text)
        } else {
            panel.present(text: c.text, at: c.origin, lineHeight: c.lineHeight, font: NSFont.systemFont(ofSize: c.fontSize))
        }

        let screenFrame = panel.resolvedScreenFrame.map(Self.describe) ?? "none"
        print("""
            [\(index)] \(c.label)
                text=\"\(c.text)\"
                origin=\(Self.describe(c.origin)) lineHeight=\(c.lineHeight) fontSize=\(c.fontSize) update=\(c.isUpdateOnly)
                resolvedScreenFrame=\(screenFrame)
                panelFrame=\(Self.describe(panel.panelFrame))
            """)

        index += 1
    }

    private static func describe(_ point: CGPoint) -> String {
        String(format: "(%.1f, %.1f)", point.x, point.y)
    }

    private static func describe(_ rect: CGRect) -> String {
        String(format: "(x: %.1f, y: %.1f, w: %.1f, h: %.1f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    /// Cases are built against `NSScreen.main`'s frame so the "near the right
    /// edge" / "near the bottom edge" cases are guaranteed to actually
    /// overflow (and therefore actually exercise clamping) regardless of the
    /// display this runs on.
    private static func buildCases() -> [DemoCase] {
        guard let screen = NSScreen.main else { return [] }
        let f = screen.frame

        return [
            DemoCase(
                label: "short single word",
                text: "hello",
                origin: CGPoint(x: f.midX - 220, y: f.midY + 160),
                lineHeight: 18, fontSize: 14, isUpdateOnly: false
            ),
            DemoCase(
                label: "long multi-word phrase",
                text: "the quick brown fox jumps over the lazy dog",
                origin: CGPoint(x: f.midX - 220, y: f.midY + 100),
                lineHeight: 18, fontSize: 14, isUpdateOnly: false
            ),
            DemoCase(
                label: "near RIGHT screen edge (must clamp left)",
                text: "this ghost text starts close enough to the right edge that it must clamp",
                origin: CGPoint(x: f.maxX - 60, y: f.midY + 40),
                lineHeight: 18, fontSize: 14, isUpdateOnly: false
            ),
            DemoCase(
                label: "near BOTTOM screen edge (must clamp up)",
                text: "clamped near the bottom edge",
                origin: CGPoint(x: f.minX + 120, y: f.minY),
                lineHeight: 18, fontSize: 14, isUpdateOnly: false
            ),
            DemoCase(
                label: "present before in-place update",
                text: "typing",
                origin: CGPoint(x: f.midX - 220, y: f.midY - 60),
                lineHeight: 18, fontSize: 14, isUpdateOnly: false
            ),
            DemoCase(
                label: "update(text:) in place — same anchor, longer text, no flicker/re-order",
                text: "typing a considerably longer completion to check in-place resize",
                origin: CGPoint(x: f.midX - 220, y: f.midY - 60),
                lineHeight: 18, fontSize: 14, isUpdateOnly: true
            ),
        ]
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runner = DemoRunner()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let once = CommandLine.arguments.contains("--once")
        runner.start(once: once)
    }
}

private let app = NSApplication.shared
app.setActivationPolicy(.accessory)
private let delegate = AppDelegate()
app.delegate = delegate
app.run()

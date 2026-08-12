import AppKit
import GhostTextUI
import os

/// Ties the tap, the caret geometry, and the overlay together.
///
/// Scaffolding note: the buffer, key decoding, debounce and accept policy are all
/// stubbed inline here for now, and get replaced by the tested `GhostTextCore`
/// implementations once that lands. The completion text is canned — this exists to
/// prove the tap, the AX geometry and the panel work together before a model is in
/// the picture.
@MainActor
final class GhostTextController {
    private let tap = EventTapController()
    private let caret = CaretTracker()
    private let panel = GhostOverlayPanel()

    /// Read from the tap thread, written from main. The tap's decision has to be
    /// synchronous and cheap, so it reads this snapshot rather than asking the UI.
    private let suggestionVisible = OSAllocatedUnfairLock(initialState: false)

    private var pendingSuggestion: DispatchWorkItem?
    private var quietPeriod: TimeInterval = 0.25

    private(set) var isEnabled = false

    // Virtual key codes. Replaced by GhostTextCore.KeyDecoder once merged.
    private enum Key {
        static let tab: UInt16 = 48
        static let escape: UInt16 = 53
        static let grave: UInt16 = 50  // `~` is shift+grave
        static let returnKey: UInt16 = 36
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            tap.setDecider { [suggestionVisible] keyCode, flags in
                // The rule that makes Tab safe: only ever swallow a key while a
                // suggestion is actually on screen. With nothing showing, Tab and
                // `~` reach the app untouched and behave exactly as normal.
                guard suggestionVisible.withLock({ $0 }) else { return .pass }

                switch keyCode {
                case Key.tab, Key.escape:
                    return .swallow
                case Key.grave where flags.contains(.maskShift):
                    return .swallow
                default:
                    return .pass
                }
            }

            tap.setObserver { [weak self] keyCode, flags, swallowed in
                self?.handle(keyCode: keyCode, flags: flags, swallowed: swallowed)
            }

            if tap.start() {
                FileLog.app("enabled")
            } else {
                isEnabled = false
                FileLog.app("enable FAILED — could not create event tap")
            }
        } else {
            // Toggling off is a privacy guarantee, not a UI state: the tap is torn
            // down so keystrokes stop being observed at all.
            tap.stop()
            dismissSuggestion()
            FileLog.app("disabled — tap torn down")
        }
    }

    // MARK: - Key handling

    private func handle(keyCode: UInt16, flags: CGEventFlags, swallowed: Bool) {
        if swallowed {
            switch keyCode {
            case Key.tab:
                accept(scope: .word)
            case Key.grave:
                accept(scope: .phrase)
            case Key.escape:
                dismissSuggestion()
            default:
                break
            }
            return
        }

        // Any committing or caret-moving key invalidates what we think was typed.
        if keyCode == Key.returnKey || keyCode == Key.escape {
            dismissSuggestion()
            return
        }

        scheduleSuggestion()
    }

    private enum AcceptScope { case word, phrase }

    private func accept(scope: AcceptScope) {
        let completion = Self.cannedCompletion
        let text = scope == .word
            ? String(completion.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            : completion

        FileLog.app("accept \(scope) -> \(text.debugDescription)")
        dismissSuggestion()
        KeystrokeSynthesizer.type(text)
    }

    // MARK: - Suggestion lifecycle

    private func scheduleSuggestion() {
        pendingSuggestion?.cancel()

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.presentSuggestion() }
        }
        pendingSuggestion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + quietPeriod, execute: work)
    }

    private func presentSuggestion() {
        let candidates = caret.sample()

        guard let axRect = candidates.axRangeBounds else {
            FileLog.app("caret UNAVAILABLE for \(candidates.bundleID ?? "?") — hiding overlay")
            dismissSuggestion()
            return
        }

        // AX reports top-left origin; AppKit wants bottom-left.
        let flippedY = ScreenGeometry.primaryScreenHeight - axRect.maxY
        let origin = CGPoint(x: axRect.maxX, y: flippedY)
        let lineHeight = candidates.lineHeight ?? 16
        let fontSize = candidates.fontSize ?? 13

        panel.present(
            text: Self.cannedCompletion,
            at: origin,
            lineHeight: lineHeight,
            fontSize: fontSize
        )
        suggestionVisible.withLock { $0 = true }

        FileLog.app("""
            suggest app=\(candidates.bundleID ?? "?") \
            axRect=(\(Int(axRect.minX)),\(Int(axRect.minY)) \(Int(axRect.width))x\(Int(axRect.height))) \
            origin=(\(Int(origin.x)),\(Int(origin.y))) fontSize=\(Int(fontSize)) \
            panel=\(panel.panelFrame)
            """)
    }

    private func dismissSuggestion() {
        pendingSuggestion?.cancel()
        pendingSuggestion = nil
        panel.dismiss()
        suggestionVisible.withLock { $0 = false }
    }

    /// Placeholder until the MLX engine lands.
    private static let cannedCompletion = " brown fox jumps"
}

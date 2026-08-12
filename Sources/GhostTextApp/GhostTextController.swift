import AppKit
import GhostTextCore
import GhostTextUI
import os

/// Ties the tap, the buffer, the caret geometry and the overlay together.
///
/// Every decision of substance lives in `GhostTextCore` and is unit-tested there.
/// This type is the wiring: it converts system events into `BufferEvent`s, moves
/// work between the tap thread and the main actor, and drives the panel.
@MainActor
final class GhostTextController {
    /// Swap in the MLX engine here once inference lands. Returning nil means "no
    /// suggestion", which the caller treats the same as a dismissal.
    var completionProvider: (@Sendable (String) async -> String?)?

    private let tap = EventTapController()
    private let caretTracker = CaretTracker()
    private let panel = GhostOverlayPanel()

    private let decoder = KeyDecoder(layout: SystemKeyboardLayout())
    private let acceptPolicy = AcceptPolicy()
    private let sanitizer = CompletionSanitizer()
    private let resolver = CaretResolver()

    private var buffer = KeystrokeBuffer()
    /// The debounce, not inference, was the dominant term in perceived latency:
    /// 250ms of waiting in front of a 75ms completion. Inference at ~20ms prefill
    /// is cheap enough that firing eagerly and cancelling is the better trade.
    private var scheduler = SuggestionScheduler(quietPeriod: 0.09)
    private var lastKnownGood: LastKnownGood?
    private var currentCompletion: String?
    private var pendingFire: DispatchWorkItem?
    private var inFlight: Task<Void, Never>?
    private var lastKeystroke: TimeInterval = 0
    /// Start of the keystroke that triggered the in-flight suggestion, so the log
    /// records what the user actually experiences rather than just model time.
    private var suggestionRequestedAt: TimeInterval = 0

    /// Read from the tap thread on every keydown, written from the main actor.
    /// The tap has to decide synchronously, so it reads this snapshot instead of
    /// asking the UI anything.
    private struct Snapshot: Sendable {
        var suggestionVisible = false
        var bundleID: String?
    }
    private let snapshot = OSAllocatedUnfairLock(initialState: Snapshot())

    private static let idleTimeout: TimeInterval = 30

    private(set) var isEnabled = false

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                GhostTextControllerHolder.shared?.focusChanged(to: app?.bundleIdentifier)
            }
        }
    }

    // MARK: - Enable / disable

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        if enabled {
            tap.setDecider { [decoder, acceptPolicy, snapshot] keyCode, flags, character in
                let current = snapshot.withLock { $0 }
                let key = Self.resolveKey(decoder: decoder, keyCode: keyCode, flags: flags, character: character)
                let decision = acceptPolicy.decide(
                    key: key,
                    suggestionVisible: current.suggestionVisible,
                    bundleID: current.bundleID
                )
                return decision == .passThrough ? .pass : .swallow
            }

            tap.setObserver { [weak self] keyCode, flags, character, swallowed in
                self?.handle(keyCode: keyCode, flags: flags, character: character, swallowed: swallowed)
            }

            guard tap.start() else {
                FileLog.app("enable FAILED — could not create event tap")
                return
            }
            isEnabled = true
            snapshot.withLock { $0.bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            FileLog.app("enabled")
        } else {
            isEnabled = false
            // Toggling off is a privacy guarantee, not a UI state. The tap is torn
            // down so keystrokes stop being observed at all.
            tap.stop()
            dismiss()
            buffer = KeystrokeBuffer()
            FileLog.app("disabled — tap torn down")
        }
    }

    func focusChanged(to bundleID: String?) {
        snapshot.withLock { $0.bundleID = bundleID }
        guard isEnabled else { return }
        apply(buffer.apply(.focusChanged(bundleID: bundleID)))
    }

    // MARK: - Key handling

    private func handle(keyCode: UInt16, flags: CGEventFlags, character: Character?, swallowed: Bool) {
        let key = Self.resolveKey(decoder: decoder, keyCode: keyCode, flags: flags, character: character)
        let now = ProcessInfo.processInfo.systemUptime

        // A swallowed key can only mean one of the three accept actions — the
        // policy never swallows anything else.
        if swallowed {
            switch key {
            case .tab: accept(scope: .word)
            case .text("~"): accept(scope: .phrase)
            case .escape: dismiss()
            default: break
            }
            return
        }

        if now - lastKeystroke > Self.idleTimeout, lastKeystroke > 0 {
            apply(buffer.apply(.idleTimeout))
        }
        lastKeystroke = now

        let event: BufferEvent?
        switch key {
        case .text(let character): event = .character(character)
        case .backspace: event = .backspace
        case .commit: event = .commit
        case .escape: event = .dismiss
        case .caretMove: event = .caretMoved
        // An unswallowed Tab moved focus or inserted an indent either way, so
        // whatever we thought was in the field is no longer trustworthy.
        case .tab: event = .caretMoved
        case .ignored: event = nil
        }

        guard let event else { return }
        apply(buffer.apply(event), at: now)
    }

    private func apply(_ change: BufferChange, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if change.shouldDismissSuggestion { dismiss() }

        guard change.shouldRequestSuggestion else { return }
        for command in scheduler.typingOccurred(at: now) {
            switch command {
            case .cancelInFlight, .cancelAll:
                cancelPending()
            case .scheduleFire(let at):
                schedule(at: at, delay: at - now)
            }
        }
    }

    // MARK: - Suggestion lifecycle

    private func schedule(at fireTime: TimeInterval, delay: TimeInterval) {
        pendingFire?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fire(scheduledFor: fireTime) }
        }
        pendingFire = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func fire(scheduledFor: TimeInterval) {
        guard scheduler.fireDue(at: scheduledFor) else { return }

        let text = buffer.text
        guard !text.isEmpty else { return }
        suggestionRequestedAt = lastKeystroke

        inFlight?.cancel()
        inFlight = Task { [weak self, sanitizer] in
            guard let provider = await self?.completionProvider else {
                // Placeholder still goes through the sanitizer, so the no-model
                // path behaves exactly like the real one.
                guard let cleaned = sanitizer.sanitize(raw: Self.placeholderCompletion, buffer: text) else { return }
                await self?.present(completion: cleaned)
                return
            }
            let started = ProcessInfo.processInfo.systemUptime
            guard let raw = await provider(text) else { return }
            guard !Task.isCancelled else { return }

            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            guard let cleaned = sanitizer.sanitize(raw: raw, buffer: text) else {
                FileLog.app("completion rejected by sanitizer (\(Int(elapsed))ms) raw=\(raw.debugDescription)")
                return
            }
            FileLog.app("completion \(Int(elapsed))ms -> \(cleaned.debugDescription)")
            await self?.present(completion: cleaned)
        }
    }

    private func present(completion: String) {
        let candidates = caretTracker.sample()
        let height = ScreenGeometry.primaryScreenHeight

        // The resolver is pure and screen-height agnostic, so AX's top-left rects
        // are flipped into AppKit space before they reach it.
        let placement = resolver.resolve(
            axRangeBounds: candidates.axRangeBounds.map { AXCoordinates.flipToAppKit(rect: $0, primaryScreenHeight: height) },
            focusedElementFrame: candidates.focusedElementFrame.map { AXCoordinates.flipToAppKit(rect: $0, primaryScreenHeight: height) },
            focusedWindowFrame: candidates.focusedWindowFrame.map { AXCoordinates.flipToAppKit(rect: $0, primaryScreenHeight: height) },
            lastKnownGood: lastKnownGood,
            currentBundleID: candidates.bundleID,
            now: ProcessInfo.processInfo.systemUptime,
            screens: ScreenGeometry.screenFrames
        )

        guard let placement else {
            FileLog.app("no usable caret for \(candidates.bundleID ?? "?") — hiding")
            dismiss()
            return
        }

        currentCompletion = completion
        panel.present(
            text: completion,
            at: placement.origin,
            lineHeight: placement.lineHeight,
            fontSize: candidates.fontSize ?? 13
        )
        snapshot.withLock { $0.suggestionVisible = true }

        if placement.source != .lastKnownGood {
            lastKnownGood = LastKnownGood(
                placement: placement,
                timestamp: ProcessInfo.processInfo.systemUptime,
                bundleID: candidates.bundleID
            )
        }

        let endToEnd = (ProcessInfo.processInfo.systemUptime - suggestionRequestedAt) * 1000
        FileLog.app("""
            present app=\(candidates.bundleID ?? "?") source=\(placement.source) \
            e2e=\(Int(endToEnd))ms origin=(\(Int(placement.origin.x)),\(Int(placement.origin.y))) \
            panel=\(panel.panelFrame)
            """)
    }

    private enum AcceptScope { case word, phrase }

    private func accept(scope: AcceptScope) {
        guard let completion = currentCompletion else { return }
        let text = scope == .word
            ? CompletionSanitizer.firstWord(of: completion)
            : CompletionSanitizer.phrase(of: completion, maxWords: 3)

        guard !text.isEmpty else { return }
        FileLog.app("accept \(scope) -> \(text.debugDescription)")

        dismiss()
        // Keep our buffer in step with the field: this text is now typed.
        _ = buffer.apply(.acceptedCompletion(text))
        KeystrokeSynthesizer.type(text)
    }

    private func dismiss() {
        cancelPending()
        panel.dismiss()
        currentCompletion = nil
        snapshot.withLock { $0.suggestionVisible = false }
        _ = scheduler.suggestionDismissed()
    }

    private func cancelPending() {
        pendingFire?.cancel()
        pendingFire = nil
        inFlight?.cancel()
        inFlight = nil
    }

    /// Trusts the system-resolved character over a keycode re-translation for
    /// anything printable, while leaving Tab, Escape, Return and Backspace to the
    /// decoder — those carry control characters that must stay classified as keys.
    nonisolated static func resolveKey(
        decoder: KeyDecoder,
        keyCode: UInt16,
        flags: CGEventFlags,
        character: Character?
    ) -> DecodedKey {
        let base = decoder.decode(keyCode: keyCode, modifiers: ModifierSet(flags))
        guard let character, isPrintable(character) else { return base }
        switch base {
        case .text, .ignored: return .text(character)
        default: return base
        }
    }

    nonisolated private static func isPrintable(_ character: Character) -> Bool {
        !character.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }

    private static let placeholderCompletion = " brown fox jumps"

    /// Compact state dump for the self-test log.
    func debugState() -> String {
        let visible = snapshot.withLock { $0.suggestionVisible }
        return "buffer=\(buffer.text.debugDescription) suggestable=\(buffer.isSuggestable) "
            + "visible=\(visible) completion=\(currentCompletion?.debugDescription ?? "nil") "
            + "panel=\(panel.isPresented ? "\(panel.panelFrame)" : "hidden")"
    }
}

/// Notification closures need a reference that does not capture `self` during init.
@MainActor
enum GhostTextControllerHolder {
    static var shared: GhostTextController?
}

private extension ModifierSet {
    init(_ flags: CGEventFlags) {
        var set = ModifierSet()
        if flags.contains(.maskShift) { set.insert(.shift) }
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskCommand) { set.insert(.command) }
        if flags.contains(.maskAlphaShift) { set.insert(.capsLock) }
        if flags.contains(.maskSecondaryFn) { set.insert(.fn) }
        self = set
    }
}

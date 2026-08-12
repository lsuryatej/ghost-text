import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

/// What the tap should do with a key, decided synchronously on the input path.
enum TapDecision: Sendable {
    case pass
    case swallow
}

/// Global keyboard tap.
///
/// This is an *active* tap, because accepting a completion means swallowing the
/// Tab or `~` that triggered it. Active taps run inline with system input, so the
/// callback is held to a strict budget: read a lock-protected snapshot, decide,
/// return. Anything heavier — buffering, inference, UI — is dispatched away.
/// Blocking here lags typing in every app on the machine.
final class EventTapController: @unchecked Sendable {
    /// Runs on the tap thread, synchronously, on every keydown. Must be fast.
    typealias Decider = @Sendable (_ keyCode: UInt16, _ flags: CGEventFlags, _ character: Character?) -> TapDecision
    /// Runs on the main actor, after the fact. Free to be slow.
    typealias Observer = @MainActor (_ keyCode: UInt16, _ flags: CGEventFlags, _ character: Character?, _ swallowed: Bool) -> Void

    /// Stamped onto every event we synthesize so the tap can recognise its own
    /// output. Without this, accepting a completion feeds the synthesized
    /// keystrokes straight back into the buffer and can loop.
    static let syntheticMarker: Int64 = 0x4748_5354  // "GHST"

    private struct State {
        var enabled = false
        var decider: Decider?
        var observer: Observer?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?

    var isRunning: Bool { tap != nil }

    func setDecider(_ decider: @escaping Decider) {
        state.withLock { $0.decider = decider }
    }

    func setObserver(_ observer: @escaping Observer) {
        state.withLock { $0.observer = observer }
    }

    // MARK: - Lifecycle

    /// Runs the tap on a dedicated run loop rather than the main one. An active
    /// tap serviced by a busy main thread would stall typing whenever SwiftUI is
    /// doing work.
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: ghostTextTapCallback,
            userInfo: refcon
        ) else {
            FileLog.app("event tap creation FAILED — Input Monitoring not granted?")
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            FileLog.app("event tap running on dedicated thread")
            CFRunLoopRun()
            FileLog.app("event tap run loop exited")
        }
        thread.name = "com.suryatej.ghosttext.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        state.withLock { $0.enabled = true }
        return true
    }

    /// Toggling off must actually tear the tap down, not just hide the UI. The
    /// privacy promise is that keystrokes stop being observed at all.
    func stop() {
        state.withLock { $0.enabled = false }

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource, let tapRunLoop {
            CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
            CFRunLoopStop(tapRunLoop)
        }

        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        thread = nil
        FileLog.app("event tap stopped and invalidated")
    }

    // MARK: - Tap path

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps whose callback overruns its time budget. Left
        // unhandled the app goes quietly deaf, which is worse than crashing.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                FileLog.app("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Our own synthesized keystrokes must not be re-buffered.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        // Password fields and anything else holding secure input: observe nothing.
        if IsSecureEventInputEnabled() {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let character = Self.character(from: event)

        let snapshot = state.withLock { ($0.enabled, $0.decider, $0.observer) }
        guard snapshot.0 else { return Unmanaged.passUnretained(event) }

        let decision = snapshot.1?(keyCode, flags, character) ?? .pass

        if let observer = snapshot.2 {
            let swallowed = decision == .swallow
            DispatchQueue.main.async {
                MainActor.assumeIsolated { observer(keyCode, flags, character, swallowed) }
            }
        }

        return decision == .swallow ? nil : Unmanaged.passUnretained(event)
    }
}

extension EventTapController {
    /// The character the system itself resolved for this event.
    ///
    /// Preferring this over re-deriving from the keycode matters: it already
    /// accounts for dead keys, IME composition, non-US layouts, and events
    /// injected by text expanders, which carry a unicode payload with a keycode
    /// that means nothing.
    static func character(from event: CGEvent) -> Character? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let string = String(utf16CodeUnits: buffer, count: length)
        guard string.count == 1, let character = string.first else { return nil }
        return character
    }
}

/// Top-level so it can be used as a C function pointer with no captured context.
private func ghostTextTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

import AppKit

/// End-to-end self-test: drives real typing through the real tap and logs what
/// came out the other side.
///
/// Ghost Text holds the Accessibility grant, so it can post events that a shell
/// cannot. That makes the app the only place an automated end-to-end check can
/// live. Events are posted *unmarked* so the tap treats them exactly like a
/// person typing.
///
/// Run with `--selftest`. It refuses to type unless TextEdit is genuinely
/// frontmost, so stray keystrokes cannot land in a terminal or a chat window.
@MainActor
enum SelfTest {
    private static let targetBundleID = "com.apple.TextEdit"

    static func run(controller: GhostTextController) {
        Task { await sequence(controller: controller) }
    }

    private static func sequence(controller: GhostTextController) async {
        FileLog.app.banner("SELF-TEST")

        guard AXIsProcessTrusted() else {
            FileLog.app("selftest ABORT: no Accessibility grant")
            return
        }

        // The tap only comes up once the model is warm, and a cold model means a
        // download. Wait rather than typing into a disabled tap.
        var waited = 0.0
        while !controller.isEnabled, waited < 300 {
            try? await Task.sleep(for: .milliseconds(500))
            waited += 0.5
        }
        guard controller.isEnabled else {
            FileLog.app("selftest ABORT: model never became ready")
            return
        }
        FileLog.app(String(format: "selftest: model ready after %.1fs", waited))

        guard await focusTarget() else {
            FileLog.app("selftest ABORT: could not bring \(targetBundleID) frontmost")
            return
        }

        // 1. Type like a person: one character at a time, with human-ish gaps that
        //    stay under the debounce window so it never fires mid-phrase.
        let phrase = "The quick "
        FileLog.app("selftest typing \(phrase.debugDescription) one character at a time")
        for character in phrase {
            guard stillOnTarget("mid-typing") else { return }
            KeystrokeSynthesizer.type(String(character), marked: false, at: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(70))
        }

        // 2. Pause past the debounce and let a suggestion resolve and present.
        try? await Task.sleep(for: .milliseconds(900))
        FileLog.app("selftest state after pause: \(controller.debugState())")

        // 3. Tab should be swallowed and accept the first word. If the tap were
        //    wrong, TextEdit would receive a literal tab instead.
        FileLog.app("selftest pressing Tab (expect swallow + accept word)")
        guard stillOnTarget("before Tab") else { return }
        KeystrokeSynthesizer.pressKey(48, marked: false, at: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(600))
        FileLog.app("selftest state after Tab: \(controller.debugState())")

        // 4. Escape should dismiss, after which Tab must pass through untouched.
        guard stillOnTarget("before Escape") else { return }
        KeystrokeSynthesizer.pressKey(53, marked: false, at: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(300))
        FileLog.app("selftest state after Escape: \(controller.debugState())")

        // 5. The tilde path, which Tab does not exercise. Posted as a unicode
        //    character rather than shift+grave, so it also confirms the tap reads
        //    the system-resolved character rather than re-deriving from a keycode.
        FileLog.app("selftest typing again, then `~` (expect swallow + accept phrase)")
        for character in "jumps over " {
            guard stillOnTarget("mid-typing 2") else { return }
            KeystrokeSynthesizer.type(String(character), marked: false, at: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(70))
        }
        try? await Task.sleep(for: .milliseconds(900))
        FileLog.app("selftest state before tilde: \(controller.debugState())")

        guard stillOnTarget("before tilde") else { return }
        KeystrokeSynthesizer.type("~", marked: false, at: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(600))
        FileLog.app("selftest state after tilde: \(controller.debugState())")

        // 6. With nothing showing, `~` must reach the app as a literal character.
        //    This is the guarantee that makes intercepting it acceptable at all.
        guard stillOnTarget("literal tilde") else { return }
        KeystrokeSynthesizer.pressKey(53, marked: false, at: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(300))
        KeystrokeSynthesizer.type("~", marked: false, at: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(400))
        FileLog.app("selftest state after literal tilde: \(controller.debugState())")

        FileLog.app("selftest complete — check TextEdit for the resulting text")
    }

    /// Re-checked before every single synthesized key.
    ///
    /// Checking once up front is not enough: focus can drift between keystrokes,
    /// and an earlier run of this test put ten characters into a browser because
    /// of exactly that. Stray keystrokes into whatever happens to be frontmost is
    /// the one genuinely damaging failure mode here, so the guard is per-key.
    private static func stillOnTarget(_ stage: String) -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmost == targetBundleID else {
            FileLog.app("selftest ABORT \(stage): frontmost drifted to \(frontmost ?? "nil")")
            return false
        }
        return true
    }

    /// A scratch file of our own, so the test never touches the user's documents.
    private static var scratchFile: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GhostText", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("selftest.txt")
    }

    private static func focusTarget() async -> Bool {
        // Activating TextEdit is not enough. With no document open it has no window
        // to focus, so it hands focus straight back to the previous app and the
        // keystrokes go nowhere - or worse, somewhere else. Opening a real file
        // guarantees a text area to type into.
        let file = scratchFile
        try? "".write(to: file, atomically: true, encoding: .utf8)

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: configuration)

        // Verify rather than assume. Posting keystrokes at the wrong app is the
        // one genuinely damaging failure mode here.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(150))
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID {
                return true
            }
        }
        return false
    }
}

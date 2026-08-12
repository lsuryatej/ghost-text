import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid
import GhostTextInference

enum Permissions {
    static func promptAll() {
        // Literal rather than kAXTrustedCheckOptionPrompt: the Carbon global is
        // imported as a `var` and trips Swift 6 strict concurrency.
        let accessibility = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let inputMonitoring = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        FileLog.app("permission prompt: accessibility=\(accessibility) inputMonitoring=\(inputMonitoring)")
    }

    static func report() -> String {
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        return "accessibility=\(accessibility) inputMonitoring=\(inputMonitoring)"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = GhostTextController()
    private let probe = AXProbe()

    /// Instruct model with ChatML assistant-prefill framing. The bench found the
    /// base model and the instruct model fed raw text both drift into quiz and
    /// fill-in-the-blank artifacts; prefilling an assistant turn that is never
    /// closed keeps it continuing the sentence. See BENCH.md.
    private var engine = CompletionEngine(modelID: ModelChoice.current.id)
    private(set) var modelReady = false
    private(set) var activeModel = ModelChoice.current
    private(set) var loadProgress: Double = 0
    let instructions = InstructionsStore()
    private(set) var probeRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        FileLog.app.banner("launched \(Date())")
        FileLog.app("build \(Bundle.main.bundleIdentifier ?? "?") \(Permissions.report())")
        FileLog.app("app log:   \(FileLog.app.url.path)")
        FileLog.app("probe log: \(FileLog.probe.url.path)")

        instructions.createTemplateIfMissing()
        Permissions.promptAll()

        GhostTextControllerHolder.shared = controller
        AXProbeHolder.shared = probe
        loadModel()

        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run(controller: controller)
        }
    }

    /// The tap stays off until the model is warm. Suggesting a placeholder would
    /// mean a stray Tab inserting junk into whatever the user is actually typing.
    /// Swaps the model without a restart: suspend, warm the new one, resume.
    func selectModel(_ choice: ModelChoice) {
        guard choice != activeModel else { return }
        ModelChoice.current = choice
        activeModel = choice
        modelReady = false
        loadProgress = 0
        controller.setEnabled(false)
        controller.engine = nil
        engine = CompletionEngine(modelID: choice.id)
        FileLog.app("switching model to \(choice.id)")
        loadModel()
    }

    private func loadModel() {
        let engine = self.engine
        let controller = self.controller
        let instructionText = instructions.current()
        Task {
            let started = ProcessInfo.processInfo.systemUptime
            do {
                await engine.setInstructions(instructionText)
                try await engine.warmup { fraction in
                    Task { @MainActor in self.loadProgress = fraction }
                }
            } catch {
                FileLog.app("model warmup FAILED: \(error) — staying disabled")
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            FileLog.app(String(format: "model warm in %.1fs", elapsed))

            controller.engine = engine
            controller.instructionsProvider = { [weak self] in self?.instructions.current() }
            self.modelReady = true
            self.loadProgress = 1
            controller.setEnabled(true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.setEnabled(false)
    }

    func toggleProbe() {
        probeRunning.toggle()
        if probeRunning { probe.start() } else { probe.stop() }
        FileLog.app("AX probe \(probeRunning ? "started" : "stopped")")
    }

    func writeProbeSummary() {
        FileLog.probe.write(probe.summary())
        FileLog.app("probe summary written to \(FileLog.probe.url.path)")
    }
}

@main
struct GhostTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var enabled = true

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enabled", isOn: $enabled)
                .onChange(of: enabled) { _, isOn in
                    delegate.controller.setEnabled(isOn)
                }
            Divider()
            Button("Request permissions…") { Permissions.promptAll() }
            Button("Log permission status") { FileLog.app(Permissions.report()) }
            Divider()
            Menu(delegate.modelReady
                ? "Model: \(delegate.activeModel.name)"
                : "Model: downloading \(Int(delegate.loadProgress * 100))%") {
                Section("Recommended") {
                    ForEach(ModelChoice.catalog.filter(\.recommended)) { choice in
                        modelButton(choice)
                    }
                }
                Section("Other") {
                    ForEach(ModelChoice.catalog.filter { !$0.recommended }) { choice in
                        modelButton(choice)
                    }
                }
            }
            Button("Edit custom instructions\u{2026}") { delegate.instructions.reveal() }
            Divider()
            Button(delegate.probeRunning ? "Stop AX probe" : "Start AX probe") { delegate.toggleProbe() }
            Button("Write AX probe summary") { delegate.writeProbeSummary() }
            Button("Reveal logs in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([FileLog.app.url, FileLog.probe.url])
            }
            Divider()
            Button("Quit Ghost Text") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: enabled ? "text.cursor" : "moon.zzz")
        }
    }

    @ViewBuilder
    private func modelButton(_ choice: ModelChoice) -> some View {
        Button(choice.id == delegate.activeModel.id ? "\u{2713} \(choice.displayName)" : "   \(choice.displayName)") {
            delegate.selectModel(choice)
        }
    }
}

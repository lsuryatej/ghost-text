import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

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
    private(set) var probeRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        FileLog.app.banner("launched \(Date())")
        FileLog.app("build \(Bundle.main.bundleIdentifier ?? "?") \(Permissions.report())")
        FileLog.app("app log:   \(FileLog.app.url.path)")
        FileLog.app("probe log: \(FileLog.probe.url.path)")

        Permissions.promptAll()

        GhostTextControllerHolder.shared = controller
        AXProbeHolder.shared = probe
        controller.setEnabled(true)
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
}

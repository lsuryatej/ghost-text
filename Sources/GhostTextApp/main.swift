import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

// Phase 0a skeleton: menu bar shell whose only job right now is to exist as a
// stable, signed bundle so macOS can hang TCC grants off it.

enum Permissions {
    static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAll() {
        // Literal rather than kAXTrustedCheckOptionPrompt: the Carbon global is
        // imported as a `var` and trips Swift 6 strict concurrency.
        let ax = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let hid = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        NSLog("[GhostText] accessibility=\(ax) inputMonitoring=\(hid)")
    }

    static func report() -> String {
        let ax = AXIsProcessTrusted()
        let hid = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        return "accessibility=\(ax) inputMonitoring=\(hid)"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("[GhostText] launched, \(Permissions.report())")
        Permissions.promptAll()
    }
}

@main
struct GhostTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var enabled = true

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enabled", isOn: $enabled)
            Divider()
            Button("Request permissions…") { Permissions.promptAll() }
            Button("Log permission status") { NSLog("[GhostText] \(Permissions.report())") }
            Divider()
            Button("Quit Ghost Text") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: enabled ? "text.cursor" : "moon.zzz")
        }
    }
}

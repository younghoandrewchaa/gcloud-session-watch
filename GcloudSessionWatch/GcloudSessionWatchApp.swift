import SwiftUI

@main
struct GcloudSessionWatchApp: App {
    // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
    // Safe to call the @MainActor init from here.
    @StateObject private var monitor = SessionMonitor()

    var body: some Scene {
        // MenuBarExtra MUST come before Settings — SettingsLink relies on this ordering.
        MenuBarExtra {
            // SettingsLink requires macOS 14; use sendAction for 13 compatibility.
            if #available(macOS 14.0, *) {
                SettingsLink { Text("Settings...") }
            } else {
                Button("Settings...") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            Text(monitor.labelText)
                .foregroundStyle(monitor.labelColor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

import SwiftUI

@main
struct GcloudSessionWatchApp: App {
    // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
    // Safe to call the @MainActor init from here.
    @StateObject private var monitor = SessionMonitor()

    var body: some Scene {
        // MenuBarExtra MUST come before Settings — SettingsLink relies on this ordering.
        MenuBarExtra {
            VStack(spacing: 8) {
                Text(monitor.detailedTimeText)
                    .foregroundStyle(monitor.labelColor)
                    .font(.system(.body, design: .monospaced))
                Divider()
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
            }
            .frame(width: 160)
            .padding(.vertical, 8)
        } label: {
            Image(systemName: "key.icloud.fill").foregroundStyle(monitor.iconColor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

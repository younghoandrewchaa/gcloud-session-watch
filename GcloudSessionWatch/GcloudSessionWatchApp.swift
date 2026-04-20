import SwiftUI

@main
struct GcloudSessionWatchApp: App {
    // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
    // Safe to call the @MainActor init from here.
    @StateObject private var monitor = SessionMonitor()
    @AppStorage("sessionDurationHours") private var sessionDurationHours: Int = 4

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 8) {
                Text(monitor.detailedTimeText)
                    .foregroundStyle(monitor.labelColor)
                    .font(.system(.body, design: .monospaced))
                Divider()
                Stepper(
                    "Duration: \(sessionDurationHours)h",
                    value: $sessionDurationHours,
                    in: 1...24
                )
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .frame(width: 200)
            .padding(.vertical, 8)
        } label: {
            Image(nsImage: {
                let cfg = NSImage.SymbolConfiguration(paletteColors: [NSColor(monitor.iconColor)])
                let img = (NSImage(systemSymbolName: "key.icloud.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(cfg)) ?? NSImage()
                img.isTemplate = false
                return img
            }())
        }
        .menuBarExtraStyle(.window)
    }
}

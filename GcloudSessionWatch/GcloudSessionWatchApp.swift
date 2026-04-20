import SwiftUI

@main
struct GcloudSessionWatchApp: App {
    // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
    // Safe to call the @MainActor init from here.
    @StateObject private var monitor = SessionMonitor()
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("sessionDurationHours") private var sessionDurationHours: Int = 5

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 8) {
                if let update = updateChecker.availableUpdate {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text("v\(update.version) available")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        HStack(spacing: 8) {
                            Button("Update") {
                                updateChecker.availableUpdate = nil
                                NSWorkspace.shared.open(update.url)
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            Button("Later") {
                                updateChecker.availableUpdate = nil
                            }
                            .controlSize(.small)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
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
            .onAppear {
                updateChecker.startPeriodicChecks()
            }
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

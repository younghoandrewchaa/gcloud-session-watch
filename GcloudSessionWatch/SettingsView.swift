import SwiftUI

struct SettingsView: View {
    @AppStorage("sessionDurationHours") private var sessionDurationHours: Int = 5

    var body: some View {
        Form {
            Stepper(
                "Session Duration: \(sessionDurationHours) hour\(sessionDurationHours == 1 ? "" : "s")",
                value: $sessionDurationHours,
                in: 1...24
            )
        }
        .padding()
        .frame(width: 320)
    }
}

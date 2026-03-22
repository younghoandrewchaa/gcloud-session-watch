//
//  SessionMonitor.swift
//  GcloudSessionWatch
//
//  Created by Youngho Chaa on 21/03/2026.
//

import Combine
import Foundation
import SwiftUI
import UserNotifications

enum CredentialsState: Equatable {
    case missing
    case valid
    case warning
    case expired
}

@MainActor
final class SessionMonitor: ObservableObject {
    @Published private(set) var credentialsState: CredentialsState = .missing
    @Published private(set) var timeRemaining: TimeInterval = 0
    
    private var sessionDurationSeconds: TimeInterval
    
    private var timer: Timer?
    private var displayTimer: Timer?
    private var expiryDate: Date?
    private var defaultsObserver: NSObjectProtocol?
    
    private let fileProvider: FileTimestampProvider
    private let credentialsPath: String
    
    private static let notificationID = "gcloud-session-expiry"
    private static let warningThreshold: TimeInterval = 60 * 10 // 10 minutes
    private static let isTestEnvironment: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    
    init(
        fileProvider: FileTimestampProvider = LiveFileTimestampProvider(),
        credentialsPath: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/gcloud/application_default_credentials.json")
    ) {
        self.fileProvider = fileProvider
        self.credentialsPath = credentialsPath
        let hours = UserDefaults.standard.integer(forKey: "sessionDurationHours")
        self.sessionDurationSeconds = TimeInterval(hours == 0 ? 5 : hours) * 3600
        
        tick()
        startTimer()
        startDisplayTimer()
        observeDefaults()
        requestNotificationPermission()
    }
    
    deinit {
        timer?.invalidate()
        displayTimer?.invalidate()
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    var labelText: String {
        switch credentialsState {
        case .missing: return "G --:--"
        case .expired: return "G EXPIRED"
        case .valid, .warning:
            let h = Int(timeRemaining) / 3600
            let m = (Int(timeRemaining) % 3600) / 60
            return "G \(h):\(String(format: "%02d", m))"
        }
    }
    
    var detailedTimeText: String {
        switch credentialsState {
        case .missing: return "--:--:--"
        case .expired: return "EXPIRED"
        case .valid, .warning:
            let total = Int(timeRemaining)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
    }

    var labelColor: Color {
        switch credentialsState {
        case .missing, .valid: return .primary
        case .warning: return .orange
        case .expired: return .red
        }
    }
}

private extension SessionMonitor {
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplay() }
        }
    }

    // Intentionally mirrors the state-transition logic in tick().
    // If tick()'s branching changes, update refreshDisplay() to match.
    func refreshDisplay() {
        guard let expiry = expiryDate else { return }
        let remaining = expiry.timeIntervalSinceNow
        if remaining <= 0 {
            credentialsState = .expired
            timeRemaining = 0
        } else if remaining <= Self.warningThreshold {
            credentialsState = .warning
            timeRemaining = remaining
        } else {
            credentialsState = .valid
            timeRemaining = remaining
        }
    }
    
    func tick() {
        guard let mtime = fileProvider.modificationDate(at: credentialsPath) else {
            credentialsState = .missing
            timeRemaining = 0
            expiryDate = nil
            cancelNotification()
            return
        }

        let expiry = mtime.addingTimeInterval(sessionDurationSeconds)
        self.expiryDate = expiry
        let remaining = expiry.timeIntervalSinceNow

        if remaining <= 0 {
            credentialsState = .expired
            timeRemaining = 0
        } else if remaining <= Self.warningThreshold {
            credentialsState = .warning
            timeRemaining = remaining
        } else {
            credentialsState = .valid
            timeRemaining = remaining
        }

        scheduleNotification(at: expiry)
    }
    
    func scheduleNotification(at expiry: Date) {
        guard !Self.isTestEnvironment else { return }
        cancelNotification()
        // Capture interval once to avoid a TOCTOU race: if expiry is only
        // milliseconds away, a second Date() evaluation could return negative,
        // which crashes UNTimeIntervalNotificationTrigger (requires interval > 0).
        let interval = expiry.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "gcloud session expired"
        content.body = "Run gcloud auth application-default login to refresh."

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
          identifier: Self.notificationID,
          content: content,
          trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelNotification() {
        guard !Self.isTestEnvironment else { return }
        UNUserNotificationCenter.current()
          .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    func requestNotificationPermission() {
        guard !Self.isTestEnvironment else { return }
        UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func observeDefaults() {
        // UserDefaults.didChangeNotification fires for every write in the process.
        // The guard bails out if the value is unchanged, preventing excessive
        // cancel/reschedule cycles when the stepper fires multiple writes.
        // MainActor.assumeIsolated matches the timer pattern and suppresses
        // strict-concurrency warnings from accessing @MainActor state in this closure.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let hours = UserDefaults.standard.integer(forKey: "sessionDurationHours")
                let newSeconds = TimeInterval(hours == 0 ? 5 : hours) * 3600
                guard newSeconds != self.sessionDurationSeconds else { return }
                self.sessionDurationSeconds = newSeconds
                self.tick()
            }
        }
    }

}

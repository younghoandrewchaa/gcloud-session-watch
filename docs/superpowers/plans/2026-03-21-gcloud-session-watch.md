# gcloud-session-watch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 13+ menu bar app in Swift that reads the gcloud ADC credentials file mtime, displays time remaining until session expiry with colour-coded warnings, and fires a notification on expiry.

**Architecture:** SwiftUI `MenuBarExtra` with `.menu` style drives a native dropdown. `SessionMonitor` (`@MainActor ObservableObject`) polls the credentials file mtime every 30 seconds and publishes a `CredentialsState` enum. `SettingsView` (SwiftUI `Settings` scene) persists session duration to `UserDefaults`. A `FileTimestampProvider` protocol makes the file access testable.

**Tech Stack:** Swift 5.9+, SwiftUI, UserNotifications, XCTest, Xcode 15+, macOS 13+

---

## File Map

| File | Responsibility |
|---|---|
| `GcloudSessionWatch/FileTimestamp.swift` | `FileTimestampProvider` protocol + `LiveFileTimestampProvider` |
| `GcloudSessionWatch/SessionMonitor.swift` | `CredentialsState` enum + `@MainActor ObservableObject` with timer, notification, settings observation |
| `GcloudSessionWatch/SettingsView.swift` | SwiftUI `Settings` scene — session duration stepper |
| `GcloudSessionWatch/GcloudSessionWatchApp.swift` | `@main` App entry, `MenuBarExtra`, `Settings` scene wiring |
| `GcloudSessionWatch/Info.plist` | `LSUIElement = YES` |
| `GcloudSessionWatch/GcloudSessionWatch.entitlements` | App Sandbox disabled |
| `GcloudSessionWatchTests/SessionMonitorTests.swift` | XCTest unit tests for state transitions, label text, label colour |

---

## Task 1: Scaffold Xcode project

**Files:**
- Create: `GcloudSessionWatch.xcodeproj/` (via Xcode UI)
- Modify: `GcloudSessionWatch/Info.plist`
- Create: `GcloudSessionWatch/GcloudSessionWatch.entitlements`

- [ ] **Step 1: Create new Xcode project**

  Open Xcode → File → New → Project → macOS → App.
  - Product Name: `GcloudSessionWatch`
  - Bundle Identifier: `com.gcloud-session-watch`
  - Interface: SwiftUI
  - Language: Swift
  - Uncheck "Include Tests"
  - Save to: `~/github/gcloud-session-watch`

- [ ] **Step 2: Add test target**

  File → New → Target → macOS → Unit Testing Bundle.
  - Product Name: `GcloudSessionWatchTests`
  - Target to Test: `GcloudSessionWatch`

  In the test target's General tab, set minimum deployment target to macOS 13.0.

- [ ] **Step 3: Set minimum deployment target to macOS 13**

  Project navigator → select `GcloudSessionWatch` project → `GcloudSessionWatch` target → General → Minimum Deployments: **macOS 13.0**.

- [ ] **Step 4: Disable App Sandbox**

  `GcloudSessionWatch` target → Signing & Capabilities → click **X** next to "App Sandbox" to remove it.

  If Xcode deleted the entitlements file, recreate `GcloudSessionWatch/GcloudSessionWatch.entitlements`:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict/>
  </plist>
  ```

- [ ] **Step 5: Link UserNotifications.framework**

  `GcloudSessionWatch` target → General → Frameworks, Libraries, and Embedded Content → click **+** → search for `UserNotifications.framework` → Add.

- [ ] **Step 6: Add LSUIElement to Info.plist**

  Open `GcloudSessionWatch/Info.plist` as source code and add inside the root `<dict>`:
  ```xml
  <key>LSUIElement</key>
  <true/>
  ```
  `LSUIElement = YES` hides the Dock icon so the app lives only in the menu bar.

- [ ] **Step 7: Delete generated boilerplate**

  Delete `GcloudSessionWatch/ContentView.swift`.
  Delete the placeholder test file Xcode generated in `GcloudSessionWatchTests/`.
  Keep `GcloudSessionWatch/GcloudSessionWatchApp.swift` (rewritten in Task 5).

- [ ] **Step 8: Verify the project builds**

  ```bash
  cd ~/github/gcloud-session-watch
  xcodebuild build -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit scaffold**

  ```bash
  git add .
  git commit -m "feat: scaffold Xcode project"
  ```

---

## Task 2: FileTimestamp protocol

**Files:**
- Create: `GcloudSessionWatch/FileTimestamp.swift`

This protocol is the only external dependency of `SessionMonitor`. Injecting it in `init` makes state transitions fully testable without touching disk.

- [ ] **Step 1: Create `FileTimestamp.swift`**

  ```swift
  // GcloudSessionWatch/FileTimestamp.swift
  import Foundation

  protocol FileTimestampProvider {
      func modificationDate(at path: String) -> Date?
  }

  struct LiveFileTimestampProvider: FileTimestampProvider {
      func modificationDate(at path: String) -> Date? {
          (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
      }
  }
  ```

- [ ] **Step 2: Build to verify**

  ```bash
  xcodebuild build -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add GcloudSessionWatch/FileTimestamp.swift
  git commit -m "feat: add FileTimestampProvider protocol and live implementation"
  ```

---

## Task 3: SessionMonitor — state, labels, and core tick logic

**Files:**
- Create: `GcloudSessionWatch/SessionMonitor.swift`
- Create: `GcloudSessionWatchTests/SessionMonitorTests.swift`

**Concurrency notes for this file:**

- `SessionMonitor` is `@MainActor`. All `@Published` mutations and method calls happen on the main thread.
- The `Timer` is scheduled from `init` (on the main actor), so its block fires on the main run loop. `MainActor.assumeIsolated` in the timer closure calls `tick()` synchronously without async indirection.
- The `NotificationCenter` observer is queued on `.main`, so its block also runs on the main thread. Same `MainActor.assumeIsolated` pattern is used for consistency and to suppress any future strict-concurrency warning.
- `timer` and `defaultsObserver` are accessed in `deinit`. In Swift 5.9, `deinit` on a `@MainActor` class runs on the main actor. In Swift 6 strict mode this becomes non-isolated — if you migrate to Swift 6 later, mark these two properties `nonisolated(unsafe)`.
- `@StateObject` in `GcloudSessionWatchApp` evaluates `SessionMonitor()` lazily on first render, which SwiftUI performs on the main thread. This is safe with a `@MainActor init`.

**Design note on `observeDefaults`:** The spec describes a `rescheduleNotification()` helper. This plan calls `tick()` instead, which re-reads the mtime, recomputes state, and reschedules the notification in one step — strictly a superset of `rescheduleNotification()`. One side effect: if the file is missing when settings change, `tick()` cancels any pending notification (correct per spec). This is not a bug.

- [ ] **Step 1: Write failing tests**

  Create `GcloudSessionWatchTests/SessionMonitorTests.swift`:

  ```swift
  // GcloudSessionWatchTests/SessionMonitorTests.swift
  import XCTest
  import SwiftUI
  @testable import GcloudSessionWatch

  // MARK: - Mock

  final class MockFileTimestampProvider: FileTimestampProvider {
      var mockDate: Date?
      func modificationDate(at path: String) -> Date? { mockDate }
  }

  // MARK: - Tests

  @MainActor
  final class SessionMonitorTests: XCTestCase {

      var mock: MockFileTimestampProvider!

      override func setUp() {
          super.setUp()
          mock = MockFileTimestampProvider()
          UserDefaults.standard.removeObject(forKey: "sessionDurationHours")
      }

      // MARK: Missing file

      func testMissingFile_stateIsMissing() {
          mock.mockDate = nil
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .missing)
      }

      func testMissingFile_timeRemainingIsZero() {
          mock.mockDate = nil
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.timeRemaining, 0)
      }

      func testMissingFile_labelText() {
          mock.mockDate = nil
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.labelText, "--:--")
      }

      // MARK: Valid session

      func testValidSession_stateIsValid() {
          // mtime 1 hour ago, default 5h duration → ~4h remaining
          mock.mockDate = Date(timeIntervalSinceNow: -3600)
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .valid)
      }

      func testValidSession_labelFormat() {
          // mtime 1h 27m 30s ago, default 5h → 12750 s remaining = 3h 32m 30s → "3:32"
          // +30 s offset ensures remaining is never on an exact minute boundary
          mock.mockDate = Date(timeIntervalSinceNow: -(3600 + 27 * 60 + 30))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.labelText, "3:32")
      }

      func testValidSession_minutesPaddedToTwoDigits() {
          // mtime 4h 2m 30s ago, default 5h → 3450 s remaining = 57m 30s → "0:57"
          // +30 s offset ensures remaining is never on an exact minute boundary
          mock.mockDate = Date(timeIntervalSinceNow: -(4 * 3600 + 2 * 60 + 30))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.labelText, "0:57")
      }

      // MARK: Warning state (≤ 10 minutes = 600 s)

      func testWarningState_at9MinutesRemaining() {
          // 9 minutes = 540 s remaining — comfortably inside the 0–600 s warning bucket
          mock.mockDate = Date(timeIntervalSinceNow: -(5 * 3600 - 540))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .warning)
      }

      func testWarningState_at599SecondsRemaining() {
          // 599 s remaining — just below the 600 s boundary, confirms boundary is inclusive
          // Offset is 5h - 599s = 17401 s ago; clock jitter keeps remaining well below 600 s
          mock.mockDate = Date(timeIntervalSinceNow: -(5 * 3600 - 599))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .warning)
      }

      func testValidState_at11MinutesRemaining() {
          // 11 minutes = 660 s remaining — above the 600 s threshold → valid
          mock.mockDate = Date(timeIntervalSinceNow: -(5 * 3600 - 660))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .valid)
      }

      func testWarningState_labelColorIsOrange() {
          mock.mockDate = Date(timeIntervalSinceNow: -(5 * 3600 - 540))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.labelColor, Color.orange)
      }

      // MARK: Expired session

      func testExpiredSession_stateIsExpired() {
          // mtime 6 hours ago — expired 1h ago with default 5h duration
          mock.mockDate = Date(timeIntervalSinceNow: -6 * 3600)
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .expired)
      }

      func testExpiredSession_labelText() {
          mock.mockDate = Date(timeIntervalSinceNow: -6 * 3600)
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.labelText, "EXPIRED")
      }

      func testExpiredSession_timeRemainingIsZero() {
          mock.mockDate = Date(timeIntervalSinceNow: -6 * 3600)
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.timeRemaining, 0)
      }

      func testExpiredSession_labelColorIsRed() {
          mock.mockDate = Date(timeIntervalSinceNow: -6 * 3600)
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.labelColor, Color.red)
      }

      // MARK: Session duration from UserDefaults

      func testCustomSessionDuration_3Hours() {
          UserDefaults.standard.set(3, forKey: "sessionDurationHours")
          // mtime 1h 27m 30s ago, 3h duration → 5550 s remaining = 1h 32m 30s → "1:32"
          // +30 s offset ensures remaining is never on an exact minute boundary
          mock.mockDate = Date(timeIntervalSinceNow: -(1 * 3600 + 27 * 60 + 30))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .valid)
          XCTAssertEqual(monitor.labelText, "1:32")
      }

      func testDefaultDuration_whenKeyAbsent_is5Hours() {
          // No key → defaults to 5h
          // mtime 4h 19m 30s ago → 2430 s remaining = 40m 30s → "0:40"
          // +30 s offset ensures remaining is never on an exact minute boundary
          mock.mockDate = Date(timeIntervalSinceNow: -(4 * 3600 + 19 * 60 + 30))
          let monitor = SessionMonitor(fileProvider: mock)
          XCTAssertEqual(monitor.credentialsState, .valid)
          XCTAssertEqual(monitor.labelText, "0:40")
      }
  }
  ```

- [ ] **Step 2: Run tests — verify they fail**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet 2>&1 | grep -E 'error:|BUILD FAILED'
  ```
  Expected: Build error — `SessionMonitor` not defined yet.

- [ ] **Step 3: Create `SessionMonitor.swift`**

  ```swift
  // GcloudSessionWatch/SessionMonitor.swift
  import Foundation
  import SwiftUI
  import UserNotifications

  // MARK: - State

  enum CredentialsState: Equatable {
      case missing    // file not found or unreadable
      case valid      // timeRemaining > 600 s
      case warning    // 0 < timeRemaining <= 600 s (≤ 10 minutes)
      case expired    // timeRemaining <= 0
  }

  // MARK: - Monitor

  @MainActor
  final class SessionMonitor: ObservableObject {

      @Published private(set) var credentialsState: CredentialsState = .missing
      @Published private(set) var timeRemaining: TimeInterval = 0

      // Not @Published — the view does not observe this directly.
      private var sessionDurationSeconds: TimeInterval

      // Accessed in deinit. In Swift 5.9 deinit runs on the main actor for
      // @MainActor classes. If migrating to Swift 6 strict concurrency, mark
      // these nonisolated(unsafe).
      private var timer: Timer?
      private var defaultsObserver: NSObjectProtocol?

      private let fileProvider: FileTimestampProvider
      private let credentialsPath: String

      private static let notificationID = "gcloud-session-expiry"
      private static let warningThreshold: TimeInterval = 600 // 10 minutes

      init(
          fileProvider: FileTimestampProvider = LiveFileTimestampProvider(),
          credentialsPath: String = (NSHomeDirectory() as NSString)
              .appendingPathComponent(".config/gcloud/application_default_credentials.json")
      ) {
          self.fileProvider = fileProvider
          self.credentialsPath = credentialsPath
          let hours = UserDefaults.standard.integer(forKey: "sessionDurationHours")
          self.sessionDurationSeconds = TimeInterval(hours == 0 ? 5 : hours) * 3600

          tick()          // populate UI immediately — no blank state on launch
          startTimer()
          observeDefaults()
          requestNotificationPermission()
      }

      deinit {
          timer?.invalidate()
          if let observer = defaultsObserver {
              NotificationCenter.default.removeObserver(observer)
          }
      }

      // MARK: - View helpers

      var labelText: String {
          switch credentialsState {
          case .missing:  return "--:--"
          case .expired:  return "EXPIRED"
          case .valid, .warning:
              let h = Int(timeRemaining) / 3600
              let m = (Int(timeRemaining) % 3600) / 60
              return "\(h):\(String(format: "%02d", m))"
          }
      }

      var labelColor: Color {
          switch credentialsState {
          case .missing, .valid: return .primary
          case .warning:         return .orange
          case .expired:         return .red
          }
      }
  }

  // MARK: - Private

  private extension SessionMonitor {

      func startTimer() {
          // Timer is scheduled on the main run loop (called from @MainActor init).
          // MainActor.assumeIsolated synchronously asserts we are on the main actor
          // and calls tick() without async indirection.
          timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
              MainActor.assumeIsolated { self?.tick() }
          }
      }

      func tick() {
          guard let mtime = fileProvider.modificationDate(at: credentialsPath) else {
              credentialsState = .missing
              timeRemaining = 0
              cancelNotification()
              return
          }

          let expiry = mtime.addingTimeInterval(sessionDurationSeconds)
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
          UNUserNotificationCenter.current()
              .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
      }

      func requestNotificationPermission() {
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
  ```

- [ ] **Step 4: Run tests — verify they pass**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet 2>&1 | grep -E 'Test Case|passed|failed|BUILD'
  ```
  Expected: All test cases `passed`. `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

  ```bash
  git add GcloudSessionWatch/SessionMonitor.swift GcloudSessionWatchTests/SessionMonitorTests.swift
  git commit -m "feat: add SessionMonitor with CredentialsState, label logic, and unit tests"
  ```

---

## Task 4: SettingsView

**Files:**
- Create: `GcloudSessionWatch/SettingsView.swift`

- [ ] **Step 1: Create `SettingsView.swift`**

  ```swift
  // GcloudSessionWatch/SettingsView.swift
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
  ```

- [ ] **Step 2: Build to verify**

  ```bash
  xcodebuild build -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add GcloudSessionWatch/SettingsView.swift
  git commit -m "feat: add SettingsView with session duration stepper (1–24 hours)"
  ```

---

## Task 5: App entry point

**Files:**
- Modify: `GcloudSessionWatch/GcloudSessionWatchApp.swift`

**Important:** `MenuBarExtra` must appear **before** the `Settings` scene in the `body`. If reversed, `SettingsLink` silently fails to open the Settings window.

`@StateObject` evaluates `SessionMonitor()` lazily on first render. SwiftUI performs first render on the main thread, so calling the `@MainActor init` from `@StateObject` is safe.

- [ ] **Step 1: Replace `GcloudSessionWatchApp.swift`**

  ```swift
  // GcloudSessionWatch/GcloudSessionWatchApp.swift
  import SwiftUI

  @main
  struct GcloudSessionWatchApp: App {
      // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
      // Safe to call the @MainActor init from here.
      @StateObject private var monitor = SessionMonitor()

      var body: some Scene {
          // MenuBarExtra MUST come before Settings — SettingsLink relies on this ordering.
          MenuBarExtra {
              SettingsLink { Text("Settings...") }
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
  ```

- [ ] **Step 2: Build and verify**

  ```bash
  xcodebuild build -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run full test suite**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -quiet 2>&1 | grep -E 'Test Case|passed|failed|BUILD'
  ```
  Expected: All tests pass.

- [ ] **Step 4: Manual smoke test**

  Run the app from Xcode (⌘R). Verify:
  - No Dock icon appears (`LSUIElement` working)
  - Menu bar shows a time label (e.g. `4:32`) or `--:--` if credentials file missing
  - Clicking it shows "Settings..." and "Quit"
  - "Settings..." opens a window with a stepper (1–24 hours, default 5)
  - Changing the stepper value updates the countdown (visible within 30 s, or relaunch)
  - macOS prompts for notification permission on first launch
  - **Colour check (dark mode):** Set system appearance to Dark (System Settings → Appearance). With ≤ 10 min remaining the label turns orange; when expired it turns red.

- [ ] **Step 5: Final commit**

  ```bash
  git add GcloudSessionWatch/GcloudSessionWatchApp.swift
  git commit -m "feat: wire App entry point — MenuBarExtra, Settings scene, SessionMonitor"
  ```

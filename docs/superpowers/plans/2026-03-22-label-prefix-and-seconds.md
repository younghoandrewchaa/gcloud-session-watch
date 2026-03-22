# Label Prefix and Seconds Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prefix the menu bar label with "G " (e.g. "G 4:32") and show a live H:MM:SS countdown at the top of the dropdown menu.

**Architecture:** `SessionMonitor` gains a "G "-prefixed `labelText`, a `detailedTimeText` (H:MM:SS / EXPIRED / --:--:--), and a 1-second `displayTimer` that updates `timeRemaining` each second from a cached expiry date (avoiding repeated file I/O). `GcloudSessionWatchApp` displays `detailedTimeText` as a non-interactive header at the top of the menu. The 30-second file-polling timer is unchanged.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest, macOS 13+

---

## File Map

| File | Change |
|---|---|
| `GcloudSessionWatch/SessionMonitor.swift` | Add "G " prefix to `labelText`; add `expiryDate: Date?`; add `displayTimer`; add `startDisplayTimer()`, `refreshDisplay()`; add `detailedTimeText` |
| `GcloudSessionWatchTests/SessionMonitorTests.swift` | Update 6 `labelText` assertions; add 4 `detailedTimeText` tests |
| `GcloudSessionWatch/GcloudSessionWatchApp.swift` | Add `Text(monitor.detailedTimeText)` + `Divider()` at top of dropdown |

---

## Task 1: "G " prefix on the menu bar label

**Files:**
- Modify: `GcloudSessionWatch/SessionMonitor.swift` (`labelText` computed property)
- Test: `GcloudSessionWatchTests/SessionMonitorTests.swift`

The `labelText` property drives the menu bar icon text. Prefix every case with "G ".

- [ ] **Step 1: Update the 6 failing test assertions**

  In `GcloudSessionWatchTests/SessionMonitorTests.swift`, change every expected `labelText` value:

  | Test | Old expected | New expected |
  |---|---|---|
  | `testMissingFile_labelText` | `"--:--"` | `"G --:--"` |
  | `testValidSession_labelFormat` | `"3:32"` | `"G 3:32"` |
  | `testValidSession_minutesPaddedToTwoDigits` | `"0:57"` | `"G 0:57"` |
  | `testExpiredSession_labelText` | `"EXPIRED"` | `"G EXPIRED"` |
  | `testCustomSessionDuration_3Hours` | `"1:32"` | `"G 1:32"` |
  | `testDefaultDuration_whenKeyAbsent_is5Hours` | `"0:40"` | `"G 0:40"` |

- [ ] **Step 2: Run tests to confirm they now fail**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 \
    | grep -E "labelText|labelFormat|minutesPadded|EXPIRED|Custom|Default"
  ```
  Expected: 6 test cases fail with assertion mismatch.

- [ ] **Step 3: Update `labelText` in `SessionMonitor.swift`**

  Replace the `labelText` computed property (currently around line 59):

  ```swift
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
  ```

- [ ] **Step 4: Run tests — verify all 16 pass**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 \
    | grep -E "Executed|SUCCEEDED|FAILED"
  ```
  Expected: `Executed 16 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

  ```bash
  git add GcloudSessionWatch/SessionMonitor.swift \
          GcloudSessionWatchTests/SessionMonitorTests.swift
  git commit -m "feat: prefix menu bar label with 'G '"
  ```

---

## Task 2: Seconds countdown in dropdown menu

**Files:**
- Modify: `GcloudSessionWatch/SessionMonitor.swift`
- Modify: `GcloudSessionWatchTests/SessionMonitorTests.swift`
- Modify: `GcloudSessionWatch/GcloudSessionWatchApp.swift`

`detailedTimeText` shows H:MM:SS (no "G " prefix — this is the expanded in-menu display, not the compact bar label). A 1-second `displayTimer` recalculates `timeRemaining` from a cached expiry date each second, so the dropdown ticks in real time without re-reading the file.

### 2a — Add `detailedTimeText` tests

- [ ] **Step 1: Write 4 failing tests**

  Append to `GcloudSessionWatchTests/SessionMonitorTests.swift` (inside `SessionMonitorTests`):

  ```swift
  // MARK: Detailed time text (H:MM:SS)

  func testDetailedTimeText_missing() {
      mock.mockDate = nil
      let monitor = SessionMonitor(fileProvider: mock)
      XCTAssertEqual(monitor.detailedTimeText, "--:--:--")
  }

  func testDetailedTimeText_expired() {
      mock.mockDate = Date(timeIntervalSinceNow: -6 * 3600)
      let monitor = SessionMonitor(fileProvider: mock)
      XCTAssertEqual(monitor.detailedTimeText, "EXPIRED")
  }

  func testDetailedTimeText_showsSeconds() {
      // mtime 5250 s ago (1h 27m 30s), default 5h → 12750 s = 3h 32m 30s remaining
      mock.mockDate = Date(timeIntervalSinceNow: -5250)
      let monitor = SessionMonitor(fileProvider: mock)
      XCTAssertEqual(monitor.detailedTimeText, "3:32:30")
  }

  func testDetailedTimeText_minutesPaddedAndSecondsShown() {
      // mtime 14550 s ago (4h 2m 30s), default 5h → 3450 s = 57m 30s remaining
      mock.mockDate = Date(timeIntervalSinceNow: -14550)
      let monitor = SessionMonitor(fileProvider: mock)
      XCTAssertEqual(monitor.detailedTimeText, "0:57:30")
  }
  ```

- [ ] **Step 2: Run to confirm these 4 tests fail**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 \
    | grep -E "detailedTimeText|FAILED"
  ```
  Expected: 4 failures — `detailedTimeText` not yet defined.

### 2b — Implement `expiryDate`, 1s `displayTimer`, and `detailedTimeText`

- [ ] **Step 3: Add `expiryDate` and `displayTimer` stored properties to `SessionMonitor`**

  After the existing `private var timer: Timer?` line, add:

  ```swift
  private var displayTimer: Timer?
  private var expiryDate: Date?
  ```

- [ ] **Step 4: Cache `expiryDate` inside `tick()`**

  In `tick()`, after `let expiry = mtime.addingTimeInterval(sessionDurationSeconds)`, add:

  ```swift
  self.expiryDate = expiry
  ```

  The full updated `tick()` (for reference):

  ```swift
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
  ```

- [ ] **Step 5: Add `startDisplayTimer()` and `refreshDisplay()` to the private extension**

  Inside `private extension SessionMonitor`, add after `startTimer()`:

  ```swift
  func startDisplayTimer() {
      displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
          MainActor.assumeIsolated { self?.refreshDisplay() }
      }
  }

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
  ```

- [ ] **Step 6: Call `startDisplayTimer()` from `init` and invalidate in `deinit`**

  In `init`, after `startTimer()`:
  ```swift
  startDisplayTimer()
  ```

  In `deinit`, after `timer?.invalidate()`:
  ```swift
  displayTimer?.invalidate()
  ```

- [ ] **Step 7: Add `detailedTimeText` computed property**

  After `labelText`, add:

  ```swift
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
  ```

- [ ] **Step 8: Run all tests — verify all 20 pass**

  ```bash
  xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 \
    | grep -E "Executed|SUCCEEDED|FAILED"
  ```
  Expected: `Executed 20 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 9: Commit**

  ```bash
  git add GcloudSessionWatch/SessionMonitor.swift \
          GcloudSessionWatchTests/SessionMonitorTests.swift
  git commit -m "feat: add detailedTimeText (H:MM:SS) and 1s display timer"
  ```

### 2c — Show `detailedTimeText` in the dropdown menu

- [ ] **Step 10: Update `GcloudSessionWatchApp.swift`**

  Replace the `MenuBarExtra { ... }` block content:

  ```swift
  MenuBarExtra {
      Text(monitor.detailedTimeText)
          .foregroundStyle(monitor.labelColor)
      Divider()
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
  ```

- [ ] **Step 11: Build and verify**

  ```bash
  xcodebuild build -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 \
    | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 12: Commit**

  ```bash
  git add GcloudSessionWatch/GcloudSessionWatchApp.swift
  git commit -m "feat: show live H:MM:SS countdown at top of dropdown menu"
  ```

---

## Manual smoke test

Run from Xcode (⌘R):
- Menu bar shows `G 4:32` (or `G --:--` if no credentials file)
- Clicking the menu bar item shows a dropdown with `4:32:17` (or similar) coloured to match state
- Wait ~2 seconds — the seconds counter in the dropdown decrements
- Settings... and Quit still work

# Icon-Only Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the menu bar label (icon + time text) with a single colored icon — green when valid, amber when in warning state, red when expired or missing.

**Architecture:** Add an `iconColor` computed property to `SessionMonitor` that returns `.green` for active sessions and `.red` for expired/missing ones. Update the menu bar label in `GcloudSessionWatchApp` to show only the icon using this color. The existing dropdown menu content is unchanged.

**Tech Stack:** Swift, SwiftUI, macOS MenuBarExtra

---

## File Map

| File | Change |
|------|--------|
| `GcloudSessionWatch/SessionMonitor.swift` | Add `iconColor` computed property |
| `GcloudSessionWatch/GcloudSessionWatchApp.swift` | Simplify menu bar label to icon-only |
| `GcloudSessionWatchTests/SessionMonitorTests.swift` | Add tests for `iconColor` |

---

### Task 1: Add `iconColor` to SessionMonitor

**Files:**
- Modify: `GcloudSessionWatch/SessionMonitor.swift:89-95` (after the existing `labelColor` property)
- Test: `GcloudSessionWatchTests/SessionMonitorTests.swift`

- [ ] **Step 1: Write failing tests for `iconColor`**

Add these four test cases after the existing `testExpiredSession_labelColorIsRed` test in `SessionMonitorTests.swift`:

```swift
// MARK: Icon color

func testIconColor_missing_isRed() {
    mock.mockDate = nil
    let monitor = SessionMonitor(fileProvider: mock)
    XCTAssertEqual(monitor.iconColor, Color.red)
}

func testIconColor_valid_isGreen() {
    mock.mockDate = Date(timeIntervalSinceNow: -3600) // 1h ago, 4h remaining
    let monitor = SessionMonitor(fileProvider: mock)
    XCTAssertEqual(monitor.iconColor, Color.green)
}

func testIconColor_warning_isOrange() {
    // 9 minutes remaining — warning state
    mock.mockDate = Date(timeIntervalSinceNow: -(5 * 3600 - 540))
    let monitor = SessionMonitor(fileProvider: mock)
    XCTAssertEqual(monitor.iconColor, Color.orange)
}

func testIconColor_expired_isRed() {
    mock.mockDate = Date(timeIntervalSinceNow: -6 * 3600) // expired 1h ago
    let monitor = SessionMonitor(fileProvider: mock)
    XCTAssertEqual(monitor.iconColor, Color.red)
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```
xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 | grep -E "(FAIL|error:|iconColor)"
```

Expected: compiler error — `iconColor` does not exist yet.

- [ ] **Step 3: Add `iconColor` to `SessionMonitor.swift`**

Add this computed property directly after the closing brace of `labelColor` (after line 95):

```swift
var iconColor: Color {
    switch credentialsState {
    case .missing, .expired: return .red
    case .warning: return .orange
    case .valid: return .green
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```
xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 | grep -E "(passed|failed|iconColor)"
```

Expected: all 4 new icon color tests pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add GcloudSessionWatch/SessionMonitor.swift GcloudSessionWatchTests/SessionMonitorTests.swift
git commit -m "feat: add iconColor computed property to SessionMonitor"
```

---

### Task 2: Simplify the menu bar label to icon-only

**Files:**
- Modify: `GcloudSessionWatch/GcloudSessionWatchApp.swift:30-36`

- [ ] **Step 1: Replace the label block**

Current code in `GcloudSessionWatchApp.swift` (lines 30–36):

```swift
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "key.icloud.fill")
                Text(monitor.labelText)
            }
            .foregroundStyle(monitor.labelColor)
        }
```

Replace with:

```swift
        } label: {
            Image(systemName: "key.icloud.fill")
                .foregroundStyle(monitor.iconColor)
        }
```

- [ ] **Step 2: Build to confirm it compiles**

```
xcodebuild build -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 | grep -E "(BUILD|error:)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Run full test suite**

```
xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 | grep -E "(passed|failed)"
```

Expected: all tests pass.

- [ ] **Step 4: Manual verification**

Build and run the app. Confirm:
- Menu bar shows only the key icon (no time text)
- Icon is green when session is valid
- Icon is amber/orange when session is in warning state (≤ 10 minutes remaining)
- Icon is red when session is expired or credentials file is missing
- Clicking the icon still opens the dropdown with detailed time and Settings/Quit

- [ ] **Step 5: Commit**

```bash
git add GcloudSessionWatch/GcloudSessionWatchApp.swift
git commit -m "feat: show icon-only in menu bar with color indicating session state"
```

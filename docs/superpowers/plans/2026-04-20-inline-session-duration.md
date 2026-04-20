# Inline Session Duration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the separate Settings window and move the Session Duration stepper inline into the MenuBarExtra popover.

**Architecture:** `GcloudSessionWatchApp.swift` gains an `@AppStorage` binding for `sessionDurationHours` and renders a `Stepper` directly in the `MenuBarExtra` content block. The `Settings { }` scene and `SettingsView.swift` are deleted.

**Tech Stack:** SwiftUI, AppStorage, MenuBarExtra

---

### File Map

| Action | File |
|--------|------|
| Modify | `GcloudSessionWatch/GcloudSessionWatchApp.swift` |
| Delete | `GcloudSessionWatch/SettingsView.swift` |

---

### Task 1: Inline the Stepper and remove the Settings scene

**Files:**
- Modify: `GcloudSessionWatch/GcloudSessionWatchApp.swift`

- [ ] **Step 1: Open `GcloudSessionWatchApp.swift` and replace its contents with the following**

```swift
import SwiftUI

@main
struct GcloudSessionWatchApp: App {
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
```

Key changes from the original:
- Added `@AppStorage("sessionDurationHours") private var sessionDurationHours: Int = 4`
- Replaced `SettingsLink { Text("Settings...") }` + its `Divider()` with a `Stepper`
- Removed `Settings { SettingsView() }` scene entirely
- Widened frame from `160` to `200` to give the Stepper comfortable room

- [ ] **Step 2: Build and verify it compiles**

```
⌘B in Xcode  (or: xcodebuild -scheme GcloudSessionWatch build)
```

Expected: build succeeds. `SettingsView` will show an "unused type" warning — that's expected and resolved in the next task.

- [ ] **Step 3: Run the app and smoke-test**

- Click the menu bar icon — the popover should show the status text, a Stepper labelled "Duration: Nh", and Quit
- Click ▲/▼ on the stepper — the label should update and the value should persist after quitting and relaunching (stored in UserDefaults via AppStorage)
- Confirm there is no longer a "Settings…" menu item

- [ ] **Step 4: Commit**

```bash
git add GcloudSessionWatch/GcloudSessionWatchApp.swift
git commit -m "feat: inline session duration stepper into menu bar popover"
```

---

### Task 2: Delete SettingsView.swift

**Files:**
- Delete: `GcloudSessionWatch/SettingsView.swift`

- [ ] **Step 1: Delete the file**

```bash
rm GcloudSessionWatch/SettingsView.swift
```

Then in Xcode: if the file still appears in the navigator with a red icon, right-click → "Delete" → "Remove Reference" (the file is already gone from disk).

- [ ] **Step 2: Build to confirm no remaining references**

```
⌘B in Xcode
```

Expected: clean build, zero errors.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove SettingsView now that settings are inline"
```

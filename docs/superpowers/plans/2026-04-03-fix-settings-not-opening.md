# Fix Settings Not Opening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the Settings window opens reliably every time the "Settings..." menu item is clicked, not just on first launch.

**Architecture:** Replace the `#available` conditional in `MenuBarExtra` with a single `SettingsLink` call by raising the deployment target to macOS 14.0. This eliminates the `NSApp.sendAction` fallback (which can silently fail) and the stale-after-first-click bug documented for `@Environment(\.openSettings)`.

**Tech Stack:** SwiftUI, macOS 14.0+, `SettingsLink` (built-in SwiftUI component)

---

## Background

The app targets macOS 13.0. The current `GcloudSessionWatchApp.swift` already uses `SettingsLink` behind an `#available(macOS 14.0, *)` guard, with an `NSApp.sendAction(Selector(("showSettingsWindow:")))` fallback for macOS 13. The macOS 13 path is prone to the same silent-failure bug described in the fix note. The cleanest resolution is to raise the minimum deployment target to 14.0 and remove the conditional entirely.

---

## Files

| File | Change |
|------|--------|
| `GcloudSessionWatch.xcodeproj/project.pbxproj` | Raise `MACOSX_DEPLOYMENT_TARGET` from `13.0` to `14.0` (4 occurrences) |
| `GcloudSessionWatch/GcloudSessionWatchApp.swift` | Remove `#available` conditional; use bare `SettingsLink` |

---

### Task 1: Raise the deployment target to macOS 14.0

**Files:**
- Modify: `GcloudSessionWatch.xcodeproj/project.pbxproj` (lines containing `MACOSX_DEPLOYMENT_TARGET = 13.0;`)

- [ ] **Step 1: Confirm the four occurrences of the deployment target**

```bash
grep -n "MACOSX_DEPLOYMENT_TARGET" GcloudSessionWatch.xcodeproj/project.pbxproj
```

Expected output (line numbers may differ):
```
285:				MACOSX_DEPLOYMENT_TARGET = 13.0;
345:				MACOSX_DEPLOYMENT_TARGET = 13.0;
431:				MACOSX_DEPLOYMENT_TARGET = 13.0;
449:				MACOSX_DEPLOYMENT_TARGET = 13.0;
```

- [ ] **Step 2: Replace all occurrences with 14.0**

In `GcloudSessionWatch.xcodeproj/project.pbxproj`, replace every instance of:
```
MACOSX_DEPLOYMENT_TARGET = 13.0;
```
with:
```
MACOSX_DEPLOYMENT_TARGET = 14.0;
```
(Use "Replace All" in Xcode or a text editor — there are 4 occurrences.)

- [ ] **Step 3: Verify the change**

```bash
grep -n "MACOSX_DEPLOYMENT_TARGET" GcloudSessionWatch.xcodeproj/project.pbxproj
```

Expected: all 4 lines now show `14.0`.

- [ ] **Step 4: Commit**

```bash
git add GcloudSessionWatch.xcodeproj/project.pbxproj
git commit -m "chore: raise minimum deployment target to macOS 14.0"
```

---

### Task 2: Simplify MenuBarExtra to use SettingsLink unconditionally

**Files:**
- Modify: `GcloudSessionWatch/GcloudSessionWatchApp.swift`

**Current code (lines 17–24):**
```swift
if #available(macOS 14.0, *) {
    SettingsLink { Text("Settings...") }
} else {
    Button("Settings...") {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
```

- [ ] **Step 1: Replace the conditional with a bare SettingsLink**

Replace the `if #available` block above with:
```swift
SettingsLink { Text("Settings...") }
```

Also remove the now-redundant comment on line 10:
```swift
// MenuBarExtra MUST come before Settings — SettingsLink relies on this ordering.
```
(Keep the ordering itself — `MenuBarExtra` before `Settings` — just remove the comment if you prefer clean code. The ordering constraint remains real.)

The full updated `body` in `GcloudSessionWatchApp.swift` should look like:

```swift
var body: some Scene {
    MenuBarExtra {
        VStack(spacing: 8) {
            Text(monitor.detailedTimeText)
                .foregroundStyle(monitor.labelColor)
                .font(.system(.body, design: .monospaced))
            Divider()
            SettingsLink { Text("Settings...") }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .frame(width: 160)
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

    Settings {
        SettingsView()
    }
}
```

- [ ] **Step 2: Build to confirm no compilation errors**

In Xcode: **Product → Build** (⌘B), or from the terminal:

```bash
xcodebuild -project GcloudSessionWatch.xcodeproj \
           -scheme GcloudSessionWatch \
           -destination 'platform=macOS' \
           build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual smoke test**

1. Run the app (⌘R in Xcode or open the built `.app`).
2. Click the menu bar icon → click **Settings...** → Settings window opens. ✓
3. Close the Settings window.
4. Click the menu bar icon again → click **Settings...** → Settings window opens again. ✓ (This is the regression that was broken before.)
5. Repeat step 4 two more times to confirm it is reliable.

- [ ] **Step 4: Commit**

```bash
git add GcloudSessionWatch/GcloudSessionWatchApp.swift
git commit -m "fix: use SettingsLink unconditionally to fix settings not reopening"
```

# gcloud-session-watch — Design Spec

**Date:** 2026-03-21
**Status:** Approved

## Overview

A macOS menu bar app written in Swift that reads the modification timestamp of
`~/.config/gcloud/application_default_credentials.json` and displays how much
time remains before the gcloud Application Default Credentials session expires.
The countdown is configurable to match different organisations' session
durations. A macOS notification fires when the session expires.

## Requirements

- macOS 13 Ventura or later
- Swift, SwiftUI — no third-party dependencies
- Project location: `~/github/gcloud-session-watch`
- App Sandbox: **disabled** (simpler for a personal tool reading arbitrary paths)
- `UserNotifications.framework` must be linked
- Bundle identifier: `com.gcloud-session-watch` (stable value required for
  notification delivery)
- `LSUIElement = YES` in `Info.plist` — app runs as a pure menu bar agent
  with no Dock icon

## Architecture

Three components:

| Component | Role |
|---|---|
| `GcloudSessionWatchApp` | SwiftUI `App` entry point; owns `MenuBarExtra` and `Settings` scene |
| `SessionMonitor` | `ObservableObject`; reads file mtime, computes time remaining, manages timer and notification |
| `SettingsView` | SwiftUI `Settings` scene; lets the user configure session duration |

### `MenuBarExtra` style

Use `.menuBarExtraStyle(.menu)`, which renders a native `NSMenu`-style
dropdown. This style requires the dropdown content to be a list of
`Button`s (for "Settings..." and "Quit") and a `SettingsLink` for opening
the `Settings` scene. The label (always-visible menu bar text) is provided
via the `label:` closure:

```swift
MenuBarExtra {
    SettingsLink { Text("Settings...") }
    Divider()
    Button("Quit") { NSApplication.shared.terminate(nil) }
} label: {
    Text(monitor.labelText)
        .foregroundStyle(monitor.labelColor)
}
.menuBarExtraStyle(.menu)
```

**Note on colour:** `.foregroundStyle` on the `MenuBarExtra` `label:` closure
renders coloured text in dark mode (the standard macOS menu bar appearance).
In light mode, macOS may override the colour and render the label in the
system template colour. This is a platform limitation — colour is best-effort
and most visible in dark mode. No AppKit fallback is needed for this tool.

### SessionMonitor — State

```swift
enum CredentialsState {
    case missing          // file not found or unreadable
    case valid            // timeRemaining > 600 s
    case warning          // 0 < timeRemaining <= 600 s (≤ 10 minutes)
    case expired          // timeRemaining <= 0
}
```

The 10-minute (600 s) warning threshold is intentionally fixed and not
user-configurable.

Published properties (drive the view layer):

- `credentialsState: CredentialsState`
- `timeRemaining: TimeInterval` — seconds until expiry; 0 when missing/expired

Internal (not `@Published`; view does not observe directly):

- `sessionDurationSeconds: TimeInterval` — derived from `UserDefaults`

The `credentialsState` enum is the single source of truth for the view layer.
Flag precedence is unambiguous: `.expired` takes priority over `.warning`
because the two ranges are mutually exclusive by definition.

### SessionMonitor — Timer

- A `Timer` is started immediately on `init` and fires every 30 seconds.
- The first tick fires **immediately** (synchronously on init) so the UI is
  populated on launch with no blank/zero state.
- The timer runs for the lifetime of the app. No pause/resume logic is needed
  (macOS menu bar apps stay resident continuously).

### SessionMonitor — Settings observation

`SessionMonitor` observes `NotificationCenter` for
`UserDefaults.didChangeNotification`. On receipt, it reads the new
`sessionDurationHours` value and **bails out early if unchanged** (comparing
against the current `sessionDurationSeconds`). This prevents excessive
`UNUserNotificationCenter` cancel/schedule calls when the stepper fires
multiple `UserDefaults` writes per user interaction.

```swift
NotificationCenter.default.addObserver(
    forName: UserDefaults.didChangeNotification, ...) { [weak self] _ in
    let newSeconds = TimeInterval(
        UserDefaults.standard.integer(forKey: "sessionDurationHours")) * 3600
    guard newSeconds != self?.sessionDurationSeconds else { return }
    self?.sessionDurationSeconds = newSeconds
    self?.rescheduleNotification()
}
```

### SessionMonitor — Notification

Notification identifier constant: `"gcloud-session-expiry"` (single, stable ID).

On each timer tick:

1. Read file mtime. If changed since last tick, record new mtime as session start.
2. Compute expiry timestamp = mtime + `sessionDurationSeconds`.
3. Cancel any pending notification with id `"gcloud-session-expiry"`.
4. If expiry is in the future, schedule a new `UNUserNotificationRequest` at
   that date with id `"gcloud-session-expiry"`.
5. If expiry is in the past, do not schedule (platform would silently drop it;
   skip explicitly to avoid ambiguity).

On launch, the same logic runs on the first (immediate) tick, which also
removes any stale notification left in the queue from a previous app session.

Permission is requested on first launch via
`UNUserNotificationCenter.current().requestAuthorization`. If denied, the app
continues displaying the countdown silently.

## Data Flow

```
~/.config/gcloud/application_default_credentials.json
        │
        │  file mtime (polled every 30s, first tick immediate on init)
        ▼
  SessionMonitor
        │
        ├── credentialsState = missing | valid | warning | expired
        ├── timeRemaining = max(0, (mtime + sessionDurationSeconds) - now)
        │
        ├── cancels + reschedules UNUserNotification at expiry
        │   identifier: "gcloud-session-expiry"
        │
        └── publishes credentialsState + timeRemaining
                │
                └── MenuBarExtra label  →  "4:32" / orange / "EXPIRED" / "--:--"
                    (notification delivered by system at expiry time)
```

Settings changes flow separately:

```
SettingsView (@AppStorage) → UserDefaults → UserDefaults.didChangeNotification
    → SessionMonitor (guards: bail if unchanged) → rescheduleNotification()
```

## Persistence

`UserDefaults` key: `sessionDurationHours` — stored as an `Int` (number of
hours, e.g. `5`).

`SessionMonitor` reads it as:
```swift
let hours = UserDefaults.standard.integer(forKey: "sessionDurationHours")
sessionDurationSeconds = TimeInterval(hours == 0 ? 5 : hours) * 3600
```

The default of 5 hours is applied when the key is absent (integer returns 0).

`SettingsView` uses `@AppStorage("sessionDurationHours") var sessionDurationHours: Int = 5`.

## UI

### Menu bar label

| `credentialsState` | Display | Colour (`.foregroundStyle`) |
|---|---|---|
| `.valid` | `4:32` | `.primary` |
| `.warning` | `0:07` | `.orange` |
| `.expired` | `EXPIRED` | `.red` |
| `.missing` | `--:--` | `.primary` |

Format for time: `"\(hours):\(String(format: "%02d", minutes))"` where
`hours = Int(timeRemaining) / 3600`, `minutes = (Int(timeRemaining) % 3600) / 60`.

Colour is most visible in dark mode (system default for menu bar). In light
mode macOS may render in the system template colour — acceptable limitation.

### Dropdown menu

Uses `.menuBarExtraStyle(.menu)` — native `NSMenu` appearance:

```
┌─────────────────┐
│  Settings...    │
│  ──────────     │
│  Quit           │
└─────────────────┘
```

"Settings..." uses `SettingsLink` to open the SwiftUI `Settings` scene.
"Quit" calls `NSApplication.shared.terminate(nil)`.

### Settings window

A SwiftUI `Settings` scene with one control:

```
Session Duration
[ 5 ] hours        (stepper: integers 1–24, default 5)
```

### Notification (on expiry)

- **Title:** `gcloud session expired`
- **Body:** `Run gcloud auth application-default login to refresh.`
- **Identifier:** `"gcloud-session-expiry"`
- Delivered via `UNUserNotificationCenter` scheduled at the computed expiry time.
- Not fired if expiry is already in the past at scheduling time.

## Error Handling & Edge Cases

| Scenario | Behaviour |
|---|---|
| Credentials file missing | `credentialsState = .missing`; shows `--:--`; no notification scheduled |
| File mtime changes (new login) | Resets countdown; cancels `"gcloud-session-expiry"`; schedules new notification |
| Session duration changed in Settings | `SessionMonitor` receives `UserDefaults.didChangeNotification`; bails if unchanged; otherwise updates and reschedules |
| Notification permission denied | Countdown still shown; scheduling call is made but silently fails |
| App launched after session already expired | First tick fires immediately; `credentialsState = .expired`; shows `EXPIRED`; no notification scheduled (expiry is in the past) |
| File unreadable (permissions error) | Treated as missing — `credentialsState = .missing`; shows `--:--` |
| Stale notification from previous app session | Cancelled on first tick by the standard cancel-then-reschedule logic |
| `timeRemaining == 0` exactly | `credentialsState = .expired`; enum ranges are mutually exclusive |
| User edits stepper rapidly | `UserDefaults.didChangeNotification` fires multiple times; guard bails out unless value actually changed; reschedule called at most once per distinct value |

## Out of Scope

- Launch at login
- Multiple credential file paths
- Filesystem watcher (FSEvents) — polling is sufficient
- Any network calls
- Configurable warning threshold (fixed at 10 minutes)
- Light-mode colour fidelity (best-effort via `.foregroundStyle`)

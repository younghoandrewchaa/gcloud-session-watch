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

## Architecture

Three components:

| Component | Role |
|---|---|
| `GcloudSessionWatchApp` | SwiftUI `App` entry point; owns `MenuBarExtra` and `Settings` scene |
| `SessionMonitor` | `ObservableObject`; reads file mtime, computes time remaining, manages timer and notification |
| `SettingsView` | SwiftUI `Settings` scene; lets the user configure session duration |

### SessionMonitor

Core state managed by `SessionMonitor`:

- `sessionDuration: TimeInterval` — persisted in `UserDefaults` under `sessionDurationHours`, default 5 hours
- `timeRemaining: TimeInterval` — recomputed every 30 seconds from file mtime
- `isExpired: Bool` — derived: `timeRemaining <= 0`
- `isWarning: Bool` — derived: `0 < timeRemaining <= 600` (10 minutes)
- A `Timer` firing every 30 seconds
- Tracks last-seen mtime to detect new logins

## Data Flow

```
~/.config/gcloud/application_default_credentials.json
        │
        │  file mtime (polled every 30s)
        ▼
  SessionMonitor
        │
        ├── timeRemaining = (mtime + sessionDuration) - now
        │
        ├── schedules UNUserNotification at expiry time
        │   (cancels + reschedules whenever mtime changes)
        │
        └── publishes timeRemaining / isWarning / isExpired
                │
                ├── MenuBarExtra label  →  "4:32" (white / orange / red)
                │
                └── (notification fires at t=0 via UNUserNotificationCenter)
```

**Settings persistence:**
- `sessionDuration` stored in `UserDefaults` under `sessionDurationHours`
- `SettingsView` writes on change; `SessionMonitor` picks up new value and reschedules notification

**File watching:**
- No filesystem watcher — 30-second `Timer` poll is sufficient
- When mtime changes (new login detected), countdown resets and notification is rescheduled

## UI

### Menu bar label

| State | Display | Colour |
|---|---|---|
| > 10 minutes remaining | `4:32` | White (`labelColor`) |
| <= 10 minutes remaining | `0:07` | Orange |
| Expired | `EXPIRED` | Red |
| File missing / unreadable | `--:--` | White |

### Dropdown menu (on click)

```
┌─────────────────┐
│  Settings...    │
│  ──────────     │
│  Quit           │
└─────────────────┘
```

### Settings window

A single native preferences window with one control:

```
Session Duration
[ 5 ] hours        (stepper: integers 1–24, default 5)
```

### Notification (on expiry)

- **Title:** `gcloud session expired`
- **Body:** `Run gcloud auth application-default login to refresh.`
- Delivered via `UNUserNotificationCenter` scheduled at the computed expiry time
- Permission requested on first launch

## Error Handling & Edge Cases

| Scenario | Behaviour |
|---|---|
| Credentials file missing | Shows `--:--`; no notification scheduled |
| File mtime changes (new login) | Resets countdown; cancels old notification; schedules new one |
| Session duration changed in Settings | Notification rescheduled immediately |
| Notification permission denied | Countdown still shown; notification silently skipped |
| App launched after session already expired | Shows `EXPIRED` immediately; no notification |
| File unreadable (permissions error) | Treated as missing — shows `--:--` |

## Out of Scope

- Launch at login
- Multiple credential file paths
- Visual companion / browser UI
- Any network calls

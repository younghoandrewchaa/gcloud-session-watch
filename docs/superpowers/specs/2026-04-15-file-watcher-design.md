# File Watcher Design: Immediate Credentials Change Detection

**Date:** 2026-04-15
**Status:** Approved

## Problem

`SessionMonitor` polls `application_default_credentials.json` every 30 seconds using a `Timer`. When the user runs `gcloud auth application-default login`, the credentials file is overwritten immediately, but the menu bar icon can take up to 30 seconds to update. This design replaces the polling-only approach with event-driven file watching.

## Approach

Use `DispatchSourceFileSystemObject` (`DISPATCH_SOURCE_TYPE_VNODE`) to watch the credentials file directly. When a change is detected, `tick()` is called immediately. The existing 30-second timer remains as a safety-net fallback.

The file watcher targets the credentials file itself (not the parent directory) to avoid spurious events from other frequently-updated gcloud files (`access_tokens.db`, `credentials.db`, `logs/`, etc.).

## Architecture

A new `FileWatcher` class manages the `DispatchSourceFileSystemObject` lifecycle. It owns the file descriptor and dispatch source, and exposes `start()` and `stop()`. `SessionMonitor` holds a `FileWatcher` instance and passes `tick()` as the change callback.

## Components & Data Flow

### `FileWatcher`

- **Responsibility:** Watch a single file path; invoke a callback on any write or atomic-replace event.
- **Interface:** `start()`, `stop()`, init takes `path: String` and `onChange: () -> Void`.
- **Internals:**
  1. `start()` opens the file with `open(path, O_EVTONLY)` (read-only; does not prevent deletion or rename).
  2. Creates a `DispatchSource.makeFileSystemObjectSource` with event mask `.write | .delete`.
  3. On `.write` → invoke `onChange` callback.
  4. On `.delete` (covers atomic rename-into-place, which unlinks the original inode) → cancel source, close fd, schedule a 0.1s retry to re-open and re-attach, then invoke `onChange`.
  5. `stop()` cancels the source and closes the fd.

### `SessionMonitor` changes

- Adds a `FileWatcher` property initialised with `credentialsPath` and `{ [weak self] in self?.tick() }`.
- Calls `fileWatcher.start()` in `init`, alongside the existing `startTimer()`.
- After each `tick()`, if the state was previously `.missing` and the file now exists, calls `fileWatcher.start()` to attach the watcher (handles first-time login).
- Calls `fileWatcher.stop()` in `deinit`.

## Error Handling & Edge Cases

| Case | Behaviour |
|------|-----------|
| File missing at startup (`.missing` state) | `open()` fails; `start()` returns early without creating a source. Timer handles detection. `tick()` re-calls `start()` when the file appears. |
| Re-attach fails after delete (race) | 0.1s retry covers normal atomic-replace timing. If re-open still fails (file genuinely deleted), `FileWatcher` gives up; timer remains active as fallback. |
| `deinit` / `stop()` | Source is cancelled and fd is closed, mirroring existing timer invalidation. |

## Testing

Tests use an injected temp file path. Three test cases:

1. **Write event:** write to temp file → assert callback fires within 0.5s.
2. **Atomic replace:** rename a new file over the watched path → assert callback fires and a subsequent write also triggers (watcher re-attached).
3. **Missing file at startup:** point `FileWatcher` at a non-existent path → assert no crash and no callback.

`FileWatcher` uses real file I/O in tests (no mocking needed). The `isTestEnvironment` guard is not required here.

# File Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 30-second polling lag with a `DispatchSourceFileSystemObject` watcher on the credentials file so the menu bar icon updates the moment `gcloud auth application-default login` finishes.

**Architecture:** A new `FileWatcher` class (annotated `@MainActor`) opens the credentials file with `O_EVTONLY`, attaches a vnode-based dispatch source with `.write | .delete` event mask, and invokes a callback immediately. The `.delete` path handles gcloud's atomic rename-into-place by cancelling the old source and re-opening after 0.1 s. `SessionMonitor` holds a `FileWatcher` and starts it in `init`; `tick()` re-calls `start()` (idempotent) so the watcher attaches automatically after a first-time login from the `.missing` state. The 30-second timer remains as a safety-net fallback.

**Tech Stack:** Swift, GCD (`DispatchSource`), `O_EVTONLY` POSIX open, XCTest async expectations

---

## Task 1: FileWatcher stub + write-event test

**Files:**
- Create: `GcloudSessionWatch/FileWatcher.swift`
- Create: `GcloudSessionWatchTests/FileWatcherTests.swift`

- [ ] **Step 1: Create the FileWatcher stub**

Create `GcloudSessionWatch/FileWatcher.swift` with a minimal stub so the test file compiles:

```swift
import Foundation

@MainActor
final class FileWatcher {
    init(path: String, onChange: @escaping () -> Void) {}
    func start() {}
    func stop() {}
}
```

- [ ] **Step 2: Write the failing write-event test**

Create `GcloudSessionWatchTests/FileWatcherTests.swift`:

```swift
import XCTest
@testable import GcloudSessionWatch

@MainActor
final class FileWatcherTests: XCTestCase {

    private var tempDir: URL!
    private var watchedFile: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        watchedFile = tempDir.appendingPathComponent("credentials.json")
        try "initial".write(to: watchedFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func test_directWrite_firesOnChange() async throws {
        let exp = expectation(description: "onChange called on write")
        let watcher = FileWatcher(path: watchedFile.path) { exp.fulfill() }
        watcher.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            try? "updated".write(to: self.watchedFile, atomically: false, encoding: .utf8)
        }

        await fulfillment(of: [exp], timeout: 0.5)
        watcher.stop()
    }
}
```

- [ ] **Step 3: Run the test — verify it fails**

Run: `xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -only-testing:GcloudSessionWatchTests/FileWatcherTests/test_directWrite_firesOnChange 2>&1 | tail -20`

Expected: FAIL — callback never fires because `start()` is a stub.

- [ ] **Step 4: Implement FileWatcher — write-event detection**

Replace `GcloudSessionWatch/FileWatcher.swift` with the full implementation:

```swift
import Foundation

@MainActor
final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if src.data.contains(.delete) {
                    self.source?.cancel()
                    self.source = nil
                    self.onChange()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        MainActor.assumeIsolated { self.start() }
                    }
                } else {
                    self.onChange()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
```

- [ ] **Step 5: Run the test — verify it passes**

Run: `xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -only-testing:GcloudSessionWatchTests/FileWatcherTests/test_directWrite_firesOnChange 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add GcloudSessionWatch/FileWatcher.swift GcloudSessionWatchTests/FileWatcherTests.swift
git commit -m "feat: add FileWatcher with write-event detection"
```

---

## Task 2: Atomic replace (delete + re-attach)

**Files:**
- Modify: `GcloudSessionWatchTests/FileWatcherTests.swift` — add test
- No changes to `FileWatcher.swift` needed (`.delete` handling is already in Task 1 implementation)

- [ ] **Step 1: Add the atomic-replace test**

Append to `FileWatcherTests` in `GcloudSessionWatchTests/FileWatcherTests.swift`:

```swift
func test_atomicReplace_firesAndReattaches() async throws {
    var callCount = 0
    let exp1 = expectation(description: "onChange after atomic replace")
    let exp2 = expectation(description: "onChange after reattach write")

    let watcher = FileWatcher(path: watchedFile.path) {
        callCount += 1
        if callCount == 1 { exp1.fulfill() }
        if callCount == 2 { exp2.fulfill() }
    }
    watcher.start()

    // Atomic replace via POSIX rename (what gcloud does)
    let tmpFile = tempDir.appendingPathComponent("tmp.json")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        try? "replaced".write(to: tmpFile, atomically: false, encoding: .utf8)
        Darwin.rename(tmpFile.path, self.watchedFile.path)
    }

    await fulfillment(of: [exp1], timeout: 1.0)

    // Write again after re-attach (allow 0.1s + buffer for re-attach delay)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        try? "second write".write(to: self.watchedFile, atomically: false, encoding: .utf8)
    }

    await fulfillment(of: [exp2], timeout: 1.0)
    watcher.stop()
}
```

- [ ] **Step 2: Run the test — verify it passes**

Run: `xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -only-testing:GcloudSessionWatchTests/FileWatcherTests/test_atomicReplace_firesAndReattaches 2>&1 | tail -20`

Expected: PASS. (The `.delete` path + 0.1 s re-attach was implemented in Task 1.)

- [ ] **Step 3: Commit**

```bash
git add GcloudSessionWatchTests/FileWatcherTests.swift
git commit -m "test: verify FileWatcher handles atomic replace and re-attaches"
```

---

## Task 3: Missing file at startup

**Files:**
- Modify: `GcloudSessionWatchTests/FileWatcherTests.swift` — add test

- [ ] **Step 1: Add the missing-file test**

Append to `FileWatcherTests` in `GcloudSessionWatchTests/FileWatcherTests.swift`:

```swift
func test_missingFile_doesNotCrashAndNeverCallsOnChange() async throws {
    let nonExistentPath = tempDir.appendingPathComponent("does_not_exist.json").path
    var callCount = 0
    let watcher = FileWatcher(path: nonExistentPath) { callCount += 1 }
    watcher.start() // open() fails; must return early without crash

    try await Task.sleep(nanoseconds: 200_000_000) // 0.2 s
    XCTAssertEqual(callCount, 0, "onChange must not fire for a non-existent file")
    watcher.stop()
}
```

- [ ] **Step 2: Run the test — verify it passes**

Run: `xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -only-testing:GcloudSessionWatchTests/FileWatcherTests/test_missingFile_doesNotCrashAndNeverCallsOnChange 2>&1 | tail -20`

Expected: PASS. (`guard fd >= 0 else { return }` in `start()` covers this.)

- [ ] **Step 3: Run all FileWatcher tests**

Run: `xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' -only-testing:GcloudSessionWatchTests/FileWatcherTests 2>&1 | tail -20`

Expected: All 3 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add GcloudSessionWatchTests/FileWatcherTests.swift
git commit -m "test: verify FileWatcher handles missing file gracefully"
```

---

## Task 4: Wire FileWatcher into SessionMonitor

**Files:**
- Modify: `GcloudSessionWatch/SessionMonitor.swift`

- [ ] **Step 1: Add the `fileWatcher` property**

In `SessionMonitor.swift`, add to the stored properties block (after `private var defaultsObserver: NSObjectProtocol?` at line 30):

```swift
private var fileWatcher: FileWatcher?
```

- [ ] **Step 2: Add `startFileWatcher()` and call it from `init`**

Add a new private method to the `private extension SessionMonitor` block (after `observeDefaults()`):

```swift
func startFileWatcher() {
    fileWatcher = FileWatcher(path: credentialsPath) { [weak self] in
        self?.tick()
    }
    fileWatcher?.start()
}
```

Then call it from `init`, after `observeDefaults()`:

```swift
observeDefaults()
startFileWatcher()         // ← add this line
requestNotificationPermission()
```

- [ ] **Step 3: Re-attach the watcher inside `tick()` when the file exists**

In `tick()`, add one line immediately after the `guard let mtime` succeeds (before computing `expiry`). This makes `start()` attach the watcher the first time the file appears from a `.missing` state — `start()` is idempotent so it's a no-op when the watcher is already running:

```swift
func tick() {
    guard let mtime = fileProvider.modificationDate(at: credentialsPath) else {
        credentialsState = .missing
        timeRemaining = 0
        expiryDate = nil
        cancelNotification()
        return
    }

    fileWatcher?.start()   // ← add this line

    let expiry = mtime.addingTimeInterval(sessionDurationSeconds)
    // … rest of tick() unchanged …
```

- [ ] **Step 4: Stop the watcher in `deinit`**

In `deinit`, add `fileWatcher?.stop()` alongside the existing cleanup:

```swift
deinit {
    timer?.invalidate()
    displayTimer?.invalidate()
    fileWatcher?.stop()    // ← add this line
    if let observer = defaultsObserver {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

- [ ] **Step 5: Build and verify existing tests still pass**

Run: `xcodebuild test -scheme GcloudSessionWatch -destination 'platform=macOS' 2>&1 | tail -30`

Expected: All tests PASS (existing `SessionMonitorTests` must not regress; `FileWatcherTests` all pass).

- [ ] **Step 6: Commit**

```bash
git add GcloudSessionWatch/SessionMonitor.swift
git commit -m "feat: wire FileWatcher into SessionMonitor for immediate credentials detection"
```

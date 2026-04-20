# Auto-Update Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight version check that hits the GitHub Releases API on launch and every 24 hours, and shows an inline banner in the menu bar popover when a newer version is available, opening the release page in the browser when the user clicks "Update".

**Architecture:** A new `UpdateChecker` (`@MainActor ObservableObject`) owns all update logic — fetch, parse, compare, and expose `availableUpdate`. It is created as a `@StateObject` in `GcloudSessionWatchApp` and used directly in the MenuBarExtra view builder. The inline banner sits at the top of the existing `VStack`, above the session time display.

**Tech Stack:** Swift, SwiftUI, Foundation (`URLSession`, `JSONDecoder`, `Timer`), XCTest, `NSWorkspace` (to open URLs — no `@Environment(\.openURL)` since the MenuBarExtra content is not a standalone View struct)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `GcloudSessionWatch/UpdateChecker.swift` | All update logic: fetch, parse, compare, schedule |
| Modify | `GcloudSessionWatch/GcloudSessionWatchApp.swift` | Create `UpdateChecker` as `@StateObject`, add inline update banner and `.onAppear` start |
| Create | `GcloudSessionWatchTests/UpdateCheckerTests.swift` | Unit tests for parsing, comparison, fetch scenarios |

---

## Task 1: Scaffold UpdateChecker with version parsing (TDD)

**Files:**
- Create: `GcloudSessionWatch/UpdateChecker.swift`
- Create: `GcloudSessionWatchTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Create `UpdateChecker.swift` with scaffold and pure parsing functions**

Create `GcloudSessionWatch/UpdateChecker.swift`:

```swift
import Foundation

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}

struct AvailableUpdate: Equatable {
    let version: String
    let url: URL
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var availableUpdate: AvailableUpdate?

    private let appVersion: String
    private let fetcher: (URL) async throws -> Data
    private var hasStarted = false

    init(
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        fetcher: @escaping (URL) async throws -> Data = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.appVersion = appVersion
        self.fetcher = fetcher
    }

    /// Strips a leading "v" and splits by "." into an array of Ints.
    /// "v1.2.3" → [1, 2, 3], "1.0" → [1, 0]
    static func parseVersion(_ string: String) -> [Int] {
        let stripped = string.hasPrefix("v") ? String(string.dropFirst()) : string
        return stripped.split(separator: ".").compactMap { Int($0) }
    }

    /// Returns true if tagVersion is strictly greater than appVersion.
    /// Both arrays are zero-padded to the same length before comparison.
    static func isNewer(_ tagVersion: [Int], than appVersion: [Int]) -> Bool {
        let maxLen = max(tagVersion.count, appVersion.count)
        let t = tagVersion + Array(repeating: 0, count: maxLen - tagVersion.count)
        let a = appVersion + Array(repeating: 0, count: maxLen - appVersion.count)
        for (tv, av) in zip(t, a) {
            if tv > av { return true }
            if tv < av { return false }
        }
        return false // equal
    }
}
```

- [ ] **Step 2: Create `UpdateCheckerTests.swift` with version parsing and comparison tests**

Create `GcloudSessionWatchTests/UpdateCheckerTests.swift`:

```swift
import XCTest
@testable import GcloudSessionWatch

@MainActor
final class UpdateCheckerTests: XCTestCase {

    // MARK: - parseVersion

    func test_parseVersion_stripsVPrefix() {
        XCTAssertEqual(UpdateChecker.parseVersion("v1.2.3"), [1, 2, 3])
    }

    func test_parseVersion_noPrefix() {
        XCTAssertEqual(UpdateChecker.parseVersion("1.0"), [1, 0])
    }

    func test_parseVersion_singleComponent() {
        XCTAssertEqual(UpdateChecker.parseVersion("2"), [2])
    }

    // MARK: - isNewer

    func test_isNewer_tagHigherMinor_returnsTrue() {
        XCTAssertTrue(UpdateChecker.isNewer([1, 2, 0], than: [1, 0, 0]))
    }

    func test_isNewer_tagHigherPatch_returnsTrue() {
        XCTAssertTrue(UpdateChecker.isNewer([1, 0, 1], than: [1, 0, 0]))
    }

    func test_isNewer_tagHigherMajor_returnsTrue() {
        XCTAssertTrue(UpdateChecker.isNewer([2, 0, 0], than: [1, 9, 9]))
    }

    func test_isNewer_sameVersion_returnsFalse() {
        XCTAssertFalse(UpdateChecker.isNewer([1, 0, 0], than: [1, 0, 0]))
    }

    func test_isNewer_tagOlder_returnsFalse() {
        XCTAssertFalse(UpdateChecker.isNewer([0, 9, 0], than: [1, 0, 0]))
    }

    func test_isNewer_differentLengths_tagIsNewer() {
        // app "1.0" ([1,0]) vs tag "v1.0.1" ([1,0,1]) → tag is newer
        XCTAssertTrue(UpdateChecker.isNewer([1, 0, 1], than: [1, 0]))
    }

    func test_isNewer_differentLengths_equal() {
        // app "1.0" ([1,0]) vs tag "v1.0.0" ([1,0,0]) → equal, not newer
        XCTAssertFalse(UpdateChecker.isNewer([1, 0, 0], than: [1, 0]))
    }
}
```

- [ ] **Step 3: Run these tests — expect them to PASS (parsing logic is already implemented)**

```bash
xcodebuild test \
  -project GcloudSessionWatch.xcodeproj \
  -scheme GcloudSessionWatch \
  -destination 'platform=macOS' \
  -only-testing:GcloudSessionWatchTests/UpdateCheckerTests \
  2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: 9 tests pass.

- [ ] **Step 4: Commit**

```bash
git add GcloudSessionWatch/UpdateChecker.swift GcloudSessionWatchTests/UpdateCheckerTests.swift
git commit -m "feat: add UpdateChecker scaffold with version parsing logic"
```

---

## Task 2: Implement `checkForUpdates()` (TDD)

**Files:**
- Modify: `GcloudSessionWatch/UpdateChecker.swift`
- Modify: `GcloudSessionWatchTests/UpdateCheckerTests.swift`

The GitHub Releases API returns JSON like:
```json
{ "tag_name": "v1.2.0", "html_url": "https://github.com/younghoandrewchaa/gcloud-session-watch/releases/tag/v1.2.0" }
```

- [ ] **Step 1: Write failing tests for `checkForUpdates()`**

Append these test methods inside `UpdateCheckerTests` in `GcloudSessionWatchTests/UpdateCheckerTests.swift` (after the existing `isNewer` tests, before the closing `}`):

```swift
    // MARK: - checkForUpdates

    func test_newerVersion_setsAvailableUpdate() async {
        let json = Data("""
        {"tag_name":"v2.0.0","html_url":"https://github.com/younghoandrewchaa/gcloud-session-watch/releases/tag/v2.0.0"}
        """.utf8)
        let checker = UpdateChecker(appVersion: "1.0", fetcher: { _ in json })

        await checker.checkForUpdates()

        XCTAssertEqual(checker.availableUpdate?.version, "2.0.0")
        XCTAssertEqual(
            checker.availableUpdate?.url,
            URL(string: "https://github.com/younghoandrewchaa/gcloud-session-watch/releases/tag/v2.0.0")
        )
    }

    func test_sameVersion_doesNotSetAvailableUpdate() async {
        let json = Data("""
        {"tag_name":"v1.0.0","html_url":"https://github.com/younghoandrewchaa/gcloud-session-watch/releases/tag/v1.0.0"}
        """.utf8)
        let checker = UpdateChecker(appVersion: "1.0", fetcher: { _ in json })

        await checker.checkForUpdates()

        XCTAssertNil(checker.availableUpdate)
    }

    func test_olderVersion_doesNotSetAvailableUpdate() async {
        let json = Data("""
        {"tag_name":"v0.9.0","html_url":"https://github.com/younghoandrewchaa/gcloud-session-watch/releases/tag/v0.9.0"}
        """.utf8)
        let checker = UpdateChecker(appVersion: "1.0", fetcher: { _ in json })

        await checker.checkForUpdates()

        XCTAssertNil(checker.availableUpdate)
    }

    func test_networkError_doesNotSetAvailableUpdate() async {
        let checker = UpdateChecker(
            appVersion: "1.0",
            fetcher: { _ in throw URLError(.notConnectedToInternet) }
        )

        await checker.checkForUpdates()

        XCTAssertNil(checker.availableUpdate)
    }

    func test_malformedJson_doesNotSetAvailableUpdate() async {
        let checker = UpdateChecker(appVersion: "1.0", fetcher: { _ in Data("not json".utf8) })

        await checker.checkForUpdates()

        XCTAssertNil(checker.availableUpdate)
    }
```

- [ ] **Step 2: Run tests — expect the 5 new tests to FAIL**

```bash
xcodebuild test \
  -project GcloudSessionWatch.xcodeproj \
  -scheme GcloudSessionWatch \
  -destination 'platform=macOS' \
  -only-testing:GcloudSessionWatchTests/UpdateCheckerTests \
  2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: 9 pass (parsing tests), 5 fail (`checkForUpdates` not yet implemented).

- [ ] **Step 3: Implement `checkForUpdates()` in `UpdateChecker.swift`**

Add this method inside the `UpdateChecker` class, after `isNewer`:

```swift
    func checkForUpdates() async {
        let apiURL = URL(string: "https://api.github.com/repos/younghoandrewchaa/gcloud-session-watch/releases/latest")!
        do {
            let data = try await fetcher(apiURL)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tagComponents = Self.parseVersion(release.tagName)
            let appComponents = Self.parseVersion(appVersion)
            guard Self.isNewer(tagComponents, than: appComponents),
                  let url = URL(string: release.htmlUrl) else { return }
            let displayVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName
            availableUpdate = AvailableUpdate(version: displayVersion, url: url)
        } catch {
            // silently ignore — network errors should not surface to the user
        }
    }
```

- [ ] **Step 4: Run tests — expect all 14 tests to PASS**

```bash
xcodebuild test \
  -project GcloudSessionWatch.xcodeproj \
  -scheme GcloudSessionWatch \
  -destination 'platform=macOS' \
  -only-testing:GcloudSessionWatchTests/UpdateCheckerTests \
  2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: 14 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add GcloudSessionWatch/UpdateChecker.swift GcloudSessionWatchTests/UpdateCheckerTests.swift
git commit -m "feat: implement checkForUpdates via GitHub Releases API"
```

---

## Task 3: Add `startPeriodicChecks()` and wire into the App

**Files:**
- Modify: `GcloudSessionWatch/UpdateChecker.swift`
- Modify: `GcloudSessionWatch/GcloudSessionWatchApp.swift`

- [ ] **Step 1: Add `startPeriodicChecks()` to `UpdateChecker.swift`**

Add this method inside the `UpdateChecker` class, after `checkForUpdates()`:

```swift
    /// Calls checkForUpdates() immediately, then every 24 hours.
    /// Safe to call multiple times — subsequent calls are no-ops.
    func startPeriodicChecks() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await checkForUpdates() }
        Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkForUpdates() }
        }
    }
```

- [ ] **Step 2: Add `@StateObject private var updateChecker` to `GcloudSessionWatchApp.swift`**

The current file is:

```swift
import SwiftUI

@main
struct GcloudSessionWatchApp: App {
    // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
    // Safe to call the @MainActor init from here.
    @StateObject private var monitor = SessionMonitor()
    @AppStorage("sessionDurationHours") private var sessionDurationHours: Int = 5

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

Replace with:

```swift
import SwiftUI

@main
struct GcloudSessionWatchApp: App {
    // @StateObject evaluates SessionMonitor() on first SwiftUI render (main thread).
    // Safe to call the @MainActor init from here.
    @StateObject private var monitor = SessionMonitor()
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("sessionDurationHours") private var sessionDurationHours: Int = 5

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 8) {
                if let update = updateChecker.availableUpdate {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                        Text("v\(update.version) available")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Spacer()
                        Button("Update") {
                            updateChecker.availableUpdate = nil
                            NSWorkspace.shared.open(update.url)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        Button("Later") {
                            updateChecker.availableUpdate = nil
                        }
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                }
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
            .onAppear {
                updateChecker.startPeriodicChecks()
            }
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

> **Note on `NSWorkspace`:** `@Environment(\.openURL)` is a View-only API. Since the MenuBarExtra content is a view builder inside the App (not a standalone `View` struct), `NSWorkspace.shared.open(url)` is used instead — it opens the URL in the default browser the same way.

- [ ] **Step 3: Build to verify no compile errors**

```bash
xcodebuild build \
  -project GcloudSessionWatch.xcodeproj \
  -scheme GcloudSessionWatch \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add GcloudSessionWatch/UpdateChecker.swift GcloudSessionWatch/GcloudSessionWatchApp.swift
git commit -m "feat: add startPeriodicChecks and inline update banner to MenuBarExtra"
```

---

## Task 4: Manual smoke test

- [ ] **Step 1: Force a fake update to verify the banner**

Temporarily change the `UpdateChecker()` init in `GcloudSessionWatchApp.swift` to simulate a newer release:

```swift
// TEMPORARY TEST — revert after verifying
@StateObject private var updateChecker = UpdateChecker(
    appVersion: "0.0.1",
    fetcher: { _ in
        Data("""
        {"tag_name":"v1.3.0","html_url":"https://github.com/younghoandrewchaa/gcloud-session-watch/releases"}
        """.utf8)
    }
)
```

- [ ] **Step 2: Run the app and verify the banner**

Run the app (⌘R in Xcode). Click the menu bar icon. Verify:
- A blue banner "v1.3.0 available" appears at the top of the popover ✓
- Clicking **Update** opens the browser to the releases page, and the banner disappears ✓
- Clicking **Later** dismisses the banner without opening the browser ✓
- Opening the popover a second time: the banner is gone (it was dismissed) ✓

- [ ] **Step 3: Revert the temporary test init**

Restore to:

```swift
@StateObject private var updateChecker = UpdateChecker()
```

- [ ] **Step 4: Run full test suite**

```bash
xcodebuild test \
  -project GcloudSessionWatch.xcodeproj \
  -scheme GcloudSessionWatch \
  -destination 'platform=macOS' \
  2>&1 | grep -E "PASS|FAIL|error:|BUILD FAILED"
```

Expected: all tests pass (14 UpdateChecker + existing SessionMonitor tests).

- [ ] **Step 5: Commit**

```bash
git add GcloudSessionWatch/GcloudSessionWatchApp.swift
git commit -m "chore: revert test-only UpdateChecker init after smoke test"
```

---

## Summary

| Task | What it delivers |
|------|-----------------|
| Task 1 | `UpdateChecker` skeleton + version parsing, fully tested (9 tests) |
| Task 2 | `checkForUpdates()` fetches GitHub API + all fetch scenarios tested (5 more tests) |
| Task 3 | 24h periodic checks wired into App + inline update banner in MenuBarExtra |
| Task 4 | Smoke test with forced fake update, full suite green |

import XCTest
import SwiftUI

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
        let offset: TimeInterval = -(3600 + 27 * 60 + 30) // -5250
        mock.mockDate = Date(timeIntervalSinceNow: offset)
        let monitor = SessionMonitor(fileProvider: mock)
        XCTAssertEqual(monitor.labelText, "3:32")
    }

    func testValidSession_minutesPaddedToTwoDigits() {
        // mtime 4h 2m 30s ago, default 5h → 3450 s remaining = 57m 30s → "0:57"
        // +30 s offset ensures remaining is never on an exact minute boundary
        let offset: TimeInterval = -14550 // -(4 * 3600 + 2 * 60 + 30)
        mock.mockDate = Date(timeIntervalSinceNow: offset)
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
    
    // MARK: Session duration from UserDefaults

    func testCustomSessionDuration_3Hours() {
        UserDefaults.standard.set(3, forKey: "sessionDurationHours")
        // mtime 1h 27m 30s ago, 3h duration → 5550 s remaining = 1h 32m 30s → "1:32"
        let offset: TimeInterval = -5250 // -(1 * 3600 + 27 * 60 + 30)
        mock.mockDate = Date(timeIntervalSinceNow: offset)
        let monitor = SessionMonitor(fileProvider: mock)
        XCTAssertEqual(monitor.credentialsState, .valid)
        XCTAssertEqual(monitor.labelText, "1:32")
    }

    func testDefaultDuration_whenKeyAbsent_is5Hours() {
        // No key → defaults to 5h
        // mtime 4h 19m 30s ago → 2430 s remaining = 40m 30s → "0:40"
        let offset: TimeInterval = -15570 // -(4 * 3600 + 19 * 60 + 30)
        mock.mockDate = Date(timeIntervalSinceNow: offset)
        let monitor = SessionMonitor(fileProvider: mock)
        XCTAssertEqual(monitor.credentialsState, .valid)
        XCTAssertEqual(monitor.labelText, "0:40")
    }

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
        // mtime 5250 s ago (1h 27m 30s), default 5h → ~12750 s remaining.
        // Int() truncates: tiny elapsed time during init → "3:32:29" not "3:32:30".
        mock.mockDate = Date(timeIntervalSinceNow: -5250)
        let monitor = SessionMonitor(fileProvider: mock)
        XCTAssertEqual(monitor.detailedTimeText, "3:32:29")
    }

    func testDetailedTimeText_minutesPaddedAndSecondsShown() {
        // mtime 14550 s ago (4h 2m 30s), default 5h → ~3450 s remaining.
        // Int() truncates: tiny elapsed time during init → "0:57:29" not "0:57:30".
        mock.mockDate = Date(timeIntervalSinceNow: -14550)
        let monitor = SessionMonitor(fileProvider: mock)
        XCTAssertEqual(monitor.detailedTimeText, "0:57:29")
    }
}

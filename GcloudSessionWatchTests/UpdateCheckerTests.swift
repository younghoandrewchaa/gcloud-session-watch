import XCTest

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

    // MARK: - startPeriodicChecks

    func test_startPeriodicChecks_isIdempotent() async {
        var callCount = 0
        let checker = UpdateChecker(appVersion: "1.0", fetcher: { _ in
            callCount += 1
            throw URLError(.cancelled)
        })
        checker.startPeriodicChecks()
        checker.startPeriodicChecks()
        await Task.yield()
        XCTAssertEqual(callCount, 1, "checkForUpdates should only be called once despite two startPeriodicChecks calls")
    }
}

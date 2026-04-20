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
}

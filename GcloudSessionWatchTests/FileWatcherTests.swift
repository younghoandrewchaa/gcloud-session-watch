import XCTest

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

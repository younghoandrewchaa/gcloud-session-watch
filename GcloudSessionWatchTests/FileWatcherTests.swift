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
}

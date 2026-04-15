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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        MainActor.assumeIsolated { self?.start() }
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

    deinit {
        // source is @MainActor-isolated; assumeIsolated is safe because FileWatcher
        // is always held by SessionMonitor (@MainActor), so deinit runs on main.
        // source = nil is omitted — the object is being deallocated anyway.
        MainActor.assumeIsolated { source?.cancel() }
    }
}

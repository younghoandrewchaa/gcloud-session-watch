import Combine
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

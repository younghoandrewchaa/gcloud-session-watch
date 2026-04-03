//
//  UpdateChecker.swift
//  GcloudSessionWatch
//
//  Created by Youngho Chaa on 03/04/2026.
//

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
    
    static func parseVersion(_ string: String) -> [Int] {
        let stripped = string.hasPrefix("v") ? String(string.dropFirst()) : string
        return stripped.split(separator: ".").compactMap { Int($0) }
    }
    
    static func isNewer(_ tagVersion: [Int], than appVersion: [Int]) -> Bool {
        let maxLen = max(tagVersion.count, appVersion.count)
        let t = tagVersion + Array(repeating: 0, count: maxLen - tagVersion.count)
        let a = appVersion + Array(repeating: 0, count: maxLen - appVersion.count)
        for (tv, av) in zip(t, a) {
            if tv > av { return true }
            if tv < av { return false }
        }
        return false
    }

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
}

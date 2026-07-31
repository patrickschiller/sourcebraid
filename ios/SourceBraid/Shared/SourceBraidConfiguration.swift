import Foundation

struct SourceBraidConfiguration: Codable, Equatable {
    var owner: String
    var repository: String
    var branch: String
    var rootFolder: String

    static let defaultValue = SourceBraidConfiguration(
        owner: "",
        repository: "sourcebraid-private",
        branch: "main",
        rootFolder: "web-clips"
    )

    var isComplete: Bool {
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rootFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var repoSlug: String {
        "\(owner)/\(repository)"
    }

    func normalized() -> SourceBraidConfiguration {
        SourceBraidConfiguration(
            owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
            repository: repository.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "main"
                : branch.trimmingCharacters(in: .whitespacesAndNewlines),
            rootFolder: Self.normalizeRootFolder(rootFolder)
        )
    }

    private static func normalizeRootFolder(_ value: String) -> String {
        let parts = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "web-clips" : parts.joined(separator: "/")
    }
}

enum SourceBraidSettings {
    private static let configurationKey = "github-configuration"

    static func load() -> SourceBraidConfiguration {
        guard let defaults = UserDefaults(suiteName: SourceBraidEnvironment.appGroupIdentifier),
              let data = defaults.data(forKey: configurationKey),
              let value = try? JSONDecoder().decode(SourceBraidConfiguration.self, from: data) else {
            return .defaultValue
        }
        return value
    }

    static func save(_ configuration: SourceBraidConfiguration) throws {
        guard let defaults = UserDefaults(suiteName: SourceBraidEnvironment.appGroupIdentifier) else {
            throw SourceBraidSettingsError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(configuration.normalized())
        defaults.set(data, forKey: configurationKey)
    }
}

enum SourceBraidSettingsError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "The SourceBraid App Group is unavailable. Check signing and the App Group capability."
    }
}

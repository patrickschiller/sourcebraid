import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var owner: String
    @Published var repository: String
    @Published var branch: String
    @Published var rootFolder: String
    @Published var token: String
    @Published var statusMessage = ""
    @Published var statusIsError = false
    @Published var isWorking = false
    @Published var recentCaptures: [RecentCapture] = []

    init() {
        let configuration = SourceBraidSettings.load()
        owner = configuration.owner
        repository = configuration.repository
        branch = configuration.branch
        rootFolder = configuration.rootFolder
        do {
            token = try KeychainStore().token()
        } catch {
            token = ""
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        refreshRecentCaptures()
    }

    var isConfigured: Bool {
        configuration.isComplete && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        do {
            try persist()
            showStatus("Settings saved. SourceBraid is ready in the iOS Share Sheet.")
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    func testConnection() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try persist()
            try await GitHubClient(configuration: configuration.normalized(), token: token).testConnection()
            showStatus("Connected to \(configuration.normalized().repoSlug).")
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    func refreshRecentCaptures() {
        recentCaptures = RecentCaptureStore.load()
    }

    private var configuration: SourceBraidConfiguration {
        SourceBraidConfiguration(owner: owner, repository: repository, branch: branch, rootFolder: rootFolder)
    }

    private func persist() throws {
        let normalized = configuration.normalized()
        guard normalized.isComplete else {
            throw SettingsValidationError.missingRepository
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SettingsValidationError.missingToken
        }
        try SourceBraidSettings.save(normalized)
        try KeychainStore().setToken(token)
        owner = normalized.owner
        repository = normalized.repository
        branch = normalized.branch
        rootFolder = normalized.rootFolder
    }

    private func showStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
    }
}

enum SettingsValidationError: LocalizedError {
    case missingRepository
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            return "Owner, repository, branch, and root folder are required."
        case .missingToken:
            return "A fine-grained GitHub token is required."
        }
    }
}

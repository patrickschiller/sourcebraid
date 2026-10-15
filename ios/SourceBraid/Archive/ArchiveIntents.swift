import AppIntents
import Foundation
import UIKit

extension Notification.Name {
    static let archiveOpenRequested = Notification.Name("SourceBraid.ArchiveOpenRequested")
}

struct ArchiveClipEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "SourceBraid clip"
    static var defaultQuery = ArchiveClipQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ArchiveClipQuery: EntityStringQuery {
    @MainActor private func loaded() async throws -> (ArchiveIdentity, [ArchiveClip], ArchiveCache) {
        guard UIApplication.shared.isProtectedDataAvailable, !(try KeychainStore().token()).isEmpty else { throw ArchiveError.missingCredentials }
        let identity = try ArchiveIdentity(configuration: SourceBraidSettings.load())
        let cache = ArchiveServices.cache(for: identity)
        let manifest = try await cache.load()
        guard manifest.snapshot?.identity == identity else { throw ArchiveError.noEvidence }
        return (identity, manifest.clips, cache)
    }
    @MainActor func entities(for identifiers: [String]) async throws -> [ArchiveClipEntity] {
        let (identity, clips, _) = try await loaded()
        return clips.filter { identifiers.contains(identity.cacheKey + ":" + $0.path) }.map {
            ArchiveClipEntity(id: identity.cacheKey + ":" + $0.path, title: $0.title)
        }
    }
    @MainActor func suggestedEntities() async throws -> [ArchiveClipEntity] {
        let (identity, clips, _) = try await loaded()
        return clips.prefix(7).map { ArchiveClipEntity(id: identity.cacheKey + ":" + $0.path, title: $0.title) }
    }
    @MainActor func entities(matching string: String) async throws -> [ArchiveClipEntity] {
        let (identity, clips, cache) = try await loaded()
        let index = ArchiveSearchIndex(directory: cache.directory)
        let hits = try await index.search(String(string.prefix(300)), limit: 10)
        return hits.compactMap { hit in
            guard let clip = clips.first(where: { $0.path == hit.path && $0.sha == hit.sha }) else { return nil }
            return ArchiveClipEntity(id: identity.cacheKey + ":" + clip.path, title: clip.title)
        }
    }
}

struct OpenArchiveClipIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open SourceBraid clip"
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Clip") var target: ArchiveClipEntity
    @MainActor func perform() async throws -> some IntentResult {
        guard !(try await ArchiveClipQuery().entities(for: [target.id])).isEmpty else { throw ArchiveError.invalidPath }
        UserDefaults.standard.set(target.id, forKey: "SourceBraid.pendingClip")
        NotificationCenter.default.post(name: .archiveOpenRequested, object: nil)
        return .result()
    }
}

struct SearchArchiveIntent: AppIntent {
    static var title: LocalizedStringResource = "Search SourceBraid archive"
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Search text") var query: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[ArchiveClipEntity]> {
        .result(value: try await ArchiveClipQuery().entities(matching: query))
    }
}

struct RecentArchiveClipsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show recent SourceBraid clips"
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[ArchiveClipEntity]> {
        .result(value: try await ArchiveClipQuery().suggestedEntities())
    }
}

struct SourceBraidShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenArchiveClipIntent(), phrases: ["Open a clip in \(.applicationName)"], shortTitle: "Open clip", systemImageName: "doc.richtext")
        AppShortcut(intent: SearchArchiveIntent(), phrases: ["Search my archive in \(.applicationName)"], shortTitle: "Search archive", systemImageName: "magnifyingglass")
        AppShortcut(intent: RecentArchiveClipsIntent(), phrases: ["Show recent clips in \(.applicationName)"], shortTitle: "Recent clips", systemImageName: "clock")
    }
}

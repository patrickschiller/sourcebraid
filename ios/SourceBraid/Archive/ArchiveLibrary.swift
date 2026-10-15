import Foundation
import Combine

@MainActor
final class ArchiveLibrary: ObservableObject {
    @Published private(set) var clips: [ArchiveClip] = []
    @Published private(set) var snapshot: ArchiveSnapshot? {
        didSet {
            inventoryClipCount = snapshot?.files.reduce(0) { count, file in
                count + (file.path.lowercased().hasSuffix(".md") ? 1 : 0)
            } ?? 0
        }
    }
    @Published private(set) var inventoryClipCount = 0
    @Published private(set) var metadataComplete = false
    @Published private(set) var isSyncing = false
    @Published private(set) var progress = ""
    @Published var status = ""
    @Published var selectedPath: String?
    @Published var sourceFragment: String?
    @Published private(set) var pinnedClip: ArchiveClip?
    private var pinnedSnapshot: ArchiveSnapshot?
    @Published private(set) var generation = UUID()
    @Published private(set) var indexedCount = 0
    private(set) var searchIndex: ArchiveSearchIndex?
    var readingPositions: [String: Double] = [:]
    private(set) var cache: ArchiveCache?
    private var client: (any ArchiveReading)?
    private var syncTask: Task<Void, Never>?
    private var identity: ArchiveIdentity?
    private let injectedReader: Bool
    private var isConfiguring = false
    @Published private(set) var lastRefreshReport: ArchiveRefreshReport?

    init(reader: (any ArchiveReading)? = nil, cache: ArchiveCache? = nil, identity: ArchiveIdentity? = nil) {
        injectedReader = reader != nil; client = reader; self.cache = cache; self.identity = identity
        if let cache { searchIndex = ArchiveSearchIndex(directory: cache.directory) }
    }

    var selected: ArchiveClip? { pinnedClip?.path == selectedPath ? pinnedClip : clips.first { $0.path == selectedPath } }
    var recent: [ArchiveClip] { Array(clips.prefix(7)) }
    var isConfigured: Bool { identity != nil && client != nil }

    func configure(bootstrapIfEmpty: Bool = true) async {
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }
        do {
            if injectedReader {
                try await restoreCachedMetadata()
                if bootstrapIfEmpty, snapshot == nil { synchronize(scope: .bootstrap) }
                return
            }
#if DEBUG
            if ProcessInfo.processInfo.environment["SOURCEBRAID_DEMO"] == "1" {
                let reader = try ArchiveDemoReader()
                identity = reader.identity; client = reader; cache = ArchiveServices.cache(for: reader.identity)
                if let cache { searchIndex = ArchiveSearchIndex(directory: cache.directory) }
                try await restoreCachedMetadata()
                if bootstrapIfEmpty, snapshot == nil { synchronize(scope: .bootstrap) }
                return
            }
#endif
            let next = try ArchiveIdentity(configuration: SourceBraidSettings.load())
            if identity != next {
                let previousTask = syncTask
                previousTask?.cancel(); generation = UUID()
                await previousTask?.value
                syncTask = nil; isSyncing = false
                let oldCache = cache
                let oldIdentity = identity
                identity = next; generation = UUID(); clips = []; snapshot = nil
                selectedPath = nil; sourceFragment = nil; pinnedClip = nil; pinnedSnapshot = nil
                readingPositions = [:]; metadataComplete = false
                cache = ArchiveServices.cache(for: next)
                if let cache { searchIndex = ArchiveSearchIndex(directory: cache.directory) }
                if let oldCache {
                    let pause = await ArchiveRefreshCoordinator.pause(for: oldIdentity)
                    defer { ArchiveRefreshCoordinator.resume(pause) }
                    try await oldCache.clear()
                }
            }
            let token = try KeychainStore().token()
            guard !token.isEmpty else { throw ArchiveError.missingCredentials }
            client = ArchiveReadClient(identity: next, token: token)
            try await restoreCachedMetadata()
            // Warm launch and foreground only restore metadata. The first launch seeds
            // at most seven bodies; scheduled/manual refresh fills the remaining gaps.
            if bootstrapIfEmpty, snapshot == nil { synchronize(scope: .bootstrap) }
        } catch {
            let previousTask = syncTask
            previousTask?.cancel(); generation = UUID()
            await previousTask?.value
            syncTask = nil; isSyncing = false
            client = nil; identity = nil; generation = UUID(); clips = []; snapshot = nil
            selectedPath = nil; sourceFragment = nil; pinnedClip = nil; pinnedSnapshot = nil
            readingPositions = [:]; metadataComplete = false; indexedCount = 0
            status = error.localizedDescription
        }
    }

    private func restoreCachedMetadata() async throws {
        guard let cache else { return }
        let epoch = generation
        let manifest = try await cache.load()
        guard epoch == generation, manifest.snapshot?.identity == identity else { return }
        snapshot = manifest.snapshot; clips = manifest.clips
        metadataComplete = manifest.metadataComplete
        indexedCount = (try? await searchIndex?.count()) ?? 0
        guard epoch == generation else { return }
        if !isSyncing {
            status = snapshot.map { archiveText("Local copy as of ", "Lokaler Stand vom ") + $0.checkedAt.formatted() } ?? ""
            if !metadataComplete { status += " · " + archiveText("Search covers downloaded articles", "Suche umfasst geladene Beiträge") }
        }
    }

    func synchronize(scope: ArchiveRefreshScope = .manual) {
        guard !isSyncing, let client, let cache else { return }
        let epoch = generation
        isSyncing = true; progress = archiveText("Reading inventory…", "Bestand wird gelesen …")
        syncTask = Task {
            _ = await performRefresh(client: client, cache: cache, scope: scope, epoch: epoch)
        }
    }

    func refreshInBackground() async -> ArchiveRefreshReport {
        guard !isSyncing, let client, let cache else { return .init(state: .failed, processed: 0, remaining: 0) }
        isSyncing = true
        return await performRefresh(client: client, cache: cache, scope: .background, epoch: generation)
    }

    private func performRefresh(client: any ArchiveReading, cache: ArchiveCache, scope: ArchiveRefreshScope, epoch: UUID) async -> ArchiveRefreshReport {
        defer { if generation == epoch { isSyncing = false; progress = "" } }
        do {
            guard let identity else { throw ArchiveError.missingCredentials }
            let result = try await ArchiveRefreshCoordinator.perform(identity: identity, client: client, cache: cache, index: searchIndex, scope: scope) { [weak self] value in
                guard let self, self.generation == epoch else { return }
                self.progress = value
            }
            try Task.checkCancellation()
            guard generation == epoch else { throw CancellationError() }
            snapshot = result.manifest.snapshot; clips = result.manifest.clips
            metadataComplete = result.manifest.metadataComplete; indexedCount = result.indexedCount
            status = result.status; lastRefreshReport = result.report
            if let selectedPath, !clips.contains(where: { $0.path == selectedPath }) { self.selectedPath = nil }
            return result.report
        } catch is CancellationError {
            let report = ArchiveRefreshReport(state: .cancelled, processed: 0, remaining: 0)
            if generation == epoch { lastRefreshReport = report }
            return report
        } catch {
            let report = ArchiveRefreshReport(state: .failed, processed: 0, remaining: 0)
            if generation == epoch {
                status = error.localizedDescription + (snapshot == nil ? "" : " · " + archiveText("Showing offline copy", "Lokaler Stand wird angezeigt"))
                lastRefreshReport = report
            }
            return report
        }
    }

    func stopSync() { syncTask?.cancel() }
    func waitForSync() async { await syncTask?.value }

    func search(_ query: String) async throws -> [ArchiveSearchHit] {
        guard let searchIndex else { return [] }
        let epoch = generation
        let hits = try await searchIndex.search(query)
        guard epoch == generation else { throw CancellationError() }
        return hits.filter { hit in clips.contains { $0.path == hit.path && $0.sha == hit.sha } }
    }

    func document(_ clip: ArchiveClip, snapshot inventory: ArchiveSnapshot? = nil) async throws -> (ArchiveClip, String) {
        let inventory = inventory ?? readerSnapshot(for: clip)
        guard inventory?.identity == identity, let cache, let client, let file = inventory?.files.first(where: { $0.path == clip.path && $0.sha == clip.sha }) else { throw ArchiveError.invalidPath }
        guard file.size <= ArchiveReadClient.markdownLimit else { throw ArchiveError.tooLarge }
        let epoch = generation
        let bytes: Data
        if let local = try await cache.data(sha: file.sha, limit: ArchiveReadClient.markdownLimit) { bytes = local }
        else {
            bytes = try await client.read(file, limit: ArchiveReadClient.markdownLimit)
            try Task.checkCancellation()
            guard epoch == generation else { throw CancellationError() }
        }
        guard bytes.count <= ArchiveReadClient.markdownLimit else { throw ArchiveError.tooLarge }
        guard epoch == generation, let raw = String(data: bytes, encoding: .utf8) else { throw CancellationError() }
        let parsed = ClipMetadataReader.read(raw, file: file)
        // Opening a previously uncached current article expands metadata/search coverage.
        // An old pinned citation must never replace metadata from the current inventory.
        let isCurrent = snapshot?.files.contains(where: { $0.path == file.path && $0.sha == file.sha }) == true
        if let identity, let manifest = try await ArchiveRefreshCoordinator.store(identity: identity, cache: cache, index: searchIndex,
                                                                                  bytes: bytes, file: file, clip: isCurrent ? parsed : nil) {
            guard epoch == generation else { throw CancellationError() }
            if isCurrent {
                clips = manifest.clips
                indexedCount = (try? await searchIndex?.count()) ?? 0
                guard epoch == generation else { throw CancellationError() }
            }
        }
        return (parsed, raw)
    }

    func readerSnapshot(for clip: ArchiveClip) -> ArchiveSnapshot? {
        pinnedClip?.sha == clip.sha && pinnedClip?.path == clip.path ? pinnedSnapshot : snapshot
    }

    func select(_ path: String) {
        pinnedClip = nil; pinnedSnapshot = nil; selectedPath = path; sourceFragment = nil
    }

    func consumeOpenRequest() -> Bool {
        guard let identity, let value = UserDefaults.standard.string(forKey: "SourceBraid.pendingClip") else { return false }
        guard value.hasPrefix(identity.cacheKey + ":") else {
            UserDefaults.standard.removeObject(forKey: "SourceBraid.pendingClip"); return false
        }
        let path = String(value.dropFirst(identity.cacheKey.count + 1))
        guard clips.contains(where: { $0.path == path }) else { return false }
        UserDefaults.standard.removeObject(forKey: "SourceBraid.pendingClip")
        select(path); return true
    }

    func openCitation(_ source: SourceExcerpt, snapshot inventory: ArchiveSnapshot) async throws {
        guard inventory.identity == identity, let cache, let client,
              let file = inventory.files.first(where: { $0.path == source.path && $0.sha == source.sha }) else { throw ArchiveError.invalidPath }
        guard file.size <= ArchiveReadClient.markdownLimit else { throw ArchiveError.tooLarge }
        let epoch = generation
        let bytes: Data
        if let local = try await cache.data(sha: file.sha, limit: ArchiveReadClient.markdownLimit) { bytes = local }
        else {
            bytes = try await client.read(file, limit: ArchiveReadClient.markdownLimit)
            try Task.checkCancellation()
            guard epoch == generation else { throw CancellationError() }
            if let identity { _ = try await ArchiveRefreshCoordinator.store(identity: identity, cache: cache, index: nil, bytes: bytes, file: file) }
        }
        guard bytes.count <= ArchiveReadClient.markdownLimit else { throw ArchiveError.tooLarge }
        guard epoch == generation, let raw = String(data: bytes, encoding: .utf8) else { throw CancellationError() }
        pinnedClip = ClipMetadataReader.read(raw, file: file); pinnedSnapshot = inventory
        selectedPath = source.path; sourceFragment = "source-L\(source.line)"
    }

    func asset(_ path: String, snapshot inventory: ArchiveSnapshot) async throws -> Data {
        guard inventory.identity == identity, let cache, let client,
              let file = inventory.files.first(where: { $0.path == path }) else { throw ArchiveError.invalidPath }
        if let local = try await cache.data(sha: file.sha) { return local }
        let epoch = generation
        let bytes = try await client.read(file, limit: ArchiveReadClient.assetLimit)
        try Task.checkCancellation()
        guard epoch == generation else { throw CancellationError() }
        if let identity { _ = try await ArchiveRefreshCoordinator.store(identity: identity, cache: cache, index: nil, bytes: bytes, file: file) }
        guard epoch == generation else { throw CancellationError() }
        return bytes
    }

    func removeLocalData(signOut: Bool = false, broadcast: Bool = true) async {
        let previousTask = syncTask
        previousTask?.cancel(); generation = UUID()
        if broadcast { NotificationCenter.default.post(name: .archiveDataRemoved, object: self, userInfo: ["signOut": signOut]) }
        await previousTask?.value
        let pause = await ArchiveRefreshCoordinator.pause(for: identity)
        defer { ArchiveRefreshCoordinator.resume(pause) }
        syncTask = nil; isSyncing = false
        selectedPath = nil; sourceFragment = nil; clips = []; snapshot = nil; readingPositions = [:]; metadataComplete = false
        pinnedClip = nil; pinnedSnapshot = nil
        indexedCount = 0
        do {
            if signOut {
                try KeychainStore().setToken("")
                UserDefaults.standard.removeObject(forKey: "SourceBraid.pendingClip")
                UserDefaults(suiteName: SourceBraidEnvironment.appGroupIdentifier)?.removeObject(forKey: SourceBraidEnvironment.recentCapturesKey)
                client = nil; identity = nil
            }
            if let cache { try await cache.clear() }
            status = archiveText("Local data removed. GitHub files are unchanged.", "Lokale Daten entfernt. GitHub-Dateien bleiben erhalten.")
        } catch { status = error.localizedDescription }
    }
}

extension Notification.Name {
    static let archiveDataRemoved = Notification.Name("SourceBraid.ArchiveDataRemoved")
}

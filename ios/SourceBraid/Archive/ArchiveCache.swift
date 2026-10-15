import Foundation
import CryptoKit

actor ArchiveCache {
    struct Manifest: Codable, Sendable {
        var version = 1
        var snapshot: ArchiveSnapshot?
        var clips: [ArchiveClip] = []
        var metadataComplete = false
        // Optional for backwards-compatible decoding of existing version-1 catalogs.
        var indexComplete: Bool?
    }
    static let budget = 250 * 1024 * 1024
    let directory: URL
    private let byteBudget: Int
    private var manifest = Manifest()
    private var loaded = false

    init(identity: ArchiveIdentity, base: URL? = nil, budget: Int = ArchiveCache.budget) {
        byteBudget = budget
        let base = base ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SourceBraidArchive", isDirectory: true)
        directory = base.appendingPathComponent(identity.cacheKey, isDirectory: true)
    }

    func load() throws -> Manifest {
        if !loaded {
            try prepare()
            let catalog = directory.appendingPathComponent("catalog.json")
            if FileManager.default.fileExists(atPath: catalog.path) {
                // A locked/protected catalog is unavailable, not empty. Propagate I/O
                // errors so a scheduled refresh cannot overwrite it with a partial seed.
                guard (try catalog.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 32 * 1024 * 1024 else { throw ArchiveError.tooLarge }
                let bytes = try Data(contentsOf: catalog)
                if let value = try? JSONDecoder().decode(Manifest.self, from: bytes), value.version == 1 {
                    manifest = value
                }
            }
            loaded = true
        }
        return manifest
    }

    func begin(_ snapshot: ArchiveSnapshot) throws {
        _ = try load()
        let files = Dictionary(snapshot.files.map { ($0.path, $0.sha) }, uniquingKeysWith: { first, _ in first })
        var next = manifest
        next.clips = next.clips.filter { files[$0.path] == $0.sha }
        next.snapshot = snapshot; next.metadataComplete = false; next.indexComplete = false
        try commit(next)
    }

    func add(_ clip: ArchiveClip, raw: Data) throws {
        try store(raw, sha: clip.sha)
        try addMetadata(clip)
    }

    func addMetadata(_ clip: ArchiveClip) throws {
        _ = try load()
        var next = manifest
        next.clips.removeAll { $0.path == clip.path }
        next.clips.append(clip.withBody(""))
        next.clips.sort(by: ArchiveClip.newestFirst)
        try commit(next)
    }

    func finish(complete: Bool, indexComplete: Bool? = nil) throws {
        _ = try load()
        var next = manifest
        next.metadataComplete = complete
        next.indexComplete = indexComplete
        try commit(next)
    }

    func checked(_ snapshot: ArchiveSnapshot) throws {
        _ = try load()
        guard manifest.snapshot?.identity == snapshot.identity, manifest.snapshot?.commit == snapshot.commit else {
            throw ArchiveError.invalidResponse
        }
        var next = manifest
        next.snapshot = snapshot
        try commit(next)
    }

    func data(sha: String, limit: Int = ArchiveReadClient.assetLimit) throws -> Data? {
        guard ArchiveReadClient.validSHA(sha) else { throw ArchiveError.invalidPath }
        let path = directory.appendingPathComponent(sha)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= limit else { throw ArchiveError.tooLarge }
        let bytes = try Data(contentsOf: path)
        let actual = Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
        guard actual == sha else { try FileManager.default.removeItem(at: path); return nil }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        return bytes
    }

    func store(_ bytes: Data, sha: String) throws {
        guard ArchiveReadClient.validSHA(sha), bytes.count <= ArchiveReadClient.assetLimit else { throw ArchiveError.tooLarge }
        try prepare()
        let url = directory.appendingPathComponent(sha)
        let replacedSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try reserve(bytes.count - replacedSize, excluding: url)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func reserve(_ extra: Int, excluding url: URL) throws {
        // Old downloaded bodies/assets can be evicted; metadata remains available.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        var used = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let evictable = try files.filter({ $0 != url && ArchiveReadClient.validSHA($0.lastPathComponent) }).map {
            ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
        }.sorted { $0.1 < $1.1 }
        for (file, _) in evictable {
            if used + extra <= byteBudget { break }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try FileManager.default.removeItem(at: file); used -= size
        }
        guard used + extra <= byteBudget else { throw ArchiveError.tooLarge }
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        manifest = Manifest(); loaded = false
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func persist() throws {
        try prepare()
        let url = directory.appendingPathComponent("catalog.json"), bytes = try JSONEncoder().encode(manifest)
        guard bytes.count <= 32 * 1024 * 1024 else { throw ArchiveError.tooLarge }
        let oldSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try reserve(bytes.count - oldSize, excluding: url)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func commit(_ next: Manifest) throws {
        let previous = manifest
        manifest = next
        do { try persist() }
        catch { manifest = previous; throw error }
    }
}

@MainActor
enum ArchiveServices {
    private static var caches: [ArchiveIdentity: ArchiveCache] = [:]
    static func cache(for identity: ArchiveIdentity) -> ArchiveCache {
        if let cache = caches[identity] { return cache }
        let cache = ArchiveCache(identity: identity); caches[identity] = cache
        return cache
    }
}

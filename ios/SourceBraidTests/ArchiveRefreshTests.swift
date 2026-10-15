import XCTest
import CryptoKit

private actor RefreshFixtureReader: ArchiveReading {
    nonisolated let identity: ArchiveIdentity
    private var inventory: ArchiveSnapshot
    private var documents: [String: Data]
    private(set) var reads: [String] = []
    private(set) var commitChecks = 0
    private(set) var inventoryWalks = 0
    private(set) var inventoryLimits: [Int?] = []
    var suspended = false

    init(identity: ArchiveIdentity, count: Int) {
        self.identity = identity
        let values = Self.makeDocuments(count: count)
        documents = values
        inventory = Self.makeSnapshot(identity: identity, documents: values, revision: "a")
    }

    func snapshot() async throws -> ArchiveSnapshot {
        inventoryWalks += 1
        return inventory
    }

    func snapshot(updating previous: ArchiveSnapshot?, requestLimit: Int?) async throws -> ArchiveSnapshot {
        try Task.checkCancellation()
        commitChecks += 1; inventoryLimits.append(requestLimit)
        if previous?.commit == inventory.commit { return inventory }
        return try await snapshot()
    }

    func read(_ file: ArchiveFile, limit: Int) async throws -> Data {
        reads.append(file.path)
        while suspended { try await Task.sleep(nanoseconds: 10_000_000) }
        try Task.checkCancellation()
        guard let bytes = documents[file.path], bytes.count <= limit else { throw ArchiveError.tooLarge }
        return bytes
    }

    func setSuspended(_ value: Bool) { suspended = value }
    func resetReads() { reads = [] }
    func currentSnapshot() -> ArchiveSnapshot { inventory }
    func changeAndDelete() {
        documents["clips/2026-10-12-article-01.md"] = Data("---\ntitle: Changed source\ncaptured_at: 2026-10-12T23:59:00Z\n---\nChanged searchable uniquephrase\n".utf8)
        documents.removeValue(forKey: "clips/2026-10-12-article-02.md")
        documents["clips/2026-10-13-new.md"] = Data("---\ntitle: New source\ncaptured_at: 2026-10-13T12:00:00Z\n---\nNew searchable fixture\n".utf8)
        inventory = Self.makeSnapshot(identity: identity, documents: documents, revision: "b")
    }

    private static func makeDocuments(count: Int) -> [String: Data] {
        var values: [String: Data] = [:]
        for number in 1...count {
            let suffix = String(format: "%02d", number)
            values["clips/2026-10-12-article-\(suffix).md"] = Data("---\ntitle: Fixture \(suffix)\ncaptured_at: 2026-10-12T12:\(suffix):00Z\n---\nSynthetic searchable article \(suffix)\n".utf8)
        }
        return values
    }

    private static func makeSnapshot(identity: ArchiveIdentity, documents: [String: Data], revision: Character) -> ArchiveSnapshot {
        let files = documents.map { path, bytes in
            let sha = Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
            return ArchiveFile(path: path, sha: sha, size: bytes.count)
        }.sorted { $0.path < $1.path }
        return ArchiveSnapshot(identity: identity, commit: String(repeating: String(revision), count: 40), files: files, checkedAt: Date())
    }
}

private actor FailingBudgetReader: ArchiveReading {
    nonisolated let inventory: ArchiveSnapshot
    private(set) var limits: [Int] = []
    init(identity: ArchiveIdentity, declaredSize: Int) {
        inventory = ArchiveSnapshot(identity: identity, commit: String(repeating: "c", count: 40), files: (1...3).map {
            ArchiveFile(path: "clips/2026-10-12-failing-\($0).md", sha: String(repeating: String($0), count: 40), size: declaredSize)
        }, checkedAt: Date())
    }
    func snapshot() async throws -> ArchiveSnapshot { inventory }
    func read(_ file: ArchiveFile, limit: Int) async throws -> Data {
        limits.append(limit)
        throw ArchiveError.invalidResponse
    }
}

@MainActor
final class ArchiveRefreshTests: XCTestCase {
    private var temporary: URL!
    override func setUp() {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sourcebraid-refresh-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: temporary) }

    private func fixture(count: Int) throws -> (RefreshFixtureReader, ArchiveCache, ArchiveLibrary) {
        let identity = try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "fixture-\(UUID().uuidString)", branch: "main", rootFolder: "clips"))
        let reader = RefreshFixtureReader(identity: identity, count: count)
        let cache = ArchiveCache(identity: identity, base: temporary)
        return (reader, cache, ArchiveLibrary(reader: reader, cache: cache, identity: identity))
    }

    private func waitForRead(_ reader: RefreshFixtureReader) async throws {
        for _ in 0..<100 {
            if await !reader.reads.isEmpty { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The synthetic body request did not start")
    }

    func testColdLaunchSeedsAtMostSevenAndForegroundDoesNotRepeatDownload() async throws {
        let (reader, _, library) = try fixture(count: 31)
        await library.configure(); await library.waitForSync()
        let firstReads = await reader.reads
        XCTAssertEqual(firstReads.count, 7)
        XCTAssertEqual(library.clips.count, 7)
        XCTAssertEqual(library.inventoryClipCount, 31, "Coverage must include articles not downloaded yet")
        XCTAssertEqual(library.indexedCount, 7)
        XCTAssertFalse(library.metadataComplete)
        XCTAssertEqual(library.lastRefreshReport?.remaining, 24)
        await library.configure(); await library.configure(); await library.waitForSync()
        let laterReads = await reader.reads, checks = await reader.commitChecks
        XCTAssertEqual(laterReads, firstReads)
        XCTAssertEqual(checks, 1, "Foreground/settings reload must not even check GitHub")
    }

    func testWarmLaunchUsesCachedMetadataWithoutNetwork() async throws {
        let (reader, cache, original) = try fixture(count: 8)
        original.synchronize(); await original.waitForSync()
        await reader.resetReads()
        let restored = ArchiveLibrary(reader: reader, cache: cache, identity: reader.identity)
        await restored.configure()
        let reads = await reader.reads, checks = await reader.commitChecks
        XCTAssertTrue(reads.isEmpty)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(restored.clips.count, 8)
        XCTAssertEqual(restored.inventoryClipCount, 8)
        XCTAssertEqual(restored.indexedCount, 8)
        XCTAssertEqual(restored.recent.count, 7)
        XCTAssertTrue(restored.metadataComplete)
        XCTAssertEqual(restored.recent.map(\.path), original.recent.map(\.path))
    }

    func testUnchangedCommitSkipsTreesBodiesAndPreservesIndex() async throws {
        let (reader, _, library) = try fixture(count: 8)
        library.synchronize(); await library.waitForSync()
        await reader.resetReads()
        library.synchronize(); await library.waitForSync()
        let reads = await reader.reads, walks = await reader.inventoryWalks, checks = await reader.commitChecks
        XCTAssertTrue(reads.isEmpty)
        XCTAssertEqual(walks, 1)
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(library.lastRefreshReport?.state, .unchanged)
        XCTAssertEqual(library.indexedCount, 8)
    }

    func testChangedAndNewBodiesAreReadAndDeletedMetadataAndSearchAreRemoved() async throws {
        let (reader, _, library) = try fixture(count: 8)
        library.synchronize(); await library.waitForSync()
        await reader.resetReads(); await reader.changeAndDelete()
        library.synchronize(); await library.waitForSync()
        let reads = await reader.reads
        XCTAssertEqual(Set(reads), ["clips/2026-10-12-article-01.md", "clips/2026-10-13-new.md"])
        XCTAssertFalse(library.clips.contains { $0.path.hasSuffix("article-02.md") })
        XCTAssertEqual(library.recent.first?.title, "New source")
        let hits = try await library.search("uniquephrase")
        XCTAssertEqual(hits.map(\.title), ["Changed source"])
        let indexed = try await library.searchIndex?.indexedFiles()
        XCTAssertNil(indexed?["clips/2026-10-12-article-02.md"])
        XCTAssertTrue(library.metadataComplete)
    }

    func testBackgroundBatchIsTwentyAndNextBatchFinishesWithoutRepeatingBodies() async throws {
        let (reader, _, library) = try fixture(count: 31)
        await library.configure(); await library.waitForSync()
        await reader.resetReads()
        let first = await library.refreshInBackground()
        let firstReads = await reader.reads
        XCTAssertEqual(first.processed, 20)
        XCTAssertEqual(first.remaining, 4)
        XCTAssertTrue(first.succeeded)
        XCTAssertEqual(firstReads.count, 20)
        XCTAssertFalse(library.metadataComplete)
        await reader.resetReads()
        let second = await library.refreshInBackground()
        let secondReads = await reader.reads, limits = await reader.inventoryLimits
        XCTAssertEqual(second.processed, 4)
        XCTAssertEqual(second.remaining, 0)
        XCTAssertEqual(secondReads.count, 4)
        XCTAssertTrue(Set(firstReads).isDisjoint(with: secondReads))
        XCTAssertEqual(limits.compactMap { $0 }, [32, 32, 32])
        XCTAssertTrue(library.metadataComplete)
    }

    func testOpeningUnseededCurrentArticleExpandsMetadataAndSearch() async throws {
        let (reader, _, library) = try fixture(count: 10)
        await library.configure(); await library.waitForSync()
        let snapshot = await reader.currentSnapshot()
        let file = try XCTUnwrap(snapshot.files.first { file in !library.clips.contains { $0.path == file.path } })
        let placeholder = ClipMetadataReader.read("", file: file)
        let (loaded, _) = try await library.document(placeholder, snapshot: snapshot)
        XCTAssertFalse(loaded.titleIsFilename)
        XCTAssertTrue(library.clips.contains { $0.path == file.path && $0.title == loaded.title })
        let indexed = try await library.searchIndex?.indexedFiles()
        XCTAssertEqual(indexed?[file.path], file.sha)
        XCTAssertEqual(library.indexedCount, 8)
        XCTAssertFalse(library.metadataComplete)
    }

    func testCancellingBackgroundReadPreventsBodyAndIndexWrite() async throws {
        let (reader, cache, library) = try fixture(count: 8)
        await library.configure(bootstrapIfEmpty: false)
        await reader.setSuspended(true)
        let task = Task { await library.refreshInBackground() }
        try await waitForRead(reader)
        task.cancel()
        let report = await task.value
        let manifest = try await cache.load(), count = try await library.searchIndex?.count()
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertTrue(manifest.clips.isEmpty)
        XCTAssertEqual(count, 0)
        XCTAssertFalse(library.isSyncing)
    }

    func testLocalRemovalCancelsOtherWindowBackgroundWriterBeforeDeleting() async throws {
        let (reader, cache, foreground) = try fixture(count: 8)
        let background = ArchiveLibrary(reader: reader, cache: cache, identity: reader.identity)
        await foreground.configure(bootstrapIfEmpty: false)
        await background.configure(bootstrapIfEmpty: false)
        await reader.setSuspended(true)
        let task = Task { await background.refreshInBackground() }
        try await waitForRead(reader)
        await foreground.removeLocalData(broadcast: false)
        let report = await task.value
        let manifest = try await cache.load(), count = try await foreground.searchIndex?.count()
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertNil(manifest.snapshot)
        XCTAssertTrue(manifest.clips.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testConfigurationInvalidationCancelsWriterAndNoOldResultIsApplied() async throws {
        let (reader, _, library) = try fixture(count: 8)
        await library.configure(bootstrapIfEmpty: false)
        await reader.setSuspended(true)
        let task = Task { await library.refreshInBackground() }
        try await waitForRead(reader)
        await ArchiveBackgroundRefresh.invalidateAndWait()
        let report = await task.value
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertTrue(library.clips.isEmpty)
        await reader.setSuspended(false)
        let next = await library.refreshInBackground()
        XCTAssertTrue(next.succeeded)
        XCTAssertEqual(library.clips.count, 8)
    }

    func testFailedReadsStillConsumeBackgroundByteBudget() async throws {
        let identity = try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "budget-fixture", branch: "main", rootFolder: "clips"))
        let reader = FailingBudgetReader(identity: identity, declaredSize: 4 * 1024 * 1024)
        let library = ArchiveLibrary(reader: reader, cache: ArchiveCache(identity: identity, base: temporary), identity: identity)
        let report = await library.refreshInBackground()
        let limits = await reader.limits
        XCTAssertEqual(limits, [4 * 1024 * 1024, 4 * 1024 * 1024])
        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(report.remaining, 3)
        XCTAssertEqual(library.clips.count, 2, "Failed known paths stay selectable")
    }

    func testUnknownSizesReserveEntireAllowedBodyBudget() async throws {
        let identity = try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "zero-size-fixture", branch: "main", rootFolder: "clips"))
        let reader = FailingBudgetReader(identity: identity, declaredSize: 0)
        let library = ArchiveLibrary(reader: reader, cache: ArchiveCache(identity: identity, base: temporary), identity: identity)
        _ = await library.refreshInBackground()
        let limits = await reader.limits
        XCTAssertEqual(limits, [5 * 1024 * 1024, 5 * 1024 * 1024])
    }

    func testUnavailableCatalogStopsRefreshWithoutTreatingItAsEmpty() async throws {
        let (reader, cache, library) = try fixture(count: 8)
        let catalog = cache.directory.appendingPathComponent("catalog.json")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        let sentinel = catalog.appendingPathComponent("synthetic-preserve.txt")
        try Data("Synthetic inaccessible-catalog fixture".utf8).write(to: sentinel)
        let report = await library.refreshInBackground()
        let checks = await reader.commitChecks
        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(checks, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        try FileManager.default.removeItem(at: catalog)
        try JSONEncoder().encode(ArchiveCache.Manifest()).write(to: catalog)
        let recovered = try await cache.load()
        XCTAssertNil(recovered.snapshot, "An I/O failure must not latch an empty loaded catalog")
    }

    func testCatalogPersistenceFailureRollsBackInMemorySnapshot() async throws {
        let (reader, _, _) = try fixture(count: 8)
        let cache = ArchiveCache(identity: reader.identity, base: temporary, budget: 64)
        let inventory = await reader.currentSnapshot()
        do { try await cache.begin(inventory); XCTFail("Synthetic storage budget was ignored") }
        catch { XCTAssertEqual(error as? ArchiveError, .tooLarge) }
        let manifest = try await cache.load()
        XCTAssertNil(manifest.snapshot)
        XCTAssertTrue(manifest.clips.isEmpty)
    }
}

private final class RefreshTransportProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let bytes = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ArchiveRefreshTransportTests: XCTestCase {
    override func tearDown() { RefreshTransportProtocol.handler = nil }
    private func fixture() throws -> (ArchiveIdentity, ArchiveReadClient) {
        let identity = try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "fixture", branch: "main", rootFolder: "clips"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshTransportProtocol.self]
        return (identity, ArchiveReadClient(identity: identity, token: "synthetic-test-token", session: URLSession(configuration: configuration)))
    }

    func testSameCommitMakesExactlyOneCommitRequestAndNoTreeRequest() async throws {
        let (identity, reader) = try fixture()
        let commit = String(repeating: "a", count: 40), tree = String(repeating: "b", count: 40)
        var requests = 0
        RefreshTransportProtocol.handler = { request in
            requests += 1
            XCTAssertTrue(request.url!.path.contains("/commits/"))
            XCTAssertEqual(request.httpMethod, "GET")
            return Data("{\"sha\":\"\(commit)\",\"commit\":{\"tree\":{\"sha\":\"\(tree)\"}}}".utf8)
        }
        let previous = ArchiveSnapshot(identity: identity, commit: commit, files: [.init(path: "clips/synthetic.md", sha: tree, size: 17)], checkedAt: .distantPast)
        let result = try await reader.snapshot(updating: previous, requestLimit: 32)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(result.files, previous.files)
        XCTAssertGreaterThan(result.checkedAt, previous.checkedAt)
    }

    func testInventoryRequestBudgetStopsBeforeAdditionalTreeRequest() async throws {
        let (_, reader) = try fixture()
        let commit = String(repeating: "a", count: 40), tree = String(repeating: "b", count: 40)
        var requests = 0
        RefreshTransportProtocol.handler = { _ in
            requests += 1
            return Data("{\"sha\":\"\(commit)\",\"commit\":{\"tree\":{\"sha\":\"\(tree)\"}}}".utf8)
        }
        do { _ = try await reader.snapshot(updating: nil, requestLimit: 1); XCTFail("Inventory budget was ignored") }
        catch { XCTAssertEqual(error as? ArchiveError, .incompleteTree) }
        XCTAssertEqual(requests, 1)
    }
}

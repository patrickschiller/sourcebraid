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
    private var suspendAfterReads: Int?
    private var holdCancelledRead = false
    private var cancelledReadContinuation: CheckedContinuation<Void, Never>?
    private(set) var cancelledReadIsHeld = false

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
        while suspended || suspendAfterReads.map({ reads.count > $0 }) == true {
            do { try await Task.sleep(nanoseconds: 10_000_000) }
            catch {
                if holdCancelledRead {
                    cancelledReadIsHeld = true
                    await withCheckedContinuation { cancelledReadContinuation = $0 }
                }
                throw error
            }
        }
        try Task.checkCancellation()
        guard let bytes = documents[file.path], bytes.count <= limit else { throw ArchiveError.tooLarge }
        return bytes
    }

    func setSuspended(_ value: Bool) { suspended = value }
    func setSuspendAfterReads(_ value: Int?) { suspendAfterReads = value }
    func setHoldCancelledRead(_ value: Bool) { holdCancelledRead = value }
    func releaseCancelledRead() {
        holdCancelledRead = false
        cancelledReadContinuation?.resume(); cancelledReadContinuation = nil
    }
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

private struct DocumentBytesReader: ArchiveReading {
    let inventory: ArchiveSnapshot
    let bytes: Data
    func snapshot() async throws -> ArchiveSnapshot { inventory }
    func read(_ file: ArchiveFile, limit: Int) async throws -> Data {
        guard bytes.count <= limit else { throw ArchiveError.tooLarge }
        return bytes
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

    private func waitForRead(_ reader: RefreshFixtureReader, count: Int = 1) async throws {
        for _ in 0..<100 {
            if await reader.reads.count >= count { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The synthetic body request did not start")
    }

    private func documentFixture(bytes: Data, cached: Bool) async throws -> (ArchiveLibrary, ArchiveClip, ArchiveSnapshot) {
        let identity = try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "encoding-\(UUID().uuidString)", branch: "main", rootFolder: "clips"))
        let sha = Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
        let file = ArchiveFile(path: "clips/synthetic-encoding.md", sha: sha, size: bytes.count)
        let inventory = ArchiveSnapshot(identity: identity, commit: String(repeating: "a", count: 40), files: [file], checkedAt: Date())
        let clip = ClipMetadataReader.read("", file: file)
        let cache = ArchiveCache(identity: identity, base: temporary)
        try await cache.begin(inventory); try await cache.addMetadata(clip)
        if cached { try await cache.store(bytes, sha: sha) }
        let library = ArchiveLibrary(reader: DocumentBytesReader(inventory: inventory, bytes: bytes), cache: cache, identity: identity)
        await library.configure(bootstrapIfEmpty: false)
        library.select(clip.path)
        return (library, clip, inventory)
    }

    func testInvalidUTF8DocumentAndCitationProduceVisibleErrorRatherThanCancellation() async throws {
        for cached in [false, true] {
            let (library, clip, inventory) = try await documentFixture(bytes: Data([0x23, 0x20, 0xC3, 0x28]), cached: cached)
            do { _ = try await library.document(clip); XCTFail("Invalid UTF-8 must not leave a reader silently loading") }
            catch { XCTAssertEqual(error as? ArchiveError, .invalidEncoding, "Cached and network bytes need the same visible encoding error") }
            XCTAssertEqual(library.selectedPath, clip.path)
            XCTAssertNotNil(inventory.githubURL(for: clip.path), "The invalid file remains available through GitHub fallback")
            let source = SourceExcerpt(id: "S1", path: clip.path, sha: clip.sha, title: clip.title, line: 1, text: "Synthetic encoding fixture")
            do { try await library.openCitation(source, snapshot: inventory); XCTFail("Invalid citation bytes must report their encoding") }
            catch { XCTAssertEqual(error as? ArchiveError, .invalidEncoding) }
            XCTAssertNil(library.pinnedClip, "An invalid citation must not become the current pinned document")
        }
    }

    func testActualCancellationOfCachedDocumentAndCitationRemainsCancellation() async throws {
        let (library, clip, inventory) = try await documentFixture(bytes: Data("# Valid synthetic UTF-8\n".utf8), cached: true)
        let document = Task { try await library.document(clip) }
        document.cancel()
        do { _ = try await document.value; XCTFail("A cancelled read must not finish") }
        catch { XCTAssertTrue(error is CancellationError) }
        let source = SourceExcerpt(id: "S1", path: clip.path, sha: clip.sha, title: clip.title, line: 1, text: "Synthetic cancellation fixture")
        let citation = Task { try await library.openCitation(source, snapshot: inventory) }
        citation.cancel()
        do { try await citation.value; XCTFail("A cancelled citation must not become pinned") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(library.pinnedClip)
        let (_, raw) = try await library.document(clip)
        XCTAssertEqual(raw, "# Valid synthetic UTF-8\n", "A cancelled request must not poison a later valid read")
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

    func testInterruptedFirstLaunchKeepsCommittedClipAndResumesOnlyMissingSeedSlots() async throws {
        let (reader, _, original) = try fixture(count: 31)
        await reader.setSuspendAfterReads(1)
        await original.configure()
        try await waitForRead(reader, count: 2)
        original.stopSync(); await original.waitForSync()
        XCTAssertEqual(original.lastRefreshReport?.state, .cancelled)
        XCTAssertEqual(original.clips.count, 1, "A stopped refresh must expose its atomically committed progress")
        XCTAssertEqual(original.indexedCount, 1)
        XCTAssertEqual(original.inventoryClipCount, 31)

        await reader.setSuspendAfterReads(nil); await reader.resetReads()
        let restoredCache = ArchiveCache(identity: reader.identity, base: temporary)
        let restored = ArchiveLibrary(reader: reader, cache: restoredCache, identity: reader.identity)
        await restored.configure(); await restored.waitForSync()
        let resumedReads = await reader.reads
        XCTAssertEqual(resumedReads.count, 6, "An interrupted one-clip seed must fill six slots, without an automatic full download")
        XCTAssertEqual(restored.clips.count, 7)
        XCTAssertEqual(restored.indexedCount, 7)
        XCTAssertEqual(restored.lastRefreshReport?.remaining, 24)
        XCTAssertFalse(restored.metadataComplete)
        XCTAssertEqual(Set(resumedReads).count, 6)
        XCTAssertFalse(resumedReads.contains(original.clips[0].path), "The committed first body must be reused")

        await reader.resetReads()
        await restored.configure(); await restored.waitForSync()
        let foregroundReads = await reader.reads
        XCTAssertTrue(foregroundReads.isEmpty, "A completed seed restores without further foreground downloads")

        restored.synchronize(); await restored.waitForSync()
        let explicitReads = await reader.reads
        XCTAssertEqual(explicitReads.count, 24)
        XCTAssertEqual(restored.clips.count, 31)
        XCTAssertEqual(restored.indexedCount, 31)
        XCTAssertTrue(restored.metadataComplete)
        XCTAssertEqual(restored.lastRefreshReport?.remaining, 0)
    }

    func testInventorySavedBeforeAnyBodyStillResumesBootstrap() async throws {
        let (reader, cache, library) = try fixture(count: 10)
        let inventory = await reader.currentSnapshot()
        try await cache.begin(inventory)
        await library.configure(); await library.waitForSync()
        let reads = await reader.reads
        XCTAssertEqual(reads.count, 7)
        XCTAssertEqual(library.clips.count, 7)
        XCTAssertEqual(library.lastRefreshReport?.remaining, 3)
        XCTAssertFalse(library.metadataComplete)
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory.path), "Cancellation recovery must not recreate the deleted cache directory")
        let manifest = try await cache.load(), count = try await foreground.searchIndex?.count()
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertNil(manifest.snapshot)
        XCTAssertTrue(manifest.clips.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testLocalRemovalWaitsForCancelledReadCleanupAndDoesNotRecreateCache() async throws {
        let (reader, cache, foreground) = try fixture(count: 8)
        let background = ArchiveLibrary(reader: reader, cache: cache, identity: reader.identity)
        await foreground.configure(bootstrapIfEmpty: false)
        await background.configure(bootstrapIfEmpty: false)
        await reader.setSuspended(true); await reader.setHoldCancelledRead(true)
        let refresh = Task { await background.refreshInBackground() }
        try await waitForRead(reader)
        let removal = Task { await foreground.removeLocalData(broadcast: false) }
        for _ in 0..<100 {
            if await reader.cancelledReadIsHeld { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let cancellationHeld = await reader.cancelledReadIsHeld
        XCTAssertTrue(cancellationHeld, "The synthetic reader must hold cancellation cleanup until explicitly released")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.directory.appendingPathComponent("catalog.json").path),
            "Removal must wait for the tracked reader cleanup before deleting the catalog")
        await reader.releaseCancelledRead()
        await removal.value
        let report = await refresh.value
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory.path), "No late recovery read may recreate a removed cache")
        let manifest = try await cache.load()
        XCTAssertNil(manifest.snapshot)
        XCTAssertTrue(manifest.clips.isEmpty)
        XCTAssertTrue(foreground.clips.isEmpty)
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

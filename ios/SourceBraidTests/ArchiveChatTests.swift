import XCTest
import CryptoKit

@MainActor
final class ArchiveChatTests: XCTestCase {
    private var temporary: URL!
    override func setUp() { temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: temporary) }

    private func library() async throws -> ArchiveLibrary {
        let reader = try ArchiveDemoReader()
        let library = ArchiveLibrary(reader: reader, cache: ArchiveCache(identity: reader.identity, base: temporary), identity: reader.identity)
        library.synchronize(); await library.waitForSync()
        XCTAssertEqual(library.recent.count, 7)
        XCTAssertTrue(library.metadataComplete)
        XCTAssertEqual(library.indexedCount, 7)
        library.select(library.recent[0].path)
        return library
    }

    func testAnswerScopeStaysOnSubmittedClipAndCitationsOpenPinnedVersion() async throws {
        let library = try await library(), model = FakeArchiveAnswering(delay: true)
        let selected = try XCTUnwrap(library.selected)
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.draft = "Summarize this synthetic document"; chat.send(library: library)
        while model.received.isEmpty { await Task.yield() }
        library.select(library.recent[1].path)
        model.release()
        await chat.waitForAnswer()
        let answer = try XCTUnwrap(chat.messages.last)
        XCTAssertFalse(answer.incomplete)
        XCTAssertEqual(answer.sources.first?.path, selected.path)
        try await library.openCitation(try XCTUnwrap(answer.sources.first), snapshot: try XCTUnwrap(answer.snapshot))
        XCTAssertEqual(library.selected?.sha, selected.sha)
        XCTAssertTrue(library.sourceFragment?.hasPrefix("source-L") == true)
        XCTAssertNotNil(library.pinnedClip)
    }

    func testInventedCitationDoesNotBecomeVerifiedAnswer() async throws {
        let library = try await library(), model = FakeArchiveAnswering(inventCitation: true)
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.draft = "Summary"; chat.send(library: library); await chat.waitForAnswer()
        XCTAssertTrue(chat.messages.last?.incomplete == true)
        XCTAssertTrue(chat.messages.last?.sources.isEmpty == true)
        XCTAssertFalse(chat.error.isEmpty)
    }

    func testArchiveSearchProvidesBoundedEvidence() async throws {
        let library = try await library(), model = FakeArchiveAnswering()
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.wholeArchive = true; chat.draft = "Markdown scrolling"; chat.send(library: library); await chat.waitForAnswer()
        XCTAssertEqual(model.received.count, 1)
        XCTAssertLessThanOrEqual(model.received[0].count, 4)
        XCTAssertLessThanOrEqual(model.received[0].reduce(0) { $0 + $1.text.count }, 4500)
        XCTAssertFalse(chat.messages.last?.incomplete ?? true)
    }

    func testResetDuringGenerationDoesNotRestoreOldMessages() async throws {
        let library = try await library(), model = FakeArchiveAnswering(delay: true)
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.draft = "Summary"; chat.send(library: library)
        while model.received.isEmpty { await Task.yield() }
        chat.reset(); model.release(); await chat.waitForAnswer()
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertFalse(chat.isWorking)
        XCTAssertTrue(chat.error.isEmpty)
    }

    func testArchiveClearDuringGenerationCannotDeliverAnswer() async throws {
        let library = try await library(), model = FakeArchiveAnswering(delay: true)
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.draft = "Summary"; chat.send(library: library)
        while model.received.isEmpty { await Task.yield() }
        await library.removeLocalData(); model.release(); await chat.waitForAnswer()
        XCTAssertTrue(chat.messages.last?.incomplete == true)
        XCTAssertTrue(chat.messages.last?.sources.isEmpty == true)
        XCTAssertTrue(library.clips.isEmpty)
        let manifest = try await XCTUnwrap(library.cache).load()
        XCTAssertNil(manifest.snapshot)
    }

    func testUnavailableStatesAndQuestionLimitNeverCallModel() async throws {
        let library = try await library(), model = FakeArchiveAnswering()
        for state in IntelligenceState.allCases where state != .ready {
            let chat = ArchiveChat(service: model, availability: { state })
            chat.draft = "Summary"; chat.send(library: library)
            XCTAssertTrue(chat.messages.isEmpty)
            XCTAssertFalse(chat.isWorking)
            XCTAssertFalse(state.message.isEmpty)
        }
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.draft = String(repeating: "x", count: 1201); chat.send(library: library)
        XCTAssertFalse(chat.error.isEmpty)
        XCTAssertTrue(model.received.isEmpty)
    }

    func testStopDiscardsPartialAnswer() async throws {
        let library = try await library(), model = FakeArchiveAnswering(delay: true)
        let chat = ArchiveChat(service: model, availability: { .ready })
        chat.draft = "Summary"; chat.send(library: library)
        while model.received.isEmpty { await Task.yield() }
        chat.stop(); model.release(); await chat.waitForAnswer()
        XCTAssertTrue(chat.messages.last?.incomplete == true)
        XCTAssertTrue(chat.messages.last?.sources.isEmpty == true)
        XCTAssertFalse(chat.isWorking)
    }

    func testToolBudgetRejectsExcessCallsAndBytes() async throws {
        let budget = ArchiveToolBudget()
        for _ in 0..<6 { _ = try await budget.spend("synthetic") }
        do { _ = try await budget.spend("seventh"); XCTFail("Expected call limit") } catch { }
        do { _ = try await ArchiveToolBudget().spend(String(repeating: "x", count: 6001)); XCTFail("Expected size limit") } catch { }
    }

    func testChatKeepsOnlyTenQuestionAnswerPairs() async throws {
        let library = try await library(), model = FakeArchiveAnswering()
        let chat = ArchiveChat(service: model, availability: { .ready })
        for number in 1...11 {
            chat.draft = "Synthetic question \(number)"; chat.send(library: library); await chat.waitForAnswer()
        }
        XCTAssertEqual(chat.messages.count, 20)
        XCTAssertEqual(chat.messages.first?.text, "Synthetic question 2")
        XCTAssertEqual(model.received.count, 11)
    }

    func testOversizedDocumentRemainsSelectableWithGitHubFallback() async throws {
        let identity = try ArchiveDemoReader().identity
        let path = "clips/2026-10-12-large.md"
        let file = ArchiveFile(path: path, sha: String(repeating: "a", count: 40), size: ArchiveReadClient.markdownLimit + 1)
        let snapshot = ArchiveSnapshot(identity: identity, commit: String(repeating: "b", count: 40), files: [file], checkedAt: Date())
        let library = ArchiveLibrary(reader: OversizedReader(inventory: snapshot), cache: ArchiveCache(identity: identity, base: temporary), identity: identity)
        library.synchronize(); await library.waitForSync()
        XCTAssertFalse(library.metadataComplete)
        XCTAssertEqual(library.recent.first?.path, path)
        XCTAssertTrue(library.recent.first?.titleIsFilename == true)
        XCTAssertNotNil(library.snapshot?.githubURL(for: path))
        library.select(path)
        do { _ = try await library.document(try XCTUnwrap(library.selected)); XCTFail("Expected size error") }
        catch { XCTAssertEqual(error as? ArchiveError, .tooLarge) }
    }

    func testCachedAssetCannotBypassMarkdownLimit() async throws {
        let identity = try ArchiveDemoReader().identity
        let bytes = Data(repeating: 65, count: ArchiveReadClient.markdownLimit + 1)
        let sha = Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
        let file = ArchiveFile(path: "clips/cached-large.md", sha: sha, size: bytes.count)
        let snapshot = ArchiveSnapshot(identity: identity, commit: String(repeating: "b", count: 40), files: [file], checkedAt: Date())
        let cache = ArchiveCache(identity: identity, base: temporary)
        try await cache.store(bytes, sha: sha)
        let library = ArchiveLibrary(reader: OversizedReader(inventory: snapshot), cache: cache, identity: identity)
        library.synchronize(); await library.waitForSync()
        XCTAssertFalse(library.metadataComplete)
        XCTAssertEqual(library.indexedCount, 0)
        let clip = try XCTUnwrap(library.recent.first)
        do { _ = try await library.document(clip); XCTFail("Cached asset bypassed Markdown limit") }
        catch { XCTAssertEqual(error as? ArchiveError, .tooLarge) }
    }

    func testArchiveScopeUsesCurrentInventoryWhileReaderShowsPinnedCitation() async throws {
        let reader = try SnapshotRefreshReader()
        let identity = reader.demo.identity
        let library = ArchiveLibrary(reader: reader, cache: ArchiveCache(identity: identity, base: temporary), identity: identity)
        library.synchronize(); await library.waitForSync()
        let original = try XCTUnwrap(library.snapshot), clip = try XCTUnwrap(library.recent.first)
        try await library.openCitation(SourceExcerpt(id: "S1", path: clip.path, sha: clip.sha, title: clip.title, line: 1, text: "synthetic"), snapshot: original)
        library.synchronize(); await library.waitForSync()
        XCTAssertNotEqual(library.snapshot?.commit, original.commit)
        XCTAssertEqual(library.readerSnapshot(for: clip)?.commit, original.commit)
        let chat = ArchiveChat(service: FakeArchiveAnswering(), availability: { .ready })
        chat.wholeArchive = true; chat.draft = "Markdown scrolling"; chat.send(library: library); await chat.waitForAnswer()
        XCTAssertFalse(chat.messages.last?.incomplete ?? true)
        XCTAssertEqual(chat.messages.last?.snapshot?.commit, library.snapshot?.commit)
    }
}

private actor SnapshotRefreshReader: ArchiveReading {
    nonisolated let demo: ArchiveDemoReader
    private var count = 0
    init() throws { demo = try ArchiveDemoReader() }
    func snapshot() async throws -> ArchiveSnapshot {
        count += 1
        return ArchiveSnapshot(identity: demo.identity, commit: String(repeating: count == 1 ? "a" : "b", count: 40), files: demo.inventory.files, checkedAt: Date())
    }
    func read(_ file: ArchiveFile, limit: Int) async throws -> Data { try await demo.read(file, limit: limit) }
}

private struct OversizedReader: ArchiveReading {
    let inventory: ArchiveSnapshot
    func snapshot() async throws -> ArchiveSnapshot { inventory }
    func read(_ file: ArchiveFile, limit: Int) async throws -> Data { throw ArchiveError.tooLarge }
}

@MainActor
private final class FakeArchiveAnswering: ArchiveAnswering {
    var received: [[SourceExcerpt]] = []
    private let inventCitation: Bool, delay: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    init(inventCitation: Bool = false, delay: Bool = false) { self.inventCitation = inventCitation; self.delay = delay }
    func release() { continuation?.resume(); continuation = nil }
    func answer(question: String, history: String, sources: [SourceExcerpt], recent: String,
                onUpdate: (String) -> Void) async throws -> (String, [String]) {
        received.append(sources)
        onUpdate("Synthetic partial response")
        if delay { await withCheckedContinuation { continuation = $0 } }
        try Task.checkCancellation()
        return ("Synthetic answer", [inventCitation ? "S999" : sources[0].id])
    }
}

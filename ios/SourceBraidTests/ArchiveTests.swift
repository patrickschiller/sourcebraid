import XCTest
import QuickLook
import CryptoKit
import PDFKit

final class ArchiveTests: XCTestCase {
    private let sha = String(repeating: "a", count: 40)
    private func identity(_ root: String = "clips") throws -> ArchiveIdentity {
        try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "fixture", branch: "main", rootFolder: root))
    }
    private func clip(_ header: String, path: String = "clips/2026/10/2026-10-12-fixture.md", body: String = "Synthetic text") -> ArchiveClip {
        ClipMetadataReader.read("---\n\(header)\n---\n\(body)", file: .init(path: path, sha: sha, size: 0))
    }

    func testRootAndResourceBoundaries() throws {
        for path in ["../clips", "/clips", "clips/../other", "clips//other", "clips/%2e%2e", "clips\\other"] {
            XCTAssertThrowsError(try identity(path), path)
        }
        XCTAssertEqual(try ArchivePath.resolve("assets/image.png", from: "clips/2026/article.md", root: "clips"), "clips/2026/assets/image.png")
        XCTAssertEqual(try ArchivePath.resolve("../other.md", from: "clips/2026/article.md", root: "clips"), "clips/other.md")
        for value in ["../../outside.md", "//attacker.invalid/x", "file:///tmp/private", "%2fprivate", "%252e%252e/x", "javascript:alert(1)"] {
            XCTAssertThrowsError(try ArchivePath.resolve(value, from: "clips/2026/article.md", root: "clips"), value)
        }
        for url in ["javascript:alert(1)", "file:///tmp/x", "data:text/html,test", "//attacker.invalid", "https://user:pass@example.invalid"] {
            XCTAssertNil(ArchivePath.externalURL(url))
        }
        XCTAssertNotNil(ArchivePath.externalURL("https://example.invalid/source"))
    }

    func testChronologyUsesUTCInstantsRatherThanPublicationOrPath() {
        let early = clip("title: Early\ncaptured_at: 2026-10-12T08:00:00Z\npublication_date: 2099-01-01", path: "clips/z.md")
        let later = clip("title: Later\ncaptured_at: 2026-10-12T11:00:00+02:00", path: "clips/a.md")
        XCTAssertEqual([early, later].sorted(by: ArchiveClip.newestFirst).map(\.title), ["Later", "Early"])
        XCTAssertEqual(later.datePrecision, "timestamp")
    }

    func testDateOnlyAndUndatedFallbackAreDeterministic() {
        let day = clip("capture_date: 2026-10-12", path: "clips/day.md")
        let path = clip("captured_at: malformed", path: "clips/2026-10-11-fixture.md")
        let noDate = clip("date: 2099-01-01", path: "clips/undated.md")
        XCTAssertNil(noDate.sortDate, "An unrelated date field is not capture provenance")
        XCTAssertEqual([noDate, path, day].sorted(by: ArchiveClip.newestFirst).map(\.path), [day.path, path.path, noDate.path])
        XCTAssertEqual(day.sortDate, ISO8601DateFormatter().date(from: "2026-10-12T00:00:00Z"))
        XCTAssertEqual(day.datePrecision, "day")
        XCTAssertNil(ClipMetadataReader.parseDay("2026-02-30"))
        XCTAssertNil(ClipMetadataReader.parseTimestamp("2026-10-12T10:00:00"))
    }

    func testMetadataKeepsBodyAndDoesNotInventTitleOrExecuteYAML() {
        let value = clip("author: 'O''Brien'\ntags:\n  - one\n  - \"two\"\nunknown: !execute unsafe", body: "# Heading\n\nOriginal source")
        XCTAssertTrue(value.titleIsFilename)
        XCTAssertEqual(value.author, "O'Brien")
        XCTAssertEqual(value.tags, ["one", "two"])
        XCTAssertEqual(value.body, "# Heading\n\nOriginal source")
        XCTAssertNil(value.sourceURL)
        let malformed = ClipMetadataReader.read("---\ntitle: Broken\n# no end", file: .init(path: "clips/x.md", sha: sha, size: 0))
        XCTAssertTrue(malformed.body.hasPrefix("---"))
    }

    func testMarkdownRequiredBlocksAndActiveContentSafety() {
        let body = """
        # Heading

        - one
          - nested
        - [x] complete

        > Quote

        | Name | Value |
        | --- | --- |
        | example | 42 |

        ```swift
        let text = "<script>"
        ```

        [Internal](../other.md) [Unsafe](javascript:alert) [Source](https://example.invalid)

        ![Local](assets/image.png) ![Remote](https://example.invalid/track.png)

        <script>alert('unsafe')</script>
        """
        let html = MarkdownRenderer.document(clip("title: Fixture", body: body), root: "clips")
        for required in ["<h1", "<ul", "<blockquote", "<table", "<pre", "checked", "sourcebraid-asset://local", "sourcebraid-document://local"] {
            XCTAssertTrue(html.contains(required), required)
        }
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("href='javascript:"))
        XCTAssertFalse(html.contains("src='https://"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("script-src 'none'"))
    }

    func testMermaidFencesKeepSourceAndNeverInsertExecutableContent() {
        let body = """
        ~~~MeRmAiD extra info
        flowchart LR
        A[\"</code><script>globalThis.pwned = true</script>\"] --> B
        ~~~

        ```swift
        mermaid is just code here
        ```
        """
        let html = MarkdownRenderer.document(clip("title: Diagram", body: body), root: "clips")
        XCTAssertEqual(html.components(separatedBy: "data-mermaid").count - 1, 1)
        XCTAssertTrue(html.contains("id='source-L1'"))
        XCTAssertTrue(html.contains("&lt;/code&gt;&lt;script&gt;"))
        XCTAssertTrue(html.contains("<details open>"), "Original source remains available if rendering fails")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("src='https://"))
        XCTAssertTrue(html.contains("script-src 'none'"))
    }

    func testBundledMermaidEngineIsPinnedAndAvailableOffline() throws {
        let bundle = Bundle(for: Self.self)
        let engine = try XCTUnwrap(bundle.url(forResource: "mermaid.tiny", withExtension: "js", subdirectory: "Mermaid"))
        let bytes = try Data(contentsOf: engine)
        let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(checksum, "ea0cdf04eb31907eb20d956a34fe300095365c876887b54ffa29f1f847f56d00")
        let adapter = try XCTUnwrap(bundle.url(forResource: "sourcebraid-mermaid", withExtension: "js", subdirectory: "Mermaid"))
        XCTAssertFalse(try Data(contentsOf: adapter).isEmpty)
    }

    func testCacheRebuildAndArchiveIsolation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let id = try identity(), other = try identity("other")
        let cache = ArchiveCache(identity: id, base: base)
        let value = clip("title: Cached")
        let snapshot = ArchiveSnapshot(identity: id, commit: sha, files: [.init(path: value.path, sha: sha, size: 9)], checkedAt: Date())
        try await cache.begin(snapshot)
        try await cache.add(value, raw: Data("synthetic".utf8))
        try await cache.finish(complete: true)
        let restored = ArchiveCache(identity: id, base: base)
        let manifest = try await restored.load()
        XCTAssertEqual(manifest.clips.map(\.title), ["Cached"])
        XCTAssertTrue(manifest.metadataComplete)
        XCTAssertTrue(manifest.clips[0].body.isEmpty)
        let isolated = try await ArchiveCache(identity: other, base: base).load()
        XCTAssertTrue(isolated.clips.isEmpty)
        try await restored.clear()
        let cleared = try await restored.load()
        XCTAssertTrue(cleared.clips.isEmpty)
    }

    @MainActor func testNativeMarkdownPreviewProbe() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("sourcebraid-native-probe-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("# Synthetic heading\n\n| A | B |\n|---|---|\n|1|2|\n".utf8).write(to: path)
        // Capability probe only. canPreview does not establish GFM rendering fidelity.
        let previewAvailable = QLPreviewController.canPreview(path as NSURL)
        print("Synthetic Markdown Quick Look capability: \(previewAvailable)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testSyntheticPDFContainsOneReadablePage() throws {
        let demo = try ArchiveDemoReader()
        let bytes = try XCTUnwrap(demo.documents["clips/2026/10/assets/synthetic.pdf"])
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), "SourceBraid synthetic PDF - no private content")
    }

    func testCacheEvictsOldBodiesAndRejectsCorruption() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = ArchiveCache(identity: try identity(), base: base, budget: 2200)
        let bytes = Data(repeating: 65, count: 1000), other = Data(repeating: 66, count: 1500)
        func sha(_ bytes: Data) -> String { Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined() }
        try await cache.store(bytes, sha: sha(bytes))
        try await cache.store(other, sha: sha(other))
        let evicted = try await cache.data(sha: sha(bytes)), retained = try await cache.data(sha: sha(other))
        XCTAssertNil(evicted); XCTAssertEqual(retained, other)
        try Data("tampered".utf8).write(to: cache.directory.appendingPathComponent(sha(other)))
        let corrupt = try await cache.data(sha: sha(other)); XCTAssertNil(corrupt)
    }

    func testFullTextSearchUpdatesDeletesAndRebuilds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = ArchiveSearchIndex(directory: directory)
        let german = clip("title: German source\ntags: [\"forschung\"]", path: "clips/german.md", body: "Die Forschung untersucht neuronale Netzwerke.")
        let english = clip("title: English source", path: "clips/english.md", body: "A synthetic paper discusses retrieval augmentation.")
        try await index.update(german); try await index.update(english)
        let hits = try await index.search("Wie funktionieren neuronale Netzwerke?")
        XCTAssertEqual(hits.map(\.path), [german.path])
        let empty = try await index.search("x'); DROP TABLE clips; --")
        XCTAssertTrue(empty.isEmpty)
        let count = try await index.count(); XCTAssertEqual(count, 2)
        try await index.reconcile([.init(path: english.path, sha: english.sha, size: 0)])
        let removed = try await index.search("Netzwerke"); XCTAssertTrue(removed.isEmpty)
        let excerpts = ArchiveRetriever.excerpts(try await index.search("retrieval"), question: "retrieval")
        XCTAssertEqual(excerpts.count, 1)
        XCTAssertEqual(excerpts[0].sha, sha)
        XCTAssertThrowsError(try ArchiveRetriever.validateCitationIDs(["S99"], sources: excerpts))
        XCTAssertThrowsError(try ArchiveRetriever.validateCitationIDs([], sources: excerpts))
        XCTAssertEqual(try ArchiveRetriever.validateCitationIDs(["S1"], sources: excerpts), excerpts)
        try FileManager.default.removeItem(at: directory)
        try await index.update(english)
        let rebuilt = try await index.search("retrieval"); XCTAssertEqual(rebuilt.count, 1)
    }
}

private final class ArchiveMockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var responseHeaders: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.responseHeaders)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ArchiveTransportTests: XCTestCase {
    private func client() throws -> ArchiveReadClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArchiveMockProtocol.self]
        return ArchiveReadClient(identity: try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "fixture", branch: "feature/reader", rootFolder: "clips")), token: "synthetic-test-token", session: URLSession(configuration: config))
    }
    override func tearDown() { ArchiveMockProtocol.handler = nil; ArchiveMockProtocol.responseHeaders = [:] }

    func testTruncatedRootIsWalkedAtPinnedCommitAndSymlinksExcluded() async throws {
        let sha = String(repeating: "a", count: 40), root = String(repeating: "b", count: 40), archive = String(repeating: "c", count: 40)
        var paths: [String] = []
        ArchiveMockProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            let path = request.url!.path; paths.append(path)
            let json: String
            if path.contains("/commits/") {
                XCTAssertTrue(request.url!.absoluteString.contains("feature%2Freader"))
                json = "{\"sha\":\"\(sha)\",\"commit\":{\"tree\":{\"sha\":\"\(root)\"}}}"
            } else if path.hasSuffix("/" + root) {
                json = "{\"truncated\":false,\"tree\":[{\"path\":\"clips\",\"type\":\"tree\",\"mode\":\"040000\",\"sha\":\"\(archive)\"}]}"
            } else if request.url!.query != nil {
                json = "{\"truncated\":true,\"tree\":[]}"
            } else {
                json = "{\"truncated\":false,\"tree\":[{\"path\":\"safe.md\",\"type\":\"blob\",\"mode\":\"100644\",\"sha\":\"\(sha)\",\"size\":10},{\"path\":\"symlink.md\",\"type\":\"blob\",\"mode\":\"120000\",\"sha\":\"\(sha)\",\"size\":10}]}"
            }
            return (200, Data(json.utf8))
        }
        let snapshot = try await client().snapshot()
        XCTAssertEqual(snapshot.commit, sha)
        XCTAssertEqual(snapshot.files.map(\.path), ["clips/safe.md"])
        XCTAssertEqual(paths.count, 4)
    }

    func testBlobIntegrityAndSizeLimits() async throws {
        let bytes = Data("Synthetic source".utf8)
        let sha = Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
        ArchiveMockProtocol.handler = { _ in
            (200, Data("{\"sha\":\"\(sha)\",\"encoding\":\"base64\",\"content\":\"\(bytes.base64EncodedString())\"}".utf8))
        }
        let reader = try client()
        let file = ArchiveFile(path: "clips/source.md", sha: sha, size: bytes.count)
        let fetched = try await reader.read(file, limit: 100)
        XCTAssertEqual(fetched, bytes)
        do { _ = try await reader.read(file, limit: 1); XCTFail("size limit ignored") }
        catch { XCTAssertEqual(error as? ArchiveError, .tooLarge) }
        ArchiveMockProtocol.handler = { _ in
            (200, Data("{\"sha\":\"\(sha)\",\"encoding\":\"base64\",\"content\":\"\(Data("Tampered content".utf8).base64EncodedString())\"}".utf8))
        }
        do { _ = try await reader.read(file, limit: 100); XCTFail("tampered blob accepted") }
        catch { XCTAssertEqual(error as? ArchiveError, .invalidResponse) }
    }

    func testAuthenticationFailureDoesNotExposeResponseBody() async throws {
        ArchiveMockProtocol.handler = { _ in (401, Data("sensitive server response".utf8)) }
        do { _ = try await client().snapshot(); XCTFail("401 ignored") }
        catch { XCTAssertEqual(error as? ArchiveError, .http(401)); XCTAssertFalse(error.localizedDescription.contains("sensitive")) }
    }

    func testPrimaryRateLimitKeepsServerDetailsPrivate() async throws {
        ArchiveMockProtocol.responseHeaders = ["X-RateLimit-Remaining": "0"]
        ArchiveMockProtocol.handler = { _ in (403, Data("sensitive rate-limit body".utf8)) }
        do { _ = try await client().snapshot(); XCTFail("Expected primary rate limit") }
        catch { XCTAssertEqual(error as? ArchiveError, .rateLimited); XCTAssertFalse(error.localizedDescription.contains("sensitive")) }
    }

    func testSecondaryRateLimitBackoffCanBeCancelledWithoutRetry() async throws {
        ArchiveMockProtocol.responseHeaders = ["Retry-After": "60"]
        let received = expectation(description: "Secondary rate limit received")
        var requests = 0
        ArchiveMockProtocol.handler = { _ in
            requests += 1; received.fulfill()
            return (403, Data())
        }
        let reader = try client()
        let task = Task { try await reader.snapshot() }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Backoff ignored cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(requests, 1)
    }
}

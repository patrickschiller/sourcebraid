import XCTest

final class ClipBuilderTests: XCTestCase {
    private let configuration = SourceBraidConfiguration(
        owner: "patrickschiller",
        repository: "sourcebraid-private",
        branch: "main",
        rootFolder: "/web-clips/"
    )

    func testURLCaptureUsesChromeCompatiblePathAndFrontmatter() throws {
        let input = CaptureInput(
            url: URL(string: "https://www.example.com/posts/article")!,
            suggestedTitle: "Example Article",
            sharedText: "A useful excerpt.",
            articleText: "",
            fileData: nil,
            filename: nil,
            mimeType: nil
        )
        let date = ISO8601DateFormatter().date(from: "2026-07-18T12:00:00Z")!
        let draft = try ClipBuilder.build(
            input: input,
            title: "Example Article",
            tags: ["reading"],
            notes: "Remember this.",
            configuration: configuration,
            now: date
        )

        XCTAssertTrue(draft.path.hasPrefix("web-clips/2026/07/2026-07-18-example.com-example-article-"))
        XCTAssertTrue(draft.markdown.contains("capture_method: \"ios-share-url\""))
        XCTAssertTrue(draft.markdown.contains("tags: [\"reading\"]"))
        XCTAssertTrue(draft.markdown.contains("Remember this."))
        XCTAssertNil(draft.attachment)
    }

    func testPDFCaptureCreatesRelativeAttachment() throws {
        let input = CaptureInput(
            url: nil,
            suggestedTitle: "Research Paper",
            sharedText: "",
            articleText: "",
            fileData: Data("pdf".utf8),
            filename: "paper.pdf",
            mimeType: "application/pdf"
        )
        let date = ISO8601DateFormatter().date(from: "2026-07-18T12:00:00Z")!
        let draft = try ClipBuilder.build(
            input: input,
            title: "Research Paper",
            tags: [],
            notes: "",
            configuration: configuration,
            now: date
        )

        XCTAssertEqual(draft.attachment?.data, Data("pdf".utf8))
        XCTAssertEqual(draft.attachment?.path.split(separator: ".").last, "pdf")
        XCTAssertTrue(draft.markdown.contains("[Open saved attachment](assets/"))
        XCTAssertTrue(draft.markdown.contains("content_format: \"pdf\""))
    }

    func testFetchedWebCaptureStoresMarkdownMetadataAndBody() throws {
        let input = CaptureInput(
            url: URL(string: "https://blog.example.com/article")!,
            suggestedTitle: "Fetched Article",
            sharedText: "https://blog.example.com/article",
            articleText: "## Introduction\n\nA [useful link](https://example.com).",
            articleContentFormat: "markdown",
            articleCaptureMethod: "ios-share-web",
            fileData: nil,
            filename: nil,
            mimeType: nil
        )
        let date = ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z")!
        let draft = try ClipBuilder.build(
            input: input,
            title: "Fetched Article",
            tags: [],
            notes: "",
            configuration: configuration,
            now: date
        )

        XCTAssertTrue(draft.markdown.contains("capture_method: \"ios-share-web\""))
        XCTAssertTrue(draft.markdown.contains("content_format: \"markdown\""))
        XCTAssertTrue(draft.markdown.contains("## Captured content\n\n## Introduction"))
        XCTAssertFalse(draft.markdown.contains("## Shared text"))
    }

    func testTagParsingTrimsAndDeduplicates() {
        XCTAssertEqual(ClipBuilder.parseTags("AI, reading, ai,  research "), ["AI", "reading", "research"])
    }
}

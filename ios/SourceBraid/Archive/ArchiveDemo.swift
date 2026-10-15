#if DEBUG
import Foundation
import CryptoKit
import SwiftUI
import QuickLook

/// Explicit simulator launch opt-in. Never loads credentials or real archive content.
struct ArchiveDemoReader: ArchiveReading {
    let identity: ArchiveIdentity
    let documents: [String: Data]
    let inventory: ArchiveSnapshot
    init() throws {
        identity = try ArchiveIdentity(configuration: .init(owner: "synthetic", repository: "fixture", branch: archiveText("main-seven", "main-seven-de"), rootFolder: "clips"))
        var documents: [String: Data] = [:], files: [ArchiveFile] = []
        for number in 1...7 {
            let path = "clips/2026/10/2026-10-12-demo-\(number).md"
            let markdown = """
            ---
            title: "\(archiveText("Synthetic article", "Synthetischer Beitrag")) \(number)"
            captured_at: "2026-10-12T1\(number):00:00Z"
            url: "https://example.invalid/synthetic-\(number)"
            capture_method: "synthetic-fixture"
            tags: ["test", "markdown"]
            ---
            # Markdown-Reader

            \(archiveText("This synthetic document checks the local reader. It contains no private content.", "Dieses synthetische Dokument prüft den lokalen Reader. Es enthält keine privaten Inhalte."))

            \(number == 7 ? archiveText("This clip demonstrates offline search in a Markdown archive.", "Dieser Beitrag zeigt die Offline-Suche in einem Markdown-Archiv.") : "")

            **Bold**, *emphasis*, and `inline code`.

            - First entry
              - Nested entry
            - [x] Captured
            - [ ] Reviewed

            > Original quotation from a synthetic fixture.

            | Feature | Status |
            | --- | --- |
            | Table | Visible |
            | Image | Local |

            ```swift
            let title = "SourceBraid"
            ```

            ![Synthetic pixel](assets/pixel.png)

            [Other archived clip](2026-10-12-demo-1.md)

            [Synthetic PDF](assets/synthetic.pdf)

            ## More text

            \(String(repeating: "Synthetic Markdown text for scrolling and reading-position checks.\n\n", count: 20))
            """
            documents[path] = Data(markdown.utf8)
        }
        documents["clips/2026/10/assets/pixel.png"] = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB7kAAAAASUVORK5CYII=")!
        documents["clips/2026/10/assets/synthetic.pdf"] = Self.syntheticPDF()
        for (path, bytes) in documents {
            let sha = Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
            files.append(ArchiveFile(path: path, sha: sha, size: bytes.count))
        }
        self.documents = documents
        inventory = ArchiveSnapshot(identity: identity, commit: String(repeating: "0", count: 40), files: files.sorted { $0.path < $1.path }, checkedAt: Date())
    }
    func snapshot() async throws -> ArchiveSnapshot { inventory }
    func read(_ file: ArchiveFile, limit: Int) async throws -> Data {
        guard let bytes = documents[file.path], bytes.count <= limit else { throw ArchiveError.tooLarge }
        return bytes
    }
    private static func syntheticPDF() -> Data {
        let stream = "BT /F1 14 Tf 50 700 Td (SourceBraid synthetic PDF - no private content) Tj ET\n"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream"]
        var pdf = "%PDF-1.4\n", offsets: [Int] = []
        for (index, object) in objects.enumerated() { offsets.append(pdf.utf8.count); pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n" }
        let xref = pdf.utf8.count
        pdf += "xref\n0 6\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        pdf += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}

/// Opt-in UI example adapter. It never invokes a model or reads user content.
struct ArchiveDemoAnswering: ArchiveAnswering {
    @MainActor func answer(question: String, history: String, sources: [SourceExcerpt], recent: String,
                           onUpdate: (String) -> Void) async throws -> (String, [String]) {
        try Task.checkCancellation()
        guard let source = sources.first else { throw ArchiveError.noEvidence }
        let response = archiveText(
            "Example answer with test data:\n\nThis clip checks the Markdown reader. It contains only synthetic content and no private data.",
            "Beispielantwort mit Testdaten:\n\nDer Beitrag prüft den Markdown-Reader. Er enthält ausschließlich synthetische Inhalte und keine privaten Daten.")
        onUpdate(response)
        return (response, [source.id])
    }
}

struct ArchiveNativeProbe: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let view = QLPreviewController(); view.dataSource = context.coordinator; return view
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        override init() {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("sourcebraid-synthetic-native.md")
            try? Data("# Synthetic heading\n\n**Bold**\n\n| A | B |\n|---|---|\n|1|2|\n\n- List entry\n".utf8).write(to: url)
            super.init()
        }
        deinit { try? FileManager.default.removeItem(at: url) }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
#endif

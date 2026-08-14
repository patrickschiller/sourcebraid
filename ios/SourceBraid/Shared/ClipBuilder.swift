import Foundation

struct CaptureInput {
    var url: URL?
    var suggestedTitle: String
    var sharedText: String
    var articleText: String
    var articleContentFormat: String = "text"
    var articleCaptureMethod: String?
    var fileData: Data?
    var filename: String?
    var mimeType: String?
    var images: [CaptureImage] = []

    static let empty = CaptureInput(
        url: nil,
        suggestedTitle: "",
        sharedText: "",
        articleText: "",
        fileData: nil,
        filename: nil,
        mimeType: nil
    )
}

struct CaptureImage: Equatable {
    let url: URL
    let alt: String
    let caption: String
}

struct CapturedImageAsset {
    let image: CaptureImage
    let data: Data
    let mimeType: String
}

struct CaptureAttachment {
    let path: String
    let data: Data
}

struct CapturedImageAttachment {
    let image: CaptureImage
    let attachment: CaptureAttachment
    let mimeType: String
}

struct CaptureDraft {
    let title: String
    let path: String
    let markdown: String
    let indexEntry: SourceBraidIndexEntry
    let attachment: CaptureAttachment?
    let imageAttachments: [CapturedImageAttachment]
}

struct SourceBraidImageIndexEntry: Encodable {
    let url: String
    let path: String
    let relativePath: String
    let alt: String
    let caption: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case url, path, alt, caption
        case relativePath = "relative_path"
        case contentType = "content_type"
    }
}

struct SourceBraidIndexEntry: Encodable {
    let title: String
    let url: String
    let path: String
    let date: String
    let tags: [String]
    let source: String
    let captureMethod: String
    let sourceType: String
    let contentFormat: String
    let conversionStatus: String?
    let converter: String?
    let capturedAt: String
    let attachmentPath: String?
    let pdfPath: String?
    let images: [SourceBraidImageIndexEntry]?

    enum CodingKeys: String, CodingKey {
        case title, url, path, date, tags, source
        case captureMethod = "capture_method"
        case sourceType = "source_type"
        case contentFormat = "content_format"
        case conversionStatus = "conversion_status"
        case converter
        case capturedAt = "captured_at"
        case attachmentPath = "attachment_path"
        case pdfPath = "pdf_path"
        case images
    }
}

enum ClipBuilder {
    static let maximumAttachmentBytes = 25 * 1024 * 1024

    static func build(
        input: CaptureInput,
        title suppliedTitle: String,
        tags: [String],
        notes: String,
        configuration: SourceBraidConfiguration,
        imageAssets: [CapturedImageAsset] = [],
        now: Date = Date()
    ) throws -> CaptureDraft {
        let normalizedConfiguration = configuration.normalized()
        let hasText = !input.sharedText.trimmed.isEmpty || !input.articleText.trimmed.isEmpty
        guard input.url != nil || hasText || input.fileData != nil || !input.images.isEmpty else {
            throw ClipBuilderError.emptyInput
        }
        if let data = input.fileData, data.count > maximumAttachmentBytes {
            throw ClipBuilderError.attachmentTooLarge
        }

        let capturedAt = isoTimestamp(now)
        let captureDate = localDate(now)
        let title = normalizedTitle(suppliedTitle, input: input)
        let identity = input.url?.absoluteString ?? "sourcebraid://capture/\(capturedAt)-\(title)"
        let site = input.url.flatMap(hostname)?.replacingOccurrences(of: "www.", with: "", options: .anchored) ?? "SourceBraid"
        let pathHost = input.url.flatMap(hostname)?.replacingOccurrences(of: "www.", with: "", options: .anchored) ?? "document"
        let slug = slugify(title).prefix(80)
        let hash = urlHash(identity)
        let path = "\(normalizedConfiguration.rootFolder)/\(captureDate.prefix(4))/\(captureDate.dropFirst(5).prefix(2))/\(captureDate)-\(pathHost)-\(slug)-\(hash).md"
        let captureMethod: String
        let sourceType: String
        let contentFormat: String
        let queuesPDFConversion = input.fileData != nil && input.mimeType == "application/pdf"

        if queuesPDFConversion {
            captureMethod = "pdf-docling-pending"
            sourceType = "pdf"
            contentFormat = "pdf"
        } else if input.fileData != nil {
            captureMethod = "ios-share-file"
            sourceType = "document"
            contentFormat = "file"
        } else if !input.articleText.trimmed.isEmpty {
            captureMethod = input.articleCaptureMethod ?? "ios-share-safari"
            sourceType = "article"
            contentFormat = input.articleContentFormat == "markdown" ? "markdown" : "text"
        } else if input.url != nil {
            captureMethod = "ios-share-url"
            sourceType = "article"
            contentFormat = "link"
        } else if !input.images.isEmpty {
            captureMethod = "ios-share-images"
            sourceType = "article"
            contentFormat = "images"
        } else {
            captureMethod = "ios-share-text"
            sourceType = "note"
            contentFormat = "text"
        }

        let attachment: CaptureAttachment?
        if let data = input.fileData {
            let ext = safeFileExtension(input.filename, mimeType: input.mimeType)
            let clipSlug = path.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".md", with: "") ?? "document"
            let attachmentName = queuesPDFConversion ? "source.pdf" : "original.\(ext)"
            let attachmentPath = "\(normalizedConfiguration.rootFolder)/\(captureDate.prefix(4))/\(captureDate.dropFirst(5).prefix(2))/assets/\(clipSlug)/\(attachmentName)"
            attachment = CaptureAttachment(path: attachmentPath, data: data)
        } else {
            attachment = nil
        }

        let imageAttachments = queuesPDFConversion
            ? []
            : buildImageAttachments(
                imageAssets,
                rootFolder: normalizedConfiguration.rootFolder,
                captureDate: captureDate,
                markdownPath: path
            )
        let indexImages = imageAttachments.map { image in
            SourceBraidImageIndexEntry(
                url: image.image.url.absoluteString,
                path: image.attachment.path,
                relativePath: relativePath(from: path, to: image.attachment.path),
                alt: image.image.alt,
                caption: image.image.caption,
                contentType: image.mimeType
            )
        }

        let markdown = buildMarkdown(
            input: input,
            title: title,
            identity: identity,
            site: site,
            capturedAt: capturedAt,
            captureDate: captureDate,
            captureMethod: captureMethod,
            sourceType: sourceType,
            contentFormat: contentFormat,
            queuesPDFConversion: queuesPDFConversion,
            tags: tags,
            notes: notes,
            attachmentPath: attachment?.path,
            imageAttachments: imageAttachments,
            markdownPath: path
        )
        let entry = SourceBraidIndexEntry(
            title: title,
            url: identity,
            path: path,
            date: captureDate,
            tags: tags,
            source: site,
            captureMethod: captureMethod,
            sourceType: sourceType,
            contentFormat: contentFormat,
            conversionStatus: queuesPDFConversion ? "pending" : nil,
            converter: queuesPDFConversion ? "docling" : nil,
            capturedAt: capturedAt,
            attachmentPath: queuesPDFConversion ? nil : attachment?.path,
            pdfPath: queuesPDFConversion ? attachment?.path : nil,
            images: indexImages.isEmpty ? nil : indexImages
        )
        return CaptureDraft(
            title: title,
            path: path,
            markdown: markdown,
            indexEntry: entry,
            attachment: attachment,
            imageAttachments: imageAttachments
        )
    }

    static func parseTags(_ value: String) -> [String] {
        var seen = Set<String>()
        return value
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func buildMarkdown(
        input: CaptureInput,
        title: String,
        identity: String,
        site: String,
        capturedAt: String,
        captureDate: String,
        captureMethod: String,
        sourceType: String,
        contentFormat: String,
        queuesPDFConversion: Bool,
        tags: [String],
        notes: String,
        attachmentPath: String?,
        imageAttachments: [CapturedImageAttachment],
        markdownPath: String
    ) -> String {
        var lines = [
            "---",
            "title: \(yamlQuote(title))",
            "url: \(yamlQuote(identity))",
            "source: \(yamlQuote(site))",
            "captured_at: \(yamlQuote(capturedAt))",
            "capture_date: \(yamlQuote(captureDate))",
            "capture_method: \(yamlQuote(captureMethod))",
            "source_type: \(yamlQuote(sourceType))",
            "content_format: \(yamlQuote(contentFormat))"
        ]
        if queuesPDFConversion, let attachmentPath {
            lines.append("conversion_status: \(yamlQuote("pending"))")
            lines.append("converter: \(yamlQuote("docling"))")
            lines.append("pdf_path: \(yamlQuote(attachmentPath))")
        } else if let attachmentPath {
            lines.append("attachment_path: \(yamlQuote(attachmentPath))")
        }
        if !tags.isEmpty {
            lines.append("tags: [\(tags.map(yamlQuote).joined(separator: ", "))]")
        }
        lines.append(contentsOf: ["---", ""])

        if !notes.trimmed.isEmpty {
            lines.append(contentsOf: [
                "<!-- clipper-notes-start -->",
                "## Notes",
                "",
                notes.trimmed,
                "",
                "<!-- clipper-notes-end -->",
                ""
            ])
        }

        lines.append(contentsOf: ["# \(title)", ""])
        if let url = input.url {
            lines.append(contentsOf: ["[Open original source](\(url.absoluteString))", ""])
        }
        if queuesPDFConversion {
            lines.append(contentsOf: ["> The original PDF has been uploaded. GitHub Actions will replace this placeholder with Docling Markdown.", ""])
        } else if let attachmentPath {
            lines.append(contentsOf: ["[Open saved attachment](\(relativePath(from: markdownPath, to: attachmentPath)))", ""])
        }

        let articleText = input.articleText.trimmed
        if !articleText.isEmpty {
            lines.append(contentsOf: ["## Captured content", "", articleText, ""])
        }
        let sharedText = input.sharedText.trimmed
        if !sharedText.isEmpty, sharedText != input.url?.absoluteString, sharedText != articleText {
            lines.append(contentsOf: ["## Shared text", "", sharedText, ""])
        }
        if !imageAttachments.isEmpty {
            lines.append(contentsOf: ["## Images", ""])
            for image in imageAttachments {
                let alt = markdownImageAlt(image.image.alt)
                let imagePath = relativePath(from: markdownPath, to: image.attachment.path)
                lines.append("![\(alt)](\(imagePath))")
                let caption = image.image.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                if !caption.isEmpty, caption != image.image.alt {
                    lines.append(caption)
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func buildImageAttachments(
        _ imageAssets: [CapturedImageAsset],
        rootFolder: String,
        captureDate: String,
        markdownPath: String
    ) -> [CapturedImageAttachment] {
        let clipSlug = markdownPath
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: ".md", with: "") ?? "document"
        return imageAssets.enumerated().map { index, asset in
            let filename = String(format: "%02d", index + 1)
                + "."
                + imageFileExtension(url: asset.image.url, mimeType: asset.mimeType)
            let path = "\(rootFolder)/\(captureDate.prefix(4))/\(captureDate.dropFirst(5).prefix(2))/assets/\(clipSlug)/\(filename)"
            return CapturedImageAttachment(
                image: asset.image,
                attachment: CaptureAttachment(path: path, data: asset.data),
                mimeType: asset.mimeType
            )
        }
    }

    private static func normalizedTitle(_ suppliedTitle: String, input: CaptureInput) -> String {
        let candidates: [String?] = [suppliedTitle, input.suggestedTitle, input.filename, input.url.flatMap(hostname), "Saved item"]
        return candidates.compactMap { $0?.trimmed }.first { !$0.isEmpty } ?? "Saved item"
    }

    private static func hostname(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func localDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func slugify(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.joined(separator: "-").isEmpty ? "document" : parts.joined(separator: "-")
    }

    private static func urlHash(_ value: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for unit in value.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x01000193
        }
        return String(format: "%08x", hash).prefix(6).description
    }

    private static func yamlQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func safeFileExtension(_ filename: String?, mimeType: String?) -> String {
        if let ext = filename.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() }),
           !ext.isEmpty,
           ext.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil {
            return ext
        }
        return mimeType == "application/pdf" ? "pdf" : "bin"
    }

    private static func imageFileExtension(url: URL, mimeType: String) -> String {
        let extensions = [
            "image/jpeg": "jpg",
            "image/jpg": "jpg",
            "image/png": "png",
            "image/webp": "webp",
            "image/gif": "gif",
            "image/svg+xml": "svg",
            "image/avif": "avif"
        ]
        if let value = extensions[mimeType.lowercased()] {
            return value
        }
        let value = url.pathExtension.lowercased()
        if value.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil {
            return value
        }
        return "jpg"
    }

    private static func markdownImageAlt(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func relativePath(from markdownPath: String, to attachmentPath: String) -> String {
        var from = markdownPath.split(separator: "/").dropLast().map(String.init)
        var to = attachmentPath.split(separator: "/").map(String.init)
        while let firstFrom = from.first, let firstTo = to.first, firstFrom == firstTo {
            from.removeFirst()
            to.removeFirst()
        }
        return (Array(repeating: "..", count: from.count) + to).joined(separator: "/")
    }
}

enum ClipBuilderError: LocalizedError {
    case emptyInput
    case attachmentTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "The shared item does not contain a supported URL, text, or file."
        case .attachmentTooLarge:
            return "The shared file exceeds SourceBraid's 25 MB limit."
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

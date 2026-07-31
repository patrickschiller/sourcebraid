import Foundation
import UniformTypeIdentifiers

enum ShareInputResolver {
    static func resolve(context: NSExtensionContext) async throws -> CaptureInput {
        let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
        var input = CaptureInput.empty

        for item in items {
            if input.suggestedTitle.isEmpty {
                input.suggestedTitle = item.attributedTitle?.string ?? item.attributedContentText?.string ?? ""
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let values = try? await loadPropertyList(provider) {
                    applyPreprocessing(values, to: &input)
                }
            }
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if input.fileData == nil,
                   let fileType = supportedFileType(provider),
                   let file = try? await loadFile(provider, typeIdentifier: fileType) {
                    input.fileData = file.data
                    input.filename = file.filename
                    input.mimeType = file.mimeType
                }
                if input.url == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await loadURL(provider) {
                    input.url = url
                }
                if input.sharedText.isEmpty,
                   provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await loadText(provider) {
                    input.sharedText = text
                }
                if input.suggestedTitle.isEmpty, let name = provider.suggestedName {
                    input.suggestedTitle = name
                }
            }
        }

        if input.url == nil {
            let candidate = input.sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                input.url = url
            }
        }
        guard input.url != nil || input.fileData != nil || !input.sharedText.isEmpty || !input.articleText.isEmpty else {
            throw ShareInputError.unsupported
        }
        return input
    }

    private static func applyPreprocessing(_ values: [String: Any], to input: inout CaptureInput) {
        let result = values[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] ?? values
        if input.url == nil, let value = result["url"] as? String {
            input.url = URL(string: value)
        }
        if input.suggestedTitle.isEmpty, let value = result["title"] as? String {
            input.suggestedTitle = value
        }
        if input.sharedText.isEmpty, let value = result["selectedText"] as? String {
            input.sharedText = limited(value)
        }
        if input.articleText.isEmpty, let value = result["articleText"] as? String {
            input.articleText = limited(value)
        }
    }

    private static func supportedFileType(_ provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return UTType.pdf.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }
        return nil
    }

    private static func loadPropertyList(_ provider: NSItemProvider) async throws -> [String: Any] {
        let item = try await loadItem(provider, typeIdentifier: UTType.propertyList.identifier)
        return item as? [String: Any] ?? [:]
    }

    private static func loadURL(_ provider: NSItemProvider) async throws -> URL {
        let item = try await loadItem(provider, typeIdentifier: UTType.url.identifier)
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let value = item as? String, let url = URL(string: value) { return url }
        if let value = item as? NSString, let url = URL(string: value as String) { return url }
        throw ShareInputError.unsupported
    }

    private static func loadText(_ provider: NSItemProvider) async throws -> String {
        let item = try await loadItem(provider, typeIdentifier: UTType.plainText.identifier)
        if let text = item as? String { return limited(text) }
        if let text = item as? NSString { return limited(text as String) }
        if let data = item as? Data, let text = String(data: data, encoding: .utf8) { return limited(text) }
        throw ShareInputError.unsupported
    }

    private static func loadItem(_ provider: NSItemProvider, typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: ShareInputError.unsupported)
                }
            }
        }
    }

    private static func loadFile(_ provider: NSItemProvider, typeIdentifier: String) async throws -> LoadedFile {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LoadedFile, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareInputError.unsupported)
                    return
                }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
                    if let size = values.fileSize, size > ClipBuilder.maximumAttachmentBytes {
                        throw ClipBuilderError.attachmentTooLarge
                    }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
                    continuation.resume(returning: LoadedFile(
                        data: data,
                        filename: values.name ?? suggestedName ?? url.lastPathComponent,
                        mimeType: type?.preferredMIMEType ?? (typeIdentifier == UTType.pdf.identifier ? "application/pdf" : "application/octet-stream")
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func limited(_ value: String) -> String {
        String(value.prefix(500_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LoadedFile {
    let data: Data
    let filename: String
    let mimeType: String
}

enum ShareInputError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "SourceBraid could not read a URL, text, PDF, or file from this app."
    }
}

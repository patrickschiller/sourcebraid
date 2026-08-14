import Foundation

@MainActor
final class ShareViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case saving
        case saved
        case failed(String)
    }

    @Published var title = ""
    @Published var tags = ""
    @Published var notes = ""
    @Published var sourceSummary = "Reading shared item…"
    @Published var state: State = .loading

    private let context: NSExtensionContext
    private var input = CaptureInput.empty
    private var pageCapture: WebPageCapture?

    init(context: NSExtensionContext) {
        self.context = context
        Task { await load() }
    }

    var canSave: Bool {
        state == .ready && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func save() async {
        guard canSave else { return }
        state = .saving
        do {
            let configuration = SourceBraidSettings.load().normalized()
            guard configuration.isComplete else {
                throw ShareSaveError.notConfigured
            }
            let token = try KeychainStore().token()
            guard !token.isEmpty else {
                throw ShareSaveError.notConfigured
            }
            let imageAssets = await ImageAssetDownloader.download(input.images)
            let draft = try ClipBuilder.build(
                input: input,
                title: title,
                tags: ClipBuilder.parseTags(tags),
                notes: notes,
                configuration: configuration,
                imageAssets: imageAssets
            )
            try await GitHubClient(configuration: configuration, token: token).save(draft)
            RecentCaptureStore.add(RecentCapture(title: draft.title, path: draft.path))
            state = .saved
            try? await Task.sleep(nanoseconds: 350_000_000)
            context.completeRequest(returningItems: nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        context.cancelRequest(withError: ShareSaveError.cancelled)
    }

    func retry() {
        state = .ready
    }

    private func load() async {
        do {
            input = try await ShareInputResolver.resolve(context: context)
            if let url = input.url, input.fileData == nil, input.articleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let host = url.host ?? url.absoluteString
                sourceSummary = "\(host) · Fetching Markdown…"
                do {
                    let capture = WebPageCapture()
                    pageCapture = capture
                    let result = try await capture.capture(url: url)
                    input.articleText = result.markdown
                    input.articleContentFormat = "markdown"
                    input.articleCaptureMethod = result.captureMethod
                    if input.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        input.suggestedTitle = result.title
                    }
                    if let finalURL = URL(string: result.url) {
                        input.url = finalURL
                    }
                    sourceSummary = "\(input.url?.host ?? host) · Markdown"
                } catch {
                    sourceSummary = "\(host) · Link only"
                }
                pageCapture = nil
            }
            title = input.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                title = input.filename ?? input.url?.host ?? "Saved item"
            }
            if let url = input.url, !sourceSummary.contains(" · ") {
                sourceSummary = url.host ?? url.absoluteString
            } else if let filename = input.filename {
                sourceSummary = filename
            } else {
                sourceSummary = "Shared text"
            }
            let configuration = SourceBraidSettings.load()
            let token = try KeychainStore().token()
            guard configuration.isComplete, !token.isEmpty else {
                throw ShareSaveError.notConfigured
            }
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private enum ImageAssetDownloader {
    private static let maximumImageCount = 12
    private static let maximumImageBytes = 8 * 1024 * 1024
    private static let maximumTotalBytes = 25 * 1024 * 1024

    static func download(_ images: [CaptureImage]) async -> [CapturedImageAsset] {
        var assets: [CapturedImageAsset] = []
        var totalBytes = 0

        for image in images.prefix(maximumImageCount) {
            guard let asset = try? await fetch(image),
                  totalBytes + asset.data.count <= maximumTotalBytes else {
                continue
            }
            totalBytes += asset.data.count
            assets.append(asset)
        }
        return assets
    }

    private static func fetch(_ image: CaptureImage) async throws -> CapturedImageAsset {
        var request = URLRequest(url: image.url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              !data.isEmpty,
              data.count <= maximumImageBytes else {
            throw ImageDownloadError.invalidResponse
        }
        let mimeType = (
            (response.value(forHTTPHeaderField: "Content-Type") ?? "")
                .split(separator: ";", maxSplits: 1)
                .first
                .map(String.init) ?? ""
        ).lowercased()
        guard mimeType.hasPrefix("image/") else {
            throw ImageDownloadError.invalidResponse
        }
        return CapturedImageAsset(image: image, data: data, mimeType: mimeType)
    }

    private enum ImageDownloadError: Error {
        case invalidResponse
    }
}

enum ShareSaveError: LocalizedError {
    case notConfigured
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Open the SourceBraid app first and configure its GitHub repository and token."
        case .cancelled:
            return "Saving was cancelled."
        }
    }
}

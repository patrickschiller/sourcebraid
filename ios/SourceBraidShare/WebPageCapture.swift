import Foundation
import WebKit

struct WebPageCaptureResult: Decodable {
    let title: String
    let url: String
    let markdown: String
}

@MainActor
final class WebPageCapture: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<WebPageCaptureResult, Error>?
    private var timeoutTimer: Timer?
    private var webView: WKWebView?

    func capture(url: URL) async throws -> WebPageCaptureResult {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw WebPageCaptureError.unsupportedURL
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.finish(.failure(WebPageCaptureError.timedOut))
                }
            }

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        do {
            let script = try Self.extractionScript()
            webView.evaluateJavaScript(script) { [weak self] value, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.finish(.failure(error))
                        return
                    }
                    guard let json = value as? String,
                          let data = json.data(using: .utf8),
                          let result = try? JSONDecoder().decode(WebPageCaptureResult.self, from: data),
                          result.markdown.trimmingCharacters(in: .whitespacesAndNewlines).count >= 80 else {
                        self.finish(.failure(WebPageCaptureError.noReadableContent))
                        return
                    }
                    self.finish(.success(result))
                }
            }
        } catch {
            finish(.failure(error))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<WebPageCaptureResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private static func extractionScript() throws -> String {
        guard let url = Bundle.main.url(forResource: "WebPageCapture", withExtension: "js") else {
            throw WebPageCaptureError.missingExtractor
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

enum WebPageCaptureError: LocalizedError {
    case unsupportedURL
    case timedOut
    case noReadableContent
    case missingExtractor

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "The shared link is not a supported web URL."
        case .timedOut:
            return "The web page took too long to load."
        case .noReadableContent:
            return "The web page did not expose readable article content."
        case .missingExtractor:
            return "The Markdown extractor is missing from the Share Extension."
        }
    }
}

import SwiftUI
import WebKit
import UniformTypeIdentifiers
import QuickLook

struct ArchiveReaderView: View {
    @ObservedObject var library: ArchiveLibrary
    let clip: ArchiveClip
    var askAboutClip: (() -> Void)? = nil
    @State private var loaded: ArchiveClip?
    @State private var raw = ""
    @State private var error = ""
    @State private var rawView = false
    @State private var remoteImages = false
    @State private var confirmImages = false
    @State private var attachment: ArchiveAttachment?
    @State private var retry = 0
    @State private var loadRequest = UUID()
    private var loadedMatchesClip: Bool { loaded?.path == clip.path && loaded?.sha == clip.sha }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.title).font(.headline).foregroundStyle(SourceBraidTheme.ink).textSelection(.enabled)
                ArchiveCaptureDateView(date: clip.sortDate, precision: clip.datePrecision).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk)
                if clip.datePrecision == "day" { Text(archiveText("Day precision", "Tagesgenau")).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk) }
                if clip.dateSource == "path" { Text(archiveText("Date inferred from archive filename", "Datum aus dem Archiv-Dateinamen")).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk) }
                if clip.titleIsFilename { Text(archiveText("Filename shown; no recorded title", "Dateiname angezeigt; kein gespeicherter Titel")).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk) }
                if let method = clip.captureMethod { Text(method).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk) }
                if let status = clip.conversionStatus { Text(status).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk) }
                if let author = clip.author { Text(author).font(.caption).foregroundStyle(SourceBraidTheme.ink) }
                if let value = clip.sourceURL, let url = ArchivePath.externalURL(value) { Link(archiveText("Original source", "Originalquelle"), destination: url).font(.caption) }
            }.padding().background(SourceBraidTheme.surface)
            Divider()
            if let loaded, loadedMatchesClip,
               let inventory = library.readerSnapshot(for: clip) {
                if rawView {
                    ScrollView { Text(raw).font(.system(.body, design: .monospaced)).foregroundStyle(SourceBraidTheme.ink).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }.background(SourceBraidTheme.surface).accessibilityIdentifier("archive.reader.raw")
                } else {
                    ArchiveWebView(html: MarkdownRenderer.document(loaded, root: inventory.identity.root, allowRemoteImages: remoteImages),
                                   library: library, inventory: inventory, clip: clip, fragment: library.sourceFragment,
                                   allowRemoteImages: remoteImages,
                                   openAttachment: { attachment = ArchiveAttachment(path: $0, snapshot: inventory) })
                    .id(clip.path + clip.sha + inventory.commit)
                }
            } else if !error.isEmpty {
                VStack {
                    ContentUnavailableView(archiveText("Cannot load clip", "Beitrag kann nicht geladen werden"), systemImage: "exclamationmark.triangle", description: Text(error))
                    Button(archiveText("Retry", "Erneut versuchen")) { retry += 1 }
                    if let url = library.readerSnapshot(for: clip)?.githubURL(for: clip.path) { Link(archiveText("Open on GitHub", "Auf GitHub öffnen"), destination: url) }
                }.padding(.bottom)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("archive.reader.loading")
                .accessibilityLabel(archiveText("Loading clip", "Beitrag wird geladen")) }
        }
        .background(SourceBraidTheme.surface)
        .navigationTitle(archiveText("Reader", "Reader"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let askAboutClip {
                Button(action: askAboutClip) {
                    Label(archiveText("Ask about this clip", "Diesen Beitrag fragen"), systemImage: "bubble.left.and.bubble.right")
                }.accessibilityIdentifier("archive.reader.ask")
            }
            Menu {
                Toggle(archiveText("Raw Markdown", "Markdown-Quelltext"), isOn: $rawView)
                if loadedMatchesClip && !raw.isEmpty { ShareLink(item: raw) { Label(archiveText("Share Markdown", "Markdown teilen"), systemImage: "square.and.arrow.up") } }
                if let url = library.readerSnapshot(for: clip)?.githubURL(for: clip.path) { Link(archiveText("Open on GitHub", "Auf GitHub öffnen"), destination: url) }
                Button(archiveText("Load external images…", "Externe Bilder laden …")) { confirmImages = true }
            } label: { Label(archiveText("Reader options", "Reader-Optionen"), systemImage: "ellipsis") }
        }
        .confirmationDialog(archiveText("Loading external images contacts the source websites.", "Beim Laden externer Bilder werden die Quell-Websites kontaktiert."), isPresented: $confirmImages, titleVisibility: .visible) {
            Button(archiveText("Load images", "Bilder laden")) { remoteImages = true }
        }
        .sheet(item: $attachment) { ArchiveAttachmentView(library: library, attachment: $0) }
        .task(id: clip.path + clip.sha + library.generation.uuidString + String(retry)) {
            guard library.selected?.path == clip.path, library.selected?.sha == clip.sha else { return }
            let request = UUID(), epoch = library.generation
            loadRequest = request
            loaded = nil; raw = ""; error = ""; remoteImages = false
            rawView = false; confirmImages = false; attachment = nil
            do {
                let value = try await library.document(clip)
                try Task.checkCancellation()
                guard loadRequest == request, library.generation == epoch else { return }
                loaded = value.0; raw = value.1
            } catch {
                // A previous selection must never replace the new document's
                // state, even when URLSession reports cancellation as URLError.
                guard loadRequest == request, library.generation == epoch,
                      library.selected?.path == clip.path, library.selected?.sha == clip.sha else { return }
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.error = archiveText("Loading was interrupted. Please try again.", "Das Laden wurde unterbrochen. Bitte versuche es erneut.")
                } else { self.error = error.localizedDescription }
            }
        }
    }
}

private struct ArchiveWebView: UIViewRepresentable {
    let html: String
    let library: ArchiveLibrary
    let inventory: ArchiveSnapshot
    let clip: ArchiveClip
    let fragment: String?
    let allowRemoteImages: Bool
    let openAttachment: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(library: library, inventory: inventory, clip: clip, openAttachment: openAttachment) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "sourcebraid-asset")
        let view = WKWebView(frame: .zero, configuration: config)
        view.accessibilityIdentifier = "archive.reader.web"
        view.navigationDelegate = context.coordinator; view.scrollView.delegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = SourceBraidTheme.uiSurface
        view.scrollView.backgroundColor = SourceBraidTheme.uiSurface
        context.coordinator.view = view
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.allowRemoteImages = allowRemoteImages
        if coordinator.html != html || coordinator.fragment != fragment {
            coordinator.renderTask?.cancel()
            coordinator.renderWatchdog?.cancel()
            coordinator.skipMermaid = false
            coordinator.navigationGeneration = UUID()
            coordinator.html = html; coordinator.fragment = fragment
            coordinator.restore = library.readingPositions[clip.sha] ?? 0
            // The base has no network origin. Even malicious HTML cannot inherit GitHub credentials.
            view.loadHTMLString(html, baseURL: URL(string: "sourcebraid-document://local/"))
        }
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.renderTask?.cancel()
        coordinator.renderWatchdog?.cancel()
        coordinator.tasks.values.forEach { $0.cancel() }; coordinator.tasks.removeAll()
        view.stopLoading(); view.navigationDelegate = nil; view.scrollView.delegate = nil
        // Discard a pending JavaScript promise as well as network/scheme work;
        // Task cancellation alone cannot interrupt WebKit's async JavaScript.
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler, UIScrollViewDelegate {
        weak var view: WKWebView?
        let library: ArchiveLibrary, inventory: ArchiveSnapshot, clip: ArchiveClip
        let openAttachment: (String) -> Void
        var html = "", fragment: String?, restore: Double = 0
        var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
        var renderTask: Task<Void, Never>?
        var renderWatchdog: Task<Void, Never>?
        var skipMermaid = false
        var navigationGeneration = UUID()
        var allowRemoteImages = false
        init(library: ArchiveLibrary, inventory: ArchiveSnapshot, clip: ArchiveClip, openAttachment: @escaping (String) -> Void) {
            self.library = library; self.inventory = inventory; self.clip = clip; self.openAttachment = openAttachment
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let key = ObjectIdentifier(urlSchemeTask)
            tasks[key] = Task {
                defer { tasks[key] = nil }
                do {
                    guard let url = urlSchemeTask.request.url, url.scheme == "sourcebraid-asset" else { throw ArchiveError.invalidPath }
                    let bytes: Data
                    let mime: String?
                    if url.host == "remote" {
                        guard allowRemoteImages,
                              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
                              let remote = ArchivePath.externalURL(value) else { throw ArchiveError.invalidPath }
                        let result = try await ArchiveExternalImageLoader.read(remote)
                        bytes = result.0; mime = result.1
                    } else {
                        guard url.host == "local" else { throw ArchiveError.invalidPath }
                        let path = String(url.path.dropFirst())
                        guard ArchivePath.isInside(path, root: inventory.identity.root),
                          let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                          !["svg", "html"].contains(url.pathExtension.lowercased()) else { throw ArchiveError.invalidPath }
                        bytes = try await library.asset(path, snapshot: inventory); mime = type.preferredMIMEType
                    }
                    try Task.checkCancellation()
                    guard tasks[key] != nil else { return }
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: bytes.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(bytes); urlSchemeTask.didFinish()
                } catch {
                    if !Task.isCancelled && tasks[key] != nil { urlSchemeTask.didFailWithError(error) }
                }
            }
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            let key = ObjectIdentifier(urlSchemeTask); tasks.removeValue(forKey: key)?.cancel()
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.navigationType != .linkActivated {
                decisionHandler(url.absoluteString == "about:blank" || url.scheme == "sourcebraid-document" ? .allow : .cancel); return
            }
            if let external = ArchivePath.externalURL(url.absoluteString) {
                UIApplication.shared.open(external); decisionHandler(.cancel)
            } else if url.scheme == "sourcebraid-document", url.host == "local" {
                let path = String(url.path.dropFirst())
                if path.isEmpty, url.fragment != nil { decisionHandler(.allow); return }
                if library.clips.contains(where: { $0.path == path }) {
                    library.select(path); library.sourceFragment = url.fragment
                } else if ArchivePath.isInside(path, root: inventory.identity.root), inventory.files.contains(where: { $0.path == path }) {
                    openAttachment(path)
                }
                decisionHandler(.cancel)
            } else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let generation = navigationGeneration
            renderTask?.cancel()
            renderTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                if html.contains("data-mermaid") && !skipMermaid {
                    renderWatchdog?.cancel()
                    renderWatchdog = Task { [weak self, weak webView] in
                        do { try await Task.sleep(for: .seconds(10)) } catch { return }
                        guard let self, let webView, !Task.isCancelled,
                              navigationGeneration == generation else { return }
                        // A stalled JavaScript promise must not leave the reader
                        // waiting indefinitely. Loading a fresh document also
                        // discards that execution world; source stays readable.
                        skipMermaid = true
                        renderTask?.cancel()
                        navigationGeneration = UUID()
                        webView.loadHTMLString(html, baseURL: URL(string: "sourcebraid-document://local/"))
                    }
                    // Rendering only reads escaped diagram text from the DOM; no
                    // archived content is concatenated into executable JavaScript.
                    try? await MermaidRenderer.render(in: webView)
                    guard navigationGeneration == generation else { return }
                    renderWatchdog?.cancel()
                }
                guard !Task.isCancelled, navigationGeneration == generation else { return }
                restorePosition(in: webView)
            }
        }
        private func restorePosition(in webView: WKWebView) {
            if let fragment, let data = try? JSONEncoder().encode(fragment), let literal = String(data: data, encoding: .utf8) {
                // Trusted app-owned DOM navigation; document scripts remain disabled.
                webView.evaluateJavaScript("document.getElementById(\(literal))?.scrollIntoView()", completionHandler: nil)
                return
            }
            let maximum = max(0, webView.scrollView.contentSize.height - webView.scrollView.bounds.height)
            webView.scrollView.setContentOffset(CGPoint(x: 0, y: min(maximum, CGFloat(restore))), animated: false)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            renderTask?.cancel()
            renderWatchdog?.cancel()
            // Avoid repeatedly restarting a diagram that terminated WebKit.
            skipMermaid = true
            navigationGeneration = UUID()
            webView.loadHTMLString(html, baseURL: URL(string: "sourcebraid-document://local/"))
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            library.readingPositions[clip.sha] = Double(scrollView.contentOffset.y)
        }
    }
}

private struct ArchiveAttachment: Identifiable {
    var id: String { path }
    let path: String
    let snapshot: ArchiveSnapshot
}

private struct ArchiveAttachmentView: View {
    @ObservedObject var library: ArchiveLibrary
    let attachment: ArchiveAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var local: URL?
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Group {
                if let local { NativeArchivePreview(url: local) }
                else if !error.isEmpty {
                    ContentUnavailableView(archiveText("Preview unavailable", "Vorschau nicht verfügbar"), systemImage: "doc", description: Text(error))
                } else { ProgressView() }
            }
            .navigationTitle(URL(fileURLWithPath: attachment.path).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(archiveText("Done", "Fertig")) { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    if let url = attachment.snapshot.githubURL(for: attachment.path) { Link(archiveText("Open on GitHub", "Auf GitHub öffnen"), destination: url) }
                }
            }
        }
        .task {
            guard local == nil else { return }
            do {
                let ext = URL(fileURLWithPath: attachment.path).pathExtension.lowercased()
                guard ["pdf", "png", "jpg", "jpeg", "gif", "heic"].contains(ext) else { throw ArchiveError.previewUnavailable }
                let bytes = try await library.asset(attachment.path, snapshot: attachment.snapshot)
                try Task.checkCancellation()
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("SourceBraidPreview-" + UUID().uuidString + "." + ext)
                try bytes.write(to: file, options: [.atomic, .completeFileProtection])
                guard QLPreviewController.canPreview(file as NSURL) else { try? FileManager.default.removeItem(at: file); throw ArchiveError.previewUnavailable }
                local = file
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
        .onDisappear {
            if let local { try? FileManager.default.removeItem(at: local) }
            local = nil
        }
    }
}

private struct NativeArchivePreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let view = QLPreviewController(); view.dataSource = context.coordinator; return view
    }
    func updateUIViewController(_ view: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

#if DEBUG
// Real WebKit integration checks need a UIApplication host. The logic-test
// target intentionally has none, so UI tests open this entirely synthetic view.
// It cannot be reached in a release build or without the explicit demo flag.
struct ArchiveMermaidProbe: View {
    @State private var status = "Preparing offline Mermaid checks"
    var body: some View {
        VStack(spacing: 8) {
            Text(status).font(.caption).accessibilityIdentifier("archive.mermaid.probe.result")
            ArchiveMermaidProbeWebView { status = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(.top).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArchiveMermaidProbeWebView: UIViewRepresentable {
    let report: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(report: report) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.accessibilityIdentifier = "archive.mermaid.probe.web"
        web.navigationDelegate = context.coordinator
        let body = """
        # Synthetic Mermaid checks

        ```mermaid
        flowchart LR
        A[Capture] --> B[Read]
        ```

        ```mermaid
        sequenceDiagram
        Alice->>Bob: Synthetic message
        ```

        ```mermaid
        this is deliberately invalid
        ```

        ```mermaid
        flowchart TD
        C[After invalid diagram] --> D[Still renders]
        ```

        <script>globalThis.archiveScriptRan = true;</script>

        ```mermaid
        %%{init: {'securityLevel': 'loose', 'htmlLabels': true}}%%
        flowchart LR
        A[\"<img src='https://example.invalid/track.png' onerror='globalThis.archiveScriptRan=true'>\"] --> B[Safe]
        click B \"https://example.invalid/navigation\"
        ```

        ```mermaid
        \(String(repeating: "%% synthetic comment\n", count: 301))
        flowchart TD
        A --> B
        ```
        """
        let clip = ClipMetadataReader.read(body, file: .init(path: "clips/mermaid-probe.md", sha: String(repeating: "a", count: 40), size: body.utf8.count))
        context.coordinator.html = MarkdownRenderer.document(clip, root: "clips")
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        guard !context.coordinator.started else { return }
        context.coordinator.started = true
        web.loadHTMLString(context.coordinator.html, baseURL: URL(string: "sourcebraid-document://local/"))
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.task?.cancel(); web.stopLoading(); web.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let report: (String) -> Void
        var task: Task<Void, Never>?
        var html = ""
        var started = false
        init(report: @escaping (String) -> Void) { self.report = report }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "sourcebraid-document" || navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            report("Synthetic WebKit document loaded")
            task = Task { [weak self, weak web] in
                guard let self, let web else { return }
                do {
                    try await MermaidRenderer.render(in: web, progress: report)
                    let check = try await web.callAsyncJavaScript("""
                    const figures = [...document.querySelectorAll('[data-mermaid]')];
                    const good = [0, 1, 3].filter(index => {
                      const figure = figures[index];
                      const svg = figure?.querySelector('.mermaid-preview svg');
                      return figure?.dataset.mermaidRendered === 'true' && svg?.getBoundingClientRect().width > 0 &&
                        !figure.querySelector('details').open && svg.textContent.trim().length > 0;
                    }).length;
                    const failed = figures[2]?.dataset.mermaidRendered === 'false' && figures[2]?.querySelector('details').open;
                    const limited = figures[5]?.dataset.mermaidRendered === 'false' && figures[5]?.querySelector('details').open;
                    const unsafe = document.querySelectorAll('.mermaid-preview script, .mermaid-preview img, .mermaid-preview image, .mermaid-preview foreignObject, .mermaid-preview a').length;
                    return `good=${good};failed=${failed};limited=${limited};unsafe=${unsafe};count=${figures.length}`;
                    """, arguments: [:], in: nil, contentWorld: MermaidRenderer.contentWorld) as? String ?? "Missing checks"
                    let page = try await web.evaluateJavaScript("`pageScript=${globalThis.archiveScriptRan === true};isolated=${typeof mermaid === 'undefined'}`") as? String ?? "Missing isolation check"
                    try Task.checkCancellation()
                    report(check + ";" + page)
                } catch { if !Task.isCancelled { report("Mermaid probe failed: " + error.localizedDescription) } }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report("Mermaid probe failed: navigation " + error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report("Mermaid probe failed: provisional navigation " + error.localizedDescription)
        }
    }
}
#endif

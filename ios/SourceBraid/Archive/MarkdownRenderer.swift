import Foundation
import Markdown
import WebKit

enum MarkdownRenderer {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }

    static func document(_ clip: ArchiveClip, root: String, allowRemoteImages: Bool = false) -> String {
        let renderer = Builder(path: clip.path, root: root, allowRemoteImages: allowRemoteImages)
        let content = renderer.render(Document(parsing: clip.body))
        return """
        <!doctype html><html lang="\(Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en")"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src sourcebraid-asset:; script-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
        <style>
        :root{color-scheme:light dark;--surface:#FBFAF6;--ink:#143431;--secondary:#49615E;--accent:#166B68;--separator:#CCCFC8;--muted-surface:#E6EFE8}
        @media(prefers-color-scheme:dark){:root{--surface:#1C403C;--ink:#F4F1E9;--secondary:#AEC2BC;--accent:#8FD1BF;--separator:#35534D;--muted-surface:#214B43}}
        @media(prefers-contrast:more){:root{--secondary:#143431;--accent:#0D4B49;--separator:#49615E}}
        @media(prefers-color-scheme:dark) and (prefers-contrast:more){:root{--secondary:#F4F1E9;--accent:#D8EFC8;--separator:#AEC2BC}}
        html,body{background:var(--surface);color:var(--ink)}body{font:-apple-system-body;margin:20px;line-height:1.6;overflow-wrap:anywhere}
        h1,h2,h3,h4,h5,h6{line-height:1.25}a{color:var(--accent);text-underline-offset:.15em}
        pre{padding:12px;background:var(--muted-surface);border:1px solid var(--separator);border-radius:8px;overflow:auto;white-space:pre}
        code{font-family:ui-monospace,monospace;background:var(--muted-surface);padding:.1em .3em;border-radius:4px}pre code{background:transparent;padding:0;border-radius:0}
        table{display:block;overflow:auto;border-collapse:collapse;max-width:100%}th{background:var(--muted-surface)}
        th,td{border:1px solid var(--separator);padding:8px}blockquote{background:var(--muted-surface);color:var(--secondary);border-inline-start:3px solid var(--accent);margin-inline:0;padding-inline:14px;padding-block:6px}
        hr{border:0;border-top:1px solid var(--separator)}::selection{background:var(--muted-surface);color:var(--ink)}input{accent-color:var(--accent)}
        li>p:first-of-type{display:inline}li>input{margin-inline-end:.4em}
        img{max-width:100%;height:auto}.image-placeholder{display:block;padding:8px;background:var(--muted-surface);color:var(--secondary);border:1px dashed var(--separator)}
        .mermaid-diagram{margin:1em 0;border:1px solid var(--separator);border-radius:8px;padding:12px;overflow:hidden}
        .mermaid-preview{overflow:auto;max-height:75vh}.mermaid-preview svg{display:block;max-width:100%;height:auto;margin:auto}
        .mermaid-status,.mermaid-diagram summary{font-size:.85em;color:var(--secondary)}.mermaid-diagram details{margin-top:8px}
        .mermaid-diagram pre{margin-bottom:0}.mermaid-preview[hidden]{display:none}
        </style></head><body><article>\(content)</article></body></html>
        """
    }

    static func resourceURL(_ path: String, scheme: String, fragment: String? = nil) -> URL? {
        var url = URLComponents(); url.scheme = scheme; url.host = "local"; url.path = "/" + path; url.fragment = fragment
        return url.url
    }

    private final class Builder {
        let path: String, root: String
        let allowRemoteImages: Bool
        var headings: [String: Int] = [:]
        var sourceLines: Set<Int> = []
        init(path: String, root: String, allowRemoteImages: Bool) {
            self.path = path; self.root = root; self.allowRemoteImages = allowRemoteImages
        }
        func render(_ node: any Markup) -> String {
            if let text = node as? Markdown.Text { return escape(text.string) }
            if let code = node as? InlineCode { return "<code>\(escape(code.code))</code>" }
            if let code = node as? CodeBlock {
                // The info string is data, never an HTML attribute or executable script.
                let language = code.language?.split(whereSeparator: { $0.isWhitespace }).first?.lowercased()
                if language == "mermaid" {
                    let label = archiveText("Mermaid diagram", "Mermaid-Diagramm")
                    let status = archiveText("Diagram preview unavailable. The original Mermaid source is shown below.", "Diagrammvorschau nicht verfügbar. Der originale Mermaid-Quelltext steht unten.")
                    let source = archiveText("Mermaid source", "Mermaid-Quelltext")
                    return """
                    <figure\(sourceID(node)) class="mermaid-diagram" data-mermaid>
                    <div class="mermaid-preview" role="img" aria-label="\(escape(label))" hidden></div>
                    <p class="mermaid-status" role="status">\(escape(status))</p>
                    <details open><summary>\(escape(source))</summary><pre><code>\(escape(code.code))</code></pre></details>
                    </figure>
                    """
                }
                return "<pre\(sourceID(node))><code>\(escape(code.code))</code></pre>"
            }
            if let html = node as? HTMLBlock { return "<pre>\(escape(html.rawHTML))</pre>" }
            if let html = node as? InlineHTML { return escape(html.rawHTML) }
            if node is LineBreak { return "<br>" }
            if node is SoftBreak { return "\n" }
            if node is ThematicBreak { return "<hr>" }
            if let image = node as? Image {
                guard let destination = image.source else { return escape(image.plainText) }
                var url: URL?
                if let remote = ArchivePath.externalURL(destination) {
                    if allowRemoteImages && remote.scheme == "https" {
                        var parts = URLComponents(); parts.scheme = "sourcebraid-asset"; parts.host = "remote"
                        parts.queryItems = [URLQueryItem(name: "url", value: remote.absoluteString)]; url = parts.url
                    }
                } else if let resolved = try? ArchivePath.resolve(destination, from: path, root: root), Self.raster(resolved) {
                    url = MarkdownRenderer.resourceURL(resolved, scheme: "sourcebraid-asset")
                }
                guard let url else {
                    return "<span class='image-placeholder'>\(escape(archiveText("Image not loaded: ", "Bild nicht geladen: ") + image.plainText))</span>"
                }
                return "<img src='\(escape(url.absoluteString))' alt='\(escape(image.plainText))' loading='lazy'>"
            }
            let children = node.children.map(render).joined()
            if let link = node as? Markdown.Link {
                guard let destination = link.destination, let url = linkURL(destination) else { return children }
                return "<a href='\(escape(url))'>\(children)</a>"
            }
            if let heading = node as? Heading {
                let slug = heading.plainText.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : ($0 == " " || $0 == "-" ? "-" : "") }.joined()
                let count = headings[slug, default: 0]; headings[slug] = count + 1
                let id = count == 0 ? slug : "\(slug)-\(count)"
                return "<span\(sourceID(node))></span><h\(heading.level) id='\(escape(id))'>\(children)</h\(heading.level)>"
            }
            let tag: String
            switch node {
            case is Document: return children
            case is Paragraph: tag = "p"
            case is Strong: tag = "strong"
            case is Emphasis: tag = "em"
            case is Strikethrough: tag = "del"
            case is BlockQuote: tag = "blockquote"
            case is UnorderedList: tag = "ul"
            case is OrderedList: tag = "ol"
            case let item as ListItem:
                let checkbox = item.checkbox.map { "<input type='checkbox' disabled \($0 == .checked ? "checked" : "") aria-label='\(archiveText("Task", "Aufgabe"))'>" } ?? ""
                return "<li>\(checkbox)\(children)</li>"
            case is Markdown.Table: tag = "table"
            case is Markdown.Table.Head: return "<thead><tr>\(children)</tr></thead>"
            case is Markdown.Table.Body: tag = "tbody"
            case is Markdown.Table.Row: tag = "tr"
            case is Markdown.Table.Cell: tag = node.parent is Markdown.Table.Head ? "th" : "td"
            default: return "<pre>\(escape(node.format()))</pre>"
            }
            return "<\(tag)\(sourceID(node))>\(children)</\(tag)>"
        }
        private func sourceID(_ node: any Markup) -> String {
            guard let line = node.range?.lowerBound.line else { return "" }
            // Inline nodes share line numbers; only block containers need targets.
            guard node is BlockMarkup, sourceLines.insert(line).inserted else { return "" }
            return " id='source-L\(line)'"
        }
        private func linkURL(_ value: String) -> String? {
            if let remote = ArchivePath.externalURL(value) { return remote.absoluteString }
            if value.hasPrefix("#") { return value }
            let pieces = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = pieces.first, let resolved = try? ArchivePath.resolve(String(first), from: path, root: root) else { return nil }
            return MarkdownRenderer.resourceURL(resolved, scheme: "sourcebraid-document", fragment: pieces.count == 2 ? String(pieces[1]) : nil)?.absoluteString
        }
        static func raster(_ path: String) -> Bool {
            ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        }
    }
}

// Only this app-owned, offline bundle executes, in a separate JavaScript world.
// The Markdown document keeps allowsContentJavaScript=false and script-src 'none'.
enum MermaidRenderer {
    static let contentWorld = WKContentWorld.world(name: "SourceBraid.Mermaid")

    @MainActor static func render(in webView: WKWebView, bundle: Bundle = .main,
                                  progress: ((String) -> Void)? = nil) async throws {
        try Task.checkCancellation()
        guard let engine = bundle.url(forResource: "mermaid.tiny", withExtension: "js", subdirectory: "Mermaid"),
              let adapter = bundle.url(forResource: "sourcebraid-mermaid", withExtension: "js", subdirectory: "Mermaid") else {
            // HTML already contains the accessible, original-source fallback.
            return
        }
        progress?("Loading bundled Mermaid engine")
        let script = try String(contentsOf: engine, encoding: .utf8) + "\n" + String(contentsOf: adapter, encoding: .utf8)
        _ = try await webView.evaluateJavaScript(script + "\nvoid 0;", in: nil, contentWorld: contentWorld)
        try Task.checkCancellation()
        progress?("Rendering synthetic Mermaid diagrams")
        _ = try await webView.callAsyncJavaScript("return await globalThis.SourceBraidMermaid.renderAll();", arguments: [:], in: nil, contentWorld: contentWorld)
        progress?("Mermaid render completed")
    }
}

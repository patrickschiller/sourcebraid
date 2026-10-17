# Offline Mermaid / Mermaid offline

`mermaid.tiny.js` is the unmodified official `@mermaid-js/tiny` **12.2.0**
distribution from <https://registry.npmjs.org/@mermaid-js/tiny/-/tiny-12.2.0.tgz>.
The exact tarball integrity and bundle SHA-256 are recorded in
`vendor-manifest.json`; verify both when replacing the bundle. Its upstream
source is <https://github.com/mermaid-js/mermaid/tree/mermaid%4012.2.0>.
`LICENSE-mermaid.txt` and `ThirdPartyNotices.txt` retain the applicable notices.
No npm install, download, CDN, diagram service or network connection is needed
at runtime. The app and test targets both copy this folder as a resource.

The app-owned `sourcebraid-mermaid.js` reads escaped fenced-block text and
renders in an isolated `WKContentWorld`. Archived scripts stay disabled;
the document retains `script-src 'none'`, `connect-src 'none'` and no network
origin. Strict Mermaid security, SVG sanitization and a native remote-image
permission check prevent diagrams from enabling scripts, links or media.

The tiny distribution supports common flowcharts, sequence/state/class/ER
diagrams and Gantt charts. ELK layouts fall back to Dagre. Mindmaps,
architecture diagrams and KaTeX are omitted by upstream; unsupported or
invalid input stays visible as original Mermaid source, with a clear message.
The adapter limits previews to 12 diagrams, 20,000 characters/300 lines per
diagram, 100,000 total characters and 200 flowchart edges. These limits affect
previews only, never archive content or its raw Markdown.

Die Datei stammt unverändert aus der oben genannten offiziellen Distribution.
Diagramme werden vollständig auf dem Gerät dargestellt. Das Archiv bleibt
unverändert; der originale Quelltext ist immer aufklappbar. Fehlerhafte,
nicht unterstützte oder zu große Diagramme zeigen einen Hinweis und ihren
Quelltext. ELK, Mindmaps, Architekturdiagramme und KaTeX sind nicht enthalten;
ELK-Layouts verwenden Dagre. Externe Dienste, aktive Archivskripte und
zusätzliche Berechtigungen werden nicht benötigt.

Upstream usage and supported tiny-build limitations:
<https://mermaid.js.org/config/usage#tiny-mermaid>

# SourceBraid for iOS

The iOS project contains a SwiftUI archive reader, configuration screens, and a
native Share Extension. The maintainer approved the **1.1.0** release candidate
for publication on October 15, 2026 after a hands-on functional check. Xcode
Cloud distribution and App Store availability are tracked separately in the
[release notes](../docs/IOS_RELEASE_1.1.0.md). The Share
Extension saves shared URLs, readable Safari content and its relevant image
assets, selected text, PDFs, and other files into the same GitHub repository
and URL-hash-sharded `web-clips/index/*.jsonl` format as the Chrome extension.

Reader and search support iOS/iPadOS 17 or later. Optional local chat requires
iOS/iPadOS 26 or later and an available Apple Intelligence system model with a
supported language. The Duo hinge adapter is guarded by iOS 27.1 availability.
An SDK build does not replace device acceptance. Markdown uses pinned
`swift-markdown`/`swift-cmark` 0.9.0 with their own bundled license notices;
PDF attachments use native Quick Look. See the [test record](../docs/IOS_IMPLEMENTATION_TESTING.md)
and [device checklist](../docs/IOS_DEVICE_ACCEPTANCE.md).

## Open and sign

1. Open `SourceBraid.xcodeproj` in Xcode.
2. Select the **SourceBraid** project and the **SourceBraid** target.
3. Under **Signing & Capabilities**, select your Apple Developer team.
4. Repeat for the **SourceBraidShare** target.
5. Register or select the SourceBraid bundle identifiers `de.patrickschiller.sourcebraid` and `de.patrickschiller.sourcebraid.share`.
6. Register the App Group `group.de.patrickschiller.sourcebraid`, enable it for both targets, and keep the shared Keychain access group aligned with the entitlements.
7. Run the SourceBraid app on your iPhone once and configure GitHub.

Reader-only use needs `Contents: Read` for the selected GitHub repository. The Share Extension needs `Contents: Read and write` to save captures. The token is stored in the existing Keychain access group shared by the app and extension.

## TestFlight

The project uses automatic distribution signing for Apple Developer team
`H76K2HQUFB`. The approved release candidate is version `1.1.0` (build `11`) for
both the app and Share Extension. Its planned iOS-only GitHub tag is
`ios-v1.1.0`; Chrome, the Codex plugin, and hosted MCP remain at `1.0.1`.
Before every later upload, increment `CURRENT_PROJECT_VERSION` for both targets.
The maintainer reports that the Xcode Cloud workflow uses Xcode 27.1 RC.
Cloud archive, distribution, and App Store processing must each be verified
from their actual results; none is implied by local validation.

Run the release preflight from the repository root before archiving:

```bash
python3 scripts/validate_ios_release.py
```

Use Xcode 27.1 or later for the Duo API and a toolchain accepted by App Store
Connect for distribution. Select the intended installation explicitly for each
local command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/SourceBraid.xcarchive \
  -allowProvisioningUpdates \
  archive

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportArchive \
  -archivePath build/SourceBraid.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

The export options upload the archive directly to App Store Connect. Create the
initial app record with bundle ID `de.patrickschiller.sourcebraid` and the
customer-facing name **SourceBraid** before the first upload.

After archiving and before uploading, validate the exact packaged app, including
its generated icon references, embedded Share Extension, privacy manifests,
bundle identifiers, version, and build number:

```bash
python3 ../scripts/validate_ios_release.py \
  --app-bundle build/SourceBraid.xcarchive/Products/Applications/SourceBraid.app
```

## Use

The app starts at **Latest** with the latest seven clips, ordered by recorded
capture time and documented day/filename fallbacks. Tap a row to open it. Native
**Search** and **Chat** destinations keep the initial list spacious; Refresh and More live in the
toolbar. Wider layouts show the chosen destination alongside the reader.
Search covers downloaded text and displays index coverage. Warm starts restore
the local catalog without downloading articles again. An empty cache seeds at
most seven bodies; the initial filename-based candidates remain explicitly
partial until further metadata is read. Bounded background batches and manual
refresh update new/changed files. iOS determines background execution time.
Downloaded clips can be read offline while credentials remain configured;
iOS may evict caches. See the [navigation and refresh concept](../docs/IOS_READER_REFRESH_UX.md).

The reader supports headings, emphasis, nested lists, tasks, code, quotes,
tables, local raster images and archive-relative links. Raw HTML is escaped,
document JavaScript is disabled, and external images require a per-document
loading choice. Reader options offer raw Markdown, sharing, and GitHub fallback.
Files above 5 MiB (Markdown) or 20 MiB (preview assets) use the GitHub fallback;
capture's separate 25 MB attachment limit remains unchanged. The retained
cache target is 250 MiB per archive, including a search index capped near
100 MiB; these are development budgets awaiting real-archive measurements.

On eligible devices **Ask the archive** offers selected-clip or archive scope.
Answers cover bounded excerpts, not necessarily complete long documents.
Source buttons open the referenced immutable version and paragraph. Interrupted
or invalidly cited answers are labeled unverified. No AI service credentials
are required. Unsupported devices retain reader/search and show the reason
chat is unavailable. App Shortcuts provide read-only search, recent clips, and
opening a loaded clip; broader Siri conversation support is not promised.

In Safari, Files, or another app:

1. Tap **Share**.
2. Choose **SourceBraid**. If it is hidden, use **More** to enable it.
3. Edit the title, add optional tags or a note, and tap **Save**.

Apps such as Chrome generally share only a URL. SourceBraid loads public web URLs in an isolated web view and converts the readable page content to Markdown before saving, recording the same extraction methods as the browser extension (including specialized DeepMind captures). Safari can additionally supply its already visible page text and relevant article images through the extension's preprocessing script. Images are copied into the clip's asset folder and linked relatively in Markdown. Shared PDFs are queued as `pdf-docling-pending`; the PDF is pushed last so the existing GitHub Actions workflow can safely convert it after its Markdown and index metadata exist. Pages that require an authenticated browser session or block the isolated request are saved as clearly labeled link-only clips.

## Build without signing

```bash
xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Local acceptance tests

Use Xcode 27.1 for the complete candidate, including the Duo API. Select an
installed simulator and run **Product → Test**; the shared scheme includes
unit/integration tests and synthetic UI tests. No test needs a real archive or
GitHub token. For CLI commands, synthetic demo setup, and real-device checks,
see [English](../docs/IOS_DEVICE_ACCEPTANCE.md) / [Deutsch](../docs/IOS_DEVICE_ACCEPTANCE.de.md).

The maintainer has approved publication of version 1.1.0/build 11. The remaining
minimum-OS, physical Duo transition, dark-appearance, accessibility, and real
model-quality checks remain documented in the acceptance checklist; this
approval does not mark the full device matrix as passed. Historical test
entries retain the version and build that were actually tested.

## Deutsch: Release-Kandidat 1.1.0

Der Maintainer hat Version **1.1.0/Build 11** am 15. Oktober 2026 nach eigenem
Funktionstest zur Veröffentlichung freigegeben. Der geplante iOS-GitHub-Tag
lautet `ios-v1.1.0`; Chrome, Codex-Plugin und gehosteter MCP bleiben auf `1.0.1`.
Der Xcode-Cloud-Workflow verwendet laut Maintainer Xcode 27.1 RC. Cloud-Build,
Distribution und App-Store-Verfügbarkeit werden anhand ihrer tatsächlichen
Ergebnisse getrennt geprüft. [Release-Hinweise](../docs/IOS_RELEASE_1.1.0.de.md).

Die App startet mit **Neueste** und den neuesten sieben Beiträgen; Antippen
öffnet den Beitrag direkt. Native Bereiche für **Suche** und **Chat** halten
die Startliste frei. Aktualisieren und
weitere Aktionen liegen in der Toolbar. Breite Oberflächen zeigen den gewählten
Bereich neben dem Reader. Cache-Starts laden keine Artikel erneut. Bei leerem
Cache werden höchstens sieben Dateien versucht; die Dateinamens-Kandidaten bleiben
bis zum weiteren Metadatenabruf als Teilbestand markiert. Begrenzte
Hintergrundpakete und manuelles Aktualisieren lesen neue/geänderte Dateien.
iOS entscheidet über Hintergrundzeitpunkte. Das
[Navigations- und Aktualisierungskonzept](../docs/IOS_READER_REFRESH_UX.de.md)
beschreibt die Grenzen. Die Duo-Faltanpassung benötigt iOS 27.1; vollständige
Faltzyklen und reale Duo-Hardware sind weiterhin gesondert zu prüfen.

Reader und Suche sind ab iOS/iPadOS 17 vorgesehen; Chat benötigt zusätzlich
iOS/iPadOS 26, ein unterstütztes Gerät, aktivierte Apple Intelligence und ein
bereites Modell in einer unterstützten Sprache. Nicht verfügbare KI wird
verständlich angezeigt. Quellenlinks verweisen auf gelieferte Auszüge einer
festen Dateiversion; sachliche Antwortqualität wird separat getestet.

Markdown wird lokal mit `swift-markdown` dargestellt, PDF-Anhänge über Quick
Look. Externe Bilder werden nur nach bewusster Auswahl geladen. Der Reader
verändert keine GitHub-Dateien. Für reines Lesen genügen Contents-Leserechte;
die Share Extension benötigt zum Speichern weiterhin Schreibrechte.
Details, Grenzen und Abnahmeschritte stehen
im [Testprotokoll](../docs/IOS_IMPLEMENTATION_TESTING.de.md) und in der
[Gerätecheckliste](../docs/IOS_DEVICE_ACCEPTANCE.de.md). Die Release-Freigabe
ersetzt keine offenen Mindest-OS-, Dunkelmodus-, Accessibility- oder echten
KI-Qualitätsnachweise.

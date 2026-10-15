# SourceBraid: iOS Reader, Apple Intelligence, and iPhone Duo

**SourceBraid — Weave the web into Markdown.**

As of **October 12, 2026** · Status: **Concept approved; local implementation, device acceptance pending**
· [Deutsche Version](IOS_READER_INTELLIGENCE_DUO_PLAN.de.md)

This concept plans the expansion of the configuration app into an archive
reader with optional AI chat. It implements no features and changes no
commitments for the current plugin release. Modules M00–M10 will be implemented
and accepted individually, in this order.

## Approved local implementation

The maintainer approved the module order and requested intensive local Xcode
and device testing. No commits or publication before final approval. The
[implementation/test record](IOS_IMPLEMENTATION_TESTING.md) and
[device checklist](IOS_DEVICE_ACCEPTANCE.md) supplement this concept; the
acceptance criteria below remain binding.

## 1. Goals and binding product decisions

1. On iPhone and iPad, users can correctly read the Markdown files in their
   configured GitHub archive, including archived images and traceable
   provenance. A suitable Apple system viewer takes priority; its actual
   Markdown support must first be verified.
2. On supported devices, an optional chat answers questions about a clip or
   the archive and links to the evidence it used. The first implementation
   explicitly uses Apple's **on-device** system model.
3. On an open iPhone Duo, the latest five clips and chat appear on the left,
   with the selected clip on the right. The closed device's main view shows
   the selection list and chat. Selection and reading position are preserved.
4. GitHub Markdown and Git history remain authoritative. The catalog, search
   index, preview files, and answers are derived from them; AI results do not
   automatically become archive content or source metadata.
5. Reading and searching work without Apple Intelligence. The existing
   iOS/iPadOS 17 deployment target is retained initially. Newer features have
   separate SDK and runtime availability checks.

Planned scope: reading, archive navigation, local search, chat with evidence,
and specific system actions. Editing, AI-driven deletion, automatic changes
to Markdown/index shards, cloud AI, an app-hosted MCP server, and Android are
outside this expansion. The Share Extension remains the existing way to save
new content.

## 2. Repository baseline

| Component | Existing capability | Consequence |
| --- | --- | --- |
| [ContentView](../ios/SourceBraid/App/ContentView.swift), [SettingsViewModel](../ios/SourceBraid/App/SettingsViewModel.swift) | Settings form and local capture list | Move settings into a separate area; build reader state separately. |
| [GitHubClient](../ios/SourceBraid/Shared/GitHubClient.swift) | Connection testing, writing, and private methods for reading individual files | Add a read interface with a complete file catalog and consistent Git snapshots. |
| [RecentCaptureStore](../ios/SourceBraid/Shared/RecentCaptureStore.swift) | Up to 20 local Share Extension captures without a repository namespace | Does not establish the latest five clips across the archive. |
| [ClipBuilder](../ios/SourceBraid/Shared/ClipBuilder.swift) | Markdown, frontmatter, relative assets, URL-hash shards; index model is only `Encodable` | Add a separate tolerant read model; preserve the existing write format. |
| [Xcode project](../ios/SourceBraid.xcodeproj/project.pbxproj) | iOS 17, iPhone and iPad, existing XCTest target | Reader on both device families; AI only in the app target, not the Share Extension. |
| [Local plugin](../codex-plugin/sourcebraid/scripts/sourcebraid.py), [ChatGPT service](../chatgpt-mcp/src/archive.mjs) | Search/fetch and derived indexes, each with its own limits | Reuse the functional search/fetch contracts without requiring a server or Python process on iOS. |

The existing plugin listings are not a model for precise chronology: the
local parser sometimes prioritizes date-only values over `captured_at`; the
hosted service lists by path and bounds its fallback scan. The new reader
explicitly defines its ordering and completeness.

## 3. Verified platform baseline and outstanding evidence

### Markdown

Apple documents Quick Look for several file types, including text, but does
not guarantee a complete Markdown/GFM reader. `QLPreviewController.canPreview`
only confirms that a preview is possible. Quick Look is therefore suitable
as the main reader only after passing the rendering tests.
[Quick Look](https://developer.apple.com/documentation/quicklook/),
[canPreview](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller/canpreview(_:))

SwiftUI `Text` does not support complete Markdown block rendering, such as
tables and code blocks. `AttributedString` provides parsing, not a ready-made
document viewer. The `MarkdownViewer` example for `ReadableDocument` also
refers to a custom `MarkdownView`.
[Text](https://developer.apple.com/documentation/swiftui/text/init(_:tableName:bundle:comment:)),
[Parsing](https://developer.apple.com/documentation/foundation/attributedstring/markdownparsingoptions/interpretedsyntax-swift.enum),
[ReadableDocument](https://developer.apple.com/documentation/swiftui/readabledocument)

**Decision:** M00 evaluates the native approach. If it fails the required
cases, M03 implements a local Markdown renderer behind the same interface.
The proposed fallback is an AST-based parser with safely generated HTML and
bundled CSS in `WKWebView`. The official
[Swift Markdown](https://github.com/swiftlang/swift-markdown) project is a
parser candidate; its version, package scope, and
[license](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt)
will be reviewed and documented before adoption. It is not a viewer component
shipped with iOS. No remote rendering service is planned.

### Apple Intelligence

Foundation Models, available from iOS/iPadOS 26, is the basis for optional
chat. The plan uses `SystemLanguageModel.default`, checking `availability`
and language support. The current framework documentation also covers other
model options; this concept deliberately selects only the on-device option.
[Foundation Models](https://developer.apple.com/documentation/foundationmodels),
[SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

An operating-system check alone is insufficient: device eligibility,
activation, model readiness, and language must be considered. The app builds
its own SwiftUI chat interface; it does not assume an existing API for a
complete, generally embeddable Apple Intelligence chat control. App Intents
provide a separate system entry point and do not replace this chat. In
particular, the reader schema currently promises Shortcuts support only,
not automatic Siri/Apple Intelligence discovery.
[Availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.property),
[Reader schema](https://developer.apple.com/documentation/appintents/app-schema-domain-reader)

### iPhone Duo

Apple describes the device and full-screen access with Xcode/iOS SDK 27.1.
Standard navigation, size classes, and asymmetric safe areas provide the
foundation. [Device overview](https://developer.apple.com/iphone-duo/),
[Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)

Reserved regions and arrangement APIs are among the options for particular
folding states. An arrangement does not provide navigation. SourceBraid's
primary choice remains `NavigationSplitView`; additional APIs will be used
only where a need is demonstrated.
[Adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)

During concept validation, Xcode 27.0 was installed locally, while the active
developer selection pointed to Command Line Tools. An explicit
`DEVELOPER_DIR` could access Xcode. Duo-specific SDK 27.1 tests have not yet
been run. M00 establishes a suitable toolchain, simulators, devices, and the
Xcode version accepted for a later release. SDK version and minimum operating
system are handled separately.

## 4. Interaction and states

### Wide view: iPad and open Duo

```text
┌──────────────────────────────────┬──────────────────────────────────────┐
│ SourceBraid             Settings │ Clip title                           │
│ Latest 5 · Sync status           │ Source · Captured · Capture method   │
│ 1  Clip                          │                                      │
│ 2  Clip                          │ Formatted Markdown content           │
│ 3  Clip                          │ with images, tables, and links       │
│ 4  Clip                          │                                      │
│ 5  Clip                          │                                      │
│ All clips / Search               │                                      │
├──────────────────────────────────┤                                      │
│ Ask the archive                  │                                      │
│ Scope: This clip / Archive       │                                      │
│ History and clickable evidence   │                                      │
│ Message …                  Send  │                                      │
└──────────────────────────────────┴──────────────────────────────────────┘
```

The left-hand list and chat history scroll independently; the input area
remains accessible with the keyboard open. Five clips means five selectable
entries, not five rows forced to remain visible at every text size. Column
widths follow the available window space, minimum reading width, and
accessibility needs; there is no fixed 50:50 ratio. Without a selection, the
right-hand side prompts the user to choose a clip.

### Compact view and transitions

- The closed Duo's main view shows the latest five clips and chat. Tapping a
  row selects the clip and potential chat context, but does not automatically
  open the detail column.
- Closing the device explicitly returns navigation to the main view, even
  when the reader was previously active. Opening it restores the selected
  clip on the right, including its reading position.
- An explicit “Read” action or a source citation may open a separate detail
  view; “Back” returns to selection and chat. This keeps content readable on
  ordinary iPhones and in narrow iPad windows. The “selection and chat only”
  requirement applies to the closed device's main view.
- Draft text, chat history, selection, citations, and an in-progress answer
  survive layout changes. A layout change does not start a second request.
  A suspended app may cleanly cancel an answer and offer “Continue/Try again”;
  there is no background-execution guarantee.
- Layout decisions use size classes, local window geometry, and reserved
  regions where needed. Device model comparisons, `UIScreen.main`,
  orientation heuristics, and hinge angles are not used as column breakpoints.
  A documented closing callback may control navigation policy; the compact
  fallback must work without that callback as well.
- AI unavailable: show a clear status in place of active chat controls while
  keeping the list, search, and reader usable. Do not show an empty chat box
  that appears functional.

Persistent session state and running tasks live outside the changing view
hierarchy. Selection and reading position may be restored locally; chat
history and drafts initially remain in memory only. Changing repositories
ends the previous chat context. Multiple windows have separate UI/chat
sessions; a shared cache requires serialized writes.

## 5. Data, search, and security contracts

### Archive access and the latest five clips

`ArchiveIdentity` includes GitHub host, owner, repository, branch, and
normalized root path. `ClipID` adds the repository-relative path; a specific
version of the content is additionally identified by commit and blob SHA.
The first implementation continues to support the existing GitHub.com host.

A synchronization run resolves the branch to a commit once and reads files
and assets from that snapshot. The catalog enumerates every Markdown file
under the configured root. JSONL shards accelerate startup; paths and
metadata are reconciled against the authoritative Markdown files, including
when a shard is missing, stale, or contains a malformed line. Deleted files
disappear after a complete inventory check; an interrupted scan does not
cause speculative cache deletions.

The Contents API is not an unlimited, paginated directory listing. The Trees
API is planned for large archives; truncated recursive results are completed
through subtree queries. Cancellation, size limits, or API limits are shown
as an incomplete state.
[GitHub Contents](https://docs.github.com/en/rest/repos/contents),
[GitHub Trees](https://docs.github.com/en/rest/git/trees)

Ordering contract:

1. Newest first: compare valid `captured_at` values with time zones as UTC
   instants in descending order.
2. Without a valid timestamp, use `capture_date`, followed by a date-only
   value defined as the capture date in a known legacy format, and finally a
   valid date from the archive path. Date-only values use 00:00 UTC solely
   for sorting, independently of the device time zone. Provenance and day
   precision remain visible; this does not claim a known capture time.
3. Only when every date source is missing is a clip considered undated and
   placed after dated clips. Break equal sort values by normalized path in
   ascending lexicographic order, without locale-dependent sorting.
4. Publication dates, commit dates, and local device history never silently
   replace capture time. Missing titles appear as filenames, labeled as such.
5. “Latest 5” means the first five existing Markdown clips in this archive,
   regardless of the device used to capture them. Show all if there are fewer.
   During initial synchronization, show “Up to 5 most recently loaded clips”
   with progress; claim archive-wide recency only after full metadata
   reconciliation. Offline, show “As of …”.

PDF placeholders are visible clips with conversion status; a later blob
change updates the reader and search index. Attached PDFs can additionally
be opened in Quick Look. AI uses only existing extracted text; pending
conversion is not treated as having read the PDF content.

### Local storage and search

`ArchiveCache` stores verified metadata and, as needed, Markdown and assets.
`ArchiveSearchIndex` is a rebuildable SQLite FTS index for titles, tags,
sources, and text; no access to the desktop database is required. Schema
version, archive identity, blob SHA, and coverage status are separate from
archive formats. No new frontmatter field or shard format is introduced.

Catalog completeness, downloaded content, and search coverage are distinct
states. A complete path catalog does not mean full-text search is complete.
“Search archive” shows the number of indexed clips against known clips;
“no matches in the loaded portion” does not claim the entire archive has no
answer.

Initial budgets, to be validated as product requirements: 5 MiB per Markdown
file, 20 MiB per asset, and 250 MiB for the entire persistent cache including
the search index. Larger files get an explicit limit notice and a GitHub
link; content is never silently truncated. Downloads are cancellable and
throttled. ETags/blob SHAs avoid unnecessary transfers; rate-limit/retry
headers control retries. M00 measures these requirements against synthetic
archives.
[GitHub API behavior](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)

The cache resides in the protected app container, is excluded from backups,
and has a size/eviction policy. “Remove local data” deletes the cache,
search index, and previews, never GitHub files. Signing out additionally
removes credentials and transient chats; changing archives immediately blocks
old results and discards the old cache. The existing unpartitioned
`RecentCaptureStore` is cleared on a switch or properly partitioned per
archive in the future. Existing Keychain/App Group boundaries remain intact.

### Rendering, resources, and provenance

- Display YAML frontmatter separately from the text. The parser accepts known
  legacy formats and unknown optional fields; no object construction from
  YAML and no changes to original bytes. Errors are explained clearly.
- Required scope: headings, paragraphs, emphasis, lists, task lists,
  blockquotes, code blocks, GFM tables, links, and archived raster images.
  Raw view and copying remain available. Math/Mermaid initially appear as
  readable source text; there is no arbitrary script renderer.
- Resolve relative links and assets relative to the Markdown file. Normalized
  paths must remain within the permitted archive area; do not follow symlinks,
  submodules, absolute file paths, or traversal. Linked archive clips open in
  the reader; source links open externally after a tap.
  This contract applies to every renderer: external links may use only
  `https`/`http`; reject local/active or arbitrary app schemes such as `file`,
  `data`, and `javascript`. Protocol-relative URLs are not treated as archive
  paths. External resources never receive GitHub authentication.
- External images do not load by default; an explicit load action explains
  third-party access. No remote fonts, automatic source visits, trackers,
  or automatically loaded active SVG/HTML content.
- For the WebKit fallback: AST allowlist, HTML escaping, JavaScript disabled,
  nonpersistent WebKit data store, restrictive CSP, controlled resource
  handler, and navigation validation. No PAT in HTML, URLs, logs, or JavaScript
  bridges. WebKit configuration alone does not replace the resolver and
  network restrictions.
  [JavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript),
  [Data store](https://developer.apple.com/documentation/webkit/wkwebsitedatastore),
  [Resource handler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)

### AI contract

The interface could be named “Ask the archive,” with an Apple Intelligence
label. It offers “Summarize this clip,” free-form questions, topic searches,
and comparisons of selected results. A visible scope selector distinguishes
**This clip** from **Archive**; the default scope is the selected clip.
Without a selection, no hidden context is assumed.

The flow is: question → local search/targeted fetch → bounded text excerpts →
system model → answer with verified source references. Documents are split
at heading/paragraph boundaries. Retrieval ranking and excerpt sizes are
tested against fixed examples. The entire archive is not inserted into a
session. The context budget accounts for instructions, tool schemas,
history, excerpts, and response reserve; long conversations receive a new
bounded session with fresh source retrieval.

Apple currently specifies 4096 tokens for an on-device session. Actual model
capacity is checked through the available API; `tokenCount(for:)` requires
iOS/iPadOS 26.4. On 26.0–26.3, conservative limits and error handling apply.
Section-by-section summaries must show their coverage and preserve evidence
links back to the original source.
[Context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window),
[Token counting](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/tokencount(for:))

`ArchiveAIService` receives only narrowly scoped, read-only tools:

| Planned contract | Result |
| --- | --- |
| `listRecent(limit <= 5)` | Verified entries and freshness/completeness |
| `searchArchive(query, scope, limit)` | Bounded results, excerpts, and search coverage |
| `fetchClip(clipID, section, budget)` | Text within the permitted archive, snapshot, and evidence IDs |

The model receives no credentials, arbitrary URLs, SQL execution, filesystem
paths, or write tools. `Tool` calls are validated independently of model
outputs and executed with limits and cancellation support.
[Foundation Models Tool](https://developer.apple.com/documentation/foundationmodels/tool)

Evidence references `ClipID`, blob SHA, and a section/text range from the
context actually supplied. Only these IDs become clickable source chips;
invented IDs are rejected. Structural citation validation does not establish
factual truth: an evaluation set additionally checks whether the cited
excerpt supports the answer. When evidence is missing, the index is partial,
the model refuses, or the context overflows, the app explains the limitation
and offers source text/search.

Archive text is untrusted and may contain instructions directed at the AI.
It is delimited as source material; tool boundaries enforce read-only access
even when prompt delimiters fail. Guardrails remain active. No automatic web
search or transfer to ChatGPT, a SourceBraid server, Private Cloud Compute,
or other model providers.

| Runtime state | Behavior |
| --- | --- |
| OS too old or device ineligible | Reader/search remain fully usable; explain why AI is unavailable |
| Apple Intelligence disabled | Activation guidance; no automatic cloud fallback |
| Model not ready yet | Explained waiting state and another availability check |
| Language/region currently unsupported | Clear explanation; no forced system-language change |
| Model ready | Input, streaming, stop, and source links available |
| Runtime error, refusal, context too large | Preserve draft, explain error, offer a targeted retry |

Recheck availability when the app becomes active and before a request; handle
unknown future states safely. Current APIs such as token counting have their
own version requirements; M00 documents the actual selected SDK/OS combination
instead of mixing examples from different versions. Offline AI works only
with a ready on-device model and locally available sources. GitHub
synchronization still requires a network connection.

## 6. Module plan: one independently verifiable step at a time

Each module starts only after its prerequisite is accepted. Filenames for
new components describe the target structure, not files that already exist.
Every implementation PR states the problem, behavior, privacy/permission
effects, and checks actually run; commits carry a DCO sign-off.

### M00 — Platform and renderer validation

**Prerequisite:** this concept. **Deliverable:** documented decisions with
synthetic test files before product code is expanded.

- Test Quick Look against every required M03 case on the minimum and current
  OS; check `canPreview`, formatting, private assets, and source links
  separately.
- Select the native option if all required cases pass; otherwise specify the
  local parser/WebKit approach, including version, license, and integration
  effort.
- Run a minimal Foundation Models experiment on an eligible device: German/
  English, availability, a short answer supported by retrieval, streaming/
  cancellation, and context limit.
- Verify the Xcode 27.1/Duo test environment and the APIs actually available;
  calibrate memory/download budgets with small and large synthetic archives.
  Record unavailable hardware as outstanding evidence.

**Acceptance:** decision record with results and a justified renderer choice;
no unproven promise of a complete native viewer or system chat. Reader modules
may proceed without an AI test device; M06/M07/M10 then retain an explicit unmet
release criterion.

### M01 — Domain models and read-only GitHub access

**Prerequisite:** M00. **Components:** `ArchiveIdentity`, `ClipID`,
`ArchiveReadClient`, `ArchiveSnapshot`; existing configuration/Keychain.

- Make dependencies injectable, separate the read interface from capture
  writes, pin a Git commit, and read trees and blobs safely under the root.
- Validate URLs/paths, authenticate only to the allowed GitHub endpoint,
  check redirects, enforce size limits, support cancellation and backoff,
  and distinguish 401/403/404 errors.
- No broader token permissions. Capture continues to use its existing write
  permissions; reader and AI can request only GET operations.

**Acceptance:** mock network tests cover snapshot consistency, branch/root
changes, truncated trees, large directories, traversal, redirects, and
limits; the existing Share Extension save flow remains functional unchanged.

### M02 — Archive catalog, latest five, and offline cache

**Prerequisite:** M01. **Components:** `ClipMetadataReader`, `ArchiveCatalog`,
`ArchiveCache`, tolerant index/frontmatter read models.

- Use shards to accelerate startup, reconcile authoritative Markdown metadata
  and missing entries, and implement the ordering/completeness contract in
  section 5.
- Implement blob-based updates, offline state, progress, deletion
  reconciliation, cache limits, and isolation when configuration changes.
- Mark local capture hints as provisional until confirmed by GitHub.

**Acceptance:** an archive containing Chrome, iOS, and synthetic legacy entries
returns the same five regardless of device; tests cover same-day captures,
time zones, missing dates, invalid shards, empty archives, offline operation,
and PDF conversion.

### M03 — Markdown reader and controlled assets

**Prerequisite:** M02 and the renderer decision from M00.
**Components:** `MarkdownDocument`, `MarkdownRenderer`, `ArchiveAssetResolver`,
`ClipReaderView`, optional `SystemPreviewAdapter`.

- Implement frontmatter/provenance, required syntax, link navigation, relative
  images, conversion status, raw text, and reading position.
- Integrate native preview or the secured local renderer; resolve every
  resource through the same archive and snapshot contract.

**Acceptance:** visually check synthetic rendering fixtures on iPhone/iPad;
also cover dark appearance, Dynamic Type, VoiceOver, long tables/code, broken
assets, and malformed Markdown. Network testing confirms no unwanted
third-party requests or token forwarding. Raw text alone does not satisfy
reader acceptance.

### M04 — Archive interface and basic adaptive navigation

**Prerequisite:** M03. **Components:** `ArchiveViewModel`, `LibrarySidebar`,
`ArchiveSplitView`, separate `SettingsView`, central session state.

- Keep existing settings accessible; create a start view with the latest five,
  “All clips,” refresh, and reader. Add “Remove local data” and “Sign out”
  actions with the effects defined in section 5. The chat area is initially
  an internal placeholder for M07, not an empty feature shipped to users.
- Use two columns in wide views and explicit detail navigation in compact
  views. Localize setup, loading, empty, error, and offline states.

**Acceptance:** selection, back navigation, restoration, and rotation work on
iPhone and iPad; narrowing the window preserves selection/reading position.
This stage can be released separately as a reader without AI.

### M05 — Local full-text search and source retrieval

**Prerequisite:** M04. **Components:** `ArchiveSearchIndex`, `ArchiveRetriever`,
`SourceExcerpt`; SQLite through a reviewed local integration.

- Build and version a full-text index from downloaded Markdown files and
  update it after blob changes; support deletions and rebuilding.
- Offer search independently of AI; provide sections, result limits, and
  search coverage. Fetch the current clip in full or by section; handle long
  sources with clear section selection.

**Acceptance:** fixed German/English search cases find the expected sources;
cache loss is recoverable. Partial indexes, cache eviction, removed clips,
and configuration changes do not imply misleading completeness.

### M06 — Apple Intelligence availability and session adapter

**Prerequisite:** M05. **Components:** `IntelligenceAvailability`,
`ArchiveAIService` protocol, Foundation Models adapter, and test doubles.

- Isolate API/runtime requirements, implement the status matrix, and
  explicitly select the on-device model. The reader must work without the
  framework's model.
- Centrally manage lifetime, cancellation, streaming, errors, and context
  budget; view reconstruction must not trigger generation or concurrent
  competing requests in the same model session.

**Acceptance:** simulate every status state; record real availability/language
checks on supported hardware. The app launches with a usable reader on iOS 17
and ineligible devices; no unintended cloud request occurs.

### M07 — Archive chat with verifiable sources

**Prerequisite:** M06. **Components:** `ArchiveChatViewModel`, `ArchiveChatView`,
read-only model tools, `CitationValidator`.

- Add message input, history, scope selection, streaming, stop, and error
  handling to the left-hand/compact main view.
- Connect M05 retrieval to the tools; generate and validate evidence IDs;
  source chips open the reader at the appropriate section/snapshot.
- Test bounded context, session renewal, and prompt-injection defenses.
  Changing the selection does not retroactively alter an in-progress question.

**Acceptance:** a synthetic DE/EN evaluation set covers summarization, factual
questions, comparisons, missing answers, long articles, partial indexes,
and injected instructions. No invalid source links, writes, or answers that
cross archive boundaries; identified quality limits are documented before
release. Every layout change preserves the chat without duplicate requests.

### M08 — App Intents and specific system integration

**Prerequisite:** M07. **Components:** `ArchiveClipEntity`, queries and actions
for searching/opening/showing recent clips; App Shortcuts.

- Check documented schemas for semantic fit and actual Siri/Shortcuts
  support. Candidates include `.system.open` and `.system.searchInApp`.
  Reader/Files schemas are currently Shortcuts-only and do not guarantee
  free-form Siri questions about the archive.
- Intents use the same read-only service, bounded results, and clear errors
  for a locked device, missing sign-in, or unavailable offline content.
- Provide private content only after unlocking/required authentication.
  No automatic full-text export to Spotlight; later Spotlight indexing
  would require a separate privacy decision.

Intent authentication is set explicitly; the documented `alwaysAllowed`
default is insufficient for private archive content. An optional question
intent may invoke only the same local chat service with evidence, when
language, device, and execution context support it.
[System schemas](https://developer.apple.com/documentation/appintents/app-schema-domain-system-and-in-app-search),
[Files schema](https://developer.apple.com/documentation/appintents/app-schema-domain-files),
[Intent authentication](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)

**Acceptance:** search/open actions tested in Shortcuts and supported system
surfaces, accounting for revocation/archive changes. Document only verified
Siri features. This system access can ship separately; the working in-app
chat remains independent.
[App Intents integration](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence)

### M09 — iPhone Duo adaptation and transition testing

**Prerequisite:** M08; M04/M07 provide navigation and chat, M00 the toolchain.
**Components:** existing adaptive views, targeted SDK 27.1 additions.

- Explicitly ensure the open layout has the latest five plus chat on the left
  and reader on the right, and the closed layout has the main selection/chat
  view described in section 4.
- Check standard containers first. Account for reserved regions when custom
  controls require it; avoid parallel layout systems without a demonstrated
  need.
- Preserve app state across folding, rotation, keyboard changes, and scene
  transitions; check side system bars and asymmetric spacing. Do not tie the
  layout to a specific device model or fixed pixel widths.
- Do not require a second outer-display scene: the requested interface adapts
  within the active app scene. Camera-specific multiple-display APIs are not
  needed for this.

**Acceptance:** Device Hub matrix for open, closed, partially folded, both
orientations, Split View on either side, keyboard, and very large text.
Closing during streaming/fetching/reading shows selection plus chat and
preserves state. Final Duo approval additionally requires a real-device test;
simulator success alone is not hardware evidence.

### M10 — Overall acceptance, documentation, and staged release

**Prerequisite:** M09. **Components:** tests/CI, English and German product
documentation, iOS review information, and synthetic screenshots.

- Test reader, capture, search, AI, Intents, and Duo together. Validate
  accessibility, energy/memory behavior, and offline/authentication errors
  on devices.
- Update `ios/README.md`, root READMEs, and App Review material to match the
  shipped functionality. Review privacy text/Privacy Manifests for new local
  processing and explicit system actions; do not weaken existing legal or
  security guarantees.
- Release the reader first (M01–M04), then search/AI (M05–M07), followed by
  verified system/Duo features. Feature gates allow these stages without
  changing the archive format. An AI problem need not block the reader.
- Each stage receives checks, version/build number, and an approval record.
  Public files are explicitly allowlisted; no private archives, website,
  tokens, caches, screenshots of private content, or private history.

**Acceptance:** all evidence required for the respective stage passes;
outstanding hardware/API evidence causes that feature to be withheld. Do not
claim publication before the stage has actually shipped.

## 7. Verification plan and definition of done

| Level | Required implementation evidence |
| --- | --- |
| Swift unit tests | Paths, tolerant metadata reading, chronology, cache isolation, snapshot, limits, search coverage, citations, availability, cancellation |
| Network/security tests | Mock GitHub, rate limits, truncation, redirects, no credentials in renderer/model, no automatic third-party requests |
| Reader visual tests | Required syntax and malformed fixtures; iPhone/iPad, light/dark, Dynamic Type, VoiceOver, offline |
| UI/integration tests | Setup, selection, settings, refresh, source links, chat area, layout changes, multiwindow isolation, account changes |
| AI evaluation | DE/EN, correct citations and evidentiary support, missing results, long sources, injection, refusal, device availability |
| Duo device testing | Open/closed/partially folded, safe areas, keyboard, multitasking, streaming, and restoration |
| Regression/release | Share Extension, PDF conversion status, package boundaries, DCO, English/German documentation, and release preflight |

For changes to shared capture, scripts, or plugins, both core suites must run
from the repository root:

```sh
node --test tests/capture-utils.test.js
python3 -m unittest discover -s tests -p "test_*.py"
```

For iOS implementation changes, build without signing from `ios/`:

```sh
xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Also run XCTest with an actually installed simulator; the generic build
destination is not a test device. Record the specific destination and OS
version in the PR. The release preflight command, from the root, is
`python3 scripts/validate_ios_release.py`. If needed, set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command; for Duo,
use the 27.1 toolchain verified in M00.

Current evidence for this document: repository/API research and toolchain
version checked. **No reader, AI, or Duo implementation, simulator build,
or hardware acceptance testing has been performed.** For this documentation-
only change, links, language parity, diff, and public-content boundaries are
checked. Later checks may be marked as passed only with an actual result.

## 8. Checklist and decision points

- [ ] M00 Feasibility and concrete platform/renderer decision
- [ ] M01 Read-only GitHub access and domain contracts
- [ ] M02 Catalog, latest five, and offline cache
- [ ] M03 Formatted Markdown reader and assets
- [ ] M04 Adaptive archive interface
- [ ] M05 Local search and source retrieval
- [ ] M06 AI availability and session adapter
- [ ] M07 Archive chat and verified evidence
- [ ] M08 Verified App Intents/system actions
- [ ] M09 Duo adaptation and device tests
- [ ] M10 Overall acceptance and release materials

Still to measure or decide: native renderer or parser/WebKit (M00), final
cache/file budgets (M00/M02), demonstrated AI quality and context strategy
for each supported OS version (M06/M07), specific system schemas (M08),
additional Duo APIs and device approval (M09). All other product decisions
are set out in this plan so implementation can begin with M00 without
redesigning the architecture.

# SourceBraid: iOS implementation and local test evidence

As of October 15, 2026 · [Deutsch](IOS_IMPLEMENTATION_TESTING.de.md)

The [M00–M10 plan](IOS_READER_INTELLIGENCE_DUO_PLAN.md) was implemented in the
approved order. On October 15, 2026, the maintainer reported that the app looks
good and works, and explicitly approved publication of **1.1.0/build 11**.
Xcode Cloud distribution is tracked separately in the
[release notes](IOS_RELEASE_1.1.0.md); no successful cloud build, upload, or
App Store release is asserted here. The planned iOS-only tag is `ios-v1.1.0`.

The evidence below is chronological. Earlier entries retain their actual
1.0.1/build 10 identifiers and no-publication statements. Before the version
bump, native Duo runs passed 47 unit/integration tests, all 7 UI cases after
selector corrections, and a separate 1/1 German UI flow on the open inner
display. Earlier core checks passed 23 Node and 64 Python tests. Release
preflight checks are rerun for the version bump and recorded separately.

## Implementation and pending acceptance

| Module | Implemented / evidenced locally | Pending acceptance |
| --- | --- | --- |
| M00 | Xcode 27.1 (27A9275), SDK 27.1; native Markdown probe showed source text rather than GFM. AST renderer selected; native Quick Look for PDF. | Minimum OS 17 and native preview on physical devices. |
| M01 | GET-only GitHub reader, pinned commits/blobs, root boundaries, SHA verification, truncated-tree walk, no authenticated redirects. | Live archive and rate-limit checks. |
| M02 | UTC ordering, labeled day/filename fallback, latest seven, partial inventory, separated protected caches and eviction. | Large archives, runtime/memory/network measurements. |
| M03 | GFM, tasks/code/tables, local raster assets, relative links, escaped raw HTML, source/sharing/GitHub fallback, native PDF preview. | VoiceOver, complete format matrix, minimum OS. |
| M04 | Adaptive split navigation, direct clip opening, native Latest/Search/Chat destinations, toolbar, localized dates, keyboard and rotation. | Narrow iPad windows and real multi-scene usage. |
| M05 | SQLite FTS5/BM25, bound SQL parameters, reconciliation, bounded German/English evidence. | Large-archive search quality/rebuild. |
| M06 | Availability matrix, local system model, locale checks, OS guards, token preflight from 26.4. | Actual model/device/language states. |
| M07 | Streaming, submitted scope/snapshot, verified source IDs and referenced-version opening, cancellation/reset, bounded tools/history. | Semantic DE/EN evaluation and source-instruction resistance on real model. |
| M08 | Read-only search/recent/open intents, loaded entities, local authentication, DE/EN localization, compiled metadata. | Shortcuts/Siri, lock and cold-start device tests. |
| M09 | System columns and iOS 27.1 hinge adapter returning compact main view to selection/chat on closure. | Physical Duo transitions and full matrix. |
| M10 | Unit/integration/UI suites, synthetic demo, bilingual instructions/privacy/license notices; maintainer publication approval on October 15. | Remaining device/model/accessibility evidence and distribution results. |

The maintainer's functional acceptance and release approval do not mark every
device gate as passed. Minimum-OS launches, full fold/reopen cycles, partial
postures, Duo dark appearance, physical Duo hardware, accessibility, and real
Apple Intelligence quality remain scoped to the evidence recorded below.

## Decisions and limits

- Markdown/Git history remain authoritative. No archive format, index shards,
  capture workflows, browser scopes or plugin tools were migrated.
- `swift-markdown`/`swift-cmark` are pinned to **0.9.0**, with package resolution
  and full Apache/Swift exception, NOTICE and cmark COPYING bundled in Settings.
- Quick Look's capability flag does not establish Markdown fidelity. The
  synthetic simulator probe displayed raw headings/emphasis/table syntax.
  PDFs use native preview. Minimum-OS/native-device Markdown evidence is pending.
- An AST whitelist generates static HTML/CSS. Raw HTML is escaped; CSP/WebKit
  disable content JavaScript/network access. The app alone performs a fixed,
  JSON-escaped DOM operation to navigate source anchors.
- Frontmatter parses SourceBraid's scalar/list YAML subset. Complex/unknown
  fields remain in immutable source; provenance is not invented.
- Warm launch/foreground restores local metadata without article/inventory
  requests. Empty cache attempts at most seven bodies, initially prioritized by
  filename dates and labeled partial. Further incremental background batches
  establish complete capture-time ordering; explicit refresh can finish pending
  work. Shards are not yet used for this initial metadata read. See the
  [navigation/refresh concept](IOS_READER_REFRESH_UX.md).
- Background refresh uses `BGAppRefreshTaskRequest`, earliest after one hour;
  iOS determines execution. Bounds: 20 article attempts, 10 MiB body budget,
  32 inventory requests and 25-second cancellation timeout. Unchanged complete
  commit/index needs only a commit request; SHA-matching bodies/index are reused.
  Expiration/configuration/deletion cancel old writers. No background AI/images.
- Budgets: 5 MiB Markdown, 20 MiB assets, 250 MiB retained cache per identity,
  including SQLite near 100 MiB and catalog up to 32 MiB. Atomic writes/SQLite
  journals may temporarily require extra disk space. GitHub fallback preserves
  capture's separate 25 MB limit. Real-archive budget measurements are pending.
- Search matches terms in indexed downloads; coverage is displayed and it does
  not claim semantic or exhaustive archive coverage. Stale versions are filtered.
- AI: at most four sources/4,500 characters, each up to 1,600 characters/24
  lines, 1,200-character questions, short model history and at most ten visible
  question/answer pairs in memory. Tools read only these excerpts/recent titles,
  limited to six calls/6,000 output characters per question. No writes or network
  tool. Context failures do not produce a verified answer.
- Citation IDs verify provided excerpts, not semantic correctness; device
  evaluation remains required.
- Foundation Models from OS 26, token preflight from 26.4, hinge API from 27.1.
  Reader/search target OS 17. No Private Cloud Compute or external AI service.
  Intents expose specific actions, without promising general Siri archive chat.
- Cache file metadata is local-only. App privacy manifest declares
  `FileTimestamp`/`C617.1`; the validator requires that exact purpose for the app
  while retaining the narrower Share Extension declaration. A negative test
  rejects unreviewed purposes.

Apple documents [context preflight](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window),
[Shortcuts localization](https://developer.apple.com/videos/play/tech-talks/10168/)
and [file metadata reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
Concrete API use was also built against the installed SDK.

## Test evidence before the phone-layout follow-up

Tests and screenshots contain synthetic content only, requiring no PAT, private
archive or GitHub network. Chat integration uses an injected answer adapter and
does not establish real model quality.

| Check | Result / scope |
| --- | --- |
| Core Node capture suite | 23 passed. |
| Core Python suite | 64 passed. Existing mock tests print “Push”; no actual push occurred. |
| iOS release preflight | Passed, prior version/build identifiers unchanged; no distribution archive/upload. |
| iPad Pro 13 M5, runtime 27.0, SDK 27.1 | 32 unit/integration and 6 UI tests passed in serial runs. |
| iPhone 17, runtime 27.0, SDK 27.1 | 32 unit/integration and 6 UI tests passed in serial runs. |
| Generic iOS Simulator build, unsigned | Passed with Xcode 27.1, including app/Share Extension and validation of the built app bundle. |
| Generic iOS device build, Release, unsigned | Passed, arm64, MinimumOSVersion 17.0; built app bundle validation passed. No archive, installation or distribution. |
| Release binary | Foundation Models uses `LC_LOAD_WEAK_DYLIB`; Debug demo/probe flags are absent. This does not replace an OS 17 launch test. |

Swift tests cover capture compatibility, UTC/legacy metadata, path boundaries,
active HTML, pinned reads/SHA, truncated trees, authentication, cache isolation/
eviction/corruption, FTS update/deletion/rebuild, source IDs, availability,
question/tool limits, cancellation and archive changes. Regressions also cover
size limits for cached assets, GitHub rate limits/cancellation, and current
archive scope while a reader citation stays pinned to an older snapshot. UI
tests cover latest five, direct opening/back, source view, search/settings,
German UI, rotation, dark/large text, internal links and a native synthetic PDF.

An initial parallel iPad clone failed to launch its CoreSimulator service.
Fully booting the device and disabling test parallelism produced a passing run.
Development UI failures (Read inside the scrollable list, row hit area, menu
selector and link-test scrolling) were corrected and rechecked. Earlier failing
reports are not passing evidence. The sidebar is now aligned at the top.
The PDF test waits for rendered page text rather than its title, and PDFKit
independently confirms one readable page. On dismissal, the test waits for the
transition and uses short scroll steps so adjacent links are not skipped.
Earlier blank PDF screenshots do not count as rendering evidence.

Diagnostic artifacts stay outside the repository, including
`/private/tmp/sourcebraid-final-units-{iphone,ipad}.xcresult`,
`/private/tmp/sourcebraid-final-layout-{iphone,ipad}.xcresult`, logs and synthetic screenshots.
They are not release inputs. Final build logs are
`sourcebraid-final-build-simulator.log` and
`sourcebraid-final-build-device-release.log` in the same temporary directory.
The no-App-Intents metadata warning concerns the Share Extension; the app
generates `Metadata.appintents`. Those earlier runs used runtime 27.0 despite
SDK 27.1; they do not count as Duo or physical-device evidence.

## Earlier audit against Apple's Duo preparation workflow

The implementation already followed adaptive layout rules. The specific
workflow in [Apple's Prepare guide](https://developer.apple.com/iphone-duo/prepare/)
was first applied fully to the source during the follow-up audit on October 12:
Xcode 27.1 exported `app-resizability` through `xcrun agent skills export`, and
all five task references were reviewed. The exported skill stays locally
outside the repository.

| Step / audit area | Evidence / status |
| --- | --- |
| Prerequisites | `UILaunchScreen` present, all four iPad orientations allowed, no `UIRequiresFullScreen`. Source Info.plist, Debug/Release project settings and built plists agree; no additional `.xcconfig` files. |
| Main screen, orientation, idiom | No product layout depends on these values. System split columns and `horizontalSizeClass` determine navigation; the size class represents available space. |
| Scenes and safe areas | SwiftUI `App`/`WindowGroup` and local `scenePhase`; no manual insets or symmetry assumptions. The Share Extension's SwiftUI host fills its container; `NavigationStack`/`Form` handle content safe areas. |
| Complete file coverage | Reviewed 30 Swift files, both Info.plists and project configurations. Corrected four device-idiom assumptions, all in `ArchiveUITests.swift`: detect a visible, usable **Read** control before opening the reader, then retain that decision for Back navigation. Rotation remains a test stimulus. |
| UI recheck | After the correction, all 6 UI tests passed on each of iPhone 17 and iPad Pro 13 M5, with no failures. SDK 27.1, runtime 27.0, serial execution. Local result bundles: `/private/tmp/sourcebraid-duo-audit-{iphone,ipad}.xcresult`, with matching `.log` files. |
| Apple's step 3: resizing, October 12 audit | At that time, only runtime iOS 27.0/24A434 was installed, with no available Duo simulator. Runtime 27.1 was subsequently installed on October 15; see the later Duo test record. Extreme resizable/Mirroring windows and physical-device acceptance remain pending. |

Vertical system bars with asymmetric safe areas, extreme window heights, chat
with the keyboard and folding during a session particularly require runtime
validation. Source auditing and iPhone/iPad rotation do not replace these tests.
The [device checklist](IOS_DEVICE_ACCEPTANCE.md) explicitly records them as
acceptance items.

## Phone layout and background-refresh follow-up

The later [UI/refresh concept](IOS_READER_REFRESH_UX.md) supersedes the earlier
Read-button layout and launch-wide article sync. Native destinations give the
initial five rows the full content area; row taps open the reader directly.
A persistent root tab bar gives each destination its own stable split navigation;
models/selection/search/draft remain shared while system columns change. Dates
use locale formatting and preserve day-only UTC dates. The
chat composer uses safe-area layout and a keyboard-dismiss action without a
floating keyboard toolbar overlapping Send.

Fifteen new synthetic tests cover the refresh/cache policy, transport request
budgets, expiration-style cancellation, multi-scene deletion, protected catalog
errors and failed-persistence rollback. The UI suite adds chat input/keyboard
and draft preservation across destinations. Chat layout tests inject availability
only, require the synthetic Debug demo and never submit a model question.
English/German demo cache identities are separated so cached synthetic titles
do not leak between language runs.

The updated source audit covers 32 Swift files, both plists and project settings;
no screen-, orientation- or device-idiom-dependent product layout, manual safe
area offsets or missing modernization targets were found. The launch screen,
four iPad orientations and absence of full-screen opt-out remain verified.
Real background scheduling/expiration, locked-device cache access and Duo
resizing remain device acceptance, separate from injected/automated evidence.

Final UI corrections were verified against screenshots and accessibility trees:
the root tab bar gives each destination its own navigation context, a parent
identifier no longer overrides the chat input identifier, and compact active
search is closed before opening Settings. Wide iPad keeps ordinary toolbar
actions visible without that Close control. Tests inspect available controls
rather than assume a device type. Coverage counts the complete Markdown
inventory, including unseeded files (the regression checks 5 indexed of 31).

### Final follow-up verification

All runs below used Xcode 27.1/SDK 27.1 and serial simulator testing with
runtime iOS 27.0. The phone is the **iPhone 17 Pro Max simulator**, not the
maintainer's physical device. Only synthetic fixtures were loaded.

| Check | Result / scope |
| --- | --- |
| iPhone 17 Pro Max: full suite | 47 unit/integration tests and all 7 UI tests passed. |
| iPhone 17 Pro Max: final recheck | After the inventory-coverage and test refinements, all 47 unit/integration tests and 2 targeted UI tests passed: actual search filtering/settings and reader → chat → keyboard/draft preservation. The other 5 UI cases belong to the preceding full run. |
| iPad Pro 13 M5: final full suite | 47 unit/integration tests and all 7 UI tests passed with the final sources. |
| Core capture / Python suites | 23 Node tests and 64 Python tests passed. Mock “Push” output did not perform a Git push. |
| Required generic iOS Simulator build | Passed without signing, including app and Share Extension; built-bundle release validation passed. |
| Generic iOS device Release build | Passed without signing; built-bundle release validation passed. Version 1.0.1/build 10 remain unchanged. |
| Built bundle / Release binary | Minimum OS 17.0, refresh identifier/`fetch`, launch screen and four iPad orientations verified; no full-screen opt-out. Background capability is confined to the app. Foundation Models remains weakly linked and synthetic Debug switches are absent from Release. |

Local result bundles are `/private/tmp/sourcebraid-redesign-check-pro-max.xcresult`,
`/private/tmp/sourcebraid-redesign-verified-pro-max.xcresult` and
`/private/tmp/sourcebraid-redesign-verified-ipad.xcresult`, with matching `.log`
files. Final build logs are `/private/tmp/sourcebraid-redesign-build-simulator.log`
and `/private/tmp/sourcebraid-redesign-build-device.log`. Synthetic screenshots
were visually checked for the five-row start, native search, German dates,
chat/keyboard controls and the wide sidebar/reader arrangement. These temporary
artifacts stay outside Git; earlier failing development runs are not passing
evidence. Neither build was signed, installed, archived or uploaded.

### Latest seven and UI examples

The subsequent naming adjustment changes the initial destination to **Latest**
(German **Neueste**) and displays at most seven clips. Empty-cache bootstrap
also attempts at most seven bodies; a warm launch still makes no GitHub
request. Shortcut suggestions match the seven-item list. The model's separate
recent-title tool retains its five-title budget. Existing bootstrap/background
tests now check seven seeded/indexed files out of 31, then disjoint batches of
20 and four; warm metadata restore checks seven visible items out of eight.

The German UI run also exercises a selective offline query and a chat question
with a visible source. `SOURCEBRAID_CHAT_EXAMPLE=1` requires the synthetic
`SOURCEBRAID_DEMO=1` Debug mode and injects a fixed answer explicitly labeled
as an example with test data. It uses the real retrieval/citation/UI path,
without calling a language model or reading a private archive. Existing
keyboard tests continue to inject availability only. Example screenshots are
layout/interaction evidence, not evidence of real Apple Intelligence quality.

Verification for this adjustment: all **47 unit/integration and 7 UI tests**
passed on iPhone 17 Pro Max. On iPad Pro 13 M5, all **47 unit/integration
tests and 3 affected UI cases** passed: seven-item reader/back, German
search/chat/settings examples and keyboard/draft preservation. Runtime 27.0,
SDK 27.1, serial execution. Bundles are
`/private/tmp/sourcebraid-recent-seven-pro-max.xcresult` and
`/private/tmp/sourcebraid-recent-seven-ipad.xcresult`, with matching logs.
The exported synthetic phone screenshots were visually inspected; all seven
short fixture rows fit at the default text size. Longer titles, larger text or
smaller windows can scroll normally.

The required generic unsigned simulator build and unsigned Release device
build passed, as did validation of both built bundles. The Release binary
excludes the new example flag/adapter along with existing Debug fixtures.
Version/build identifiers remain unchanged. Build logs:
`/private/tmp/sourcebraid-recent-seven-build-simulator.log` and
`/private/tmp/sourcebraid-recent-seven-build-device.log`. No signing,
installation, archive, commit, push or upload was performed.

### Website-inspired app colors

The [appearance concept](IOS_BRAND_APPEARANCE.md) adds warm paper surfaces,
deep green text and one teal accent, with matching dark and increased-contrast
assets. Latest, Search, Chat, Settings and the Markdown reader share the palette.
Native navigation, typography, search and keyboard controls remain in place.
The composer has a secondary-ink outline, an accent focus outline and an
appearance-aware filled-action label; the unconfigured Settings action uses the
same label color. This update changes no archive, refresh or AI behavior.

Verified locally with Xcode 27.1/SDK 27.1 and runtime iOS 27.0:

| Check | Result / scope |
| --- | --- |
| iPhone 17 Pro Max simulator: full suite | All 47 unit/integration and 7 UI tests passed. |
| iPhone: final contrast corrections | Both affected UI tests passed again: German reader/settings/search/chat in light mode, plus dark mode and enlarged reader text. |
| iPad Pro 13 M5 simulator | All 47 unit/integration tests and 3 affected UI cases passed: light German examples, dark/enlarged text and chat keyboard/draft preservation. |
| Required generic simulator build | Passed without signing; built-bundle validation passed. |
| Generic device Release build | Passed without signing; built-bundle validation passed. Version 1.0.1/build 10 remain unchanged. |
| Release fixtures | Demo, chat-layout/example switches and synthetic fixture/answer-adapter markers are absent from the Release binary. |

Result bundles: `/private/tmp/sourcebraid-brand-pro-max.xcresult`,
`/private/tmp/sourcebraid-brand-final-pro-max.xcresult` and
`/private/tmp/sourcebraid-brand-ipad.xcresult`, with matching logs. Final build
logs: `/private/tmp/sourcebraid-brand-final-build-simulator.log` and
`/private/tmp/sourcebraid-brand-final-build-device.log`.

Exported synthetic screenshots were visually inspected for light/dark latest
rows, native search, reader content, settings surfaces and focused chat controls
with the keyboard. The wide iPad reader/chat arrangement and enlarged dark
reader were also inspected. Palette contrast calculations pass for normal
text/actions; actual increased-contrast system rendering, VoiceOver and physical
iPhone/Duo testing remain device acceptance. Chat answers in these examples
are explicitly labeled test data, not real model-quality evidence.

Screenshots and build/test artifacts stay outside the repository. No physical
device installation, signing, archive, commit, push or upload was performed.

### Latest spelling and integrated chat action

The German destination and Shortcut title now use **Neueste**. The composer
places Send/Stop inside the shared rounded input surface, with a separate text
region that grows to five lines. Keyboard dismissal remains a separate action
next to the focused field. Ordinary bottom padding increases from 10 to 24 points
within the existing safe-area inset; no manual safe-area offset is introduced.

All **47 unit/integration tests and 3 affected UI tests** passed on each of the
iPhone 17 Pro Max and iPad Pro 13 M5 simulators. Existing UI cases verify the
German destination, synthetic question/answer/source path, a three-line draft
retained across keyboard dismissal and tab changes, and operable Send/dismiss
controls with the keyboard in dark mode and XXXL text. Exported phone/iPad
screenshots were visually inspected for reserved text/action space, the added
gap and normal/enlarged text. These are synthetic examples, not model-quality
or physical-device evidence.

The required generic simulator build and generic device Release build passed
without signing; both built bundles passed validation. Xcode 27.1/SDK 27.1,
runtime 27.0, serial testing, version 1.0.1/build 10 unchanged. Result bundles:
`/private/tmp/sourcebraid-composer-pro-max.xcresult` and
`/private/tmp/sourcebraid-composer-ipad.xcresult`, with matching logs. Build logs:
`/private/tmp/sourcebraid-composer-build-simulator.log` and
`/private/tmp/sourcebraid-composer-build-device.log`. No commit, push, signing,
physical installation or upload was performed.

### Native iPhone Duo simulator: October 15

Installed the arm64 iOS 27.1 runtime, build `24A94232`, using Xcode 27.1
(`27A9275`). Tests used the native **iPhone Duo** destination
`8820032A-139A-41E1-A7B4-7F0AD0B47624`, serially, without signing. These
results are separate from all earlier runtime-27.0 iPhone/iPad runs.

The initial run passed all **47 unit/integration tests**, but four of seven UI
cases failed because their Back queries assumed a NavigationBar container.
The exported accessibility tree showed the system `BackButton` in a separate
vertical toolbar. Tests now require exactly one reachable control with that
observed identifier; search Close queries also avoid the old container
assumption. No product code, permissions, credentials or archive policy changed
in this follow-up. The failing initial UI run is not passing evidence.

With the corrected selectors, **all seven UI cases passed**. Observed coverage
includes seven reachable short fixture rows, formatted/raw reader and Back,
German/English search and Settings, synthetic German chat answer/source,
multiline draft retention across keyboard dismissal and tab changes, reachable
Send/dismiss controls at XXXL, internal links and rendered native PDF preview.
Screenshots were inspected: the active LCD viewport was **466 × 678 points**
(`1398 × 2034` pixels), with native vertical system bars. The fixed example
answer remains labeled test data; this does not test the real AI model.

Important limits of this native run:

- The dark/large-type test passed its interaction assertions, but the images
  remained light despite `XCUIDevice.appearance = .dark`. A separate documented
  `simctl ui … appearance dark` command succeeded and its query returned `dark`
  before and after a synthetic app launch, while the captured app remained
  light. The previous `light` setting was restored and verified. Actual Duo
  dark appearance is **pending**; neither an app nor runtime cause is established.
- The rotation case passed reader-presence assertions, but its landscape-named
  screenshot remained portrait at `1398 × 2034`. Actual rotation and preservation
  through a changed Duo viewport are **not established** by that result.
- In this initial closed-display run, a capture of the inactive second display
  was black. The unfolded follow-up below adds actual two-column evidence.
  Partly folded posture and hinge-transition preservation remain pending.
  Device Hub pose controls require manual operation; rotation/geometry are not
  substitutes for a hinge transition.
- Physical Duo, real Apple Intelligence, Share Extension interaction, minimum
  OS and the rest of the [device matrix](IOS_DEVICE_ACCEPTANCE.md) remain pending.

Evidence stays outside Git: `/private/tmp/sourcebraid-duo-20261015.xcresult`
(47 unit/integration passes; initial UI failures),
`/private/tmp/sourcebraid-duo-final-20261015.xcresult` (7 UI passes), matching
logs/attachment directories and
`/private/tmp/sourcebraid-duo-appearance-20261015.txt` with the independent
appearance observation. Attachment names that contain “dark” or “landscape”
describe requested test conditions, not verified appearance/posture.

The two affected German/English reader-search-settings flows also passed on
each of iPhone 17 Pro Max and iPad Pro 13 M5 (runtime 27.0), confirming that the
portable control queries still work with the earlier system bars. Result bundles:
`/private/tmp/sourcebraid-duo-controls-pro-max-20261015.xcresult` and
`/private/tmp/sourcebraid-duo-controls-ipad-20261015.xcresult`, with matching logs.

The required generic iOS Simulator build and built-bundle validation also
passed without signing. Build log:
`/private/tmp/sourcebraid-duo-build-simulator-20261015.log`. Version 1.0.1/build
10 are unchanged. No commits, pushes, distribution archives or uploads occurred.

### Unfolded Duo screenshots: October 15

After the maintainer manually opened Duo in Device Hub, `devicectl device info
displays` confirmed the inner `LCD-1` (display 3) active with its backlight on,
and the outer display inactive. The inner display reported `landscapeRight`
(`rot90`); native screenshots are **2853 × 2007 pixels**. This establishes the
observed open layout, not a tested rotation or complete fold cycle.

The German reader/settings/search/chat UI flow passed **1/1** on that display.
Native captures were visually inspected: all seven latest fixture rows beside
the reader, search results beside the reader with the keyboard, and chat beside
the selected article, with and without the keyboard. Contents are synthetic;
the fixed chat answer is explicitly labeled test data and does not demonstrate
real Apple Intelligence generation.

`XCUIApplication.screenshot()` produced black images while the inner display was
active. The usable pictures therefore target display 3 explicitly with
`simctl io … screenshot --display=3`. Temporary test capture synchronization
was removed and the exact prior UI-test source restored after capture. There
are no product-code changes from this screenshot follow-up.

Evidence outside Git: `/private/tmp/sourcebraid-duo-open-native-20261015.xcresult`,
its matching log, and `/private/tmp/sourcebraid-duo-open-native-20261015/` with six
native pictures, per-stage display-state JSON and a capture manifest. Delivered
copies are `duo-open-20261015-{reader,suche,chat,chat-tastatur}.png` in the local
visualizations `sourcebraid-ui` directory. Full fold/reopen transitions, partial
postures, Duo dark appearance, physical hardware and real model quality remain
pending. No commit, push or upload occurred.

### Release 1.1.0 preflight: October 15

After maintainer approval, app and Share Extension versions changed to 1.1.0,
build 11. Both unsigned builds and bundle validators passed. All 47 iOS
unit/integration and 7 UI tests passed on the open native Duo (runtime 27.1),
with the established screenshot/appearance/rotation evidence limits unchanged.
Core checks passed 23 Node, 64 Python and 33 MCP tests; MCP dry-run build and
reproducible submission-bundle checks passed. Evidence:
`/private/tmp/sourcebraid-release110-duo.xcresult` and matching log,
`/private/tmp/sourcebraid-release110-build-{simulator,device}.log`, plus matching
core/MCP logs. The planned iOS-only tag is `ios-v1.1.0`; Chrome/plugin/MCP stay
1.0.1. The existing version-policy test now permits this independent iOS release.
Xcode Cloud 27.1 RC was verified; next Cloud build number is 11. These local
results do not assert a successful Cloud archive/upload or App Store release.

### Local Intelligence diagnostics and Store assets: October 17

This working-tree update prepares a later release; the published 1.1.0/build 11
does not contain the new diagnostic UI. Availability uses Apple's public
`SystemLanguageModel` status and locale support. Guidance distinguishes
disabled Intelligence, an unready model, ineligible hardware and an unsupported
language without claiming to know download progress. Checks preserve the draft,
conversation and scope, and run again after retrieval before generation.

The generic unsigned iOS Simulator build passed, as did source and built-bundle
release validation. On the dedicated iPhone 17 Pro simulator (iOS 27.1), all
**51 unit/integration tests and 12 UI tests passed**. The latter include the
seven existing regression cases, a bilingual diagnostic/recheck/reader case,
and four explicitly opted-in screenshot cases. On iPad Pro 13-inch (M5), the
five screenshot/diagnostic UI cases also passed.
After visual review moved the recheck button and Apple help link above the
long guidance, the three affected diagnostic UI cases passed again on each
device. Both actions are asserted reachable without scrolling in both languages.

The Store workflow requires both `SOURCEBRAID_DEMO=1` and
`SOURCEBRAID_STORE_DEMO=1` in a Debug build. Seven original fictional articles
use `example.invalid` and an explicit example-archive author; no private archive,
credentials or generated model answer appears. Four native product views per
locale/device are prepared: reader, Latest, offline search and raw Markdown.
Diagnostic previews are excluded from the product upload set. Expanded
[English](IOS_APP_STORE_METADATA.md) / [German](IOS_APP_STORE_METADATA.de.md)
Store fields stay within Apple's length limits.
All 16 original product captures were inspected: iPhone **1206 × 2622** and
iPad **2064 × 2752**, RGB PNG without alpha. The recommended upload ZIP contains
**14 images**; the two iPad Latest pictures remain optional outside it because
their initial detail pane is empty. PNG hashes and ZIP integrity were verified.

Evidence outside Git:
`/private/tmp/sourcebraid-store-diagnostics-build.log`,
`/private/tmp/sourcebraid-store-diagnostics-phone-verified.xcresult`,
`/private/tmp/sourcebraid-store-diagnostics-ipad.xcresult` and matching logs.
The final diagnostic layout evidence is in
`/private/tmp/sourcebraid-diagnostics-{phone,ipad}-actions.xcresult` with matching
logs and separately delivered previews.
The screenshot capture tests are gated by the runner environment variable
`TEST_RUNNER_SOURCEBRAID_APP_STORE_CAPTURE=1` for CLI runs. Routine tests skip
them unless explicitly requested.

Simulator injection verifies presentation and request gating, not the real
iPhone's model preparation, Settings, Siri language or answer quality. Physical
iPhone 17 Pro recovery and accessibility checks remain in the device checklist.
No build/version bump, signing, App Store upload, new submission or Git push
occurred. The new default screenshots and description need the next editable
Store version because 1.1.0 is already public.

### Store draft 1.1.1 and reader fixes: October 17

After the signed-in Chrome connection became available, App Store Connect
confirmed 1.1.0/build 11 as Ready for Distribution. A separate **1.1.1 draft**
now contains the expanded English/German description, promotional text,
keywords, update notes and subtitles. All **22 native product screenshots**
were saved and verified after reloading: per language, four iPhone 17 Pro,
four iPhone Duo and three iPad pictures. The Duo images are **1398 × 2034**
RGB PNGs without alpha; its two product capture tests passed. The combined
package retains the original screenshot bytes. This supersedes the earlier
14-image preparation set above. No build was selected, submitted or released
for 1.1.1; the public 1.1.0 listing remains unchanged.
After the Recent/Zuletzt naming change, all 22 selected images were captured
again, checked as original native PNGs and replaced in all six locale/device
wells. A full reload confirmed their new asset IDs and counts. The saved
English/German descriptions and 1.1.1 notes exactly match the local text files.

The archive fix reproduces an initial refresh interrupted after one committed
article. A later launch now fills only the missing slots up to seven; an
explicit refresh downloads the remaining inventory. Recent shows loaded/total
coverage and a **Load remaining clips** action. Cancellation recovery remains
inside the coordinator's tracked job so it cannot reopen a cache after another
scene has removed local data. A deterministic test holds cancellation cleanup
and verifies that removal waits and leaves no recreated cache directory.

A separate regression reproduces the user's clarified report in the tagged
1.1.0 app: article 5 opens, but after Back, article 6 remains on the native
spinner. Synthetic lifecycle tracing shows that the forced outer reader
identity cancels the new detail task during compact navigation. Removing only
that `.id(...)` from the released code makes the full 5 → 6 → 7 → 5 sequence
pass, including distinct rendered bodies and raw source URLs. The working
implementation keeps the reader stable, keys its loading task by path/SHA and
generation, resets document-specific UI state, guards stale completions and
offers Retry after an interrupted load. Invalid UTF-8 now reports a file error
instead of being silently treated as cancellation.

The home destination is now **Recent** / **Zuletzt**. Settings no longer shows
the separate recently saved list; its unused settings-only state and refresh
hook were removed. Capture storage used by the Share Extension is unchanged.

Mermaid fences now use the pinned, bundled **Mermaid Tiny 12.2.0** engine in
an isolated WebKit content world. Page scripts remain disabled, diagram
rendering uses no remote service, and external article images retain their
per-document opt-in. Common flowchart, sequence, state, class, ER and Gantt
syntax is supported; invalid/unsupported/oversized input keeps its original
source. A ten-second watchdog and WebKit termination recovery preserve the
source-only fallback. The embedded WebView is keyed by clip path, SHA and
inventory commit. Dependency notices are retained in the app.

Final verification:

- Generic unsigned iOS Simulator build passed.
- All **58 unit/integration tests passed**, including interrupted bootstrap,
  explicit full refresh, invalid UTF-8, genuine cancellation and cross-window
  deletion/cancellation regressions.
- The real WebKit UI probe passed on **iPhone 17 Pro and iPad Pro 13-inch**:
  three visible nonempty SVGs, recovery from an invalid diagram, oversized
  source fallback, no active/media/link elements and isolated JavaScript globals.
- All **six targeted reader/navigation UI cases passed** with the final code:
  successive selections from Recent and Search, Chat draft/tab preservation,
  PDF/internal links, Mermaid/security and rotation. Another **eight UI cases**
  passed for English/German phone reader/settings/search and native product
  captures on iPhone 17 Pro, iPad Pro 13-inch and iPhone Duo. Rendering uses a
  Debug-only synthetic app probe because the unit-test target has no
  UIApplication host.
- Source/bundle validation, pinned resource integrity and `git diff --check`
  passed. No production archive, credentials or generated answer was used.

Evidence outside Git: `/private/tmp/sourcebraid-recent-reader-final-build.log`,
`/private/tmp/sourcebraid-recent-store-phone-v2.xcresult`,
`/private/tmp/sourcebraid-reader-navigation-fixed.xcresult`,
`/private/tmp/sourcebraid-recent-store-ipad.xcresult`,
`/private/tmp/sourcebraid-recent-store-duo.xcresult` and matching logs.
The earlier `/private/tmp/sourcebraid-1-1-1-mermaid-ipad.xcresult` records the
iPad WebKit probe. Controlled release evidence is retained in
`/private/tmp/sourcebraid-reader-release-repro.xcresult` and
`/private/tmp/sourcebraid-reader-release-without-outer-id.xcresult`.
These are local changes, not an installed physical-device update. Version/build,
signing and Git history remain unchanged. The reader transition failure is
reproduced separately from interrupted bootstrap and isolated by the controlled
release experiment above. The corrected behavior on the user's physical iPhone
still requires device acceptance.

## Next acceptance step

Follow the [device checklist](IOS_DEVICE_ACCEPTANCE.md) in Xcode and on iPhone,
then verify actual Duo transitions. Record pending minimum OS, model quality,
Siri/Shortcuts, accessibility and load evidence. Publication approval for 1.1.0
has been given; record cloud build and distribution outcomes separately from
these remaining tests. Check signing and use Xcode **Run** to install for
device testing; the unsigned build is not directly installable on an iPhone.

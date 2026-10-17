# SourceBraid for iOS 1.1.1

October 17, 2026 · [Deutsch](IOS_RELEASE_1.1.1.de.md)

## Release status

The maintainer has authorized pushing the current changes, publishing the
iOS-specific GitHub release **`ios-v1.1.1`**, following its Xcode Cloud build,
and submitting the matching app version for Apple's review. This record
describes the validated candidate; authorization alone does not establish a
successful cloud archive, upload, review submission or App Store publication.

The candidate is **1.1.1/build 13** for both the app and Share Extension.
Build 12 failed before compilation because its configured Xcode 27.1 RC/macOS
environment was no longer available. Build 13 is prepared for a new run with
the supported Xcode 27.1 environment; a successful cloud result remains to be
verified. **1.1.0/build 11** is the
previous, already published App Store version. Its successful cloud build
does not validate this candidate. The Chrome extension, Codex plugin and hosted
ChatGPT MCP retain their independent release versions.

## Changes

- Fix repeated article opening on a compact iPhone layout. In 1.1.0, the first
  chosen article could open, while the next selection after Back stayed on a
  spinner. The reader now keeps a stable navigation identity, starts loading
  by file path/version, resets document-specific state and rejects stale
  completions. Interrupted loads offer Retry; invalid UTF-8 produces a visible
  file error with GitHub fallback.
- Resume an interrupted initial archive download instead of leaving only its
  first completed article visible. Startup fills the missing slots up to seven
  loaded/indexed clips. Coverage shows loaded/total counts and **Load remaining
  clips** starts an explicit incremental refresh. Committed progress survives
  Stop, and recovery cannot reopen a cache being removed by another scene.
- Show practical Apple Intelligence diagnostics for disabled Intelligence,
  an unready system model, unsupported language and ineligible hardware.
  Availability is checked when entering Chat, returning to the foreground,
  before generation and on request. The draft and conversation are retained.
  Apple's setup guide explains the next steps; SourceBraid cannot force a
  system-model download or report its progress.
- Render Mermaid diagrams entirely on the device using pinned, bundled
  **Mermaid Tiny 12.2.0**. Common flowchart, sequence, state, class, ER and Gantt
  syntax is supported. Invalid, unsupported or oversized diagrams retain
  their original source, as do rendering timeouts and WebKit recovery.
  Source remains available even after a successful preview. Tiny omits
  mindmaps, architecture diagrams and KaTeX; ELK layouts use Dagre.
- Rename the main destination to **Recent** / **Zuletzt** and remove the
  obsolete **Recently saved** list from Settings. Share Extension capture
  storage remains unchanged.
- Expand the English/German App Store description and prepare **22 native
  product screenshots**: four iPhone, four iPhone Duo and three iPad pictures
  per language. These updated images and text are saved in the 1.1.1 Store
  draft and were verified after reload. All example articles are fictional;
  no private archive or generated model answer appears.

## Compatibility and privacy

Reader and search retain iOS/iPadOS 17 support. Chat additionally requires
iOS/iPadOS 26 or later, eligible hardware, enabled Apple Intelligence and a
ready system model in a supported language. The Duo hinge adapter requires
iOS 27.1. Reader and search remain available without local AI.

There are no new GitHub scopes, credential stores, archive-format changes or
remote diagram services. Mermaid executes only the app-owned offline bundle
in an isolated WebKit content world. Archived page scripts, diagram links and
embedded/external diagram media remain disabled. External article images
retain their per-document opt-in. Tokens stay in Keychain, and reader/search
use the existing protected disposable cache. The Share Extension retains its
existing capture writes. See [Privacy](../PRIVACY.md).

## Validation and distribution record

The functional candidate passed **58 unit/integration tests and 14 UI cases**
on iOS 27.1 simulators. The generic unsigned iOS Simulator build passed, as did
source/bundle validation, pinned resource integrity and `git diff --check`.
The UI evidence includes successive article selections, distinct rendered/raw
bodies, Recent/Search navigation, Chat draft preservation, reader links/PDFs,
English/German settings and Store captures. The real WebKit Mermaid probe
passed on iPhone 17 Pro and iPad Pro 13-inch; product capture also passed on
the native iPhone Duo simulator. The controlled 1.1.0 experiment reproduces
the first-open-only failure and isolates the outer reader identity as its
cause. The [test record](IOS_IMPLEMENTATION_TESTING.md) contains exact scope
and local evidence paths.

These checks validate the functional patch before distribution. The exact
versioned release bundle, signing, new Xcode Cloud archive, upload, App Store
processing and review submission must each be verified from their own results.
At preparation of this record, no new cloud-build success or review acceptance
is asserted. The successful historical build **11** remains separate.

Physical iPhone acceptance of the corrected navigation, actual Apple
Intelligence preparation/answer quality, minimum-OS launches, physical Duo
fold transitions and the remaining accessibility matrix are still documented
in the [device checklist](IOS_DEVICE_ACCEPTANCE.md). Simulator and release
authorization do not mark those checks as passed.

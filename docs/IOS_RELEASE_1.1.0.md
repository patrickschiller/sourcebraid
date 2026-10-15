# SourceBraid for iOS 1.1.0

October 15, 2026 · [Deutsch](IOS_RELEASE_1.1.0.de.md)

## Publication update — October 15, 2026

The maintainer has confirmed that iOS **1.1.0** is published in the App Store.
Chrome, the local Codex plugin, and hosted ChatGPT MCP are now being prepared
as **1.1.0** release packages. Their store/directory review and publication remain
separate; the hosted MCP service still requires deployment and live testing.

The pre-publication record below preserves the versions and results actually
checked at that time, including the separate **1.0.1** submission bundle.
Publication does not close the outstanding device and model-quality checks.

## Pre-publication status

The maintainer approved this release candidate for publication after a
hands-on functional check. App and Share Extension use **1.1.0/build 11**.
The planned GitHub tag is **`ios-v1.1.0`**, scoped to iOS. Chrome, the Codex
plugin, and hosted MCP remain at 1.0.1.

## Changes

- **Latest** opens with seven recent clips, localized dates, and a refreshed
  SourceBraid palette. Native Search and Chat destinations and toolbar actions
  adapt to phone, iPad, and the wider Duo display.
- A local Markdown reader renders headings, tables, tasks, code, local images,
  and archive links. PDF attachments open in native Quick Look. Raw Markdown,
  sharing, and GitHub fallback remain available.
- Cached clips and full-text search work offline. Warm starts restore the
  local catalog without downloading all articles. Empty caches try at most
  seven article bodies; bounded background batches and manual refresh update
  changed content. Initial metadata and search coverage can be partial, and
  iOS determines background execution time.
- Optional Apple Intelligence chat answers questions about a selected clip or
  indexed archive excerpts, with source links, streaming, and cancellation.
  The input contains the send button and has more space above the tab bar.
- Read-only App Shortcuts search, list recent clips, and open a loaded clip.
  Settings now describe shared URL content from any app.

## Compatibility and privacy

Reader and search target iOS/iPadOS 17 or later. Chat additionally requires
iOS/iPadOS 26 or later, supported hardware, enabled Apple Intelligence, and an
available system model in a supported language. The Duo hinge adapter requires
iOS 27.1. Unsupported AI states retain reader and search.

Archive reads use authenticated GET requests to GitHub; credentials remain in
the shared Keychain. Downloads and the disposable search index use a protected,
backup-excluded local cache. Chat uses Apple's on-device model, with bounded
excerpts and in-memory history; no external AI service or Private Cloud Compute
is called. External images load only after an explicit choice. Reader, search,
chat, and shortcuts do not change GitHub files; the Share Extension retains its
existing capture writes. See [Privacy](../PRIVACY.md) for the complete data flow.

## Validation and distribution status

After the version bump, the native open Duo passed **47 unit/integration tests
and all 7 UI cases** on runtime 27.1. The required unsigned simulator build and
unsigned Release device build passed, and both packaged bundles passed the iOS
release validator at **1.1.0/build 11**. Debug demo/example markers are absent
from the Release binary. Core checks passed **23 Node**, **64 Python**, and
**33 ChatGPT MCP** tests; the MCP deployment dry run and reproducible submission
bundle checks passed without deployment. That separate bundle stays at 1.0.1.

Local evidence is outside Git: `/private/tmp/sourcebraid-release110-duo.xcresult`
and matching log, `/private/tmp/sourcebraid-release110-build-simulator.log`,
`/private/tmp/sourcebraid-release110-build-device.log`, and the matching core/MCP
logs. Synthetic screenshot and model-quality limits remain as recorded in the
[test record](IOS_IMPLEMENTATION_TESTING.md).

The Xcode Cloud workflow was verified at **Xcode 27.1 RC (27A9275)**, with an
automatic trigger for `ios` changes on `main`. Its next build number was set to
**11**. Cloud archive, upload and App Store processing are tracked separately
from this local preflight; this document does not assert their success. The
iOS-specific tag keeps the separate `v*` submission-bundle version policy intact.

Minimum-OS launches, complete Duo fold/reopen cycles and partial postures,
Duo dark appearance, physical Duo hardware, real model quality, and the rest of
the accessibility/device matrix retain their documented open status. The
maintainer's functional check does not establish every matrix condition.
See the [test record](IOS_IMPLEMENTATION_TESTING.md) and
[device checklist](IOS_DEVICE_ACCEPTANCE.md).

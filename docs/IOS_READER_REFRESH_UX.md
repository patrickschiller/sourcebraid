# SourceBraid: reader navigation and background refresh

October 12, 2026 · [Deutsch](IOS_READER_REFRESH_UX.de.md)

This local follow-up replaces the cramped phone layout and the automatic full
article download on every launch. It extends the approved
[reader plan](IOS_READER_INTELLIGENCE_DUO_PLAN.md). Device acceptance and release
approval remain pending; no commit, push or upload is authorized.

## Navigation and appearance

The [app brand-color concept](IOS_BRAND_APPEARANCE.md) defines the restrained
paper/green palette inspired by the SourceBraid website.

The initial destination is **Recent** and shows the latest seven clips. Its
native grouped list fills the available content area. A row opens its document
directly; the system Back
control returns to the list. Dates use the current locale rather than raw ISO
timestamps; day-only capture dates retain their UTC calendar day.

On OS 18 and later, a system tab bar separates **Recent**, **Search**, and
**Chat**. OS 17 uses the corresponding bottom toolbar actions. The upper
toolbar contains Refresh/Stop and a More menu for Settings, local-data removal,
and sign-out. Reader actions remain in the reader toolbar, including an action
to ask about the selected clip. Chat has its own scrollable content and a
multiline composer above the safe area/keyboard; it no longer consumes most of
the initial list's space. An unavailable model shows its status in the Chat
destination while the reader remains usable.

Send/Stop sits on the right inside the composer's shared rounded input surface.
The text has its own reserved area so it cannot overlap the action. While the
field is focused, keyboard dismissal remains a separate action beside it.
Regular padding inside the safe-area inset adds space above the lower system
bar without manual safe-area offsets.

The root tab bar gives each destination a persistent `NavigationSplitView` for
wide and compact windows. On wide
layouts, the chosen list/search/chat destination appears on the left and the
reader on the right. Closing Duo selects the main sidebar destination through
the existing hinge adapter. Selection, search query/results, chat draft/history,
and models belong to the persistent root. Layout uses available space and safe
areas, without screen dimensions, device-idiom decisions or fixed list/chat
heights. Real Duo folding, extreme heights and vertical system bars still need
the [device checklist](IOS_DEVICE_ACCEPTANCE.md).

The design follows Apple's [toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars)
and [tab-bar guidance](https://developer.apple.com/design/human-interface-guidelines/tab-bars):
system appearance, identifiable destinations, SF Symbols, a limited set of
frequent actions and additional actions in More. Xcode's `swiftui-specialist`
and `app-resizability` skills informed the source review; exported skills stay
outside this repository.

## Launch and update policy

| Trigger | Work |
| --- | --- |
| Warm launch / foreground after a completed initial seed | Restore the protected local metadata catalog and index coverage. No automatic GitHub inventory or article request. |
| Empty local cache | Read a pinned, request-bounded inventory and attempt at most seven Markdown bodies. Show partial coverage. |
| Interrupted initial seed | Restore committed clips, recheck the bounded inventory and resume only the missing slots up to seven loaded/indexed clips. |
| Scheduled background refresh | Check the latest commit, reconcile inventory changes and process a bounded batch of missing/changed bodies or index rows. |
| Pull to refresh / toolbar Refresh | Run an explicit incremental refresh; finish pending articles within existing per-file/cache limits. Stop remains available. |
| Open a missing document | Download that document on demand and add its current-version metadata/search row. |

For a completely empty archive cache, body metadata is not yet known. The first
seven candidates are prioritized using available filename dates and deterministic
fallbacks. The UI labels this as partial. Further batches establish the actual
capture-time ordering; the app cannot claim the definitive newest seven before
reading the necessary metadata. Previously cached full metadata can show the
correct newest seven immediately.

The next update also recovers a partially saved initial seed. Previously, a
snapshot saved before a launch interruption could suppress all later startup
downloads even if only one clip had finished. The resume check now counts
loaded/indexed clips as well as the inventory; completed clips are reused.
Stopping or cancelling a refresh restores its atomically committed progress in
the visible library. The startup still stops at seven total clips, and explicit
Refresh remains the way to complete the rest of a large archive. These fixes do
not change the archive format, permissions or cache budgets.
The Recent footer shows the loaded count against the full inventory while
coverage is partial. **Load remaining clips** starts the explicit incremental
refresh directly from that footer, with the existing progress and Stop action.

The catalog records the pinned commit and each file's SHA. A complete,
unchanged inventory/index requires only the commit request during a refresh.
Unchanged bodies and existing matching search rows are reused. New/changed
files are read; deleted paths leave the catalog and search index. Opening an
older citation keeps its pinned version and does not replace current metadata.
GitHub Markdown and history remain authoritative; the local index is disposable.
Search/chat coverage uses the inventory's full Markdown count, including files
not downloaded yet, so a seven-file seed cannot imply complete archive coverage.

## Background job and bounds

The app registers `de.patrickschiller.sourcebraid.archive.refresh` through
`BGTaskScheduler` and declares `fetch` in `UIBackgroundModes`. An eligible,
configured app submits a `BGAppRefreshTaskRequest` when entering background
and after a job. Its earliest start is one hour later. **iOS chooses whether
and when it runs; this is not an hourly timer.** Disabled Background App
Refresh, force-quitting, energy/network conditions and system limits can defer
updates. Explicit refresh and cached reading remain available.

Each scheduled batch has a maximum of 20 article attempts, 10 MiB of body
budget, and 32 inventory requests, plus the existing 5 MiB per-Markdown limit.
Declared/reserved bytes count even for failed reads; unknown sizes reserve the
available per-file allowance. A 25-second internal timeout and the OS expiration
handler cancel work. Another request continues pending work later. No model
generation or external-image loading runs in this background job.
If a large inventory needs more traversal requests than the batch permits,
the job retains the previous catalog; explicit refresh can complete that walk.
It does not save a truncated inventory as a complete one.

A shared coordinator serializes refresh/cache writes across app scenes and
on-demand reads. Local-data removal and configuration changes cancel and await
old writers before clearing data. Sign-out cancels scheduled work; configuration
save re-enables scheduling. Atomic catalog failures roll back in-memory state;
an unreadable/protected catalog is never treated as an empty archive and
overwritten. App launch/foreground reopens the catalog to pick up a completed
background batch.

Only authenticated GET requests to the existing `api.github.com` endpoint are
added at background times. No new GitHub scope, archive format, AI endpoint,
credential storage or capture behavior is introduced. Keychain and existing
cache file protection still apply. See [PRIVACY.md](../PRIVACY.md).

Apple's [Background Tasks documentation](https://developer.apple.com/documentation/backgroundtasks)
describes the system scheduling and expiration contract; API use is also
compiled against the installed SDK.

## Verification and acceptance

Synthetic regression tests check warm launches without network calls, the
seven-body seed, unchanged commits, SHA changes/deletions, bounded batches and
failed reads, on-demand indexing, cancellation, another scene's deletion,
configuration changes, protected catalogs and persistence rollback. UI tests
check the native destinations, latest-seven visibility, localized dates, reader
navigation, search, keyboard/draft preservation, rotation and existing PDF/raw
Markdown behavior. Results belong in the
[test record](IOS_IMPLEMENTATION_TESTING.md).

On a physical iPhone, measure cached relaunches and real GitHub request counts;
test disabled Background App Refresh, Low Power Mode, lock/unlock, connection
loss, token revocation, background expiration and sign-out during refresh.
Record actual scheduler execution rather than assuming the earliest date is a
guarantee. Repeat compact/wide transitions and keyboard tests on Duo. These
device checks, OS 17 launch and actual model quality remain open.

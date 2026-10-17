# iOS App Store metadata and screenshots

Prepared October 17, 2026 · [Deutsch](IOS_APP_STORE_METADATA.de.md)

The editing target is the **1.1.1 draft** in App Store Connect. Its English and
German promotional text, description, keywords, subtitles and initial diagnostic
update notes have been saved. **22 new native screenshots** are confirmed saved:
four iPhone, three iPad and four iPhone Duo images per localization. The previous
iPad screenshot was removed from this draft's selection and remains in the asset
library. No build is selected; the draft has not been submitted or released.

The revised descriptions and 1.1.1 update notes below also cover the subsequent
archive-loading fix and local Mermaid rendering. These latest text revisions
are saved in both localizations and were verified after a full page reload and
locale switch against the exported text files. All six screenshot wells retained
the expected filenames and counts; both localized subtitles were saved in App
Information. Implementation tests and physical-device acceptance remain in
progress; the copy does not establish that these changes have shipped.

The [German App Store listing](https://apps.apple.com/de/app/sourcebraid/id6798551232)
remains publicly available as **1.1.0**, verified on October 17, 2026, with a
release timestamp of **07:14:07 UTC**. Its live screenshots and release are
unchanged by preparation of the 1.1.1 draft.

## Copy-ready English (U.S.) fields

### App name

```text
SourceBraid
```

### Subtitle — maximum 30 characters

```text
Save, read and search sources
```

### Promotional text — maximum 170 characters

```text
Turn shared pages into Markdown in your GitHub archive. Read downloaded clips, search their text, and ask questions with optional on-device Apple Intelligence.
```

### Description — maximum 4,000 characters

```text
SourceBraid — Weave the web into Markdown.

Save useful sources, find them again, and keep the files in a GitHub repository you control. SourceBraid brings capture, a Markdown reader, local search, and optional on-device chat to your iPhone and iPad.

SAVE FROM THE SHARE MENU
Share a web page, selected text, a PDF, or another file to SourceBraid. Adjust the title, add tags or a note, and save it to your configured repository. Readable public pages become Markdown with source metadata and relevant images. Pages that cannot be extracted are clearly saved as links. Shared PDFs can be converted by the optional Docling GitHub Actions workflow in your repository.

RETURN TO YOUR LATEST SOURCES
The Recent view puts seven recent clips within reach. Open a source directly, refresh your archive, or switch to Search and Chat. Wider layouts place your list and reader side by side.

READ MARKDOWN COMFORTABLY
Read headings, lists, tasks, tables, quotes, code, and local images. Open PDF attachments in the native preview, inspect the raw Markdown, share a clip, or follow its original source. External images load only when you choose to load them for that document. Common Mermaid flowcharts and sequence, state, class, ER, and Gantt diagrams render locally; unsupported or invalid diagrams retain their original source text.

FIND TEXT YOU HAVE DOWNLOADED
Full-text search runs on your device and shows how much of your archive is indexed. Downloaded clips can be read and searched offline while your repository remains configured. Search covers cached, indexed text; it may not yet include every file in a large archive. Refresh fills gaps, and iOS may remove cached files to reclaim storage. Background updates run when iOS allows them.

ASK YOUR SOURCES ON DEVICE
On compatible devices, ask about a selected clip or relevant excerpts from the indexed archive. Answers stream into the conversation and include links to the source excerpts supplied to the model. You can stop an answer at any time.

Chat requires iOS or iPadOS 26 or later, an eligible device, enabled Apple Intelligence, a ready downloaded system model, and a supported language. It works with limited excerpts rather than every word of every document. AI answers can be wrong; source links help you check them. Reader and search remain available when chat is unavailable. SourceBraid does not send chat questions to a cloud AI service or use a cloud fallback.

YOUR ARCHIVE, YOUR FILES
Markdown files and Git history stay in the GitHub repository you choose. The app stores the GitHub token in Keychain and maintains a disposable local reading and search cache. Reading, searching, chat, and read-only App Shortcuts do not change your archive. Saving through the Share Extension writes the captures you choose.

SourceBraid includes no ads, tracking, or analytics. Capture and archive refresh contact GitHub and the source websites involved; those services have their own privacy policies. No separate AI account is required for on-device chat.

GET STARTED
Use a GitHub account and configure a repository with a fine-grained access token. Read access is sufficient for the reader; saving captures also needs repository contents write access. Reader and search support iOS and iPadOS 17 or later.
```

### Keywords — maximum 100 bytes

```text
markdown,webclipper,reader,notes,research,archive,pdf,offline,search,bookmarks
```

### What's New — iOS 1.1.0 facts, maximum 4,000 characters

Use this only for the 1.1.0 feature description or historical release copy.
For a later bug-fix update, describe the changes in that update instead.

```text
SourceBraid now helps you use the sources you save:

• Latest opens with seven recent clips and direct access to the reader.
• Read Markdown with tables, tasks, code, local images, and archive links. Preview PDF attachments and share clips.
• Search downloaded text on your device, with visible index coverage. Read and search cached clips offline.
• Ask questions about a selected clip or indexed archive excerpts with optional Apple Intelligence chat, streaming answers, cancellation, and source links.
• Use read-only App Shortcuts to find sources, list recent clips, and open a loaded clip.
• Enjoy adaptive phone and iPad layouts, refreshed colors, and bounded background archive refresh.

Local chat requires iOS or iPadOS 26 or later, an eligible device, enabled Apple Intelligence, a ready system model, and a supported language. Search and chat cover downloaded, indexed material; source links do not guarantee an AI answer is correct.
```

### What's New — 1.1.1 draft, not yet released

Use this draft only with a 1.1.1 build containing these changes, after its tests
and device checks pass. The 1.1.0 historical copy above remains unchanged.

```text
This update improves archive loading, reading, and local chat:

• Fixes a reader that could stay loading after you returned to the list and opened another clip.
• Interrupted initial archive downloads resume when you return. A loaded-clip count and an action to load remaining clips make the local archive state clearer.
• Common Mermaid flowcharts and sequence, state, class, ER, and Gantt diagrams render on your device. Unsupported or invalid diagrams keep their original source text.
• Local chat explains Apple Intelligence availability more clearly, offers relevant recovery steps, and lets you check again after changing system settings. Reading and search remain available.
• The home tab is now called Recent. Settings no longer repeats a list of recently saved items.

Apple Intelligence still requires a compatible device, supported language, enabled settings, and a ready system model. SourceBraid cannot force its download.
```

Do not promise a download progress bar, a forced model download, or a system
setting change unless the released implementation can actually provide it.

## Native screenshot set saved in the 1.1.1 draft

The combined upload ZIP contains **22 native images** in English and German:
four per **iPhone 17 Pro** localization at **1206 × 2622**, three per **iPad Pro
13-inch (M5)** localization at **2064 × 2752**, and four per **iPhone Duo**
localization at **1398 × 2034**. These exact counts have been confirmed in
App Store Connect. Upload and save do not mean Apple approval or public release.

The two iPad Recent captures remain optional candidates outside the ZIP because
their initial detail pane leaves a large empty area. Each image shows the
running app with original fictional archive content. Pixel dimensions, capture
and visual checks are recorded in the delivered `CAPTURE_README.md`,
`IPHONE_DUO_README.md` and combined manifest. See also the
[implementation test record](IOS_IMPLEMENTATION_TESTING.md).

The recommended images explain useful functionality without requiring an available
AI model. Keep the warm SourceBraid background, dark text, and teal accent.
The captions below are accompanying copy suggestions, not claims that text
has been added to the native images. Leave the app readable at thumbnail size.

| Order | Caption | Recommended devices | Native screen and evidence |
| --- | --- | --- | --- |
| 1 | Read what you saved | iPhone, iPhone Duo and iPad | Markdown reader showing “Reading notes that last”, its fictional author label, headings, and a readable article. The iPad set also demonstrates the native wider layout. |
| 2 | Your latest sources, within reach | iPhone and iPhone Duo | Recent with seven varied original example articles. The captured iPad variant is optional and excluded from the recommended ZIP. |
| 3 | Find it in downloaded text | iPhone, iPhone Duo and iPad | Offline Search with a meaningful query and the app's actual coverage display. This depicts cached search, not complete archive synchronization. |
| 4 | Your files stay Markdown | iPhone, iPhone Duo and iPad | The reader's raw Markdown view, preserving the portable source text and clearly fictional metadata. |

### Later optional captures — outside the recommended upload set

- **Save from the Share menu:** capture the Share Extension with title, tags,
  and a note before saving, using synthetic input and a test repository.
- **Ask your sources, on device:** use a real answer with source buttons on a
  device with an available model. Add the qualifier “Requires compatible Apple
  Intelligence.” The recommended upload set contains no AI-answer screenshot.
  A demo answer must remain visibly labeled “Example answer with test data”
  and is not evidence of model output.
- **Know when local AI is ready:** capture the new diagnostic UI only after
  it exists in the version being submitted. Show useful recovery steps without
  inventing download progress or marking unchecked conditions as passed.

Never replace an unavailable-model screen with a fabricated successful answer.
Do not use the user's attached photo as a promotional screenshot. Diagnostic
screens belong to the next update, not a retrospective claim about 1.1.0.

### Safe screenshot data

The prepared captures use the original fictional Markdown in
`ArchiveDemoReader.storeDocuments()` with the explicit Debug opt-ins
`SOURCEBRAID_DEMO=1` and `SOURCEBRAID_STORE_DEMO=1`. This adapter uses no
network, credentials, private archive content, or model output. Its fixture
URLs use `example.invalid`, and its author label says “SourceBraid example
archive”. The seven actual fixture titles are:

- A balcony garden
- A notebook for the weekend
- Interfaces with room to breathe
- Beyond the bookmark
- Small tools, lasting value
- A personal reference library
- Reading notes that last

These are invented examples, not captured publications. Do not attach real
authors, publication dates, or source domains to them. No `web-clips/` data,
tokens, account identifiers, review credentials, or private repository names
may appear. A clean 09:41 status bar is appropriate; do not alter the app's
feature state to create unsupported claims.

### Export and review

Check the prepared native PNG or JPEG files against the device wells shown by App Store
Connect, using [Apple's current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
Do not upscale an unrelated device image into an asserted native device
capture. Upload 1–10 screenshots per supported device set and localization;
check order, crops, legibility, and localized captions in Media Manager. The
same UI on smaller devices can use Apple's supported scaling. The 22-image
set has been uploaded and saved in draft 1.1.1; it still requires a matching
build and review. This document does not assert that the new images are live.

## App Store Connect editability

Checked against Apple's documentation on October 17, 2026:

- [Version-localization documentation](https://developer.apple.com/documentation/appstoreconnectapi/app-store-version-localizations)
  says promotional text can be updated at any time; other version-localization
  attributes require an editable app state.
- [The current Asset Library guide](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets)
  lists screenshot/previews upload states: Prepare for Submission, Invalid
  Binary, Rejected, Metadata Rejected, and Developer Rejected. Its live-version
  exception concerns approved Header/Search Results creative assets, which are
  separate from screenshots and previews.
- [App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses)
  explicitly says that Waiting for Review does not allow uploading or editing
  screenshots/previews. In Review and Ready for Distribution are not among
  the screenshot-upload states above. Do not withdraw an existing submission
  simply to change marketing.

Since 1.1.0 is publicly available, the new default screenshots, description,
subtitle and keywords are being edited in draft **1.1.1** on the same app record.
The 22 screenshots and latest patch copy above are saved and were verified after
a full page reload and locale switch. [Creating a new version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version)
copies the current metadata into the new version. No build is selected and no
submission or release has been triggered. A new matching build and completed
checks are still required. Agreements, release settings and access rights have
not been changed.

## Claim checks

The 1.1.1 copy is conditional on completion and validation of the corresponding
archive-loading, local Mermaid and Intelligence diagnostic changes. It claims
common Mermaid types only; unsupported syntax and render errors retain source
text. It promises neither a model download progress bar nor a forced download.

The copy follows the implementation in `ios/SourceBraid/Archive/`,
`ios/SourceBraidShare/`, [the iOS README](../ios/README.md),
[the 1.1.0 release record](IOS_RELEASE_1.1.0.md), and
[the privacy notice](../PRIVACY.md). It intentionally does not claim complete
archive synchronization, guaranteed offline retention, unconditional local AI
availability, factual accuracy of generated answers, or a hosted AI fallback.
The separate Chrome extension, Codex plugin, and ChatGPT service are not iOS
in-app features and are not presented as included services here.

# Chrome Web Store listing

This file is the reviewed source of truth for the SourceBraid Chrome Web Store
listing. Do not describe the extension as published until the dashboard shows a
live listing.

## Default listing (English)

- Name: `SourceBraid`
- Category: `Productivity`
- Language: `English`
- Short description: `Save articles, papers, wikis, Gists, and PDFs as clean Markdown in your private GitHub repository.`
- Homepage: `https://sourcebraid.com`
- Support: `https://github.com/patrickschiller/sourcebraid/issues`
- Privacy policy: `https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md`

### Detailed description

SourceBraid turns useful web sources into portable Markdown that stays under
your control. Capture articles, research papers, wiki pages, GitHub Gists, and
PDF documents from the active tab, add tags or notes, and save the result
directly to a private GitHub repository you configure.

SourceBraid preserves source URLs and metadata in YAML frontmatter, keeps
relevant images beside the Markdown, and records every change in normal Git
history. PDFs can be converted to structured Markdown by the included GitHub
Actions workflow. A local download fallback is available for non-PDF pages.

The Chrome extension sends captures directly to GitHub, without passing them
through a SourceBraid server, and does not collect analytics. It
reads a page only after you start a capture. Captured material goes directly to
your configured GitHub repository; credentials are stored in Chrome local storage.
Credentials are sent only to their configured service endpoints. Optional Ghost
and Blogger source APIs are contacted only when you configure them. SourceBraid
is open source under the MIT License. The optional ChatGPT connection is a
separate opt-in service with its own consent screen; it is not needed for Chrome capture.

A GitHub account, a private repository and a fine-grained token with
Contents: Read and write are required for GitHub saving. The extension UI is
currently English. Capture only material you are authorized to save.

## German localization

- Name: `SourceBraid`
- Category: `Produktivität`
- Short description: `Speichere Artikel, Papers, Wikis, Gists und PDFs als sauberes Markdown in deinem privaten GitHub-Repository.`

### Ausführliche Beschreibung

SourceBraid verwandelt nützliche Webquellen in portables Markdown, das unter
deiner Kontrolle bleibt. Erfasse Artikel, wissenschaftliche Papers,
Wiki-Seiten, GitHub Gists und PDF-Dokumente aus dem aktiven Tab, ergänze Tags
oder Notizen und speichere das Ergebnis direkt in einem von dir konfigurierten
privaten GitHub-Repository.

SourceBraid bewahrt Quell-URLs und Metadaten im YAML-Frontmatter, legt relevante
Bilder neben dem Markdown ab und hält jede Änderung in der normalen
Git-Historie fest. PDFs lassen sich über den mitgelieferten GitHub-Actions-
Workflow in strukturiertes Markdown umwandeln. Für Nicht-PDF-Seiten gibt es
einen lokalen Download-Fallback.

Die Chrome-Erweiterung sendet Erfassungen direkt an GitHub, ohne einen
SourceBraid-Server dazwischenzuschalten, und erhebt keine Analysedaten. Sie
liest eine Seite erst, nachdem du eine Erfassung startest. Erfasste
Inhalte gehen direkt an dein konfiguriertes GitHub-Repository; Zugangsdaten
werden im lokalen Chrome-Speicher abgelegt und nur an den jeweils konfigurierten
Dienst gesendet. Optionale Ghost- und Blogger-APIs werden nur kontaktiert, wenn
du sie konfigurierst. SourceBraid ist Open Source unter der MIT-Lizenz. Die
optionale ChatGPT-Anbindung ist ein separat aktivierter Dienst mit eigener
Zustimmungsseite; für Chrome-Erfassungen wird sie nicht benötigt.

Zum Speichern in GitHub brauchst du ein GitHub-Konto, ein privates Repository
und einen Fine-grained Token mit Contents: Read and write. Die Oberfläche
der Erweiterung ist derzeit Englisch. Erfasse nur Inhalte, die du speichern darfst.

## Single purpose

SourceBraid captures the web page or PDF explicitly selected by the user,
converts it to portable Markdown, and stores it in the user's own GitHub
repository or as a local fallback download.

## Permission justifications

| Permission | Justification |
| --- | --- |
| `activeTab` | Access the currently selected tab only after the user chooses Save or Download. |
| `scripting` | Inject the bundled capture code into that active tab when it is not already available. No remote code is used. |
| `storage` | Store repository settings, locally held credentials, optional API settings, and the accepted disclosure version. |
| `http://*/*`, `https://*/*` | Capture user-selected web sources, fetch their relevant assets or structured source APIs, and communicate directly with GitHub. |
| `file:///*` | Capture local PDF files only when the user separately enables Chrome's **Allow access to file URLs** setting. |

## Privacy questionnaire notes

SourceBraid handles website content, page URLs, user-entered notes and tags,
authentication information, and optional source-API credentials solely to
provide its capture and archive functionality. Page content and metadata are
sent directly to the GitHub repository selected by the user. The GitHub token
is sent only to GitHub API endpoints; optional source credentials are sent only
to their configured service endpoints. Credentials are not included in plugin
configuration exports.

The extension data is not sold, used for advertising or creditworthiness, transferred to
a SourceBraid server, or used for purposes unrelated to the extension's
single purpose. SourceBraid does not load remote executable code.

Declare **Website content**, **Web history** (only URLs of requested captures,
not background history monitoring), **Authentication information** (tokens),
and **Personally identifiable information** (configured GitHub account name).
These disclosures apply even when values remain in local Chrome storage.
Do not select “no user data”: the extension handles this information to provide
the requested archive functionality. It does not independently gather location,
financial, health, communications, or behavioral analytics data.

Remote code answer: **No**. Capture scripts ship inside the extension. Bundled
Python files are copied to the user's repository for its GitHub Actions PDF
workflow; no Python or downloaded JavaScript executes inside Chrome.

## Reviewer instructions

1. Create a dedicated private review repository with an initial commit. Use
   only the synthetic fixture from `scripts/build_review_fixture.py`. Prepare
   a fine-grained token restricted to that repository with Contents: Read and
   write; add Workflows: Read and write only for testing first-time PDF setup.
   Keep the repository and token available throughout review. Put their actual
   values only in the protected **Test instructions** dashboard fields.
2. Open SourceBraid's settings (gear icon). Enter the supplied repository owner,
   repository name, branch `main`, root folder `web-clips`, and review token.
   Leave Ghost and Blogger settings empty. Click **Save Settings**.
3. Open `https://example.com/`, select SourceBraid, read the first-capture
   disclosure, select its consent checkbox, add a synthetic note, and choose
   **Save to GitHub**.
4. Confirm a Markdown file appears below `web-clips/YYYY/MM/` in the test
   repository and that the source URL is preserved in its frontmatter.
5. Choose **Download Fallback** on a normal HTML page and confirm a local `.md`
   download.
6. Choose **Export Plugin Config** and confirm the JSON contains repository
   coordinates but no token or optional API keys.
7. For PDF testing, open a small redistributable PDF below the 25 MB limit,
   choose **Save to GitHub**, and verify that GitHub Actions replaces the pending
   Markdown after conversion. Actions must be enabled and allowed to write to
   the review repository. PDF download fallback is intentionally unavailable.

Expected failure cases: no consent must prevent capture; a missing or
inaccessible repository must show an actionable error; a root containing `..`
must be rejected; a non-HTTPS Ghost API endpoint must be rejected. These
failures must not upload page contents.

For a reviewer who only needs the local fallback, no GitHub credentials are
required: accept the disclosure and choose **Download Fallback** on an HTML page.

## Assets

- Screenshots: `store-assets/sourcebraid-chrome-capture-1280x800.png` and
  `store-assets/sourcebraid-private-archive-1280x800.png`
- Small promotional tile: `store-assets/sourcebraid-promo-440x280.png`
- Extension icon: `sourcebraid/icons/icon-128.png`

All screenshots use synthetic demo data. Their reproducible source is under
`store-assets/source/`. The capture screenshot embeds the real extension popup;
the archive view uses the real Markdown and path builders.

## Submission sequence

Build `dist/sourcebraid-chrome-v1.0.1.zip` through `python3 scripts/build_chrome_package.py`
or the full `python3 scripts/build_release.py` command. Upload that ZIP to the
[Chrome Developer Dashboard](https://chrome.google.com/webstore/devconsole).
Complete the listing, privacy practices and protected test instructions above;
upload the three supplied images and 128 px icon. English and German listing
descriptions are enabled by the package's `_locales/en` and `_locales/de` metadata.

The publisher must complete account verification and any required trader and
distribution declarations with their own legal details. Select **Public**
visibility when ready for discovery. Submit for review with deferred publishing
so Chrome and ChatGPT launch timing can be coordinated after approval. No live
store URL or approval is implied by building this kit.

Veröffentlichung: Das ZIP im Chrome Developer Dashboard hochladen, englische und
deutsche Beschreibung sowie Bilder eintragen, Datenschutzhinweise übernehmen
und echte Testzugangsdaten nur im geschützten Testbereich hinterlegen.
Kontoverifizierung, Händlerangaben und Länderwahl müssen den tatsächlichen
Angaben des Herausgebers entsprechen. Für den öffentlichen Start **Public**
wählen und zunächst mit verzögerter Veröffentlichung zur Prüfung einreichen.

Reference requirements checked against Google's official
[listing guidance](https://developer.chrome.com/docs/webstore/cws-dashboard-listing),
[privacy fields](https://developer.chrome.com/docs/webstore/cws-dashboard-privacy),
[image requirements](https://developer.chrome.com/docs/webstore/images), and
[publishing process](https://developer.chrome.com/docs/webstore/publish).

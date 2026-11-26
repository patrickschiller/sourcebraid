# SourceBraid on Mozilla Add-ons

| Field | Value |
| --- | --- |
| Name | SourceBraid |
| Category | Bookmarks |
| Compatibility | Firefox desktop 140 and later |
| License | MIT |
| Homepage | https://sourcebraid.com |
| Support | https://github.com/patrickschiller/sourcebraid/issues |
| Privacy policy | https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md |

## English listing

**Summary**

Save web pages and PDFs as Markdown in your private GitHub repository.

**Description**

Use SourceBraid to save an article, research paper, wiki page, GitHub Gist, or
HTTPS PDF from the active Firefox tab. Add tags and notes, then save the capture
to a private GitHub repository you control. SourceBraid preserves the source URL
and available metadata in the Markdown file and saves relevant images alongside
it. A GitHub Actions workflow can convert web PDFs to Markdown and retain the
original PDFs. You can also download Markdown from an HTML page to your device.

SourceBraid reads page content when you choose to capture the page. Saving sends
the selected URL, content and assets, tags, and notes directly to GitHub over
HTTPS. The add-on may make HTTPS requests to prepare the capture. It stores
your credentials in your local Firefox profile and sends them to the services
they authorize. SourceBraid servers receive no captures or telemetry.

GitHub saving requires a GitHub account, a private repository, and a fine-grained
token with **Contents: Read and write** for that repository. The first PDF
workflow installation also requires **Workflows: Read and write**. SourceBraid
runs in regular Firefox desktop windows. The extension interface is in English.

## Deutsche Store-Beschreibung

**Kurzbeschreibung**

Speichere Webseiten und PDFs als Markdown in deinem privaten GitHub-Repository.

**Beschreibung**

Erfasse Artikel, wissenschaftliche Papers, Wiki-Seiten, GitHub Gists oder
PDFs über HTTPS aus dem aktiven Firefox-Tab. Ergänze Tags und Notizen und speichere das
Ergebnis in einem privaten GitHub-Repository, das du kontrollierst. SourceBraid
bewahrt die Quell-URL und verfügbare Metadaten in der Markdown-Datei und legt
relevante Bilder daneben ab. Ein GitHub-Actions-Workflow kann Web-PDFs in
Markdown umwandeln und die Originale erhalten. Markdown aus HTML-Seiten kannst
du auch direkt auf dein Gerät herunterladen.

SourceBraid liest Seiteninhalte, wenn du eine Erfassung startest. Beim Speichern
sendet die Erweiterung die gewählte URL, Inhalte und Dateien, Tags und Notizen
direkt per HTTPS an GitHub. Für die Erfassung können HTTPS-Anfragen an die
Quelle erforderlich sein. Das Add-on speichert Zugangsdaten lokal im Firefox-Profil und sendet sie
an die Dienste, für die sie bestimmt sind. SourceBraid-Server erhalten keine
Captures oder Telemetrie.

Zum Speichern in GitHub brauchst du ein GitHub-Konto, ein privates Repository
und einen Fine-grained Token mit **Contents: Read and write** für genau dieses
Repository. Die erste Installation des PDF-Workflows benötigt zusätzlich
**Workflows: Read and write**. SourceBraid läuft in regulären
Firefox-Desktopfenstern. Die Oberfläche der Erweiterung ist auf Englisch.

## Permissions and privacy

| Firefox permission | Purpose |
| --- | --- |
| `activeTab` | Read the active capture target and show its title in the popup. |
| `scripting` | Inject bundled capture code into the active tab on Save or Download. |
| `https://*/*` | Fetch source APIs, related assets and HTTPS PDFs during capture, and write to the selected repository through GitHub's API. |
| `authenticationInfo` | Authenticate requests using the configured GitHub token and any configured Ghost or Blogger API credentials. Protected source requests can use the source site's existing browser session. |
| `browsingActivity` | Include the URL of the page chosen for capture in its archived metadata. |
| `websiteContent` | Save captured HTML-derived content, PDFs, images, source metadata, and accompanying tags or notes. |

Enable the privacy policy field in the Developer Hub and supply the browser
and external-services disclosures from [PRIVACY.md](../PRIVACY.md). Firefox
asks the user to accept the required data permissions during installation.
Capture code runs locally. Packaged Python and YAML resources are copied to
the user's GitHub repository for the optional PDF conversion workflow.

## Reviewer testing

### Prepare private review access

Set up a dedicated private GitHub repository with an initial commit and only
synthetic test content. The [GitHub setup script](https://github.com/patrickschiller/sourcebraid/blob/main/scripts/setup_github.py)
initializes it and installs the optional PDF support files. Use the review
account's GitHub username for `OWNER`.

```bash
python3 scripts/setup_github.py --repo OWNER/sourcebraid-firefox-review --no-config
```

Create a fine-grained PAT for that repository alone with **Contents: Read and
write** and an expiry that covers the review window. The setup script installs
the PDF workflow so the browser's review token only needs repository contents
access. Give reviewers the owner, repository, branch, and PAT through the
private **Notes for Reviewers** field. Revoke the token when review is complete
and provision fresh access for later reviews. See Mozilla's [review policy](https://extensionworkshop.com/documentation/publish/add-on-policies/#3-submission-guidelines).

### Steps for reviewers

1. On Firefox desktop, open `https://example.com/` in a regular window and
   choose SourceBraid from the extensions menu. Tick the first-capture consent
   checkbox and choose **Download Fallback**. This produces a local `.md` file
   containing the example page and source URL, without GitHub setup.
2. Open the settings gear and enter the supplied owner, repository, branch,
   root folder `web-clips`, and fine-grained token. Leave the optional Ghost
   and Blogger inputs empty and click **Save Settings**.
3. Add the tag `amo-review` and the note `Synthetic Firefox review`. Choose
   **Save to GitHub**. The popup shows the saved path. Check the Markdown under
   `web-clips/YYYY/MM/` and its corresponding entry in `web-clips/index/`
   using the supplied repository access.
4. Choose **Export Plugin Config**. The downloaded JSON contains the repository
   settings and omits credentials.
5. Open the [W3C dummy PDF](https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf)
   and choose **Save to GitHub**. The popup reports the queued file. Check for
   `source.pdf` and pending Markdown in the review repository, then confirm
   that **Convert PDFs to Markdown** completes and updates the Markdown.

## Submission

In [Submit a New Add-on](https://addons.mozilla.org/developers/addon/submit/),
choose **On this site**, upload `sourcebraid-firefox-v1.1.1.zip`, select
Firefox desktop, and complete the listing details. Attach the matching
`sourcebraid-firefox-source-v1.1.1.zip` in the source code step. To attach
it later, open the version under **Manage Status & Versions** and use **Source
code**. Rebuild instructions are in
`firefox-extension/BUILD.md` inside the archive. See Mozilla's [source upload
instructions](https://extensionworkshop.com/documentation/publish/source-code-submission/#upload-source-for-an-existing-version).

For listing screenshots, use the actual Firefox popup with synthetic data.
The packaged SourceBraid icon is at `icons/icon-128.png`. See Mozilla's
[listing guidance](https://extensionworkshop.com/documentation/develop/create-an-appealing-listing/).

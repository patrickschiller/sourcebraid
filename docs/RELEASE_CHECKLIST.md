# SourceBraid 1.0 release checklist

This checklist turns the four publication tracks into reviewable release gates.
Store dashboards, identity verification, legal attestations, credentials, and
the final **Submit** actions remain manual account-owner steps.

## 0. Establish the release commit

- Reconcile the private `main`, `origin/main`, and public `public/main` before
  bumping versions. Never publish the current private checkout while it is
  behind the public branch or contains unrelated uncommitted work.
- Select one release commit and tag. If this is the first non-beta release,
  align the customer-facing versions at `1.0.0`; iOS build numbers remain
  monotonically increasing.
- Export the public release through the existing explicit public-file allowlist.
  Never copy `website/`, `web-clips/`, private Git history, credentials, caches,
  or build artifacts into the public repository.
- Run the core Node and Python suites and the unsigned iOS build from
  `AGENTS.md`.

## 1. Chrome Web Store

### Release artifact

```bash
python3 scripts/build_chrome_package.py
unzip -l dist/sourcebraid-chrome-v*.zip
```

The builder places `manifest.json` at the ZIP root and includes only 15 known
runtime/PDF-support files. It excludes the private archive, website, iOS project,
plugin config, Git data, tests, caches, and local configuration.

Before building, ensure the manifest version is greater than every previously
uploaded version. The public branch currently contains `0.7.1`, while the
private checkout inspected during this preparation still contained `0.7.0`.

### Listing material

- Category: `Productivity`.
- Single purpose: "Save the page, paper, wiki, Gist, or PDF explicitly selected
  by the user as portable Markdown in the user's own GitHub repository."
- Required graphics: 128×128 PNG store icon, at least one 1280×800 screenshot,
  and a 440×280 small promo tile. The existing 1200×675 marketing screenshots
  do not meet the Chrome screenshot dimensions and must not be uploaded as-is.
- Recommended screenshots: capture popup/settings, a completed GitHub archive,
  PDF conversion, and fallback download using only synthetic data.
- Homepage: `https://sourcebraid.com`.
- Support: `https://github.com/patrickschiller/sourcebraid/issues`.
- Privacy: `https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md`.

### Privacy and permission declarations

- `activeTab`: inspect only the tab on which the user invokes SourceBraid.
- `scripting`: run the packaged capture script in that selected tab.
- `storage`: store repository settings, fine-grained token, optional source API
  keys, tags, and UI preferences locally in extension storage.
- `downloads`: save the explicit Markdown/config fallback selected by the user.
- `<all_urls>`: read the selected source and its linked content assets or source
  APIs across origins; SourceBraid does not monitor tabs in the background.
- `https://api.github.com/*`: upload the user-confirmed capture directly to the
  configured repository and read/update its metadata shard.
- Remote code: **No**. All executable JavaScript is packaged in the extension;
  fetched page data and APIs are treated as data.
- Disclose at least authentication information, website content, the selected
  page URL/browsing activity, and user-provided notes/tags. State that data is
  used only for the user-facing capture workflow and sent directly to the
  configured GitHub repository.

Upload the ZIP in the [Chrome Developer Dashboard](https://chrome.google.com/webstore/devconsole),
complete Store Listing, Privacy, Distribution, and Test Instructions, then use
deferred publishing so approval and launch can be separated.

## 2. ChatGPT and Codex plugin

Build the initial public **Skills only** package:

```bash
python3 scripts/build_plugin_package.py
unzip -l dist/sourcebraid-plugin-skills-v*.zip
python3 /path/to/plugin-creator/scripts/validate_plugin.py codex-plugin/sourcebraid
```

The release ZIP intentionally removes the local `.mcp.json` reference and MCP
server. It contains the three skills, their OpenAI metadata, the dependency-free
CLI, and listing assets. Local/repo marketplace installs keep the bundled MCP
server. This avoids introducing a central SourceBraid service merely for
publication.

Submission prerequisites:

- OpenAI Platform organization role with **Apps Management: Write**.
- Verified individual or business developer identity matching the website and
  legal/support URLs.
- Final logo, descriptions, starter prompts, country availability, and release
  notes.
- Five positive test cases: status/config guidance; first index build; search
  and fetch with citations; incremental index update; deletion preview followed
  by a separate exact confirmation.
- Three negative test cases: refuse deletion without a fresh preview; refuse a
  stale deletion after the branch head changes; do not browse the public web as
  a substitute for an unavailable private archive.

Create a **Skills only** draft in the
[OpenAI plugin submission portal](https://platform.openai.com/plugins), upload
the package, complete the test cases and attestations, submit for review, and
publish the approved version. One publication lists it in the universal
directory shared by ChatGPT and Codex.

## 3. iOS App Store

- Preserve the existing App Store/TestFlight identifiers
  `de.patrickschiller.stowmark` and `de.patrickschiller.stowmark.share`, the
  shared App Group, and Keychain group. Changing them would create a new app and
  break the existing migration path.
- Confirm the customer-facing version and increment `CURRENT_PROJECT_VERSION`
  beyond the latest uploaded build for both app and Share Extension.
- Run the unsigned simulator build, then archive and upload with the commands in
  `ios/README.md` using a current supported Xcode.
- Product metadata: name, subtitle, description, keywords, primary category,
  support URL, marketing URL, copyright, price/availability, age rating, content
  rights, and EU Digital Services Act trader status.
- Upload real in-use screenshots for each required device class/localization,
  using only synthetic repository names and captures.
- App Privacy: provide the public privacy-policy URL and answer the label for all
  data sent to GitHub. Review user content/files, GitHub account identifiers,
  repository metadata, and credentials as app-functionality data; do not claim
  "no data collected" merely because SourceBraid itself has no central server.
- App Review notes: explain the Share Extension, direct GitHub data flow, token
  storage in Keychain, PDF workflow, and how to test. Provide a dedicated demo
  private repository and non-expiring review token through App Store Connect,
  never in source control.
- Confirm export compliance (`ITSAppUsesNonExemptEncryption = false`), select the
  processed build, add it for review, submit the draft, and choose manual release
  for launch coordination.

## 4. Automatic GitHub setup

Prerequisite: install `gh` and run `gh auth login` with an account allowed to
create the target repository and manage Actions.

```bash
python3 scripts/setup_github.py --repo OWNER/sourcebraid-private --dry-run
python3 scripts/setup_github.py --repo OWNER/sourcebraid-private
```

The script:

- creates a private repository when absent and refuses an existing public one;
- enables Actions; the bundled workflow itself requests only
  `contents: write` for PDF conversion commits;
- uploads only the Docling workflow, conversion scripts, requirements, and an
  empty archive placeholder;
- preserves every existing file by default; and
- never creates, prints, or stores a GitHub access token.

After setup, create a fine-grained client token restricted to that repository
with `Contents: Read and write`. `Workflows: Read and write` is needed only when
the Chrome extension must install the workflow itself instead of using this
setup script.

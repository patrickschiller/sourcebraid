# Releasing SourceBraid

This document describes the reproducible, public part of a SourceBraid release.
Store credentials, account verification, legal attestations, review accounts,
and final submission decisions are intentionally maintained outside the public
repository.

The iOS app is published in the App Store as `1.0.1`. The Chrome Web Store and
public ChatGPT/Codex directory releases remain separate maintainer actions and
must not be described as available before their listings are live. The first
coordinated Chrome and OpenAI plugin release uses `1.0.1` so all available
clients start from the same customer-facing version.

## Release principles

- Build and tag releases from a clean commit on the public `main` branch.
- Never merge private repository history into this repository.
- Never include `website/`, `web-clips/`, credentials, local configuration,
  Keychain data, caches, indexes, or generated build directories in a release.
- Use the checked-in package builders. They construct archives from explicit
  allowlists instead of copying the repository broadly.
- Preserve source provenance and use only synthetic or redistributable content
  in release screenshots and examples.
- Every pull-request commit must carry a DCO `Signed-off-by:` trailer.

## Version alignment

Before creating the first release candidate, align these customer-facing
versions:

- Chrome: `version` in `chrome-extension/sourcebraid/manifest.json`.
- Local Codex/optional skills package: `version` in
  `codex-plugin/sourcebraid/.codex-plugin/plugin.json`.
- Hosted ChatGPT MCP: `version` in `chatgpt-mcp/package.json` and its server
  metadata.
- iOS app and Share Extension: `MARKETING_VERSION` in
  `ios/SourceBraid.xcodeproj/project.pbxproj`.

Chrome versions use one to four dot-separated integers. The plugin uses semantic
versioning. After the first iOS upload, increase `CURRENT_PROJECT_VERSION` for
every new binary while keeping the app and Share Extension build numbers equal.

The first iOS publication uses the SourceBraid identities:

- app: `de.patrickschiller.sourcebraid`;
- Share Extension: `de.patrickschiller.sourcebraid.share`;
- App Group: `group.de.patrickschiller.sourcebraid`;
- shared Keychain group:
  `$(AppIdentifierPrefix)de.patrickschiller.sourcebraid.shared`.

## Preflight checks

Run from the repository root:

```bash
git status --short --branch
node --test tests/capture-utils.test.js
python3 -m unittest discover -s tests -p "test_*.py"
npm --prefix chatgpt-mcp ci
npm --prefix chatgpt-mcp test
npm --prefix chatgpt-mcp run build
```

Run the unsigned iOS build from `ios/`:

```bash
python3 ../scripts/validate_ios_release.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Do not release while a required check fails or the worktree contains unrelated
changes.

## Chrome package

The unpacked extension source lives in `chrome-extension/sourcebraid`. Build the
Manifest V3 archive from its explicit allowlist:

```bash
python3 scripts/build_chrome_package.py
unzip -l dist/sourcebraid-chrome-v*.zip
```

The script prints the package path, version, SHA-256 digest, and file count. The
ZIP must contain `manifest.json` at its root and must not contain source archives,
the private website, plugin configuration, iOS sources, tests, Git metadata, or
local settings.

## Optional local skills package

Build the optional local-runtime archive:

```bash
python3 scripts/build_plugin_package.py
unzip -l dist/sourcebraid-plugin-skills-v*.zip
```

The public package contains the three SourceBraid skills, their OpenAI metadata,
the dependency-free CLI, and listing assets. The builder intentionally removes
the local MCP server declaration and app entries from the packaged manifest.
Local repository installations can continue to use the complete plugin source.
This ZIP needs a runtime with Python and GitHub credentials. It is not a
standalone normal-ChatGPT connection and is not the primary OpenAI submission.

## Hosted ChatGPT MCP package

The separate Worker in `chatgpt-mcp/` is prepared for
`https://mcp.sourcebraid.com/mcp`; it is not deployed. Build the allowlisted
service source package and synthetic reviewer archive:

```bash
python3 scripts/build_mcp_package.py
python3 scripts/build_review_fixture.py \
  --output dist/sourcebraid-review-fixture-v1.0.1.zip
```

The review ZIP contains only three synthetic Markdown clips and their three
metadata shards. It does not read or copy a user's archive. Follow
[`docs/CHATGPT_MCP_DEPLOYMENT.md`](docs/CHATGPT_MCP_DEPLOYMENT.md) for account,
domain, KV, OAuth, and live smoke checks. A Worker dry-run or source ZIP is not a
successful production deployment.

## OpenAI Plugins Directory submission

The primary `1.0.1` ChatGPT submission is **With MCP**, using the hosted
read-only service after deployment and live tests. Supply the actual public
HTTPS endpoint and complete domain verification. Do not submit the intended
`https://mcp.sourcebraid.com/mcp` URL as a working service before it is live.

Use [`marketing/OPENAI_MCP_SUBMISSION.md`](marketing/OPENAI_MCP_SUBMISSION.md)
as the submission source of truth. It contains the copy-ready listing, starter
prompts, reviewer setup, five positive tests, three negative tests, release
notes, privacy disclosures, and the final portal checklist. Before submitting:

1. confirm `Apps Management: Write` access and the verified publisher identity;
2. build and inspect the hosted MCP source package and deploy the reviewed
   Worker with verified domain and OAuth configuration;
3. seed the dedicated private review repository from the synthetic fixture ZIP
   and validate the live OAuth/search/fetch flow;
4. restrict its review PAT to Contents read-only on that one repository and
   provide credentials only through OpenAI's protected submission fields;
5. select country availability deliberately and complete the policy
   attestations; and
6. submit for review, then publish only after approval.

Follow the current [OpenAI submission guide](https://developers.openai.com/plugins/deploy/submission)
and [plugin packaging guide](https://developers.openai.com/plugins/build/plugins)
when the portal or required fields change. Builds, deployment, review
submission, approval, and publication are distinct states. The optional
[local skills kit](marketing/OPENAI_PLUGIN_SUBMISSION.md) describes different
capabilities and must not be copied into the hosted read-only listing.

## Complete reviewable release bundle

Build and verify the allowlisted artifacts, submission documents, graphics, and
synthetic fixture from the final reviewed commit:

```bash
python3 scripts/build_release.py --verify-reproducible --require-clean
python3 scripts/build_release.py --verify dist/sourcebraid-release-v1.0.1
```

Use the generated `RELEASE_MANIFEST.json` and `SHA256SUMS` as the artifact and
digest record. Do not hard-code a ZIP digest in documentation: runtime changes
require rebuilding and verifying the bundle. The builders export only explicit
public allowlists, never broad copies or private repository history.

## iOS archive

Confirm that the SourceBraid bundle identifiers, App Group, and Keychain access
group are registered for the selected Apple Developer team before enabling
signing. First validate the unsigned simulator build above. Then use the archive
and export commands in [`ios/README.md`](ios/README.md). Validate the archived
`.app` with `scripts/validate_ios_release.py --app-bundle PATH` before uploading
it. This catches stale icons and mismatched app/extension versions in the actual
package rather than only checking the Xcode sources.

Signing and App Store upload credentials are not part of this repository. Never
commit provisioning profiles, certificates, export credentials, review tokens,
or App Store Connect API keys.

## GitHub setup script

Validate the user-facing repository bootstrap workflow without changing a
repository:

```bash
python3 scripts/setup_github.py --dry-run
```

Without `--repo`, the script targets
`AUTHENTICATED_USER/sourcebraid-private`. It writes a token-free
`sourcebraid-config.json`, preserves existing repositories and support files,
and refuses to configure a public archive. Build the standalone release artifact
with the same embedded allowlist:

```bash
python3 scripts/build_setup_package.py
python3 dist/sourcebraid-github-setup-v1.0.1.py --help
```

The setup and builder must avoid printing or embedding credentials and must
never include `web-clips/`, `website/`, or files outside the documented support
allowlist.

## Codex marketplace

Validate `.agents/plugins/marketplace.json` and
`codex-plugin/sourcebraid/.codex-plugin/plugin.json` before tagging. The
marketplace entry uses the repository-local plugin path and is consumed from
GitHub with both paths included in the sparse checkout:

```bash
codex plugin marketplace add patrickschiller/sourcebraid \
  --ref v1.0.1 \
  --sparse .agents/plugins \
  --sparse codex-plugin/sourcebraid
codex plugin add sourcebraid@sourcebraid
```

Do not advertise that command as live before the referenced tag exists.

## Tag and publish artifacts

1. Review the complete diff from the previous release tag, or the repository
   root commit for the first release.
2. Record the passing check results and package SHA-256 digests.
3. Create an annotated version tag on the reviewed public commit.
4. Push the tag to the public repository.
5. Attach the Chrome ZIP, hosted MCP source ZIP, optional local skills ZIP,
   standalone GitHub setup script, synthetic fixture, and generated digest
   record to the corresponding GitHub release when artifacts are distributed.
6. Verify that every published archive can be traced back to the tagged commit.

Store review and publication remain separate maintainer actions. A GitHub tag or
release must not imply that a store submission has already been approved.

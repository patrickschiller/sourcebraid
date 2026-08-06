# Releasing SourceBraid

This document describes the reproducible, public part of a SourceBraid release.
Store credentials, account verification, legal attestations, review accounts,
and final submission decisions are intentionally maintained outside the public
repository.

No Chrome Web Store, ChatGPT/Codex directory, or App Store release has been
published yet. The first coordinated public release should use `1.0.0` as its
customer-facing version unless the maintainers document a different decision.

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
- ChatGPT/Codex skills package: `version` in
  `codex-plugin/sourcebraid/.codex-plugin/plugin.json`.
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

## ChatGPT and Codex skills package

Build the initial skills-only archive:

```bash
python3 scripts/build_plugin_package.py
unzip -l dist/sourcebraid-plugin-skills-v*.zip
```

The public package contains the three SourceBraid skills, their OpenAI metadata,
the dependency-free CLI, and listing assets. The builder intentionally removes
the local MCP server declaration and app entries from the packaged manifest.
Local repository installations can continue to use the complete plugin source.

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
python3 scripts/setup_github.py --repo OWNER/REPOSITORY --dry-run
```

The setup script must continue to refuse public archive repositories, preserve
existing files, avoid printing credentials, and upload only its documented
allowlist.

## Tag and publish artifacts

1. Review the complete diff from the previous release tag, or the repository
   root commit for the first release.
2. Record the passing check results and package SHA-256 digests.
3. Create an annotated version tag on the reviewed public commit.
4. Push the tag to the public repository.
5. Attach the Chrome and skills ZIP files and their digests to the corresponding
   GitHub release when binary artifacts are distributed there.
6. Verify that every published archive can be traced back to the tagged commit.

Store review and publication remain separate maintainer actions. A GitHub tag or
release must not imply that a store submission has already been approved.

# SourceBraid Repository Guidelines

These instructions apply to human contributors and automated coding agents.

## Product contract

- Product name: **SourceBraid**.
- Slogan: **SourceBraid — Weave the web into Markdown.**
- SourceBraid captures web pages, papers, wikis, Gists, PDFs, and shared iOS
  content as portable Markdown in a GitHub repository controlled by the user.
- The archive's Markdown files and Git history are authoritative. The local
  SQLite index is a disposable, rebuildable search cache.
- Preserve provenance. Never fabricate a source title, author, publication
  date, canonical URL, or extraction method.

## Repository boundaries

- `sourcebraid-private` is the maintainer's private authoring repository;
  `sourcebraid` is the public open-source repository.
- Public contributions target `https://github.com/patrickschiller/sourcebraid`.
- The `website/` directory remains private and must not be exported to the
  public repository unless the maintainer explicitly changes that policy.
- `web-clips/` contains a user's private archive. Never copy it, its history, or
  derived content into the public repository, tests, issues, or screenshots.
- Never publish access tokens, cookies, local configuration, Keychain data,
  SQLite indexes, build artifacts, or private Git history.
- Create public release commits from an explicit allowlist of project files;
  do not push the private repository's history or use a broad copy command.

## Project map

- Chrome extension: root-level `manifest.json`, HTML, CSS, and JavaScript files.
- Shared capture behavior and tests: `capture-utils.js` and `tests/`.
- PDF conversion: `scripts/`, `requirements-docling.txt`, and
  `.github/workflows/convert-pdfs.yml`.
- ChatGPT/Codex plugin: `codex-plugin/sourcebraid/`.
- iOS app and Share Extension: `ios/`.
- Public documentation and community policy: root Markdown files and `.github/`.
- Public launch and community material: `marketing/`.
- Private website source: `website/`; do not include it in a public release
  unless the maintainer explicitly approves that change.

## Working rules

- Inspect `git status` and the relevant files before editing. Preserve unrelated
  work already present in the checkout.
- Prefer small, reviewable changes and avoid unrelated refactors.
- Keep Chrome code compatible with Manifest V3 and avoid increasing permissions
  without a documented user need and security review.
- Keep archive paths, YAML frontmatter, URL-hash index shards, and plugin parsing
  mutually compatible. Treat a format change as a migration concern.
- Keep plugin code compatible with Python's standard library unless a dependency
  is necessary, documented, and accepted by the maintainer.
- Store secrets only through the existing browser storage, environment, or iOS
  Keychain paths. Never log credentials or write them into the archive.
- Use only synthetic or clearly redistributable content in tests and examples.
- Android remains a roadmap item until the maintainer explicitly starts that
  implementation.

## Required checks

Run the checks relevant to the changed components. For shared capture, scripts,
or plugin changes, run both core suites from the repository root:

```bash
node --test tests/capture-utils.test.js
python3 -m unittest discover -s tests -p "test_*.py"
```

For an iOS build without signing, run from `ios/`:

```bash
xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Maintainers changing the private website should run:

```bash
npm --prefix website ci
npm --prefix website test
```

If a check cannot run because its platform or dependency is unavailable, state
that clearly in the pull request rather than claiming it passed.

## Legal and community requirements

- SourceBraid code and project documentation are published under the MIT
  License in `LICENSE`. Do not copy code with an incompatible license.
- Third-party dependencies and captured user content retain their own licenses;
  do not describe them as MIT-licensed SourceBraid code.
- Every pull-request commit must include a DCO `Signed-off-by:` trailer. Use
  `git commit -s` and follow `CONTRIBUTING.md`.
- Follow `CODE_OF_CONDUCT.md`. Report vulnerabilities privately through
  `SECURITY.md`, never in a public issue.
- Do not weaken `LICENSE`, `NOTICE`, `PRIVACY.md`, `TERMS.md`, contribution
  provenance, or security-reporting guidance without explicit maintainer review.

## Pull request handoff

- Explain the problem, the implementation, privacy or permission effects, and
  the checks that were run.
- Highlight changes to browser permissions, GitHub scopes, network endpoints,
  storage formats, deletion behavior, or credential handling.
- Update English and German documentation together when user-facing behavior
  changes.
- Do not mark work complete while required tests fail or public-release safety
  checks find private content.

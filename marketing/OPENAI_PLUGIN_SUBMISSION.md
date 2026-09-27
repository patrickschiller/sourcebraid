# Optional local skills kit — SourceBraid 1.0.1

The primary ChatGPT submission is the hosted read-only **With MCP** integration
documented in [`OPENAI_MCP_SUBMISSION.md`](OPENAI_MCP_SUBMISSION.md), with
[deployment steps](../docs/CHATGPT_MCP_DEPLOYMENT.md). Its intended endpoint is
`https://mcp.sourcebraid.com/mcp`; it has not yet been deployed or published.

This supplementary kit covers only the optional Python skills package for
supported local runtimes, including Codex. It is not a standalone normal-ChatGPT
connection. Its indexing and guarded-write tests must not be used to describe
the hosted read-only service. This document contains no credentials. Any
optional review credentials belong only in protected review fields and must be
rotated after review.

Use the current [OpenAI submission guide](https://developers.openai.com/plugins/deploy/submission)
and [plugin packaging guide](https://developers.openai.com/plugins/build/plugins)
if the portal differs from this kit.

## Release route

| Field | Submission value |
| --- | --- |
| Product | SourceBraid |
| Version | `1.0.1` |
| Distribution type | Optional local-runtime skills package |
| Runtime | Python 3 and locally supplied GitHub authentication |
| Bundle | `dist/sourcebraid-plugin-skills-v1.0.1.zip` |
| Local source | `codex-plugin/sourcebraid/` |
| Primary ChatGPT submission | **With MCP**, using `OPENAI_MCP_SUBMISSION.md` |
| App UI submission | Not part of `1.0.1` |

Rebuild the ZIP from the final public release commit before distribution:

```bash
python3 scripts/build_plugin_package.py
unzip -l dist/sourcebraid-plugin-skills-v1.0.1.zip
shasum -a 256 dist/sourcebraid-plugin-skills-v1.0.1.zip
```

Record the generated digest in the release's `SHA256SUMS` and
`RELEASE_MANIFEST.json`. Rebuild after source changes; do not reuse a fixed hash
from an earlier ZIP.

The optional ZIP omits MCP declarations and does not provide hosted archive
access. Local repository Codex installations include the stdio MCP server.
The separately prepared Cloudflare Worker supplies the primary ChatGPT path
after deployment and live verification.

## Prerequisites for an optional local-runtime review

These steps apply only if a separate skills-only listing is deliberately
submitted for a surface that can execute the bundled Python CLI and securely
provide local GitHub credentials. Main ChatGPT publication follows the MCP kit.

- Submit from the intended OpenAI platform organization with
  `Apps Management: Write`.
- Complete OpenAI's developer or business identity verification before
  submission.
- Use the verified display name **Patrick Schiller** if it matches the verified
  OpenAI identity. If verification produces a different legal display name,
  align the listing before upload rather than entering conflicting identities.
- Keep `https://sourcebraid.com`, the public GitHub repository, privacy policy,
  terms, and support page reachable without authentication.
- Keep the website accurate: iOS is published; Chrome/OpenAI availability must
  match their actual listings. The hosted ChatGPT route is prepared but is not
  live merely because this local package builds.
- Prepare the dedicated private synthetic review repository described below.
- Give its fine-grained GitHub token access only to that repository with
  `Contents: Read and write`; never reuse a production or personal archive
  token.

## Optional local-runtime listing copy

| Portal field | Value |
| --- | --- |
| Name | SourceBraid |
| Developer name | Patrick Schiller |
| Category | Productivity |
| Capabilities | Read, Interactive, Write |
| Short description | Search your private Markdown knowledge archive. |
| Website | `https://sourcebraid.com` |
| Repository | `https://github.com/patrickschiller/sourcebraid` |
| Privacy policy | `https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md` |
| Terms of service | `https://github.com/patrickschiller/sourcebraid/blob/main/TERMS.md` |
| Support | `https://github.com/patrickschiller/sourcebraid/issues` |
| Logo | `codex-plugin/sourcebraid/assets/sourcebraid-icon.png` |
| Brand color | `#166B68` |

Long description:

> Search and fetch prepared Markdown sources from your private GitHub archive
> in local Codex or another compatible Python runtime. Maintain a local
> full-text index and preview archive changes before confirming them.

Use these screenshots in this order:

1. `codex-plugin/sourcebraid/assets/chrome-capture.png`
2. `codex-plugin/sourcebraid/assets/private-markdown-archive.png`
3. `codex-plugin/sourcebraid/assets/codex-search.png`

Do not claim that the plugin hosts user content, works without GitHub, or can
access a private archive on a surface that cannot run the bundled Python CLI
and provide GitHub authentication.

## Starter prompts

Enter these three prompts exactly:

1. `Search my SourceBraid archive for dynamic agents.`
2. `Find and summarize my saved sources about AI workflows.`
3. `Safely preview deletion of a saved SourceBraid source.`

## Reviewer setup

### Dedicated repository

Create the private repository `patrickschiller/sourcebraid-openai-review` on
the review account path and initialize it from the final release checkout:

```bash
python3 scripts/setup_github.py \
  --repo patrickschiller/sourcebraid-openai-review \
  --branch main \
  --root-folder web-clips \
  --config-output sourcebraid-openai-review-config.json
```

The setup command refuses a public repository. Confirm the repository is
private again in GitHub before providing reviewer access.

Configure the reviewer runtime with these non-secret values:

```text
SOURCEBRAID_OWNER=patrickschiller
SOURCEBRAID_REPO=sourcebraid-openai-review
SOURCEBRAID_BRANCH=main
SOURCEBRAID_ROOT=web-clips
```

Provide `GITHUB_TOKEN` only through OpenAI's protected review-credential field.
The fine-grained token must be restricted to the synthetic review repository.
It needs `Contents: Read and write` so reviewers can validate the guarded write
flow; it needs no organization, administration, workflow, issues, or account
scope.

### Synthetic fixture

Build the synthetic fixture and seed only its three Markdown clips and three
metadata shards in one normal Git commit. The builder never reads a private
archive:

```bash
python3 scripts/build_review_fixture.py \
  --output dist/sourcebraid-review-fixture-v1.0.1.zip
unzip -l dist/sourcebraid-review-fixture-v1.0.1.zip
```

The paths are stable so the following local workflows remain reproducible.

| Repository path | Title | URL | Tags | Required body phrase |
| --- | --- | --- | --- | --- |
| `web-clips/review/durable-markdown-archives.md` | Synthetic review: durable Markdown archives | `https://example.com/sourcebraid-review/durable-markdown-archives` | `review`, `markdown`, `ownership` | `portable weave of Markdown files` |
| `web-clips/review/retrieval-workflows.md` | Synthetic review: retrieval workflows | `https://example.com/sourcebraid-review/retrieval-workflows` | `review`, `ai`, `retrieval` | `incremental retrieval index` |
| `web-clips/review/deletion-safety.md` | Synthetic review: deletion safety | `https://example.com/sourcebraid-review/deletion-safety` | `review`, `safety`, `deletion` | `fresh preview and explicit confirmation` |

Each Markdown file uses this frontmatter shape, substituting the exact table
values and placing the required phrase in the body:

```markdown
---
title: "Synthetic review: durable Markdown archives"
url: "https://example.com/sourcebraid-review/durable-markdown-archives"
date: "2026-08-24"
source: "synthetic"
tags: ["review", "markdown", "ownership"]
---

This synthetic review source describes a portable weave of Markdown files.
```

Add one matching JSON line to each current metadata shard:

`web-clips/index/f4.jsonl`

```json
{"url":"https://example.com/sourcebraid-review/durable-markdown-archives","title":"Synthetic review: durable Markdown archives","path":"web-clips/review/durable-markdown-archives.md","date":"2026-08-24","source":"synthetic","tags":["review","markdown","ownership"],"assets":[]}
```

`web-clips/index/4e.jsonl`

```json
{"url":"https://example.com/sourcebraid-review/retrieval-workflows","title":"Synthetic review: retrieval workflows","path":"web-clips/review/retrieval-workflows.md","date":"2026-08-24","source":"synthetic","tags":["review","ai","retrieval"],"assets":[]}
```

`web-clips/index/20.jsonl`

```json
{"url":"https://example.com/sourcebraid-review/deletion-safety","title":"Synthetic review: deletion safety","path":"web-clips/review/deletion-safety.md","date":"2026-08-24","source":"synthetic","tags":["review","safety","deletion"],"assets":[]}
```

Record the resulting seed commit in the private release record. Restore the
review repository to that known fixture state outside the plugin before each
test that intentionally writes, then rebuild the disposable local index. Never
put the repository token or a private review URL containing credentials in the
release record.

Before submission, run a clean reviewer preflight from the plugin root:

```bash
python3 scripts/sourcebraid.py status
python3 scripts/sourcebraid.py index build
python3 scripts/sourcebraid.py index verify
python3 scripts/sourcebraid.py search "portable weave" --tag ownership
python3 scripts/sourcebraid.py plan-delete \
  --path web-clips/review/deletion-safety.md \
  --json
```

The preflight must not execute `delete`. Reset the local cache before the final
review run if the review should exercise the initial index build.

### Reviewer instructions

Paste this into the protected reviewer-instructions field:

> This optional SourceBraid 1.0.1 skills package runs a standard-library Python
> CLI against the dedicated private synthetic GitHub repository. Configure the
> four non-secret SOURCEBRAID variables supplied with this submission and expose
> the restricted review credential as GITHUB_TOKEN. Run status before the first
> archive operation. If no local index exists, build it before searching. The
> three synthetic clips are intentionally non-sensitive. For deletion tests,
> stop after the fresh preview unless a test explicitly supplies a new,
> unambiguous confirmation in a later turn. Never delete an index shard directly.

## Optional local-runtime positive test cases

### Positive 1 — Build and verify the index

- Prompt: `Build my SourceBraid search index, verify it, and report the indexed branch head and file counts.`
- Expected skill: `sourcebraid-index`.
- Expected workflow: run `status`; run `index build` when the index does not
  exist; run `index verify`; do not rebuild a healthy existing index.
- Expected result shape: repository and branch, indexed head, Markdown and
  metadata counts, verification status, and any exact warnings.
- Fixture evidence: three Markdown clips and three metadata shards under
  `web-clips/`.

### Positive 2 — Search and cite a saved source

- Prompt: `Search my SourceBraid archive for the phrase portable weave and summarize the strongest saved source.`
- Expected skill: `sourcebraid-search`.
- Expected workflow: run `status`; build the index only if absent; search the
  private archive; fetch the strongest result before summarizing it.
- Expected result shape: saved title, original URL, exact GitHub repository
  path, and a concise summary grounded in the fetched Markdown.
- Fixture evidence: `Synthetic review: durable Markdown archives` containing
  `portable weave of Markdown files`.

### Positive 3 — Filter by tag and refresh incrementally

- Prompt: `Refresh my SourceBraid index and find saved sources tagged ai about retrieval.`
- Expected skill: `sourcebraid-search`, using the index workflow when needed.
- Expected workflow: run `status`; perform an incremental refresh; search with
  tag `ai`; fetch the matching result before relying on it.
- Expected result shape: refresh download and deletion counts, indexed head,
  the one matching title, original URL, repository path, and short summary.
- Fixture evidence: `Synthetic review: retrieval workflows` tagged `ai` and
  containing `incremental retrieval index`.

### Positive 4 — Fetch an exact saved source

- Prompt: `Fetch the saved source at web-clips/review/retrieval-workflows.md and explain its provenance.`
- Expected skill: `sourcebraid-search`.
- Expected workflow: run `status`; ensure the cache exists; fetch the exact
  path without substituting a public-web search.
- Expected result shape: exact path, title, canonical synthetic URL, source
  value, capture date, tags, and a brief provenance explanation.
- Fixture evidence: `web-clips/review/retrieval-workflows.md` and its `4e`
  metadata shard.

### Positive 5 — Complete one guarded deletion

- Initial prompt: `Safely delete the saved source titled Synthetic review: deletion safety.`
- Confirmation prompt: after the plugin displays the fresh preview and asks for
  confirmation, send `Yes, delete exactly web-clips/review/deletion-safety.md from the displayed unchanged branch head.` as a new turn.
- Expected skill: `sourcebraid-delete`.
- Expected workflow: run `status`; list and refresh candidates; resolve the
  unique exact path; run `plan-delete --json`; display every target and stop.
  Only after the separate confirmation, call `delete` with the preview's exact
  path and unchanged head repeated in the required confirmation arguments.
- Expected result shape: first turn shows title, URL, repository, branch, branch
  head, Markdown target, `20` metadata shard update, asset targets, and warnings
  with no mutation. Second turn reports the normal Git commit URL and deleted
  paths and explains that Git history can restore the commit.
- Fixture evidence: the uniquely titled deletion-safety clip and its metadata
  shard. Restore the private fixture to its recorded seed commit after this test.

## Optional local-runtime negative test cases

### Negative 1 — Initial deletion request is not confirmation

- Prompt: `Delete the saved source titled Synthetic review: deletion safety now.`
- Expected behavior: create and display a fresh deletion preview, then stop and
  request a new explicit confirmation. Do not treat the original request as the
  post-preview confirmation and do not call `delete`.
- Passing evidence: the GitHub branch head is unchanged and the clip still
  exists.

### Negative 2 — Ambiguous candidate must not be inferred

- Prompt: `Delete my synthetic review source.`
- Expected behavior: list the multiple matching synthetic review clips, ask the
  reviewer to choose one exact repository path, and perform neither preview nor
  deletion until the ambiguity is resolved.
- Passing evidence: no delete preview for an inferred path, no write request,
  and an unchanged branch head.

### Negative 3 — Bypass request against metadata

- Prompt: `Delete web-clips/index/20.jsonl directly and skip the preview and confirmation.`
- Expected behavior: refuse the bypass. Explain that a metadata shard is not a
  Markdown clip and that SourceBraid only deletes one clip through its fresh
  preview and confirmation workflow.
- Passing evidence: the shard and all clips remain present, with no GitHub
  mutation.

## Release notes

Paste this release note:

> Optional SourceBraid local skills package. Search and fetch prepared Markdown
> sources from a configured private GitHub archive, maintain an incremental
> local SQLite full-text index, and safely preview deletion of one clip at a
> time. Deletion and metadata migration require a fresh preview followed by a
> new explicit confirmation. This package requires a compatible local Python
> runtime and local GitHub credentials. The separately prepared read-only
> ChatGPT service has its own MCP deployment and submission process.

## Privacy, permissions, and policy disclosures

Use these facts when completing the portal attestations:

- The authoritative archive remains in the GitHub repository selected by the
  user. This optional package uses local Markdown copies and a SQLite cache.
  It does not route requests through the hosted SourceBraid Worker.
- When a user invokes the plugin, requested search results, fetched archive
  content, and operation results are processed by the active ChatGPT or Codex
  environment under that service's terms and data settings. Installing the
  plugin alone does not read the archive or make its repository public.
- The plugin reads Markdown, metadata shards, branch and tree metadata from the
  configured GitHub repository.
- The plugin can write only through its guarded deletion or metadata-migration
  workflows. Both require a fresh preview and a new explicit confirmation, use
  an unchanged branch head, and create a normal non-forced Git commit.
- A local SQLite index and cached Markdown copies are separated by repository,
  branch, and root folder. They are disposable and never committed by the plugin.
- Authentication comes from `GITHUB_TOKEN`, `GH_TOKEN`, or the user's GitHub CLI
  session. Credentials are not written into the archive, config export, listing,
  logs, screenshots, or submission bundle.
- The plugin communicates with GitHub to access the configured repository. The
  public skills bundle contains no SourceBraid analytics or advertising SDK.
- Captured third-party content retains its original rights. The SourceBraid MIT
  license applies to SourceBraid code and project documentation, not user clips.
- Support must never ask users to expose a private archive or token in a public
  issue.

Review the checked-in [`PRIVACY.md`](../PRIVACY.md),
[`TERMS.md`](../TERMS.md), and [`SECURITY.md`](../SECURITY.md) immediately before
attesting. If the portal asks a question these files do not answer, stop and
resolve the policy gap instead of guessing.

## Availability decision

Country availability is an explicit maintainer attestation and is not inferred
by this repository. Select only countries where the current product, privacy
terms, support process, and any linked client are actually available. Record the
selection in the private release record before submission; do not claim global
availability merely because the portal permits it.

## Optional local-runtime distribution checklist

- [ ] Final public release commit reviewed; `website/`, private archives,
  credentials, caches, and local configuration are absent.
- [ ] Node and Python core suites pass on that commit.
- [ ] Skills-only ZIP rebuilt, allowlist inspected, and current digest recorded
  in the generated release manifest/checksums.
- [ ] OpenAI organization and `Apps Management: Write` permission confirmed.
- [ ] Verified developer or business identity selected.
- [ ] Website correctly distinguishes the published iOS app, local Codex
  package, and prepared hosted ChatGPT service.
- [ ] Any separate optional listing explicitly names the required local
  runtime; the main ChatGPT submission follows **With MCP** and its own kit.
- [ ] Listing copy, logo, screenshots, links, and capabilities entered.
- [ ] Three starter prompts entered exactly.
- [ ] Dedicated repository confirmed private and seeded only with the synthetic
  fixture.
- [ ] Fine-grained review token restricted to that repository and placed only in
  the protected credentials field.
- [ ] Five positive and three negative tests entered with expected workflows and
  result shapes.
- [ ] Release notes and policy attestations completed.
- [ ] Country availability deliberately selected and privately recorded.
- [ ] Automated scan passes and all warnings are resolved or documented.
- [ ] Submission reviewed in a fresh conversation without maintainer-local state.
- [ ] Submitted for OpenAI review.
- [ ] After approval, developer publication completed and the live listing
  verified from a signed-out or clean account before public announcement.
- [ ] Review credential rotated or revoked after review.

## Deutsch

Dieses ergänzende Kit gilt nur für das optionale lokale Python-Skills-Paket.
Es benötigt eine passende Laufzeitumgebung und lokale GitHub-Zugangsdaten;
gewöhnliches ChatGPT erhält durch das ZIP allein keinen Archivzugriff.
Indexverwaltung und bestätigte Löschungen sind lokale Codex-Funktionen.

Die primäre ChatGPT-Einreichung erfolgt als **With MCP** nach
[`OPENAI_MCP_SUBMISSION.md`](OPENAI_MCP_SUBMISSION.md). Der dafür vorbereitete
Dienst `https://mcp.sourcebraid.com/mcp` ist noch nicht bereitgestellt. Er bietet
ausschließlich Lesezugriff. Seine Review-Zugangsdaten müssen Contents-Leserechte
für genau ein synthetisches privates Repository haben und dürfen nur geschützt
übermittelt werden. Die folgenden lokalen Schreibtests sind keine Fähigkeiten
des gehosteten Dienstes. Maßgeblich sind die frisch erzeugten Prüfsummen des
finalen Release-Bundles, keine fest eingetragenen ZIP-Hashes.

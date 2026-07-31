---
name: sourcebraid-search
description: Search and fetch Markdown sources stored in a configured private SourceBraid GitHub repository. Use when the user asks to search saved sources, gespeicherte Quellen, SourceBraid, captured articles, Markdown knowledge, or their private clip archive without switching workspaces.
---

# SourceBraid Search

Search or fetch sources from the user's private SourceBraid archive. Treat that GitHub repository as the source of truth without changing the active Codex workspace.

## Commands

Run the bundled script from the plugin root:

```bash
python3 scripts/sourcebraid.py status
python3 scripts/sourcebraid.py search "<query>"
python3 scripts/sourcebraid.py fetch "<repo-path>"
python3 scripts/sourcebraid.py index status
python3 scripts/sourcebraid.py index build
python3 scripts/sourcebraid.py index update
python3 scripts/sourcebraid.py config --repo-slug OWNER/REPO --branch main --root-folder web-clips
```

Resolve configuration in this order:

1. CLI flags.
2. `SOURCEBRAID_OWNER`, `SOURCEBRAID_REPO`, `SOURCEBRAID_BRANCH`, and `SOURCEBRAID_ROOT` environment variables.
3. `GITHUB_TOKEN` or `GH_TOKEN` for authentication.
4. `~/.config/sourcebraid/config.json`.

Use GitHub's REST API directly when a token is available. Otherwise fall back to `gh api` and the user's GitHub CLI authentication.

## Workflow

1. Run `status` before the first search in a thread.
2. If `configured: no`, give the exact setup command. If the user already supplied `OWNER/REPO`, run the command.
3. If `search_index: no`, run `index build`. Do not hide the first full build inside a search.
4. Run `search` with the user's query. Add `--tag TAG`, `--source SOURCE`, `--limit N`, or `--refresh` when useful. `--refresh` is incremental.
5. Use `--scan` only as an explicit diagnostic fallback when SQLite search is unavailable or the user requests a raw scan.
6. Run `fetch` for relevant matches before relying on them as evidence.
7. Cite the saved title, the original URL from frontmatter or a metadata shard, and the GitHub repository path.

## Examples

```bash
python3 scripts/sourcebraid.py status
python3 scripts/sourcebraid.py config --repo-slug OWNER/sourcebraid-private --branch main --root-folder web-clips
python3 scripts/sourcebraid.py search "dynamic agents" --limit 8
python3 scripts/sourcebraid.py search "identity spoofing" --tag security --refresh
python3 scripts/sourcebraid.py search "literal diagnostic" --scan
python3 scripts/sourcebraid.py fetch "web-clips/2026/07/2026-07-09-blog-mayflower-de-example-abc123.md"
```

## Guardrails

- Do not treat the archive repository as the active Codex workspace.
- Do not browse the public web for saved sources unless explicitly requested.
- If GitHub access fails, report the exact authentication or API error and suggest checking the fine-grained PAT or `gh auth status`.

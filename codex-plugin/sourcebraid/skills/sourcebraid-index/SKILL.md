---
name: sourcebraid-index
description: Build, incrementally update, inspect, verify, repair, or migrate the local SQLite FTS index for a configured private SourceBraid archive. Use when the user asks to speed up SourceBraid search, build or rebuild the Markdown index, refresh stale results, diagnose index health, schedule regular index maintenance, or migrate legacy index.jsonl metadata into shards.
---

# SourceBraid Index

Maintain the local search index without treating the archive repository as the active Codex workspace. Run the shared deterministic CLI from the plugin root.

## Commands

```bash
python3 scripts/sourcebraid.py index status
python3 scripts/sourcebraid.py index build
python3 scripts/sourcebraid.py index update
python3 scripts/sourcebraid.py index update --max-age 900
python3 scripts/sourcebraid.py index verify
python3 scripts/sourcebraid.py index rebuild
```

Use `build` when no SQLite index exists. Use `update` for normal maintenance; it compares Git blob SHAs and downloads only changed Markdown and metadata files. Use `rebuild` only for corruption, an incompatible schema, or an explicitly requested clean rebuild.

## Workflow

1. Run `status`.
2. If `exists: False`, run `build`; do not trigger an implicit full scan through search.
3. For stale results, run `update` and report downloaded/deleted counts and the indexed head.
4. For suspected corruption, run `verify`. Run `rebuild` only if verification fails or the user requests it.
5. For recurring maintenance, schedule `index update --max-age 900` through a Codex automation or the user's scheduler. A skill cannot schedule itself.

Search also performs a remote head check at most once every 15 minutes and keeps using the local index when that check cannot reach GitHub.

## Metadata shard migration

Preview migration before writing:

```bash
python3 scripts/sourcebraid.py index plan-shards --json
```

Show the head SHA, entry count, shard count, legacy action, targets, and every warning. End the turn and obtain a new explicit confirmation. After confirmation, use the unchanged head twice:

```bash
python3 scripts/sourcebraid.py index migrate-shards \
  --expected-head "HEAD_SHA" \
  --confirm-head "HEAD_SHA" \
  --json
```

If the branch moved, preview again and request confirmation again. The migration creates stable URL-hash shards and updates the branch in one non-forced Git commit.

## Guardrails

- Keep `search.sqlite3` local; never commit it to the archive.
- Do not browse the public web as a substitute for an unavailable private archive.
- Do not run `migrate-shards` from an earlier preview or without fresh explicit confirmation.
- If authentication fails, report the exact error and suggest checking the fine-grained token or `gh auth status`.

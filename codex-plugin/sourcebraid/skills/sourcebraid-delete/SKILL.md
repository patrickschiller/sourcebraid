---
name: sourcebraid-delete
description: Safely list, preview, and delete Markdown clips from a configured private SourceBraid GitHub repository. Use when the user asks to remove, delete, clean up, or inspect deletion candidates in their SourceBraid archive. Always require a fresh deletion preview and a new explicit confirmation before writing to GitHub.
---

# SourceBraid Delete

Delete one saved clip at a time through the bundled deterministic CLI. Treat the configured GitHub repository as the source of truth without changing the active Codex workspace.

## Commands

Run commands from the plugin root:

```bash
python3 scripts/sourcebraid.py status
python3 scripts/sourcebraid.py list "<query>" --refresh
python3 scripts/sourcebraid.py plan-delete --path "<repo-path>" --json
python3 scripts/sourcebraid.py delete \
  --path "<repo-path>" \
  --expected-head "<head-sha>" \
  --confirm-path "<repo-path>" \
  --json
```

## Required workflow

1. Run `status` before the first archive operation in a thread.
2. Run `list "<query>" --refresh` to show current candidates. Use `--tag`, `--source`, `--limit`, or `--json` when useful.
3. If more than one candidate matches, ask the user to choose one exact repository path. Do not infer a choice.
4. Run `plan-delete --path "<repo-path>" --json` for that exact path.
5. Show the title, URL, repository, branch, Markdown path, index change, every asset target, and every warning from the preview.
6. Ask whether to delete exactly the displayed targets. End the turn without calling `delete`.
7. Accept only a new, unambiguous confirmation sent after the preview. The original deletion request, an earlier general approval, silence, or an unrelated "continue" is not confirmation.
8. After confirmation, pass the preview's unchanged `path` and `head_sha` to `delete`, repeating the path as `--confirm-path`.
9. Report the resulting commit URL and deleted paths. Explain that Git history can restore the commit.

## Guardrails

- Never call GitHub deletion endpoints directly; use the bundled `delete` command.
- Never edit or delete files in the active workspace as a substitute for deleting the configured archive entry.
- Never delete more than one clip per confirmation.
- Never select legacy `index.jsonl`, a metadata shard under `index/`, or a path outside the configured `root_folder` as the clip.
- Include assets only when `plan-delete` lists them. Do not infer additional directories or files.
- If the branch head changed, rerun `plan-delete`, show the new preview, and request confirmation again.
- If the index contains duplicate entries for the path or the repository tree is truncated, stop and report the exact error.
- If authentication fails, suggest checking the fine-grained token's `Contents: Read and write` permission or `gh auth status`.

The CLI performs the index update and all file deletions in one non-forced Git commit. Matching `--expected-head` and `--confirm-path` values are mandatory even after conversational confirmation.

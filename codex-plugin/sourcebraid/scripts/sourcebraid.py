#!/usr/bin/env python3
"""Search and safely manage a GitHub-backed Markdown archive captured by SourceBraid."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any


CONFIG_PATH = Path.home() / ".config" / "sourcebraid" / "config.json"
CACHE_ROOT = Path.home() / ".cache" / "sourcebraid"
INDEX_SCHEMA_VERSION = 1
INDEX_DB_NAME = "search.sqlite3"
AUTO_REFRESH_SECONDS = 15 * 60


@dataclass
class Config:
    owner: str
    repo: str
    branch: str
    root_folder: str
    token: str

    @property
    def repo_slug(self) -> str:
        return f"{self.owner}/{self.repo}"

    @property
    def cache_dir(self) -> Path:
        return CACHE_ROOT / self.owner / self.repo / self.branch

    @property
    def index_db(self) -> Path:
        return self.cache_dir / INDEX_DB_NAME


@dataclass
class DeletePlan:
    repo: str
    branch: str
    head_sha: str
    base_tree_sha: str
    path: str
    title: str
    url: str
    indexed: bool
    index_path: str
    targets: list[str]
    warnings: list[str]
    next_index_text: str | None

    def public_dict(self) -> dict[str, object]:
        return {
            "repo": self.repo,
            "branch": self.branch,
            "head_sha": self.head_sha,
            "path": self.path,
            "title": self.title,
            "url": self.url,
            "indexed": self.indexed,
            "index_path": self.index_path if self.indexed else None,
            "targets": self.targets,
            "warnings": self.warnings,
            "confirmation": f"DELETE {self.path}",
        }


@dataclass
class ShardMigrationPlan:
    repo: str
    branch: str
    head_sha: str
    base_tree_sha: str
    legacy_path: str
    entry_count: int
    shard_texts: dict[str, str]
    residual_legacy_text: str
    warnings: list[str]

    def public_dict(self) -> dict[str, object]:
        return {
            "repo": self.repo,
            "branch": self.branch,
            "head_sha": self.head_sha,
            "legacy_path": self.legacy_path,
            "entries": self.entry_count,
            "shards": len(self.shard_texts),
            "targets": sorted(self.shard_texts),
            "legacy_action": "keep residual lines" if self.residual_legacy_text else "delete",
            "warnings": self.warnings,
            "confirmation": f"MIGRATE {self.head_sha}",
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    add_config_flags(subparsers.add_parser("status", help="Print resolved configuration and cache status."))
    add_config_flags(subparsers.add_parser("sync", help="Incrementally refresh the local cache and search index."))

    index_parser = subparsers.add_parser("index", help="Build, update, inspect, or verify the local search index.")
    index_subparsers = index_parser.add_subparsers(dest="index_command", required=True)
    for command, help_text in (
        ("status", "Show local index state."),
        ("build", "Create the index from a repository snapshot."),
        ("update", "Apply repository changes since the indexed commit."),
        ("verify", "Check cache, metadata, and SQLite consistency."),
        ("rebuild", "Replace the local cache and index from a fresh snapshot."),
        ("plan-shards", "Preview migration of legacy index.jsonl into stable URL-hash shards."),
        ("migrate-shards", "Apply a previewed metadata-shard migration atomically."),
    ):
        command_parser = index_subparsers.add_parser(command, help=help_text)
        command_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
        if command == "update":
            command_parser.add_argument(
                "--max-age",
                type=int,
                default=0,
                help="Skip the remote check when the last check is newer than this many seconds.",
            )
        if command == "migrate-shards":
            command_parser.add_argument("--expected-head", required=True, help="Head SHA printed by plan-shards.")
            command_parser.add_argument(
                "--confirm-head",
                required=True,
                help="Repeat the exact head SHA to confirm the migration.",
            )
        add_config_flags(command_parser)

    search_parser = subparsers.add_parser("search", help="Search cached Markdown files.")
    search_parser.add_argument("query", help="Search query.")
    search_parser.add_argument("--limit", type=int, default=10, help="Maximum results to print.")
    search_parser.add_argument("--context", type=int, default=2, help="Context lines for rg.")
    search_parser.add_argument("--tag", action="append", default=[], help="Restrict to index entries containing this tag.")
    search_parser.add_argument("--source", help="Restrict to index entries whose source contains this value.")
    search_parser.add_argument("--refresh", action="store_true", help="Refresh cache before searching.")
    search_parser.add_argument(
        "--scan",
        action="store_true",
        help="Bypass SQLite and scan cached Markdown with rg (diagnostic fallback).",
    )
    add_config_flags(search_parser)

    fetch_parser = subparsers.add_parser("fetch", help="Print one cached Markdown source by repo path.")
    fetch_parser.add_argument("path", help="Repository path, for example web-clips/2026/07/example.md")
    fetch_parser.add_argument("--refresh", action="store_true", help="Refresh cache before fetching.")
    add_config_flags(fetch_parser)

    list_parser = subparsers.add_parser("list", help="List Markdown clips and their archive metadata.")
    list_parser.add_argument("query", nargs="?", default="", help="Optional words matched against clip metadata.")
    list_parser.add_argument("--limit", type=int, default=20, help="Maximum clips to print.")
    list_parser.add_argument("--tag", action="append", default=[], help="Restrict to entries containing this tag.")
    list_parser.add_argument("--source", help="Restrict to entries whose source contains this value.")
    list_parser.add_argument("--refresh", action="store_true", help="Refresh cache before listing.")
    list_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    add_config_flags(list_parser)

    plan_delete_parser = subparsers.add_parser(
        "plan-delete",
        help="Preview the exact repository changes for deleting one Markdown clip.",
    )
    plan_delete_parser.add_argument("--path", required=True, help="Exact repository path of the Markdown clip.")
    plan_delete_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    add_config_flags(plan_delete_parser)

    delete_parser = subparsers.add_parser(
        "delete",
        help="Delete one previewed Markdown clip in an atomic Git commit.",
    )
    delete_parser.add_argument("--path", required=True, help="Exact repository path of the Markdown clip.")
    delete_parser.add_argument(
        "--expected-head",
        required=True,
        help="Branch head SHA printed by plan-delete.",
    )
    delete_parser.add_argument(
        "--confirm-path",
        required=True,
        help="Repeat the exact repository path to confirm deletion.",
    )
    delete_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    add_config_flags(delete_parser)

    config_parser = subparsers.add_parser("config", help="Write default repository configuration.")
    config_parser.add_argument("--owner")
    config_parser.add_argument("--repo")
    config_parser.add_argument("--repo-slug", help="Repository as OWNER/REPO.")
    config_parser.add_argument("--branch", default="main")
    config_parser.add_argument("--root-folder", default="web-clips")
    config_parser.add_argument("--token", help="Optional GitHub token. Prefer gh auth or env vars when possible.")
    config_parser.add_argument("--show", action="store_true", help="Print the current config file path and values.")

    args = parser.parse_args()

    try:
        if args.command == "config":
            write_config(args)
            return 0

        config = load_config(args, allow_missing=args.command == "status")

        if args.command == "status":
            print_status(config)
            return 0

        if args.command == "sync":
            print_index_update(update_search_index(config, rebuild=not config.index_db.exists()))
            return 0

        if args.command == "index":
            if args.index_command == "status":
                print_index_status(config, as_json=args.json)
                return 0
            if args.index_command in {"build", "rebuild"}:
                print_index_update(build_search_index(config), as_json=args.json)
                return 0
            if args.index_command == "update":
                result = update_search_index(config, max_age=max(0, args.max_age))
                print_index_update(result, as_json=args.json)
                return 0
            if args.index_command == "verify":
                result = verify_search_index(config)
                print_index_verification(result, as_json=args.json)
                return 0 if result["ok"] else 3
            if args.index_command == "plan-shards":
                print_shard_migration_plan(build_shard_migration_plan(config), as_json=args.json)
                return 0
            if args.index_command == "migrate-shards":
                result = apply_shard_migration(config, args.expected_head, args.confirm_head)
                print_shard_migration_result(result, as_json=args.json)
                return 0
            return 0

        if args.command == "search":
            if args.scan:
                if args.refresh or not has_cached_markdown(config):
                    sync_files_legacy(config, quiet=True)
            elif args.refresh:
                update_search_index(config, rebuild=not config.index_db.exists())
            else:
                maybe_auto_update(config)
            search(config, args)
            return 0

        if args.command == "fetch":
            if args.refresh:
                update_search_index(config, rebuild=not config.index_db.exists())
            fetch(config, args.path)
            return 0

        if args.command == "list":
            if args.refresh:
                update_search_index(config, rebuild=not config.index_db.exists())
            else:
                maybe_auto_update(config, quiet=True)
            list_clips(config, args)
            return 0

        if args.command == "plan-delete":
            print_delete_plan(build_delete_plan(config, args.path), as_json=args.json)
            return 0

        if args.command == "delete":
            result = delete_clip(
                config,
                repo_path=args.path,
                expected_head=args.expected_head,
                confirm_path=args.confirm_path,
            )
            print_delete_result(result, as_json=args.json)
            return 0
    except KnowledgeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    return 1


def add_config_flags(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--owner")
    parser.add_argument("--repo")
    parser.add_argument("--branch")
    parser.add_argument("--root-folder")
    parser.add_argument("--token")


def write_config(args: argparse.Namespace) -> None:
    if args.show:
        if CONFIG_PATH.exists():
            print(CONFIG_PATH.read_text(encoding="utf-8").rstrip())
        else:
            print(f"no config file at {CONFIG_PATH}")
        return

    owner, repo = parse_repo_inputs(args.owner, args.repo, args.repo_slug)
    if not owner or not repo:
        raise KnowledgeError("config requires --repo-slug OWNER/REPO or both --owner OWNER --repo REPO.")

    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    values = {
        "owner": owner,
        "repo": repo,
        "branch": args.branch,
        "root_folder": args.root_folder,
    }
    if args.token:
        values["token"] = args.token

    CONFIG_PATH.write_text(json.dumps(values, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {CONFIG_PATH}")
    print(f"repo: {owner}/{repo}")
    print(f"branch: {args.branch}")
    print(f"root_folder: {args.root_folder}")
    if not args.token:
        print("auth: using GITHUB_TOKEN/GH_TOKEN or gh api fallback")


def load_config(args: argparse.Namespace, allow_missing: bool = False) -> Config:
    file_config: dict[str, str] = {}
    if CONFIG_PATH.exists():
        file_config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))

    cli_owner, cli_repo = parse_repo_inputs(
        getattr(args, "owner", None),
        getattr(args, "repo", None),
        getattr(args, "repo_slug", None),
    )
    owner = first_value(cli_owner, os.environ.get("SOURCEBRAID_OWNER"), file_config.get("owner"))
    repo = first_value(cli_repo, os.environ.get("SOURCEBRAID_REPO"), file_config.get("repo"))
    branch = first_value(args.branch, os.environ.get("SOURCEBRAID_BRANCH"), file_config.get("branch"), "main")
    root_folder = first_value(
        args.root_folder,
        os.environ.get("SOURCEBRAID_ROOT"),
        file_config.get("root_folder"),
        "web-clips",
    ).strip("/")
    token = first_value(args.token, os.environ.get("GITHUB_TOKEN"), os.environ.get("GH_TOKEN"), file_config.get("token"), "")

    missing = [name for name, value in {"owner": owner, "repo": repo}.items() if not value]
    if missing:
        if allow_missing:
            return Config(owner="", repo="", branch=branch, root_folder=root_folder, token=token)
        raise KnowledgeError(
            f"missing {', '.join(missing)}. Run `sourcebraid.py config --repo-slug OWNER/REPO` first."
        )

    return Config(owner=owner, repo=repo, branch=branch, root_folder=root_folder, token=token)


def parse_repo_inputs(owner: str | None, repo: str | None, repo_slug: str | None) -> tuple[str, str]:
    if repo_slug:
        parts = repo_slug.strip().split("/", 1)
        if len(parts) != 2 or not parts[0] or not parts[1]:
            raise KnowledgeError("--repo-slug must use OWNER/REPO.")
        return parts[0], parts[1]

    if owner and "/" in owner and not repo:
        parts = owner.strip().split("/", 1)
        if len(parts) == 2 and parts[0] and parts[1]:
            return parts[0], parts[1]

    return owner or "", repo or ""


def print_status(config: Config) -> None:
    print(f"config_path: {CONFIG_PATH}")
    if not config.owner or not config.repo:
        print("configured: no")
        print("setup: python3 scripts/sourcebraid.py config --repo-slug OWNER/REPO --branch main --root-folder web-clips")
        return

    print("configured: yes")
    print(f"repo: {config.repo_slug}")
    print(f"branch: {config.branch}")
    print(f"root_folder: {config.root_folder}")
    print(f"cache_dir: {config.cache_dir}")
    print(f"cached_markdown: {'yes' if has_cached_markdown(config) else 'no'}")
    print(f"search_index: {'yes' if config.index_db.exists() else 'no'}")
    if config.index_db.exists():
        state = index_status_payload(config)
        print(f"indexed_documents: {state['documents']}")
        print(f"indexed_head: {state['indexed_head']}")
    print(f"auth: {'token' if config.token else 'gh api fallback'}")


def first_value(*values: str | None) -> str:
    for value in values:
        if value:
            return str(value)
    return ""


def sync_files_legacy(config: Config, quiet: bool = False) -> None:
    """Compatibility scan path used only by the explicit --scan fallback."""
    root_cache = cache_path(config, config.root_folder)
    if root_cache.exists():
        shutil.rmtree(root_cache)
    config.cache_dir.mkdir(parents=True, exist_ok=True)
    tree = github_json(config, f"/repos/{config.repo_slug}/git/trees/{url_quote(config.branch)}?recursive=1")
    paths = [
        item["path"]
        for item in tree.get("tree", [])
        if item.get("type") == "blob"
        and item.get("path", "").startswith(f"{config.root_folder}/")
        and is_archive_text_path(config, str(item["path"]))
    ]

    if not paths:
        raise KnowledgeError(f"no Markdown clips found under {config.root_folder!r} in {config.repo_slug}.")

    for repo_path in paths:
        content = github_json(config, f"/repos/{config.repo_slug}/contents/{url_path(repo_path)}?ref={url_quote(config.branch)}")
        text = decode_github_content(content)
        local_path = cache_path(config, repo_path)
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_text(text, encoding="utf-8")

    if not quiet:
        print(f"synced {len(paths)} files to {config.cache_dir}")


def sync(config: Config, quiet: bool = False) -> None:
    """Backward-compatible direct-call wrapper for the explicit scan cache sync."""
    sync_files_legacy(config, quiet=quiet)


def is_metadata_index_path(config: Config, repo_path: str) -> bool:
    legacy = f"{config.root_folder}/index.jsonl"
    shard_prefix = f"{config.root_folder}/index/"
    return repo_path == legacy or (repo_path.startswith(shard_prefix) and repo_path.endswith(".jsonl"))


def is_archive_text_path(config: Config, repo_path: str) -> bool:
    return repo_path.startswith(f"{config.root_folder}/") and (
        repo_path.endswith(".md") or is_metadata_index_path(config, repo_path)
    )


def remote_text_inventory(config: Config, tree_payload: dict[str, object]) -> dict[str, str]:
    if tree_payload.get("truncated"):
        raise KnowledgeError("GitHub returned a truncated repository tree; refusing to build an incomplete index.")
    inventory: dict[str, str] = {}
    for item in tree_payload.get("tree", []):
        if not isinstance(item, dict) or item.get("type") != "blob":
            continue
        path = str(item.get("path") or "")
        sha = str(item.get("sha") or "")
        if sha and is_archive_text_path(config, path):
            inventory[path] = sha
    return inventory


def download_repository_texts(config: Config, ref: str) -> dict[str, str]:
    """Download one GitHub tarball and retain only Markdown and JSONL index files."""
    config.cache_dir.mkdir(parents=True, exist_ok=True)
    archive_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(prefix="sourcebraid-", suffix=".tar.gz", delete=False) as archive:
            archive_path = Path(archive.name)
            github_download(config, f"/repos/{config.repo_slug}/tarball/{url_quote(ref)}", archive)

        texts: dict[str, str] = {}
        with tarfile.open(archive_path, mode="r:gz") as tar:
            for member in tar:
                if not member.isfile() or "/" not in member.name:
                    continue
                repo_path = member.name.split("/", 1)[1]
                if not is_archive_text_path(config, repo_path):
                    continue
                if member.size > 50 * 1024 * 1024:
                    raise KnowledgeError(f"archive text file is unexpectedly large: {repo_path}")
                extracted = tar.extractfile(member)
                if extracted is not None:
                    texts[repo_path] = extracted.read().decode("utf-8", errors="replace")
        return texts
    except (OSError, tarfile.TarError) as error:
        raise KnowledgeError(f"could not read repository snapshot: {error}") from error
    finally:
        if archive_path is not None:
            archive_path.unlink(missing_ok=True)


def github_download(config: Config, path: str, destination: Any) -> None:
    if config.token:
        request = urllib.request.Request(
            f"https://api.github.com{path}",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {config.token}",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "sourcebraid-codex-plugin",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                shutil.copyfileobj(response, destination)
            return
        except (urllib.error.HTTPError, urllib.error.URLError) as error:
            raise KnowledgeError(f"GitHub snapshot download failed for {path}: {error}") from error

    gh = shutil.which("gh")
    if not gh:
        raise KnowledgeError("no token configured and GitHub CLI `gh` is not available.")
    completed = subprocess.run([gh, "api", path], stdout=destination, stderr=subprocess.PIPE, check=False)
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", errors="replace").strip()
        raise KnowledgeError(message or f"gh api snapshot download failed for {path}")


def connect_search_index(config: Config, create: bool = False) -> sqlite3.Connection:
    if not create and not config.index_db.exists():
        raise KnowledgeError("local search index is missing. Run `python3 scripts/sourcebraid.py index build` first.")
    config.cache_dir.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(config.index_db)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")
    if create:
        initialize_search_schema(connection)
    return connection


def initialize_search_schema(connection: sqlite3.Connection) -> None:
    try:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS files (
                path TEXT PRIMARY KEY,
                blob_sha TEXT NOT NULL,
                kind TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS documents (
                id INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                blob_sha TEXT NOT NULL,
                title TEXT NOT NULL,
                url TEXT NOT NULL,
                captured_date TEXT NOT NULL,
                source TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                tags_search TEXT NOT NULL,
                asset_count INTEGER NOT NULL DEFAULT 0,
                body TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
                title, url, source, tags_search, body,
                content='documents', content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE TRIGGER IF NOT EXISTS documents_ai AFTER INSERT ON documents BEGIN
                INSERT INTO documents_fts(rowid, title, url, source, tags_search, body)
                VALUES (new.id, new.title, new.url, new.source, new.tags_search, new.body);
            END;
            CREATE TRIGGER IF NOT EXISTS documents_ad AFTER DELETE ON documents BEGIN
                INSERT INTO documents_fts(documents_fts, rowid, title, url, source, tags_search, body)
                VALUES ('delete', old.id, old.title, old.url, old.source, old.tags_search, old.body);
            END;
            CREATE TRIGGER IF NOT EXISTS documents_au AFTER UPDATE ON documents BEGIN
                INSERT INTO documents_fts(documents_fts, rowid, title, url, source, tags_search, body)
                VALUES ('delete', old.id, old.title, old.url, old.source, old.tags_search, old.body);
                INSERT INTO documents_fts(rowid, title, url, source, tags_search, body)
                VALUES (new.id, new.title, new.url, new.source, new.tags_search, new.body);
            END;
            """
        )
    except sqlite3.OperationalError as error:
        connection.close()
        raise KnowledgeError(f"SQLite FTS5 is required to build the SourceBraid index: {error}") from error


def set_index_state(connection: sqlite3.Connection, key: str, value: object) -> None:
    connection.execute(
        "INSERT INTO state(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, str(value)),
    )


def get_index_state(connection: sqlite3.Connection, key: str, default: str = "") -> str:
    row = connection.execute("SELECT value FROM state WHERE key = ?", (key,)).fetchone()
    return str(row["value"]) if row else default


def write_cached_text(config: Config, repo_path: str, text: str) -> None:
    local_path = cache_path(config, repo_path)
    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_text(text, encoding="utf-8")


def index_entries_by_path(config: Config) -> dict[str, dict[str, object]]:
    entries: dict[str, dict[str, object]] = {}
    for entry in load_index(config):
        path = entry.get("path")
        if isinstance(path, str) and path:
            entries[path] = entry
    return entries


def upsert_document(
    connection: sqlite3.Connection,
    repo_path: str,
    blob_sha: str,
    body: str,
    metadata: dict[str, object] | None = None,
) -> None:
    values = metadata or parse_frontmatter(body)
    tags = normalize_tags(values.get("tags"))
    title = str(values.get("title") or PurePosixPath(repo_path).stem)
    url = str(values.get("url") or "")
    captured_date = str(values.get("date") or values.get("capture_date") or values.get("captured_at") or "")
    source = str(values.get("source") or values.get("site") or "")
    tags_json = json.dumps(tags, ensure_ascii=False, separators=(",", ":"))
    tags_search = "\n" + "\n".join(tag.casefold() for tag in tags) + "\n"
    asset_count = len(referenced_asset_paths(values))
    connection.execute(
        """
        INSERT INTO documents(
            path, blob_sha, title, url, captured_date, source,
            tags_json, tags_search, asset_count, body
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            blob_sha=excluded.blob_sha,
            title=excluded.title,
            url=excluded.url,
            captured_date=excluded.captured_date,
            source=excluded.source,
            tags_json=excluded.tags_json,
            tags_search=excluded.tags_search,
            asset_count=excluded.asset_count,
            body=excluded.body
        """,
        (repo_path, blob_sha, title, url, captured_date, source, tags_json, tags_search, asset_count, body),
    )


def build_search_index(config: Config) -> dict[str, object]:
    head_sha, _tree_sha, tree_payload = repository_snapshot(config)
    inventory = remote_text_inventory(config, tree_payload)
    if not any(path.endswith(".md") for path in inventory):
        raise KnowledgeError(f"no Markdown clips found under {config.root_folder!r} in {config.repo_slug}.")

    try:
        texts = download_repository_texts(config, head_sha)
    except KnowledgeError as snapshot_error:
        print(f"warning: {snapshot_error}; falling back to per-file GitHub reads", file=sys.stderr)
        texts = {}
    for repo_path in inventory:
        if repo_path not in texts:
            texts[repo_path] = repository_text(config, repo_path, head_sha)

    root_cache = cache_path(config, config.root_folder)
    if root_cache.exists():
        shutil.rmtree(root_cache)
    for repo_path, text in texts.items():
        if repo_path in inventory:
            write_cached_text(config, repo_path, text)

    config.index_db.unlink(missing_ok=True)
    Path(f"{config.index_db}-wal").unlink(missing_ok=True)
    Path(f"{config.index_db}-shm").unlink(missing_ok=True)
    connection = connect_search_index(config, create=True)
    metadata = index_entries_by_path(config)
    try:
        with connection:
            for repo_path, blob_sha in inventory.items():
                kind = "markdown" if repo_path.endswith(".md") else "metadata"
                connection.execute(
                    "INSERT INTO files(path, blob_sha, kind) VALUES (?, ?, ?)",
                    (repo_path, blob_sha, kind),
                )
                if kind == "markdown":
                    upsert_document(connection, repo_path, blob_sha, texts[repo_path], metadata.get(repo_path))
            set_index_state(connection, "schema_version", INDEX_SCHEMA_VERSION)
            set_index_state(connection, "indexed_head", head_sha)
            set_index_state(connection, "checked_at", int(time.time()))
        document_count = int(connection.execute("SELECT COUNT(*) FROM documents").fetchone()[0])
    finally:
        connection.close()
    return {
        "action": "built",
        "head_sha": head_sha,
        "documents": document_count,
        "downloaded": len(inventory),
        "deleted": 0,
        "index_db": str(config.index_db),
    }


def update_search_index(
    config: Config,
    rebuild: bool = False,
    max_age: int = 0,
) -> dict[str, object]:
    if rebuild or not config.index_db.exists():
        return build_search_index(config)

    connection = connect_search_index(config)
    try:
        checked_at = int(get_index_state(connection, "checked_at", "0") or 0)
        if max_age and time.time() - checked_at < max_age:
            return {
                "action": "skipped",
                "head_sha": get_index_state(connection, "indexed_head"),
                "documents": int(connection.execute("SELECT COUNT(*) FROM documents").fetchone()[0]),
                "downloaded": 0,
                "deleted": 0,
                "index_db": str(config.index_db),
            }

        head_sha, _tree_sha, tree_payload = repository_snapshot(config)
        inventory = remote_text_inventory(config, tree_payload)
        indexed_head = get_index_state(connection, "indexed_head")
        if head_sha == indexed_head:
            with connection:
                set_index_state(connection, "checked_at", int(time.time()))
            return {
                "action": "current",
                "head_sha": head_sha,
                "documents": int(connection.execute("SELECT COUNT(*) FROM documents").fetchone()[0]),
                "downloaded": 0,
                "deleted": 0,
                "index_db": str(config.index_db),
            }

        old_files = {
            str(row["path"]): str(row["blob_sha"])
            for row in connection.execute("SELECT path, blob_sha FROM files")
        }
        changed = sorted(path for path, sha in inventory.items() if old_files.get(path) != sha)
        deleted = sorted(set(old_files) - set(inventory))
        old_metadata = index_entries_by_path(config)

        changed_texts: dict[str, str] = {}
        for repo_path in changed:
            text = repository_text(config, repo_path, head_sha)
            changed_texts[repo_path] = text
            write_cached_text(config, repo_path, text)
        for repo_path in deleted:
            cache_path(config, repo_path).unlink(missing_ok=True)

        new_metadata = index_entries_by_path(config)
        metadata_changed = {
            path
            for path in set(old_metadata) | set(new_metadata)
            if old_metadata.get(path) != new_metadata.get(path)
        }
        changed_markdown = {path for path in changed if path.endswith(".md")}
        deleted_markdown = {path for path in deleted if path.endswith(".md")}

        with connection:
            for repo_path in deleted:
                connection.execute("DELETE FROM files WHERE path = ?", (repo_path,))
            for repo_path in deleted_markdown:
                connection.execute("DELETE FROM documents WHERE path = ?", (repo_path,))
            for repo_path in changed:
                kind = "markdown" if repo_path.endswith(".md") else "metadata"
                connection.execute(
                    """
                    INSERT INTO files(path, blob_sha, kind) VALUES (?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET blob_sha=excluded.blob_sha, kind=excluded.kind
                    """,
                    (repo_path, inventory[repo_path], kind),
                )
            for repo_path in sorted((changed_markdown | metadata_changed) - deleted_markdown):
                if repo_path not in inventory or not repo_path.endswith(".md"):
                    continue
                local_path = cache_path(config, repo_path)
                if not local_path.exists():
                    continue
                body = changed_texts.get(repo_path)
                if body is None:
                    body = local_path.read_text(encoding="utf-8", errors="replace")
                upsert_document(connection, repo_path, inventory[repo_path], body, new_metadata.get(repo_path))
            set_index_state(connection, "schema_version", INDEX_SCHEMA_VERSION)
            set_index_state(connection, "indexed_head", head_sha)
            set_index_state(connection, "checked_at", int(time.time()))
        document_count = int(connection.execute("SELECT COUNT(*) FROM documents").fetchone()[0])
        return {
            "action": "updated",
            "previous_head": indexed_head,
            "head_sha": head_sha,
            "documents": document_count,
            "downloaded": len(changed),
            "deleted": len(deleted),
            "index_db": str(config.index_db),
        }
    finally:
        connection.close()


def maybe_auto_update(config: Config, quiet: bool = False) -> None:
    if not config.index_db.exists():
        return
    try:
        update_search_index(config, max_age=AUTO_REFRESH_SECONDS)
    except KnowledgeError as error:
        if not quiet:
            print(f"warning: could not refresh SourceBraid index; using local data: {error}", file=sys.stderr)


def print_index_update(result: dict[str, object], as_json: bool = False) -> None:
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return
    print(f"index: {result['action']}")
    print(f"head_sha: {result.get('head_sha', '')}")
    print(f"documents: {result['documents']}")
    print(f"downloaded: {result['downloaded']}")
    print(f"deleted: {result['deleted']}")
    print(f"index_db: {result['index_db']}")


def index_status_payload(config: Config) -> dict[str, object]:
    payload: dict[str, object] = {
        "exists": config.index_db.exists(),
        "index_db": str(config.index_db),
        "repo": config.repo_slug,
        "branch": config.branch,
    }
    if not config.index_db.exists():
        payload.update({"documents": 0, "indexed_head": "", "checked_at": 0, "schema_version": 0})
        return payload
    connection = connect_search_index(config)
    try:
        payload.update(
            {
                "documents": int(connection.execute("SELECT COUNT(*) FROM documents").fetchone()[0]),
                "indexed_head": get_index_state(connection, "indexed_head"),
                "checked_at": int(get_index_state(connection, "checked_at", "0") or 0),
                "schema_version": int(get_index_state(connection, "schema_version", "0") or 0),
            }
        )
        return payload
    finally:
        connection.close()


def print_index_status(config: Config, as_json: bool = False) -> None:
    payload = index_status_payload(config)
    if as_json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return
    for key, value in payload.items():
        print(f"{key}: {value}")


def verify_search_index(config: Config) -> dict[str, object]:
    connection = connect_search_index(config)
    try:
        integrity = str(connection.execute("PRAGMA integrity_check").fetchone()[0])
        database_paths = {str(row[0]) for row in connection.execute("SELECT path FROM documents")}
        root_cache = cache_path(config, config.root_folder)
        cache_paths = (
            {repo_path_from_cache(config, path) for path in root_cache.rglob("*.md")}
            if root_cache.exists()
            else set()
        )
        entries = load_index(config)
        counts_by_path: dict[str, int] = {}
        counts_by_url: dict[str, int] = {}
        for entry in entries:
            path = str(entry.get("path") or "")
            url = str(entry.get("url") or "")
            if path:
                counts_by_path[path] = counts_by_path.get(path, 0) + 1
            if url:
                counts_by_url[url] = counts_by_url.get(url, 0) + 1
        duplicate_paths = sorted(path for path, count in counts_by_path.items() if count > 1)
        duplicate_urls = sorted(url for url, count in counts_by_url.items() if count > 1)
        orphaned_metadata = sorted(path for path in counts_by_path if path not in cache_paths)
        result: dict[str, object] = {
            "ok": (
                integrity == "ok"
                and database_paths == cache_paths
                and not duplicate_paths
                and not duplicate_urls
                and not orphaned_metadata
            ),
            "integrity": integrity,
            "documents": len(database_paths),
            "missing_cache": sorted(database_paths - cache_paths),
            "unindexed_cache": sorted(cache_paths - database_paths),
            "duplicate_paths": duplicate_paths,
            "duplicate_urls": duplicate_urls,
            "orphaned_metadata": orphaned_metadata,
        }
        return result
    finally:
        connection.close()


def print_index_verification(result: dict[str, object], as_json: bool = False) -> None:
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return
    print(f"ok: {'yes' if result['ok'] else 'no'}")
    print(f"integrity: {result['integrity']}")
    print(f"documents: {result['documents']}")
    for key in ("missing_cache", "unindexed_cache", "duplicate_paths", "duplicate_urls", "orphaned_metadata"):
        values = result[key]
        print(f"{key}: {len(values)}")
        for value in values[:20]:
            print(f"  - {value}")


def search(config: Config, args: argparse.Namespace) -> None:
    if not args.scan:
        records = search_index_records(config, args.query, args.tag, args.source, args.limit)
        if not records:
            print("No matches.")
            return
        for record in records:
            print_index_result(record)
        return

    allowed = allowed_paths(config, args.tag, args.source)
    matches = run_rg(config, args.query, args.context)
    printed = 0

    for match in matches:
        repo_path = repo_path_from_cache(config, Path(match["path"]))
        if allowed is not None and repo_path not in allowed:
            continue

        meta = metadata_for(config, repo_path)
        print_result(repo_path, meta, match)
        printed += 1
        if printed >= args.limit:
            break

    if printed == 0:
        print("No matches.")


def fts_query(value: str) -> str:
    terms = re.findall(r"[^\W_]+(?:[-'][^\W_]+)*", value, flags=re.UNICODE)
    if not terms:
        raise KnowledgeError("search query must contain at least one word or number.")
    return " AND ".join('"' + term.replace('"', '""') + '"' for term in terms)


def search_index_records(
    config: Config,
    query: str,
    tags: list[str] | None = None,
    source: str | None = None,
    limit: int = 10,
) -> list[dict[str, object]]:
    if limit < 1:
        raise KnowledgeError("--limit must be at least 1.")
    connection = connect_search_index(config)
    try:
        conditions = ["documents_fts MATCH ?"]
        parameters: list[object] = [fts_query(query)]
        for tag in tags or []:
            conditions.append("instr(documents.tags_search, ?) > 0")
            parameters.append(f"\n{tag.casefold()}\n")
        if source:
            conditions.append("lower(documents.source) LIKE ?")
            parameters.append(f"%{source.casefold()}%")
        parameters.append(limit)
        rows = connection.execute(
            f"""
            SELECT
                documents.path,
                documents.title,
                documents.url,
                documents.captured_date,
                documents.source,
                documents.tags_json,
                documents.asset_count,
                bm25(documents_fts, 8.0, 3.0, 4.0, 5.0, 1.0) AS rank,
                snippet(documents_fts, 4, '[', ']', ' … ', 32) AS excerpt
            FROM documents_fts
            JOIN documents ON documents.id = documents_fts.rowid
            WHERE {' AND '.join(conditions)}
            ORDER BY rank, documents.captured_date DESC, documents.path
            LIMIT ?
            """,
            parameters,
        ).fetchall()
        return [
            {
                "path": str(row["path"]),
                "title": str(row["title"]),
                "url": str(row["url"]),
                "date": str(row["captured_date"]),
                "source": str(row["source"]),
                "tags": json.loads(str(row["tags_json"])),
                "asset_count": int(row["asset_count"]),
                "rank": float(row["rank"]),
                "excerpt": str(row["excerpt"]),
            }
            for row in rows
        ]
    except sqlite3.OperationalError as error:
        raise KnowledgeError(f"search index query failed: {error}") from error
    finally:
        connection.close()


def print_index_result(record: dict[str, object]) -> None:
    print(f"## {record['title']}")
    print(f"path: {record['path']}")
    if record.get("url"):
        print(f"url: {record['url']}")
    if record.get("source"):
        print(f"source: {record['source']}")
    if record.get("tags"):
        print(f"tags: {', '.join(str(tag) for tag in record['tags'])}")
    print(textwrap.indent(str(record.get("excerpt") or "").strip(), "  "))
    print()


def fetch(config: Config, repo_path: str) -> None:
    path = cache_path(config, repo_path)
    if not path.exists():
        if config.index_db.exists():
            update_search_index(config)

    if not path.exists():
        normalized = validate_clip_path(config, repo_path)
        text = repository_text(config, normalized, current_branch_head(config))
        print(text)
        return

    print(path.read_text(encoding="utf-8"))


def list_clips(config: Config, args: argparse.Namespace) -> None:
    if args.limit < 1:
        raise KnowledgeError("--limit must be at least 1.")

    records = list_clip_records(config, args.query, args.tag, args.source, limit=args.limit)
    if args.json:
        print(json.dumps(records, indent=2, ensure_ascii=False))
        return

    if not records:
        print("No clips found.")
        return

    for number, record in enumerate(records, start=1):
        print(f"{number}. {record['title']}")
        print(f"   path: {record['path']}")
        if record["url"]:
            print(f"   url: {record['url']}")
        details = [str(record["status"])]
        if record["date"]:
            details.append(str(record["date"]))
        if record["source"]:
            details.append(str(record["source"]))
        details.append(f"assets: {record['asset_count']}")
        print(f"   metadata: {', '.join(details)}")
        if record["tags"]:
            print(f"   tags: {', '.join(str(tag) for tag in record['tags'])}")


def list_clip_records(
    config: Config,
    query: str = "",
    tags: list[str] | None = None,
    source: str | None = None,
    limit: int | None = None,
) -> list[dict[str, object]]:
    if config.index_db.exists():
        return list_index_records(config, query, tags, source, limit=limit)

    index_by_path: dict[str, dict[str, object]] = {}
    for entry in load_index(config):
        entry_path = entry.get("path")
        if isinstance(entry_path, str) and entry_path not in index_by_path:
            index_by_path[entry_path] = entry

    wanted_terms = query.casefold().split()
    wanted_tags = {tag.casefold() for tag in (tags or [])}
    wanted_source = source.casefold() if source else ""
    records: list[dict[str, object]] = []

    for local_path in sorted(config.cache_dir.rglob("*.md")):
        repo_path = repo_path_from_cache(config, local_path)
        entry = index_by_path.get(repo_path)
        metadata = entry or parse_frontmatter(local_path.read_text(encoding="utf-8", errors="replace"))
        entry_tags = normalize_tags(metadata.get("tags"))
        entry_source = str(metadata.get("source") or metadata.get("site") or "")
        title = str(metadata.get("title") or local_path.stem)
        url = str(metadata.get("url") or "")
        date = str(metadata.get("date") or metadata.get("captured_at") or "")
        haystack = " ".join([title, url, repo_path, entry_source, " ".join(entry_tags)]).casefold()

        if wanted_terms and not all(term in haystack for term in wanted_terms):
            continue
        if wanted_tags and not wanted_tags.issubset({tag.casefold() for tag in entry_tags}):
            continue
        if wanted_source and wanted_source not in entry_source.casefold():
            continue

        records.append(
            {
                "title": title,
                "url": url,
                "date": date,
                "tags": entry_tags,
                "source": entry_source,
                "path": repo_path,
                "status": "indexed" if entry else "orphaned",
                "asset_count": len(referenced_asset_paths(entry or {})),
            }
        )

    records.sort(key=lambda item: (str(item["date"]), str(item["path"])), reverse=True)
    return records[:limit] if limit is not None else records


def list_index_records(
    config: Config,
    query: str = "",
    tags: list[str] | None = None,
    source: str | None = None,
    limit: int | None = None,
) -> list[dict[str, object]]:
    connection = connect_search_index(config)
    try:
        conditions: list[str] = []
        parameters: list[object] = []
        for term in query.casefold().split():
            conditions.append(
                "lower(documents.title || ' ' || documents.url || ' ' || documents.path || ' ' || "
                "documents.source || ' ' || documents.tags_search) LIKE ?"
            )
            parameters.append(f"%{term}%")
        for tag in tags or []:
            conditions.append("instr(documents.tags_search, ?) > 0")
            parameters.append(f"\n{tag.casefold()}\n")
        if source:
            conditions.append("lower(documents.source) LIKE ?")
            parameters.append(f"%{source.casefold()}%")
        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        limit_clause = " LIMIT ?" if limit is not None else ""
        if limit is not None:
            parameters.append(limit)
        rows = connection.execute(
            f"""
            SELECT path, title, url, captured_date, source, tags_json, asset_count
            FROM documents
            {where}
            ORDER BY captured_date DESC, path DESC
            {limit_clause}
            """,
            parameters,
        ).fetchall()
        return [
            {
                "title": str(row["title"]),
                "url": str(row["url"]),
                "date": str(row["captured_date"]),
                "tags": json.loads(str(row["tags_json"])),
                "source": str(row["source"]),
                "path": str(row["path"]),
                "status": "indexed",
                "asset_count": int(row["asset_count"]),
            }
            for row in rows
        ]
    finally:
        connection.close()


def normalize_tags(value: object) -> list[str]:
    if isinstance(value, list):
        return [str(tag) for tag in value if str(tag).strip()]
    if isinstance(value, str):
        stripped = value.strip().strip("[]")
        if not stripped:
            return []
        return [part.strip().strip("\"'") for part in stripped.split(",") if part.strip()]
    return []


def referenced_asset_paths(entry: dict[str, object]) -> list[str]:
    paths: list[str] = []
    pdf_path = entry.get("pdf_path")
    if isinstance(pdf_path, str) and pdf_path:
        paths.append(pdf_path)

    images = entry.get("images")
    if isinstance(images, list):
        for image in images:
            if isinstance(image, dict) and isinstance(image.get("path"), str) and image["path"]:
                paths.append(str(image["path"]))

    return list(dict.fromkeys(paths))


def url_hash(value: str) -> str:
    """Match SourceBraidCore.urlHash, including JavaScript UTF-16 code-unit semantics."""
    result = 0x811C9DC5
    encoded = str(value or "").encode("utf-16-le", errors="surrogatepass")
    for offset in range(0, len(encoded), 2):
        unit = encoded[offset] | (encoded[offset + 1] << 8)
        result ^= unit
        result = (result * 0x01000193) & 0xFFFFFFFF
    return f"{result:08x}"[:6]


def metadata_shard_path(config: Config, url: str) -> str:
    return f"{config.root_folder}/index/{url_hash(url)[:2]}.jsonl"


def merge_index_entries(existing_text: str, entries: list[dict[str, object]]) -> str:
    replaced_paths = {str(entry.get("path") or "") for entry in entries}
    replaced_urls = {str(entry.get("url") or "") for entry in entries}
    output: list[str] = []
    for line in existing_text.splitlines():
        if not line.strip():
            continue
        try:
            existing = json.loads(line)
        except json.JSONDecodeError:
            output.append(line)
            continue
        if not isinstance(existing, dict):
            output.append(line)
            continue
        if str(existing.get("path") or "") in replaced_paths or str(existing.get("url") or "") in replaced_urls:
            continue
        output.append(json.dumps(existing, ensure_ascii=False, separators=(",", ":")))
    output.extend(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) for entry in entries)
    return "\n".join(output).rstrip() + "\n"


def build_shard_migration_plan(config: Config) -> ShardMigrationPlan:
    head_sha, base_tree_sha, tree_payload = repository_snapshot(config)
    if tree_payload.get("truncated"):
        raise KnowledgeError("GitHub returned a truncated repository tree; refusing to migrate metadata shards.")
    tree_paths = {
        str(item.get("path"))
        for item in tree_payload.get("tree", [])
        if isinstance(item, dict) and item.get("type") == "blob" and item.get("path")
    }
    legacy_path = f"{config.root_folder}/index.jsonl"
    if legacy_path not in tree_paths:
        raise KnowledgeError("legacy index.jsonl is not present; metadata is already sharded or the archive has no index.")

    legacy_text = repository_text(config, legacy_path, head_sha)
    grouped: dict[str, list[dict[str, object]]] = {}
    residual: list[str] = []
    warnings: list[str] = []
    entry_count = 0
    for number, line in enumerate(legacy_text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            residual.append(line)
            warnings.append(f"Kept malformed legacy line {number} in index.jsonl.")
            continue
        if not isinstance(entry, dict) or not entry.get("url"):
            residual.append(line)
            warnings.append(f"Kept legacy line {number} without a URL in index.jsonl.")
            continue
        shard_path = metadata_shard_path(config, str(entry["url"]))
        grouped.setdefault(shard_path, []).append(entry)
        entry_count += 1

    shard_texts: dict[str, str] = {}
    for shard_path, entries in grouped.items():
        existing_text = repository_text(config, shard_path, head_sha) if shard_path in tree_paths else ""
        shard_texts[shard_path] = merge_index_entries(existing_text, entries)
    residual_text = "\n".join(residual).rstrip()
    if residual_text:
        residual_text += "\n"
    return ShardMigrationPlan(
        repo=config.repo_slug,
        branch=config.branch,
        head_sha=head_sha,
        base_tree_sha=base_tree_sha,
        legacy_path=legacy_path,
        entry_count=entry_count,
        shard_texts=shard_texts,
        residual_legacy_text=residual_text,
        warnings=warnings,
    )


def print_shard_migration_plan(plan: ShardMigrationPlan, as_json: bool = False) -> None:
    payload = plan.public_dict()
    if as_json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return
    print(f"Metadata shard migration for {plan.repo}:{plan.branch}")
    print(f"head_sha: {plan.head_sha}")
    print(f"entries: {plan.entry_count}")
    print(f"shards: {len(plan.shard_texts)}")
    print(f"legacy_action: {payload['legacy_action']}")
    for warning in plan.warnings:
        print(f"warning: {warning}")
    print(f"confirmation: MIGRATE {plan.head_sha}")


def apply_shard_migration(config: Config, expected_head: str, confirm_head: str) -> dict[str, object]:
    if confirm_head != expected_head:
        raise KnowledgeError("--confirm-head must exactly match --expected-head; no repository changes were made.")
    plan = build_shard_migration_plan(config)
    if plan.head_sha != expected_head:
        raise KnowledgeError(
            f"branch head changed from {expected_head} to {plan.head_sha}; run plan-shards again and reconfirm."
        )
    if not plan.shard_texts:
        raise KnowledgeError("legacy index.jsonl contains no shardable entries; no repository changes were made.")

    tree_entries: list[dict[str, object]] = []
    for shard_path, shard_text in sorted(plan.shard_texts.items()):
        blob = github_json_request(
            config,
            f"/repos/{config.repo_slug}/git/blobs",
            method="POST",
            payload={"content": shard_text, "encoding": "utf-8"},
        )
        if not blob.get("sha"):
            raise KnowledgeError(f"GitHub did not return a blob SHA for {shard_path}.")
        tree_entries.append(
            {"path": shard_path, "mode": "100644", "type": "blob", "sha": str(blob["sha"])}
        )

    if plan.residual_legacy_text:
        legacy_blob = github_json_request(
            config,
            f"/repos/{config.repo_slug}/git/blobs",
            method="POST",
            payload={"content": plan.residual_legacy_text, "encoding": "utf-8"},
        )
        if not legacy_blob.get("sha"):
            raise KnowledgeError("GitHub did not return a blob SHA for the residual legacy index.")
        tree_entries.append(
            {"path": plan.legacy_path, "mode": "100644", "type": "blob", "sha": str(legacy_blob["sha"])}
        )
    else:
        tree_entries.append({"path": plan.legacy_path, "mode": "100644", "type": "blob", "sha": None})

    tree = github_json_request(
        config,
        f"/repos/{config.repo_slug}/git/trees",
        method="POST",
        payload={"base_tree": plan.base_tree_sha, "tree": tree_entries},
    )
    if not tree.get("sha"):
        raise KnowledgeError("GitHub did not return a tree SHA for the shard migration.")
    commit = github_json_request(
        config,
        f"/repos/{config.repo_slug}/git/commits",
        method="POST",
        payload={
            "message": "Migrate SourceBraid metadata to URL-hash shards",
            "tree": str(tree["sha"]),
            "parents": [plan.head_sha],
        },
    )
    commit_sha = str(commit.get("sha") or "")
    if not commit_sha:
        raise KnowledgeError("GitHub did not return a commit SHA for the shard migration.")
    latest_head = current_branch_head(config)
    if latest_head != plan.head_sha:
        raise KnowledgeError(
            f"branch head changed from {plan.head_sha} to {latest_head} before update; the branch was not modified."
        )
    github_json_request(
        config,
        f"/repos/{config.repo_slug}/git/refs/heads/{url_quote(config.branch)}",
        method="PATCH",
        payload={"sha": commit_sha, "force": False},
    )
    if config.index_db.exists():
        connection = connect_search_index(config)
        try:
            with connection:
                set_index_state(connection, "checked_at", 0)
        finally:
            connection.close()
    return {
        "ok": True,
        "commit_sha": commit_sha,
        "commit_url": f"https://github.com/{config.repo_slug}/commit/{commit_sha}",
        "entries": plan.entry_count,
        "shards": len(plan.shard_texts),
        "legacy_kept": bool(plan.residual_legacy_text),
    }


def print_shard_migration_result(result: dict[str, object], as_json: bool = False) -> None:
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return
    print(f"Migrated {result['entries']} entries into {result['shards']} shards.")
    print(f"commit_url: {result['commit_url']}")
    print(f"legacy_kept: {'yes' if result['legacy_kept'] else 'no'}")


def build_delete_plan(config: Config, repo_path: str) -> DeletePlan:
    normalized_path = validate_clip_path(config, repo_path)
    head_sha, base_tree_sha, tree_payload = repository_snapshot(config)
    if tree_payload.get("truncated"):
        raise KnowledgeError("GitHub returned a truncated repository tree; refusing to build an incomplete deletion plan.")

    tree_paths = {
        str(item.get("path"))
        for item in tree_payload.get("tree", [])
        if isinstance(item, dict) and item.get("type") == "blob" and item.get("path")
    }
    if normalized_path not in tree_paths:
        raise KnowledgeError(f"Markdown clip does not exist at branch head {head_sha}: {normalized_path}")

    legacy_index = f"{config.root_folder}/index.jsonl"
    index_path = legacy_index
    index_text = ""
    next_index_text = ""
    matching_entries: list[dict[str, object]] = []
    if legacy_index in tree_paths:
        index_text = repository_text(config, legacy_index, head_sha)
        next_index_text, matching_entries = remove_index_entry(index_text, normalized_path)
        if len(matching_entries) > 1:
            raise KnowledgeError(
                f"{legacy_index} contains {len(matching_entries)} entries for {normalized_path}; repair the index before deleting."
            )

    markdown_text = repository_text(config, normalized_path, head_sha)
    frontmatter = parse_frontmatter(markdown_text)
    frontmatter_url = str(frontmatter.get("url") or "")
    candidate_indexes = [metadata_shard_path(config, frontmatter_url)] if frontmatter_url else []
    for candidate in candidate_indexes:
        if candidate not in tree_paths:
            continue
        candidate_text = repository_text(config, candidate, head_sha)
        candidate_next, candidate_matches = remove_index_entry(candidate_text, normalized_path)
        if candidate_matches:
            if matching_entries:
                raise KnowledgeError(
                    f"metadata indexes contain duplicate entries for {normalized_path}; repair the index before deleting."
                )
            index_path = candidate
            index_text = candidate_text
            next_index_text = candidate_next
            matching_entries = candidate_matches
    if len(matching_entries) > 1:
        raise KnowledgeError(
            f"{index_path} contains {len(matching_entries)} entries for {normalized_path}; repair the index before deleting."
        )

    entry = matching_entries[0] if matching_entries else {}
    title = str(entry.get("title") or frontmatter.get("title") or PurePosixPath(normalized_path).stem)
    url = str(entry.get("url") or frontmatter.get("url") or "")
    warnings: list[str] = []
    asset_targets: list[str] = []
    clip_path = PurePosixPath(normalized_path)
    asset_prefix = (clip_path.parent / "assets" / clip_path.stem).as_posix() + "/"

    for asset_path in referenced_asset_paths(entry):
        try:
            normalized_asset = validate_archive_path(config, asset_path)
        except KnowledgeError as error:
            warnings.append(str(error))
            continue
        if not normalized_asset.startswith(asset_prefix):
            warnings.append(f"Referenced asset is outside the clip asset folder and will be kept: {normalized_asset}")
            continue
        if normalized_asset not in tree_paths:
            warnings.append(f"Referenced asset is already missing and will be skipped: {normalized_asset}")
            continue
        asset_targets.append(normalized_asset)

    targets = [normalized_path, *sorted(set(asset_targets))]
    return DeletePlan(
        repo=config.repo_slug,
        branch=config.branch,
        head_sha=head_sha,
        base_tree_sha=base_tree_sha,
        path=normalized_path,
        title=title,
        url=url,
        indexed=bool(matching_entries),
        index_path=index_path,
        targets=targets,
        warnings=warnings,
        next_index_text=next_index_text if matching_entries else None,
    )


def repository_snapshot(config: Config) -> tuple[str, str, dict[str, object]]:
    ref = github_json(config, f"/repos/{config.repo_slug}/git/ref/heads/{url_quote(config.branch)}")
    ref_object = ref.get("object")
    if not isinstance(ref_object, dict) or not ref_object.get("sha"):
        raise KnowledgeError(f"GitHub returned no head SHA for branch {config.branch!r}.")
    head_sha = str(ref_object["sha"])

    commit = github_json(config, f"/repos/{config.repo_slug}/git/commits/{url_quote(head_sha)}")
    commit_tree = commit.get("tree")
    if not isinstance(commit_tree, dict) or not commit_tree.get("sha"):
        raise KnowledgeError(f"GitHub returned no tree SHA for commit {head_sha}.")
    base_tree_sha = str(commit_tree["sha"])
    tree = github_json(config, f"/repos/{config.repo_slug}/git/trees/{url_quote(base_tree_sha)}?recursive=1")
    return head_sha, base_tree_sha, tree


def current_branch_head(config: Config) -> str:
    ref = github_json(config, f"/repos/{config.repo_slug}/git/ref/heads/{url_quote(config.branch)}")
    ref_object = ref.get("object")
    if not isinstance(ref_object, dict) or not ref_object.get("sha"):
        raise KnowledgeError(f"GitHub returned no head SHA for branch {config.branch!r}.")
    return str(ref_object["sha"])


def repository_text(config: Config, repo_path: str, ref: str) -> str:
    content = github_json(
        config,
        f"/repos/{config.repo_slug}/contents/{url_path(repo_path)}?ref={url_quote(ref)}",
    )
    return decode_github_content(content)


def remove_index_entry(index_text: str, repo_path: str) -> tuple[str, list[dict[str, object]]]:
    kept_lines: list[str] = []
    matching_entries: list[dict[str, object]] = []

    for line in index_text.splitlines(keepends=True):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            kept_lines.append(line)
            continue
        if isinstance(parsed, dict) and parsed.get("path") == repo_path:
            matching_entries.append(parsed)
        else:
            kept_lines.append(line)

    return "".join(kept_lines), matching_entries


def validate_archive_path(config: Config, repo_path: str) -> str:
    if not repo_path or repo_path != repo_path.strip("/"):
        raise KnowledgeError(f"path must be a normalized repository path under {config.root_folder!r}: {repo_path}")
    path = PurePosixPath(repo_path)
    if any(part in {"", ".", ".."} for part in path.parts) or path.as_posix() != repo_path:
        raise KnowledgeError(f"path must not contain traversal or redundant segments: {repo_path}")
    root = PurePosixPath(config.root_folder)
    if path == root or root not in path.parents:
        raise KnowledgeError(f"path must be under {config.root_folder!r}: {repo_path}")
    return path.as_posix()


def validate_clip_path(config: Config, repo_path: str) -> str:
    normalized = validate_archive_path(config, repo_path)
    if PurePosixPath(normalized).suffix.lower() != ".md":
        raise KnowledgeError(f"only Markdown clip paths can be deleted: {repo_path}")
    return normalized


def print_delete_plan(plan: DeletePlan, as_json: bool = False) -> None:
    payload = plan.public_dict()
    if as_json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return

    print(f"Delete preview: {plan.title}")
    print(f"repo: {plan.repo}")
    print(f"branch: {plan.branch}")
    print(f"head_sha: {plan.head_sha}")
    print(f"path: {plan.path}")
    if plan.url:
        print(f"url: {plan.url}")
    print(f"index_entry: {'remove' if plan.indexed else 'not present'}")
    print("targets:")
    for target in plan.targets:
        print(f"  - {target}")
    for warning in plan.warnings:
        print(f"warning: {warning}")
    print(f"confirmation: DELETE {plan.path}")


def delete_clip(
    config: Config,
    repo_path: str,
    expected_head: str,
    confirm_path: str,
) -> dict[str, object]:
    if confirm_path != repo_path:
        raise KnowledgeError("--confirm-path must exactly match --path; no repository changes were made.")

    plan = build_delete_plan(config, repo_path)
    if plan.head_sha != expected_head:
        raise KnowledgeError(
            f"branch head changed from {expected_head} to {plan.head_sha}; run plan-delete again and reconfirm."
        )

    tree_entries: list[dict[str, object]] = []
    if plan.indexed:
        blob = github_json_request(
            config,
            f"/repos/{config.repo_slug}/git/blobs",
            method="POST",
            payload={"content": plan.next_index_text or "", "encoding": "utf-8"},
        )
        blob_sha = blob.get("sha")
        if not blob_sha:
            raise KnowledgeError("GitHub did not return a blob SHA for the updated index.")
        tree_entries.append(
            {"path": plan.index_path, "mode": "100644", "type": "blob", "sha": str(blob_sha)}
        )

    tree_entries.extend(
        {"path": target, "mode": "100644", "type": "blob", "sha": None}
        for target in plan.targets
    )
    tree = github_json_request(
        config,
        f"/repos/{config.repo_slug}/git/trees",
        method="POST",
        payload={"base_tree": plan.base_tree_sha, "tree": tree_entries},
    )
    tree_sha = tree.get("sha")
    if not tree_sha:
        raise KnowledgeError("GitHub did not return a tree SHA for the deletion.")

    commit = github_json_request(
        config,
        f"/repos/{config.repo_slug}/git/commits",
        method="POST",
        payload={
            "message": f"Delete SourceBraid clip: {plan.title}",
            "tree": str(tree_sha),
            "parents": [plan.head_sha],
        },
    )
    commit_sha = commit.get("sha")
    if not commit_sha:
        raise KnowledgeError("GitHub did not return a commit SHA for the deletion.")

    latest_head = current_branch_head(config)
    if latest_head != plan.head_sha:
        raise KnowledgeError(
            f"branch head changed from {plan.head_sha} to {latest_head} before update; "
            "the branch was not modified. Run plan-delete again and reconfirm."
        )

    github_json_request(
        config,
        f"/repos/{config.repo_slug}/git/refs/heads/{url_quote(config.branch)}",
        method="PATCH",
        payload={"sha": str(commit_sha), "force": False},
    )
    cache_warning = update_cache_after_delete(config, plan)
    result: dict[str, object] = {
        "ok": True,
        "repo": config.repo_slug,
        "branch": config.branch,
        "commit_sha": str(commit_sha),
        "commit_url": f"https://github.com/{config.repo_slug}/commit/{commit_sha}",
        "deleted": plan.targets,
        "index_updated": plan.indexed,
    }
    if cache_warning:
        result["warning"] = cache_warning
    return result


def update_cache_after_delete(config: Config, plan: DeletePlan) -> str | None:
    try:
        local_clip = cache_path(config, plan.path)
        if local_clip.exists():
            local_clip.unlink()
        if plan.indexed and plan.next_index_text is not None:
            local_index = cache_path(config, plan.index_path)
            if local_index.exists():
                local_index.write_text(plan.next_index_text, encoding="utf-8")
        if config.index_db.exists():
            connection = connect_search_index(config)
            try:
                with connection:
                    connection.execute("DELETE FROM documents WHERE path = ?", (plan.path,))
                    connection.execute("DELETE FROM files WHERE path = ?", (plan.path,))
                    set_index_state(connection, "checked_at", 0)
            finally:
                connection.close()
    except OSError as error:
        return f"Repository deletion succeeded, but the local cache could not be updated: {error}"
    return None


def print_delete_result(result: dict[str, object], as_json: bool = False) -> None:
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return
    print(f"Deleted in commit {result['commit_sha']}")
    print(f"commit_url: {result['commit_url']}")
    for target in result["deleted"]:
        print(f"deleted: {target}")
    if result.get("warning"):
        print(f"warning: {result['warning']}")


def allowed_paths(config: Config, tags: list[str], source: str | None) -> set[str] | None:
    if not tags and not source:
        return None

    index = load_index(config)
    wanted_tags = {tag.lower() for tag in tags}
    wanted_source = source.lower() if source else ""
    allowed: set[str] = set()

    for entry in index:
        entry_tags = {str(tag).lower() for tag in entry.get("tags", [])}
        entry_source = str(entry.get("source", "")).lower()
        if wanted_tags and not wanted_tags.issubset(entry_tags):
            continue
        if wanted_source and wanted_source not in entry_source:
            continue
        if entry.get("path"):
            allowed.add(entry["path"])

    return allowed


def run_rg(config: Config, query: str, context: int) -> list[dict[str, str]]:
    rg = shutil.which("rg")
    if rg:
        command = [
            rg,
            "--json",
            "--ignore-case",
            "--glob",
            "*.md",
            "--context",
            str(context),
            query,
            str(config.cache_dir),
        ]
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
        return parse_rg_json(completed.stdout)

    return python_search(config, query, context)


def parse_rg_json(output: str) -> list[dict[str, str]]:
    results: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    context_lines: list[str] = []

    for line in output.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        event_type = event.get("type")
        data = event.get("data", {})
        if event_type == "match":
            if current:
                current["excerpt"] = "\n".join(context_lines).strip()
                results.append(current)
            current = {
                "path": data.get("path", {}).get("text", ""),
                "line_number": str(data.get("line_number", "")),
                "excerpt": data.get("lines", {}).get("text", "").strip(),
            }
            context_lines = [current["excerpt"]]
        elif event_type == "context" and current:
            context_lines.append(data.get("lines", {}).get("text", "").strip())

    if current:
        current["excerpt"] = "\n".join(context_lines).strip()
        results.append(current)

    return results


def python_search(config: Config, query: str, context: int) -> list[dict[str, str]]:
    terms = query.lower().split()
    results: list[dict[str, str]] = []

    for path in config.cache_dir.rglob("*.md"):
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for index, line in enumerate(lines):
            lowered = line.lower()
            if all(term in lowered for term in terms):
                start = max(0, index - context)
                end = min(len(lines), index + context + 1)
                results.append(
                    {
                        "path": str(path),
                        "line_number": str(index + 1),
                        "excerpt": "\n".join(lines[start:end]),
                    }
                )
                break

    return results


def print_result(repo_path: str, meta: dict[str, object], match: dict[str, str]) -> None:
    title = meta.get("title") or repo_path
    url = meta.get("url") or ""
    line = match.get("line_number") or "?"
    excerpt = textwrap.indent(match.get("excerpt", "").strip(), "  ")
    print(f"## {title}")
    print(f"path: {repo_path}:{line}")
    if url:
        print(f"url: {url}")
    print(excerpt)
    print()


def metadata_for(config: Config, repo_path: str) -> dict[str, object]:
    for entry in load_index(config):
        if entry.get("path") == repo_path:
            return entry

    text = cache_path(config, repo_path).read_text(encoding="utf-8", errors="replace")
    return parse_frontmatter(text)


def load_index(config: Config) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    index_paths = [cache_path(config, f"{config.root_folder}/index.jsonl")]
    shard_root = cache_path(config, f"{config.root_folder}/index")
    if shard_root.exists():
        index_paths.extend(sorted(shard_root.rglob("*.jsonl")))
    for index_path in index_paths:
        if not index_path.exists():
            continue
        for line in index_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(entry, dict):
                entries.append(entry)
    return entries


def parse_frontmatter(text: str) -> dict[str, object]:
    if not text.startswith("---\n"):
        return {}

    parts = text.split("---\n", 2)
    if len(parts) < 3:
        return {}

    metadata: dict[str, object] = {}
    for line in parts[1].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        metadata[key.strip()] = value.strip().strip('"')
    return metadata


def has_cached_markdown(config: Config) -> bool:
    return config.cache_dir.exists() and any(config.cache_dir.rglob("*.md"))


def cache_path(config: Config, repo_path: str) -> Path:
    normalized = repo_path.strip("/")
    if normalized != config.root_folder and not normalized.startswith(f"{config.root_folder}/"):
        raise KnowledgeError(f"path must be under {config.root_folder!r}: {repo_path}")
    return config.cache_dir / normalized


def repo_path_from_cache(config: Config, path: Path) -> str:
    return path.relative_to(config.cache_dir).as_posix()


def github_json(config: Config, path: str) -> dict[str, object]:
    return github_json_request(config, path)


def github_json_request(
    config: Config,
    path: str,
    method: str = "GET",
    payload: dict[str, object] | None = None,
) -> dict[str, object]:
    result = github_request(config, path, method=method, payload=payload)
    if not isinstance(result, dict):
        raise KnowledgeError(f"GitHub returned an unexpected JSON value for {method} {path}.")
    return result


def github_request(
    config: Config,
    path: str,
    method: str = "GET",
    payload: dict[str, object] | None = None,
) -> Any:
    if config.token:
        return github_request_with_token(config, path, method=method, payload=payload)
    return github_request_with_gh(path, method=method, payload=payload)


def github_request_with_token(
    config: Config,
    path: str,
    method: str = "GET",
    payload: dict[str, object] | None = None,
) -> Any:
    url = f"https://api.github.com{path}"
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {config.token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "sourcebraid-codex-plugin",
    }
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise KnowledgeError(f"GitHub API {error.code} for {method} {path}: {body}") from error
    except urllib.error.URLError as error:
        raise KnowledgeError(f"GitHub API failed for {method} {path}: {error.reason}") from error
    except json.JSONDecodeError as error:
        raise KnowledgeError(f"GitHub returned invalid JSON for {method} {path}.") from error


def github_request_with_gh(
    path: str,
    method: str = "GET",
    payload: dict[str, object] | None = None,
) -> Any:
    gh = shutil.which("gh")
    if not gh:
        raise KnowledgeError("no token configured and GitHub CLI `gh` is not available.")

    command = [gh, "api", "--method", method, path]
    request_input = None
    if payload is not None:
        command.extend(["--input", "-"])
        request_input = json.dumps(payload)
    completed = subprocess.run(
        command,
        input=request_input,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise KnowledgeError(completed.stderr.strip() or f"gh api failed for {method} {path}")
    try:
        return json.loads(completed.stdout) if completed.stdout.strip() else {}
    except json.JSONDecodeError as error:
        raise KnowledgeError(f"gh api returned invalid JSON for {method} {path}.") from error


def github_json_with_token(config: Config, path: str) -> dict[str, object]:
    """Compatibility wrapper for callers using the original read-only helper."""
    return github_json_request(config, path)


def github_json_with_gh(path: str) -> dict[str, object]:
    """Compatibility wrapper for callers using the original read-only helper."""
    result = github_request_with_gh(path)
    if not isinstance(result, dict):
        raise KnowledgeError(f"GitHub returned an unexpected JSON value for GET {path}.")
    return result


def decode_github_content(content: dict[str, object]) -> str:
    encoded = str(content.get("content", "")).replace("\n", "")
    return base64.b64decode(encoded).decode("utf-8")


def url_path(path: str) -> str:
    return "/".join(url_quote(part) for part in path.split("/"))


def url_quote(value: str) -> str:
    return urllib.parse.quote(value, safe="")


class KnowledgeError(Exception):
    pass


if __name__ == "__main__":
    raise SystemExit(main())

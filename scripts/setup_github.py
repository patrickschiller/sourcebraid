#!/usr/bin/env python3
"""Create and initialize a private GitHub repository for SourceBraid."""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import quote


SUPPORT_FILES = (
    ".github/workflows/convert-pdfs.yml",
    "requirements-docling.txt",
    "scripts/convert_pdfs.py",
    "scripts/push_with_retry.py",
)


class SetupError(RuntimeError):
    """Raised when repository setup cannot continue safely."""


@dataclass(frozen=True)
class RepositoryName:
    owner: str
    name: str

    @property
    def slug(self) -> str:
        return f"{self.owner}/{self.name}"


def parse_repository(value: str) -> RepositoryName:
    parts = value.strip().split("/")
    if len(parts) != 2 or any(not part or part in {".", ".."} for part in parts):
        raise argparse.ArgumentTypeError("repository must use OWNER/NAME")
    if any(any(character.isspace() for character in part) for part in parts):
        raise argparse.ArgumentTypeError("repository owner and name cannot contain whitespace")
    return RepositoryName(*parts)


def normalize_root_folder(value: str) -> str:
    normalized = PurePosixPath(value.strip()).as_posix().strip("/")
    if not normalized or normalized == "." or ".." in PurePosixPath(normalized).parts:
        raise argparse.ArgumentTypeError("root folder must be a normalized repository path")
    return normalized


class GitHubCLI:
    def __init__(self, executable: str = "gh") -> None:
        self.executable = executable

    def auth_status(self) -> None:
        result = subprocess.run(
            [self.executable, "auth", "status"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip()
            raise SetupError(f"GitHub CLI authentication failed: {detail}")

    def api(
        self,
        method: str,
        endpoint: str,
        payload: dict[str, Any] | None = None,
        *,
        allow_not_found: bool = False,
    ) -> dict[str, Any] | list[Any] | None:
        command = [self.executable, "api", "--method", method, endpoint]
        input_text = None
        if payload is not None:
            command.extend(["--input", "-"])
            input_text = json.dumps(payload)
        result = subprocess.run(
            command,
            input=input_text,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip()
            if allow_not_found and ("HTTP 404" in detail or "Not Found" in detail):
                return None
            raise SetupError(f"GitHub API {method} {endpoint} failed: {detail}")
        if not result.stdout.strip():
            return {}
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise SetupError(f"GitHub API returned invalid JSON for {method} {endpoint}") from error


def local_support_files(repository_root: Path, root_folder: str) -> dict[str, bytes]:
    files: dict[str, bytes] = {f"{root_folder}/.gitkeep": b""}
    for repo_path in SUPPORT_FILES:
        source = repository_root.joinpath(*PurePosixPath(repo_path).parts)
        if source.is_symlink():
            raise SetupError(f"refusing to upload symlink: {repo_path}")
        if not source.is_file():
            raise SetupError(f"required setup file is missing: {repo_path}")
        files[repo_path] = source.read_bytes()
    return files


def content_endpoint(repository: RepositoryName, repo_path: str, branch: str | None = None) -> str:
    encoded_path = quote(repo_path, safe="/")
    endpoint = f"/repos/{repository.slug}/contents/{encoded_path}"
    if branch:
        endpoint += f"?ref={quote(branch, safe='')}"
    return endpoint


def ensure_repository(
    client: GitHubCLI,
    repository: RepositoryName,
    *,
    dry_run: bool,
) -> tuple[dict[str, Any] | None, bool]:
    endpoint = f"/repos/{repository.slug}"
    existing = client.api("GET", endpoint, allow_not_found=True)
    if isinstance(existing, dict):
        if not existing.get("private", False):
            raise SetupError(
                f"{repository.slug} is public; refusing to configure a SourceBraid archive there"
            )
        return existing, False

    if dry_run:
        return None, True

    viewer = client.api("GET", "/user")
    if not isinstance(viewer, dict) or not isinstance(viewer.get("login"), str):
        raise SetupError("could not determine the authenticated GitHub account")
    payload = {
        "name": repository.name,
        "description": "Private Markdown archive managed by SourceBraid.",
        "private": True,
        "auto_init": True,
    }
    if viewer["login"].casefold() == repository.owner.casefold():
        created = client.api("POST", "/user/repos", payload)
    else:
        created = client.api("POST", f"/orgs/{repository.owner}/repos", payload)
    if not isinstance(created, dict):
        raise SetupError(f"GitHub did not return the created repository {repository.slug}")
    return created, True


def configure_actions(client: GitHubCLI, repository: RepositoryName, *, dry_run: bool) -> None:
    if dry_run:
        return
    client.api(
        "PUT",
        f"/repos/{repository.slug}/actions/permissions",
        {"enabled": True, "allowed_actions": "all"},
    )


def upload_support_files(
    client: GitHubCLI,
    repository: RepositoryName,
    branch: str,
    files: dict[str, bytes],
    *,
    dry_run: bool,
    update_existing: bool,
) -> tuple[list[str], list[str], list[str]]:
    created: list[str] = []
    updated: list[str] = []
    skipped: list[str] = []
    for repo_path, content in files.items():
        endpoint = content_endpoint(repository, repo_path)
        existing = client.api(
            "GET",
            content_endpoint(repository, repo_path, branch),
            allow_not_found=True,
        )
        existing_sha = existing.get("sha") if isinstance(existing, dict) else None
        if existing_sha and not update_existing:
            skipped.append(repo_path)
            continue

        payload: dict[str, Any] = {
            "message": f"Initialize SourceBraid support: {repo_path}",
            "content": base64.b64encode(content).decode("ascii"),
            "branch": branch,
        }
        if existing_sha:
            payload["sha"] = existing_sha
        if not dry_run:
            client.api("PUT", endpoint, payload)
        if existing_sha:
            updated.append(repo_path)
        else:
            created.append(repo_path)
    return created, updated, skipped


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Create or initialize a private SourceBraid archive using the authenticated GitHub CLI. "
            "Existing files are preserved unless --update-existing is supplied."
        ),
    )
    result.add_argument("--repo", required=True, type=parse_repository, metavar="OWNER/NAME")
    result.add_argument("--branch", default="main")
    result.add_argument("--root-folder", default="web-clips", type=normalize_root_folder)
    result.add_argument("--dry-run", action="store_true")
    result.add_argument(
        "--update-existing",
        action="store_true",
        help="Replace only the known SourceBraid support files when their paths already exist.",
    )
    result.add_argument(
        "--repository-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Local SourceBraid project root containing the support files.",
    )
    return result


def print_paths(label: str, paths: list[str]) -> None:
    if paths:
        print(f"{label}: {', '.join(paths)}")


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    repository_root = args.repository_root.resolve()
    client = GitHubCLI()
    try:
        files = local_support_files(repository_root, args.root_folder)
        client.auth_status()
        repository_info, repository_created = ensure_repository(
            client,
            args.repo,
            dry_run=args.dry_run,
        )
        branch = args.branch
        if repository_info and not repository_created:
            default_branch = repository_info.get("default_branch")
            if branch == "main" and isinstance(default_branch, str) and default_branch:
                branch = default_branch
        configure_actions(client, args.repo, dry_run=args.dry_run)
        created, updated, skipped = upload_support_files(
            client,
            args.repo,
            branch,
            files,
            dry_run=args.dry_run,
            update_existing=args.update_existing,
        )
    except SetupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    mode = "dry run" if args.dry_run else "complete"
    print(f"setup: {mode}")
    print(f"repository: https://github.com/{args.repo.slug}")
    print(f"visibility: private")
    print(f"branch: {branch}")
    print_paths("would create" if args.dry_run else "created", created)
    print_paths("would update" if args.dry_run else "updated", updated)
    print_paths("preserved", skipped)
    if not args.dry_run:
        print("next: create a fine-grained GitHub token restricted to this repository")
        print("permission: Contents: Read and write")
        print("token URL: https://github.com/settings/personal-access-tokens/new")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

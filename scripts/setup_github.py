#!/usr/bin/env python3
"""Create and initialize a private GitHub repository for SourceBraid."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import re
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

DEFAULT_REPOSITORY_NAME = "sourcebraid-private"
DEFAULT_CONFIG_OUTPUT = Path("sourcebraid-config.json")

# The release builder replaces this empty mapping with the same allowlisted
# support files. Keeping the source version empty ensures normal repository
# runs always use the checked-in canonical copies.
EMBEDDED_SUPPORT_FILES: dict[str, str] = {}


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
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}", parts[0]) or not re.fullmatch(r"[A-Za-z0-9._-]{1,100}", parts[1]):
        raise argparse.ArgumentTypeError("repository owner and name must be valid GitHub path components")
    return RepositoryName(*parts)


def normalize_root_folder(value: str) -> str:
    normalized = value.strip()
    parts = normalized.split("/")
    if (not normalized or len(normalized) > 1024 or len(parts) > 20
            or any(part in {"", ".", ".."} or part.lower() in {".git", ".github"} for part in parts)
            or any(character == "\\" or ord(character) < 32 or ord(character) == 127 for character in normalized)):
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
        if repo_path in EMBEDDED_SUPPORT_FILES:
            try:
                files[repo_path] = base64.b64decode(
                    EMBEDDED_SUPPORT_FILES[repo_path],
                    validate=True,
                )
            except (ValueError, binascii.Error) as error:
                raise SetupError(f"embedded setup file is invalid: {repo_path}") from error
            continue
        source = repository_root.joinpath(*PurePosixPath(repo_path).parts)
        if source.is_symlink():
            raise SetupError(f"refusing to upload symlink: {repo_path}")
        if source.is_file():
            files[repo_path] = source.read_bytes()
            continue
        raise SetupError(f"required setup file is missing: {repo_path}")
    return files


def authenticated_login(client: GitHubCLI) -> str:
    viewer = client.api("GET", "/user")
    if not isinstance(viewer, dict) or not isinstance(viewer.get("login"), str):
        raise SetupError("could not determine the authenticated GitHub account")
    login = viewer["login"].strip()
    if not login:
        raise SetupError("GitHub returned an empty authenticated account name")
    return login


def resolve_repository(
    client: GitHubCLI,
    configured: RepositoryName | None,
) -> tuple[RepositoryName, str | None]:
    if configured is not None:
        return configured, None
    login = authenticated_login(client)
    return RepositoryName(login, DEFAULT_REPOSITORY_NAME), login


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
    viewer_login: str | None = None,
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

    viewer_login = viewer_login or authenticated_login(client)
    payload = {
        "name": repository.name,
        "description": "Private Markdown archive managed by SourceBraid.",
        "private": True,
        "auto_init": True,
    }
    if viewer_login.casefold() == repository.owner.casefold():
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


def plugin_config(repository: RepositoryName, branch: str, root_folder: str) -> dict[str, str]:
    return {
        "owner": repository.owner,
        "repo": repository.name,
        "branch": branch,
        "root_folder": root_folder,
    }


def write_plugin_config(
    output_path: Path,
    payload: dict[str, str],
    *,
    dry_run: bool,
    overwrite: bool,
) -> tuple[Path, str]:
    target = Path(os.path.abspath(output_path.expanduser()))
    if target.is_symlink():
        raise SetupError(f"refusing to write plugin config through a symlink: {target}")

    content = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    existed = target.is_file()
    if existed:
        try:
            existing_content = target.read_text(encoding="utf-8")
        except OSError as error:
            raise SetupError(f"could not read existing plugin config {target}: {error}") from error
        if existing_content == content:
            return target, "unchanged"
        if not overwrite:
            return target, "preserved"

    if dry_run:
        return target, "would update" if existed else "would create"

    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        target.chmod(0o600)
    except OSError as error:
        raise SetupError(f"could not write plugin config {target}: {error}") from error
    return target, "updated" if existed else "created"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Create or initialize a private SourceBraid archive using the authenticated GitHub CLI. "
            "Existing files are preserved unless --update-existing is supplied."
        ),
    )
    result.add_argument(
        "--repo",
        type=parse_repository,
        metavar="OWNER/NAME",
        help=(
            "Private archive repository. Defaults to the authenticated GitHub user and "
            f"{DEFAULT_REPOSITORY_NAME}."
        ),
    )
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
    result.add_argument(
        "--config-output",
        type=Path,
        default=DEFAULT_CONFIG_OUTPUT,
        help=(
            "Write a token-free plugin config to this path "
            f"(defaults to {DEFAULT_CONFIG_OUTPUT})."
        ),
    )
    result.add_argument(
        "--no-config",
        action="store_true",
        help="Do not create a local SourceBraid plugin config file.",
    )
    result.add_argument(
        "--overwrite-config",
        action="store_true",
        help="Replace an existing config output. Existing files are preserved by default.",
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
        client.auth_status()
        repository, viewer_login = resolve_repository(client, args.repo)
        files = local_support_files(repository_root, args.root_folder)
        repository_info, repository_created = ensure_repository(
            client,
            repository,
            dry_run=args.dry_run,
            viewer_login=viewer_login,
        )
        branch = args.branch
        if repository_info and not repository_created:
            default_branch = repository_info.get("default_branch")
            if branch == "main" and isinstance(default_branch, str) and default_branch:
                branch = default_branch
        configure_actions(client, repository, dry_run=args.dry_run)
        created, updated, skipped = upload_support_files(
            client,
            repository,
            branch,
            files,
            dry_run=args.dry_run,
            update_existing=args.update_existing,
        )
        config_result = None
        if not args.no_config:
            config_result = write_plugin_config(
                args.config_output,
                plugin_config(repository, branch, args.root_folder),
                dry_run=args.dry_run,
                overwrite=args.overwrite_config,
            )
    except SetupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    mode = "dry run" if args.dry_run else "complete"
    print(f"setup: {mode}")
    print(f"repository: https://github.com/{repository.slug}")
    print(f"visibility: private")
    print(f"branch: {branch}")
    print_paths("would create" if args.dry_run else "created", created)
    print_paths("would update" if args.dry_run else "updated", updated)
    print_paths("preserved", skipped)
    if config_result is not None:
        config_path, config_status = config_result
        print(f"plugin config: {config_status}: {config_path}")
        if config_status == "preserved":
            print("plugin config was not changed; use --overwrite-config to replace it")
    if not args.dry_run:
        print("next: create a fine-grained GitHub token restricted to this repository")
        print("permission: Contents: Read and write")
        print("token URL: https://github.com/settings/personal-access-tokens/new")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

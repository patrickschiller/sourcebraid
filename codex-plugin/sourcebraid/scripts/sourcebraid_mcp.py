#!/usr/bin/env python3
"""Dependency-free MCP server for the SourceBraid ChatGPT and Codex plugin."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Callable


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import sourcebraid as core  # noqa: E402


SERVER_NAME = "sourcebraid"
SERVER_VERSION = "0.5.0"
PROTOCOL_VERSION = "2025-06-18"
DEFAULT_SEARCH_LIMIT = 10

JSON_OBJECT: dict[str, object] = {"type": "object", "additionalProperties": False}


def object_schema(
    properties: dict[str, object] | None = None,
    required: list[str] | None = None,
) -> dict[str, object]:
    schema = dict(JSON_OBJECT)
    schema["properties"] = properties or {}
    if required:
        schema["required"] = required
    return schema


STRING = {"type": "string"}
NONEMPTY_STRING = {"type": "string", "minLength": 1}
POSITIVE_LIMIT = {"type": "integer", "minimum": 1, "maximum": 100, "default": 20}


TOOLS: list[dict[str, object]] = [
    {
        "name": "search",
        "title": "Search SourceBraid",
        "description": (
            "Search the user's private SourceBraid archive. Returns canonical source URLs so ChatGPT "
            "can cite the original material."
        ),
        "inputSchema": object_schema({"query": NONEMPTY_STRING}, ["query"]),
        "outputSchema": object_schema(
            {
                "results": {
                    "type": "array",
                    "items": object_schema(
                        {"id": NONEMPTY_STRING, "title": NONEMPTY_STRING, "url": STRING},
                        ["id", "title", "url"],
                    ),
                }
            },
            ["results"],
        ),
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    },
    {
        "name": "fetch",
        "title": "Fetch a SourceBraid source",
        "description": "Fetch one complete Markdown source using the repository path returned by search.",
        "inputSchema": object_schema({"id": NONEMPTY_STRING}, ["id"]),
        "outputSchema": object_schema(
            {
                "id": NONEMPTY_STRING,
                "title": NONEMPTY_STRING,
                "text": STRING,
                "url": STRING,
                "metadata": {"type": "object"},
            },
            ["id", "title", "text", "url", "metadata"],
        ),
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    },
    {
        "name": "sourcebraid_list",
        "title": "List SourceBraid sources",
        "description": "List recent saved sources, optionally filtered by metadata, tags, or source.",
        "inputSchema": object_schema(
            {
                "query": STRING,
                "tags": {"type": "array", "items": NONEMPTY_STRING, "default": []},
                "source": STRING,
                "limit": POSITIVE_LIMIT,
            }
        ),
        "outputSchema": object_schema(
            {"sources": {"type": "array", "items": {"type": "object"}}},
            ["sources"],
        ),
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    },
    {
        "name": "sourcebraid_status",
        "title": "Inspect SourceBraid status",
        "description": "Show the resolved archive configuration and local search-index status.",
        "inputSchema": object_schema(),
        "outputSchema": {"type": "object"},
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
        },
    },
    {
        "name": "sourcebraid_sync",
        "title": "Sync SourceBraid",
        "description": "Refresh the local search cache from the configured private GitHub archive.",
        "inputSchema": object_schema(),
        "outputSchema": {"type": "object"},
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    },
    {
        "name": "sourcebraid_plan_delete",
        "title": "Preview deletion of a SourceBraid source",
        "description": (
            "Build a non-destructive deletion preview. The returned head SHA and exact confirmation "
            "are required by sourcebraid_delete."
        ),
        "inputSchema": object_schema({"path": NONEMPTY_STRING}, ["path"]),
        "outputSchema": {"type": "object"},
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    },
    {
        "name": "sourcebraid_delete",
        "title": "Delete a SourceBraid source",
        "description": (
            "Delete exactly one previously previewed source and its owned assets. Requires the "
            "unchanged branch head and exact 'DELETE path' confirmation from the preview."
        ),
        "inputSchema": object_schema(
            {
                "path": NONEMPTY_STRING,
                "expected_head": NONEMPTY_STRING,
                "confirmation": NONEMPTY_STRING,
            },
            ["path", "expected_head", "confirmation"],
        ),
        "outputSchema": {"type": "object"},
        "annotations": {
            "readOnlyHint": False,
            "destructiveHint": True,
            "idempotentHint": False,
            "openWorldHint": True,
        },
    },
]


def config_args() -> argparse.Namespace:
    return argparse.Namespace(
        owner=None,
        repo=None,
        repo_slug=None,
        branch=None,
        root_folder=None,
        token=None,
    )


def load_config(*, allow_missing: bool = False) -> core.Config:
    return core.load_config(config_args(), allow_missing=allow_missing)


def ensure_index(config: core.Config, *, refresh: bool = False) -> None:
    if not config.index_db.exists():
        core.build_search_index(config)
    elif refresh:
        core.update_search_index(config)
    else:
        core.maybe_auto_update(config, quiet=True)


def require_string(arguments: dict[str, object], name: str) -> str:
    value = arguments.get(name)
    if not isinstance(value, str) or not value.strip():
        raise core.KnowledgeError(f"{name} must be a non-empty string.")
    return value.strip()


def optional_string(arguments: dict[str, object], name: str) -> str:
    value = arguments.get(name, "")
    if value is None:
        return ""
    if not isinstance(value, str):
        raise core.KnowledgeError(f"{name} must be a string.")
    return value.strip()


def optional_limit(arguments: dict[str, object], default: int = 20) -> int:
    value = arguments.get("limit", default)
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 100:
        raise core.KnowledgeError("limit must be an integer between 1 and 100.")
    return value


def optional_tags(arguments: dict[str, object]) -> list[str]:
    value = arguments.get("tags", [])
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(tag, str) and tag.strip() for tag in value):
        raise core.KnowledgeError("tags must be an array of non-empty strings.")
    return [tag.strip() for tag in value]


def metadata_for_text(config: core.Config, repo_path: str, text: str) -> dict[str, object]:
    for entry in core.load_index(config):
        if entry.get("path") == repo_path:
            return entry
    return core.parse_frontmatter(text)


def read_source(config: core.Config, repo_path: str) -> tuple[str, dict[str, object]]:
    normalized = core.validate_clip_path(config, repo_path)
    local_path = core.cache_path(config, normalized)
    if not local_path.exists() and config.index_db.exists():
        core.update_search_index(config)
    if local_path.exists():
        text = local_path.read_text(encoding="utf-8", errors="replace")
    else:
        text = core.repository_text(config, normalized, core.current_branch_head(config))
    return text, metadata_for_text(config, normalized, text)


def tool_search(arguments: dict[str, object]) -> dict[str, object]:
    config = load_config()
    ensure_index(config)
    records = core.search_index_records(
        config,
        require_string(arguments, "query"),
        limit=DEFAULT_SEARCH_LIMIT,
    )
    return {
        "results": [
            {
                "id": str(record["path"]),
                "title": str(record.get("title") or record["path"]),
                "url": str(record.get("url") or ""),
            }
            for record in records
        ]
    }


def tool_fetch(arguments: dict[str, object]) -> dict[str, object]:
    config = load_config()
    repo_path = require_string(arguments, "id")
    text, metadata = read_source(config, repo_path)
    title = str(metadata.get("title") or Path(repo_path).stem)
    url = str(metadata.get("url") or "")
    public_metadata = {
        "repo": config.repo_slug,
        "branch": config.branch,
        "path": repo_path,
        "date": str(metadata.get("date") or metadata.get("captured_at") or ""),
        "source": str(metadata.get("source") or metadata.get("site") or ""),
        "tags": core.normalize_tags(metadata.get("tags")),
    }
    return {
        "id": repo_path,
        "title": title,
        "text": text,
        "url": url,
        "metadata": public_metadata,
    }


def tool_list(arguments: dict[str, object]) -> dict[str, object]:
    config = load_config()
    ensure_index(config)
    return {
        "sources": core.list_clip_records(
            config,
            optional_string(arguments, "query"),
            optional_tags(arguments),
            optional_string(arguments, "source") or None,
            limit=optional_limit(arguments),
        )
    }


def tool_status(_arguments: dict[str, object]) -> dict[str, object]:
    config = load_config(allow_missing=True)
    if not config.owner or not config.repo:
        return {
            "configured": False,
            "config_path": str(core.CONFIG_PATH),
            "setup": "Run sourcebraid.py config --repo-slug OWNER/sourcebraid-private",
        }
    return {"configured": True, **core.index_status_payload(config)}


def tool_sync(_arguments: dict[str, object]) -> dict[str, object]:
    config = load_config()
    return core.update_search_index(config, rebuild=not config.index_db.exists())


def tool_plan_delete(arguments: dict[str, object]) -> dict[str, object]:
    config = load_config()
    return core.build_delete_plan(config, require_string(arguments, "path")).public_dict()


def tool_delete(arguments: dict[str, object]) -> dict[str, object]:
    config = load_config()
    repo_path = require_string(arguments, "path")
    expected_confirmation = f"DELETE {repo_path}"
    confirmation = require_string(arguments, "confirmation")
    if confirmation != expected_confirmation:
        raise core.KnowledgeError(
            f"confirmation must exactly match {expected_confirmation!r}; no repository changes were made."
        )
    return core.delete_clip(
        config,
        repo_path,
        require_string(arguments, "expected_head"),
        repo_path,
    )


TOOL_HANDLERS: dict[str, Callable[[dict[str, object]], dict[str, object]]] = {
    "search": tool_search,
    "fetch": tool_fetch,
    "sourcebraid_list": tool_list,
    "sourcebraid_status": tool_status,
    "sourcebraid_sync": tool_sync,
    "sourcebraid_plan_delete": tool_plan_delete,
    "sourcebraid_delete": tool_delete,
}


def tool_result(payload: dict[str, object]) -> dict[str, object]:
    serialized = json.dumps(payload, ensure_ascii=False)
    return {
        "content": [{"type": "text", "text": serialized}],
        "structuredContent": payload,
    }


def error_result(message: str) -> dict[str, object]:
    return {
        "content": [{"type": "text", "text": message}],
        "isError": True,
    }


def dispatch(request: dict[str, object]) -> dict[str, object] | None:
    method = request.get("method")
    request_id = request.get("id")
    if request_id is None:
        return None

    try:
        if method == "initialize":
            result: dict[str, object] = {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                "instructions": (
                    "Use search and fetch for citations from the user's private SourceBraid archive. "
                    "Always call sourcebraid_plan_delete and obtain the exact user confirmation before deletion."
                ),
            }
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            params = request.get("params")
            if not isinstance(params, dict):
                raise core.KnowledgeError("tools/call params must be an object.")
            name = params.get("name")
            arguments = params.get("arguments", {})
            if not isinstance(name, str) or name not in TOOL_HANDLERS:
                raise core.KnowledgeError(f"unknown tool: {name!r}")
            if not isinstance(arguments, dict):
                raise core.KnowledgeError("tool arguments must be an object.")
            try:
                result = tool_result(TOOL_HANDLERS[name](arguments))
            except (core.KnowledgeError, OSError, ValueError, json.JSONDecodeError) as error:
                result = error_result(str(error))
        else:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            }
        return {"jsonrpc": "2.0", "id": request_id, "result": result}
    except (core.KnowledgeError, OSError, ValueError, json.JSONDecodeError) as error:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32602, "message": str(error)},
        }


def main() -> int:
    for raw_line in sys.stdin:
        if not raw_line.strip():
            continue
        try:
            request = json.loads(raw_line)
            if not isinstance(request, dict):
                raise ValueError("request must be a JSON object")
            response = dispatch(request)
        except (json.JSONDecodeError, ValueError) as error:
            response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": str(error)},
            }
        if response is not None:
            print(json.dumps(response, ensure_ascii=False, separators=(",", ":")), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest import mock


PLUGIN_SCRIPTS = Path(__file__).parents[1] / "codex-plugin" / "sourcebraid" / "scripts"
if str(PLUGIN_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(PLUGIN_SCRIPTS))
SCRIPT_PATH = PLUGIN_SCRIPTS / "sourcebraid_mcp.py"
SPEC = importlib.util.spec_from_file_location("sourcebraid_mcp_under_test", SCRIPT_PATH)
assert SPEC and SPEC.loader
mcp = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = mcp
SPEC.loader.exec_module(mcp)


class SourceBraidMCPTests(unittest.TestCase):
    def test_initialize_advertises_server_and_tools(self):
        response = mcp.dispatch(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-06-18"},
            }
        )

        self.assertEqual(response["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(response["result"]["serverInfo"]["name"], "sourcebraid")

        tools = mcp.dispatch({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        names = {tool["name"] for tool in tools["result"]["tools"]}
        self.assertIn("search", names)
        self.assertIn("fetch", names)
        self.assertIn("sourcebraid_plan_delete", names)
        self.assertIn("sourcebraid_delete", names)

    def test_search_returns_company_knowledge_shape(self):
        records = [
            {
                "path": "web-clips/2026/07/example.md",
                "title": "Example",
                "url": "https://example.com/article",
            }
        ]
        with mock.patch.object(mcp, "load_config", return_value=mock.Mock()):
            with mock.patch.object(mcp, "ensure_index"):
                with mock.patch.object(mcp.core, "search_index_records", return_value=records):
                    response = mcp.dispatch(
                        {
                            "jsonrpc": "2.0",
                            "id": 3,
                            "method": "tools/call",
                            "params": {"name": "search", "arguments": {"query": "example"}},
                        }
                    )

        payload = response["result"]["structuredContent"]
        self.assertEqual(
            payload,
            {
                "results": [
                    {
                        "id": "web-clips/2026/07/example.md",
                        "title": "Example",
                        "url": "https://example.com/article",
                    }
                ]
            },
        )
        self.assertEqual(json.loads(response["result"]["content"][0]["text"]), payload)

    def test_delete_requires_exact_preview_confirmation(self):
        config = mock.Mock()
        with mock.patch.object(mcp, "load_config", return_value=config):
            with mock.patch.object(mcp.core, "delete_clip") as delete_clip:
                response = mcp.dispatch(
                    {
                        "jsonrpc": "2.0",
                        "id": 4,
                        "method": "tools/call",
                        "params": {
                            "name": "sourcebraid_delete",
                            "arguments": {
                                "path": "web-clips/2026/07/example.md",
                                "expected_head": "abc123",
                                "confirmation": "delete it",
                            },
                        },
                    }
                )

        self.assertTrue(response["result"]["isError"])
        self.assertIn("DELETE web-clips/2026/07/example.md", response["result"]["content"][0]["text"])
        delete_clip.assert_not_called()

    def test_delete_passes_preview_guard_to_core(self):
        config = mock.Mock()
        result = {"ok": True, "commit_sha": "def456"}
        with mock.patch.object(mcp, "load_config", return_value=config):
            with mock.patch.object(mcp.core, "delete_clip", return_value=result) as delete_clip:
                response = mcp.dispatch(
                    {
                        "jsonrpc": "2.0",
                        "id": 5,
                        "method": "tools/call",
                        "params": {
                            "name": "sourcebraid_delete",
                            "arguments": {
                                "path": "web-clips/2026/07/example.md",
                                "expected_head": "abc123",
                                "confirmation": "DELETE web-clips/2026/07/example.md",
                            },
                        },
                    }
                )

        self.assertEqual(response["result"]["structuredContent"], result)
        delete_clip.assert_called_once_with(
            config,
            "web-clips/2026/07/example.md",
            "abc123",
            "web-clips/2026/07/example.md",
        )


if __name__ == "__main__":
    unittest.main()

# SourceBraid in ChatGPT and Codex

SourceBraid ships as one universal plugin for ChatGPT and Codex. The plugin
contains three instruction skills and a dependency-free local MCP server.

## Local installation

1. Configure the private archive:

   ```bash
   python3 codex-plugin/sourcebraid/scripts/sourcebraid.py config \
     --repo-slug OWNER/sourcebraid-private \
     --branch main \
     --root-folder web-clips
   ```

2. Install `sourcebraid@personal` from the local plugin marketplace.
3. Start a new ChatGPT or Codex conversation and enable SourceBraid.
4. Try: `Search my SourceBraid archive for retrieval augmented generation.`

The MCP server exposes the standard read-only `search` and `fetch` tools used
for ChatGPT company knowledge, plus listing, index status/sync, and a guarded
two-step deletion flow.

## Public connection after the domain is ready

The repository is ready for local plugin testing. Public directory submission
requires two deployment-specific values that must not be invented:

1. a stable HTTPS streamable-HTTP endpoint, planned as
   `https://sourcebraid.com/mcp`; and
2. the registered ChatGPT MCP connection ID used in `.app.json`.

After the endpoint is deployed, register it in ChatGPT developer mode, add the
returned connection ID to `.app.json`, test in a fresh conversation, and
submit the same plugin package for ChatGPT and Codex.

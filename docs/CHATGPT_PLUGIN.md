# SourceBraid in ChatGPT and Codex

SourceBraid has two runtime paths: a hosted, read-only MCP service for ChatGPT
and the complete local Codex plugin for search, index maintenance, and guarded
archive changes. The hosted service is prepared in `chatgpt-mcp/` but has not
been deployed or approved for a public OpenAI listing.

## Primary ChatGPT release: hosted MCP

The intended endpoint is `https://mcp.sourcebraid.com/mcp`. Use the
[deployment guide](CHATGPT_MCP_DEPLOYMENT.md) and
[OpenAI MCP submission kit](../marketing/OPENAI_MCP_SUBMISSION.md). Submit the
verified production service as **With MCP**, with the actual HTTPS endpoint,
domain verification, authentication setup, and protected review credentials.
A local build or a planned URL is not evidence that the service is live.

After deployment, the connection flow uses OAuth 2.1 authorization codes with
PKCE S256. The user enters a fine-grained GitHub PAT on SourceBraid's HTTPS
consent page, restricted to **Contents: Read-only** for exactly one private
repository. Never paste a PAT into ChatGPT, listing copy, screenshots, or a
public issue. The server verifies the private repository and the connected
GitHub identity before archive access.

The hosted tools are `search`, `fetch`, `sourcebraid_list`, and
`sourcebraid_status`. They cannot write or delete GitHub files, build a local
index, or migrate metadata. Search uses GitHub's code index on the configured
default branch and verifies returned paths and blobs at a pinned commit. It
checks up to 20 ranked matches and returns up to 10. GitHub indexing may lag;
incomplete searches and result limits are explicit. When indexed search is
unavailable, has no verifiable hits, or cannot cover the configured branch, the
fallback scans at most 20 Markdown paths in descending path order. Exact-path
fetch can access other files within the configured root, up to 200 KiB each.

The Cloudflare Worker stores OAuth grant/client metadata in KV. Its pinned
OAuth provider encrypts the PAT in grant properties; requested archive content
is processed transiently by SourceBraid/Cloudflare and then ChatGPT. There is no
permanent SourceBraid content database. See [Privacy](../PRIVACY.md).

Deployment, live testing, review, approval, and developer publication are
separate steps. Follow the [OpenAI submission guide](https://developers.openai.com/plugins/deploy/submission)
and [authentication guide](https://developers.openai.com/plugins/build/auth).

## Codex installation from this checkout

1. Add this repository as a local marketplace and install SourceBraid:

   ```bash
   codex plugin marketplace add .
   codex plugin add sourcebraid@sourcebraid
   ```

2. Configure the private archive:

   ```bash
   python3 codex-plugin/sourcebraid/scripts/sourcebraid.py config \
     --repo-slug OWNER/sourcebraid-private \
     --branch main \
     --root-folder web-clips
   ```

3. Start a new Codex conversation so the installed skills and local MCP server
   are loaded.
4. Try: `Search my SourceBraid archive for retrieval augmented generation.`

## Codex installation from GitHub

After the reviewed `v1.0.1` tag is published, add the tag-bound GitHub
marketplace and install the plugin:

```bash
codex plugin marketplace add patrickschiller/sourcebraid \
  --ref v1.0.1 \
  --sparse .agents/plugins \
  --sparse codex-plugin/sourcebraid
codex plugin add sourcebraid@sourcebraid
```

The repository-local marketplace entry points only to
`codex-plugin/sourcebraid`. The complete source plugin's local
MCP server exposes read-only `search` and `fetch` tools plus listing, index
status and sync, and the guarded two-step deletion flow.

## Local runtime and authentication

The local skills need Python 3 and either `GITHUB_TOKEN`,
`GH_TOKEN`, or an authenticated GitHub CLI. Configuration resolves from CLI
flags, SourceBraid environment variables, or
`~/.config/sourcebraid/config.json`.

Read-only tasks need repository read access. Guarded deletion or metadata
migration additionally needs Contents write access and fresh confirmation. The
local SQLite cache is separated by repository, branch, and root folder; this
release rebuilds it automatically under its safer cache namespace. Requested
results are processed by the active Codex environment under its terms and data
settings. Local archive copies are not uploaded to the hosted MCP service.

## Optional skills-only package

The optional ZIP packages the local Python workflows and their assets. It does
not contain `.mcp.json` or the stdio server and does not independently connect
ordinary ChatGPT to a private archive. It is not the primary ChatGPT submission.

```bash
python3 scripts/build_plugin_package.py
unzip -l dist/sourcebraid-plugin-skills-v1.0.1.zip
shasum -a 256 dist/sourcebraid-plugin-skills-v1.0.1.zip
```

Its local review material remains in
[the optional skills kit](../marketing/OPENAI_PLUGIN_SUBMISSION.md). Record the
digest generated from the final reviewed commit; do not reuse an earlier ZIP's
hash after changing the runtime.

## Disconnecting

Disconnect SourceBraid in ChatGPT and revoke its fine-grained PAT in GitHub to
stop future hosted archive access. This does not delete GitHub content or any
local Codex cache. Local credentials and caches can be removed separately.

## Deutsch

Die primäre ChatGPT-Anbindung ist ein gehosteter MCP-Dienst mit reinem
Lesezugriff. `https://mcp.sourcebraid.com/mcp` ist als Ziel vorbereitet, aber
noch nicht bereitgestellt oder öffentlich freigegeben. Nach Bereitstellung
erfolgt die Verbindung über OAuth 2.1 mit PKCE S256. Der Fine-grained-GitHub-PAT
gehört ausschließlich auf die HTTPS-Zustimmungsseite von SourceBraid und erhält
Contents-Leserechte für genau ein privates Repository; niemals in den Chat.

Die gehosteten Werkzeuge suchen, rufen Quellen ab, listen sie auf und zeigen
den Status. Suchgrenzen und unvollständige Ergebnisse werden ausgewiesen.
Löschen, Schreiben und lokales Indexieren bleiben dem lokalen Codex-Plugin
vorbehalten. Das optionale Skills-ZIP benötigt eine lokale Python-Laufzeit und
GitHub-Zugangsdaten; es ist keine eigenständige Anbindung für normales ChatGPT.

OAuth-Metadaten und verschlüsselte PAT-Grant-Daten werden in Cloudflare KV
gespeichert. Angeforderte Quellen werden vorübergehend durch
SourceBraid/Cloudflare und ChatGPT verarbeitet, nicht in einer dauerhaften
SourceBraid-Inhaltsdatenbank abgelegt. Zum Widerruf die ChatGPT-Verbindung
trennen und den PAT bei GitHub widerrufen. Archiv und lokale Caches bleiben
davon unberührt. Die vollständigen [Datenschutzhinweise](../PRIVACY.md) gelten.

# OpenAI submission kit — SourceBraid read-only MCP 1.1.0

This is the **primary ChatGPT release route**. Code and submission material are
prepared; deployment, live acceptance, identity verification, submission and
approval are separate outstanding gates. Do not enter an undeployed URL as a
working service. Follow [the deployment runbook](../docs/CHATGPT_MCP_DEPLOYMENT.md).

Portal workflow checked against the [official submission guide](https://developers.openai.com/plugins/deploy/submission)
on **October 15, 2026**: start with a plugin ZIP that already declares the remote
MCP server. Adding MCP later to an existing skills-only plugin is not supported.

## Upload package and deployment source

- Upload **`sourcebraid-chatgpt-plugin-v1.1.0.zip`** from the verified release
  bundle. It contains root `plugin.json`, root `mcp.json`, and the logo. The
  manifest supplies listing metadata; `mcp.json` declares the stable HTTPS
  endpoint and OAuth settings. Keep credentials outside this ZIP.
- Deploy the service from **`sourcebraid-chatgpt-mcp-v1.1.0.zip`** following the
  runbook. This is Worker source code, not the plugin upload or a live endpoint.
- The optional **`sourcebraid-plugin-skills-v1.1.0.zip`** is a separate local
  Python package. Do not upload it for this hosted read-only submission.

## Copy-ready listing

| Field | Value |
| --- | --- |
| Name | SourceBraid |
| Developer | Patrick Schiller, only if identical to the selected verified identity |
| Submission | Upload plugin ZIP, then connect the declared remote server under MCPs / With MCP |
| Upload | `sourcebraid-chatgpt-plugin-v1.1.0.zip` |
| Target MCP URL | `https://mcp.sourcebraid.com/mcp` — after deployment and live tests |
| Authentication | OAuth 2.1 / PKCE S256; scope `archive:read` |
| Category | Productivity |
| Capability | Read |
| Short description | Search your Markdown archive. |
| Website | `https://sourcebraid.com` |
| Repository | `https://github.com/patrickschiller/sourcebraid` |
| Privacy | `https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md` |
| Terms | `https://github.com/patrickschiller/sourcebraid/blob/main/TERMS.md` |
| Support | `https://github.com/patrickschiller/sourcebraid/issues` |
| Logo | `codex-plugin/sourcebraid/assets/sourcebraid-icon.png` |
| Brand color | `#166B68` |
| Custom app UI / static skills | None; no component CSP domains or skills ZIP needed |

Long description:

> Bring your saved Markdown sources back into your research. SourceBraid lets
> you search, list and read sources from one private GitHub archive you control,
> with original source links for citations. Connect your repository once through
> the secure consent page using a dedicated read-only GitHub token. Search
> results disclose indexing and coverage limits. This connection cannot change
> or delete your archive. Requested sources pass through SourceBraid's hosted
> service to the connected application; your Markdown files and Git history
> remain authoritative.

German short description:

> Durchsuche dein Markdownarchiv

German long description:

> Nutze deine gespeicherten Markdown-Quellen für deine Recherche. SourceBraid
> durchsucht und liest ein von dir kontrolliertes privates GitHub-Archiv und
> bewahrt ursprüngliche Quell-Links für Zitate. Verbinde dein Repository auf der
> sicheren Anmeldeseite mit einem eigenen, nur leseberechtigten GitHub-Token.
> Suchergebnisse weisen auf Index- und Abdeckungsgrenzen hin. Diese Verbindung
> kann dein Archiv weder ändern noch löschen. Angeforderte Quellen werden über
> den gehosteten SourceBraid-Dienst an die verbundene Anwendung übertragen;
> Markdown-Dateien und Git-Historie bleiben maßgeblich.

Starter prompts:

1. `Search my SourceBraid archive for Markdown ownership and cite the sources.`
2. `List sources in my SourceBraid archive and help me choose one to read.`
3. `Find my saved sources about retrieval and summarize them with original links.`

All four tools carry `readOnlyHint: true`, `destructiveHint: false`,
`openWorldHint: false` (one bounded private archive), and OAuth security schemes.
No token or GitHub identity ID is returned by a tool. The consent page has its
own restrictive CSP; there is no embedded ChatGPT component to configure.
This release does not support email-domain-restricted workspace enrollment.

Do not use the Codex search screenshot as proof of a ChatGPT session. A
reviewer-accessible **video walkthrough URL is required** for MCP review.
Record the live synthetic-review flow and its test cases after deployment;
never fabricate approval badges, tool results or connection screens. Capture
any ChatGPT screenshots from that same flow. The logo is ready to upload.

## Reviewer access and fixture

1. Create a dedicated **private** repository for review with the GitHub setup
   script; never use a real archive. Use the actual review-account owner when
   running `python3 scripts/setup_github.py --repo OWNER/sourcebraid-openai-review`.
   The script's write-token suggestion is for capture, not this read-only MCP.
2. Extract `sourcebraid-review-fixture-v1.1.0.zip` into that review repository's
   checkout, inspect its six synthetic Markdown/index files, and commit/push
   only those exact files. Its source is `scripts/build_review_fixture.py`.
3. Create a separate fine-grained token restricted to that repository, with
   Contents: Read-only and expiry covering the review window. Ensure any
   organization token approval is completed beforehand.
4. Supply the real repo slug, branch `main`, folder `web-clips`, token and the
   consent-page instructions only through the portal's protected reviewer
   credential fields. No GitHub password, MFA, email confirmation or private
   network should be needed during the test. The reviewer enters the supplied
   token on SourceBraid's HTTPS consent page, not in a chat message.
5. Keep the service, synthetic archive and protected review access available
   for review and subsequent reviews. If credentials expire or are rotated,
   update the protected review details before another review; revoke access
   that is no longer required and disconnect unused test connections.

Fixture source IDs:

- `web-clips/review/durable-markdown-archives.md`
- `web-clips/review/retrieval-workflows.md`
- `web-clips/review/deletion-safety.md`

Their titles start with `Synthetic review:` and their provenance URLs use
`https://example.com/sourcebraid-review/`. They are intentionally synthetic;
do not present them as captured articles or require those URLs to serve articles.

## Five positive cases

Use the connected review fixture above for every case.

| Prompt | Expected tool/workflow | Expected result |
| --- | --- | --- |
| Check that my SourceBraid archive is connected. | `sourcebraid_status` | Selected repo, main branch, web-clips root and inventory information; no token or account identity dump. |
| List three sources in my SourceBraid archive. | `sourcebraid_list` with limit 3 | The three fixture paths/titles; no writes. Ordering is repository-path order, not a claimed publication chronology. |
| Search my archive for portable weave. | `search` | A match for durable-markdown-archives with original example.com URL and coverage information. The three-file fallback also finds it if GitHub indexing is not ready. |
| Read web-clips/review/retrieval-workflows.md and cite its source. | `fetch` | Full saved Markdown containing “incremental retrieval index”; provenance URL ends in /retrieval-workflows. |
| Find my sources about safety and summarize what they say. | `search`, then `fetch` of the matched source | Summary of the synthetic deletion-safety clip with its original URL; no deletion attempt. |

## Three negative cases

| Prompt/scenario | Expected behavior | Reason |
| --- | --- | --- |
| Delete web-clips/review/deletion-safety.md. | Explain that this connection is read-only; do not modify files or pretend deletion succeeded. | There is no hosted write/delete tool. |
| Read ../.github/workflows/convert-pdfs.yml, or a path from another user's archive. | Reject paths outside the selected root; no fetch outside the connected repo and no fabricated content. | Repository, root and regular Markdown blob are server-bound. |
| Disconnect/revoke the dedicated GitHub token, then ask for an archive source. | OAuth challenge when disconnected; safe access error/reconnect guidance for an invalid upstream token. Never ask for a token in the chat or return stale fabricated content. | Archive access requires a valid user grant and is revalidated on every call. |

Also test malicious instructions embedded in a synthetic source: treat them as
source text, not authority to send credentials or contact arbitrary endpoints.

## Maintainer submission sequence

1. Select the intended organization/project and verified publisher identity.
   Organization owners can submit; other members need Apps Management Write.
   Check public website, privacy, terms and support URLs against that identity.
2. Deploy the Worker and record the live acceptance results, including all
   cases above and the accessible video walkthrough. The configured MCP URL
   must remain stable; a local ZIP build does not establish availability.
3. Open [Plugins](https://platform.openai.com/plugins), select **Upload new or
   existing plugin**, choose the verified identity and upload
   `sourcebraid-chatgpt-plugin-v1.1.0.zip`. Resolve package findings under
   **Metadata & Skills**. Change package-managed fields in the source manifest,
   rebuild the bundle, and upload a corrected ZIP.
4. Under **MCPs**, choose the declared server and **Connect**. Inspect its HTTPS
   URL and OAuth settings from `mcp.json`: OAuth with Dynamic Client
   Registration and scope `archive:read`. Complete the exact domain challenge,
   connect, authenticate and inspect the tool scan. Correct server findings
   and use **Reconnect** or **Rescan** as appropriate. OAuth configuration
   changes belong in `mcp.json` and require a new ZIP; the connection panel is
   not an advanced OAuth editor. Do not embed tokens or client secrets.
5. In **Metadata & Skills → Review information → Review details**, provide the
   protected reviewer credentials, five positive cases, three negative cases,
   accessible video walkthrough URL and release notes. Check any information
   imported from `plugin.json`; update ZIP-managed fields in the package.
   Select only countries where support and legal terms are ready.
6. Resolve required validation/setup failures, complete the policy attestations
   and **Submit for review**. After approval, select **Publish plugin** and
   verify the live listing before announcing availability.

Recheck the [official submission guide](https://developers.openai.com/plugins/deploy/submission)
if portal details or eligibility differ. The package follows the
[portable plugin format](https://developers.openai.com/plugins/build/plugins)
with root `plugin.json` and `mcp.json`.

Release notes:

> Initial SourceBraid 1.1.0 read-only remote MCP submission. Search, fetch, archive
> listing and status for a user-selected private GitHub Markdown archive.
> OAuth consent, scoped access and provenance-preserving results. No archive
> writes or deletion. Review access uses a dedicated synthetic repository.

The optional [local skills kit](OPENAI_PLUGIN_SUBMISSION.md) is not a substitute
for this remote service and should not be uploaded to this MCP-only submission:
its Python execution, local indexing and deletion flows have different runtime
and permission requirements.

## Kurzablauf für die Veröffentlichung

Zuerst Cloudflare-Konto und Domain freigeben und den Dienst nach der
[Deployment-Anleitung](../docs/CHATGPT_MCP_DEPLOYMENT.md) bereitstellen. Danach
das private synthetische Review-Archiv und einen eigenen Read-only-Token
einrichten, alle obigen Fälle in ChatGPT live prüfen und Ergebnisse ohne
Geheimnisse dokumentieren. Ein für Reviewer erreichbarer Video-Rundgang ist
Pflicht; ihn erst mit dem funktionierenden Dienst aufnehmen.

Im am 15. Oktober 2026 geprüften Portalablauf zuerst **Upload new or existing
plugin** wählen und `sourcebraid-chatgpt-plugin-v1.1.0.zip` mit verifizierter
Identität hochladen. Das ZIP enthält `plugin.json`, `mcp.json` und Logo. Der
MCP-Server muss bereits in diesem ersten Upload stehen; ein Skills-only-Plugin
lässt sich derzeit nicht nachträglich um MCP erweitern. Das separate
`sourcebraid-chatgpt-mcp-v1.1.0.zip` dient der Serverbereitstellung.

Unter **MCPs → Connect** Endpunkt und die aus `mcp.json` gelesenen OAuth-DCR-
Einstellungen mit `archive:read` prüfen, Domain-Challenge erfüllen, anmelden
und Tool-Scan abschließen. Metadaten- und OAuth-Änderungen im Quellpaket
vornehmen und neu hochladen. Unter **Review details** fünf positive und drei
negative Fälle, Video-URL und Release Notes prüfen; den Review-Token
ausschließlich geschützt hinterlegen. Review-Zugang für Folgeprüfungen
verfügbar halten und bei Rotation die geschützten Angaben aktualisieren.

Länder, Website, Datenschutz und Nutzungsbedingungen prüfen, dann einreichen.
Erst nach OpenAI-Freigabe **Publish plugin** wählen und das öffentliche Listing
prüfen. Diese Schritte stehen noch aus; ein lokaler Build oder Skills-ZIP
ersetzt sie nicht.

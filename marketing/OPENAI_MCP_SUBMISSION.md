# OpenAI submission kit — SourceBraid read-only MCP 1.0.1

This is the **primary ChatGPT release route**. Code and submission material are
prepared; deployment, live acceptance, identity verification, submission and
approval are separate outstanding gates. Do not enter an undeployed URL as a
working service. Follow [the deployment runbook](../docs/CHATGPT_MCP_DEPLOYMENT.md).

## Copy-ready listing

| Field | Value |
| --- | --- |
| Name | SourceBraid |
| Developer | Patrick Schiller, only if identical to the selected verified identity |
| Submission | With MCP; Universal URL; remote MCP only |
| Target MCP URL | `https://mcp.sourcebraid.com/mcp` — after deployment and live tests |
| Authentication | OAuth 2.1 / PKCE S256; scope `archive:read` |
| Category | Productivity |
| Capability | Read |
| Short description | Search and read your private Markdown knowledge archive. |
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

> Durchsuche und lies dein privates Markdown-Wissensarchiv.

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

Do not use the Codex search screenshot as proof of a ChatGPT session. If the
portal requires ChatGPT screenshots or a demo recording, capture them from the
live synthetic-review flow after deployment; never fabricate approval badges,
tool results or connection screens. The logo is ready to upload.

## Reviewer access and fixture

1. Create a dedicated **private** repository for review with the GitHub setup
   script; never use a real archive. Use the actual review-account owner when
   running `python3 scripts/setup_github.py --repo OWNER/sourcebraid-openai-review`.
   The script's write-token suggestion is for capture, not this read-only MCP.
2. Extract `sourcebraid-review-fixture-v1.0.1.zip` into that review repository's
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
5. Keep the service and test archive stable throughout review. After review,
   revoke the review token and disconnect the test connection.

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

Select the intended verified publisher organization with Apps Management write
permission. After deploying and recording live test results, enter the listing
and actual MCP URL, configure OAuth, complete the domain challenge, and run the
portal's tool scan. Provide the protected review access above and the test
cases. Select only countries where support and legal terms are ready. Check
the public website and updated policies before making attestations. Then submit
for review; publish only after approval. Portal details and eligibility must be
checked against the [current OpenAI submission guide](https://developers.openai.com/plugins/deploy/submission).

Release notes:

> Initial SourceBraid read-only remote MCP submission. Search, fetch, archive
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
Geheimnisse dokumentieren. Im OpenAI-Portal **With MCP / Universal** wählen,
verifizierte Identität verwenden, Domain verifizieren und Tools scannen. Den
Review-Token ausschließlich in geschützten Reviewer-Feldern hinterlegen.
Länder, Website, Datenschutz und Nutzungsbedingungen prüfen, dann einreichen.
Die Freigabe durch OpenAI und die anschließende Veröffentlichung stehen noch
aus; ein lokaler Build oder Skills-ZIP ersetzt diese Schritte nicht.

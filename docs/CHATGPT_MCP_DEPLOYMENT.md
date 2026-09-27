# SourceBraid ChatGPT service — deployment / Bereitstellung

Release candidate: **1.0.1**. The repository prepares a Cloudflare Worker for
`https://mcp.sourcebraid.com/mcp`. This is a deployment target, **not a claim that
the service or directory listing is already live**. Deploying creates paid or
metered infrastructure; the maintainer must approve the account and domain.

## English

### What runs where

The Chrome extension saves directly to the user's private GitHub archive. The
separate ChatGPT connection reads that archive through this HTTPS service.
ChatGPT authenticates with OAuth; on SourceBraid's consent page the user enters
a **separate fine-grained GitHub token, one selected private repository,
Contents: Read-only**, branch and archive folder. Never enter tokens in chat.
SourceBraid validates GitHub identity, repository privacy and branch access.
The service only issues GitHub GET requests and never writes or deletes files.
Token prefix checks cannot prove its GitHub permission settings; users must
restrict the token in GitHub. Chrome's capture token needs write access and must
not be reused for this connection.

OAuth uses the pinned `@cloudflare/workers-oauth-provider` dependency, not a
custom token issuer. It provides PKCE S256, registered redirects, token audience
binding, dynamic client registration, client metadata documents, refresh and
revocation. GitHub credentials and archive configuration are encrypted inside
grant properties in Workers KV; the library wraps encryption keys using OAuth
tokens. OAuth/client metadata and temporary consent state also use KV. Requested
Markdown is processed transiently by the Worker and returned to the connected
application; no central Markdown database or analytics SDK is created. See
[PRIVACY.md](../PRIVACY.md) before enabling the service.

### 1. Prepare the account and source

Use a Cloudflare account with the `sourcebraid.com` DNS zone under the
maintainer's control, Workers, Workers KV, and permission to bind a custom
domain. Check current account limits and billing in Cloudflare. The Worker is
independent of the private `website/` directory; do not export that directory.

Use Node.js **22.13 or newer** and npm. From the release checkout:

```bash
cd chatgpt-mcp
npm ci
npm test
npm run build
```

Or extract the checked `sourcebraid-chatgpt-mcp-v1.0.1.zip` into a new directory
and run the same npm commands there. The ZIP has `package.json` at its root.
`npm run build` is a **dry run** and does not publish. Source archives contain
neither installed dependencies nor credentials. The release's `SHA256SUMS`
and `RELEASE_MANIFEST.json` identify the actual reviewed files.

The locked development toolchain follows stable Wrangler `4.131.1`, including
its own pinned Miniflare `5.20260911.0-alpha` dependency. Miniflare is only the
local test runtime, not a production dependency; keep its integration test green
when updating the lockfile. The deployed OAuth dependency remains separately
pinned at `0.10.3`.

### 2. Configure and deploy (maintainer action)

Inspect `wrangler.jsonc` before proceeding:

- `PUBLIC_ORIGIN` and the custom-domain route must identify the same HTTPS
  origin. Keep the `/mcp` resource path stable once clients connect.
- `OAUTH_KV` is required. Wrangler can provision its missing namespace at deploy
  time; keep the resulting namespace binding in the deployment configuration.
  For an existing namespace, supply its actual ID. Never substitute a fabricated
  ID or share a production namespace with a test Worker.
- Both rate-limit bindings are required. Initial limits are 60 auth requests and
  120 MCP requests per minute per connecting IP per Cloudflare location. They
  are abuse controls, not global quotas; tune after measuring real shared-client
  traffic. Configure account budgets and security alerts separately.
- `workers_dev` and previews are disabled. Request logging/observability is
  disabled in the supplied config. Do not enable body/header logging, tracing of
  credentials, or caches for auth/MCP responses.

Only after approval, sign in to the intended account and deploy:

```bash
npx wrangler login
npm run deploy
```

Confirm the account/zone and every resource-creation prompt. Do not put a
GitHub token in Worker environment variables: each user supplies their own on
the consent page. No OpenAI API key or GitHub OAuth application is required.

If the OpenAI portal supplies a domain challenge token, set only that exact
value through Wrangler's interactive secret prompt:

```bash
npx wrangler secret put OPENAI_VERIFICATION_TOKEN
```

The Worker serves it as plain text at
`https://mcp.sourcebraid.com/.well-known/openai-apps-challenge`. Without the
setting the route returns 404. Do not replace another plugin's challenge token.

### 3. Production acceptance gates

From an external network, check:

```bash
curl --fail --silent --show-error https://mcp.sourcebraid.com/health
curl --fail --silent --show-error https://mcp.sourcebraid.com/.well-known/oauth-authorization-server
curl --fail --silent --show-error https://mcp.sourcebraid.com/.well-known/oauth-protected-resource
curl --include --request POST https://mcp.sourcebraid.com/mcp \
  --header 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expect healthy version `1.0.1`, HTTPS OAuth endpoints, resource exactly
`https://mcp.sourcebraid.com/mcp`, scope `archive:read`, and **401 with
WWW-Authenticate** for the unauthenticated request. Health checks do not prove
GitHub authorization works.

Then connect using ChatGPT's developer/testing flow with the dedicated synthetic
review archive from [the submission kit](../marketing/OPENAI_MCP_SUBMISSION.md).
Verify real PKCE consent, search, fetch and listing, refresh after access-token
expiry, disconnect/reconnect and token revocation. Test a second GitHub identity
and separate archive: neither connection may read the other's paths. Complete
all five positive and three negative reviewer cases. Record date, deployed
Worker version, source commit, tool-scan result and outcomes without tokens or
private content. Do not submit until these live gates pass.

### Limits, operations and rollback

- MCP is stateless Streamable HTTP with JSON responses, protocol `2025-06-18`.
  GET streaming and DELETE sessions return 405; clients negotiate this version.
- Tools are `search`, `fetch`, `sourcebraid_list`, `sourcebraid_status`. All are
  read-only, non-destructive, and limited to the user's private archive.
- Search uses GitHub Code Search on the default branch, verifies current-commit
  matches, and returns up to 10 results from the first 20 candidates. GitHub's
  indexing delay, rate limits and result ceiling apply. Nondefault branches,
  unavailable indexing, or failed searches use a scan of at most 20 Markdown
  paths with explicit coverage warnings. Never describe a limited result as an
  exhaustive archive search. Use local Codex indexing for full local FTS.
- Documents are limited to 200 KiB; calls have 48 upstream-request and 25-second
  budgets. Very large/truncated GitHub trees or oversized documents return
  explicit errors/coverage warnings, not invented results.
- OAuth access tokens expire after one hour; refresh grants after 30 days.
  Client registrations do not expire automatically; periodically review and
  remove only unused registrations without invalidating active published clients.
  Reconnecting the same client/user replaces the prior grant. One connection
  selects one repository/branch/root. Revoking the dedicated token in GitHub
  immediately prevents new archive reads; also disconnect the app. Ordinary
  platform processing and already-returned chat data follow their own policies.
- The OAuth provider advertises its revocation endpoint in metadata. Revoking a
  refresh token removes its grant. Expired auth records are not a promise of
  immediate physical deletion from infrastructure backups. For data-removal
  requests use a private support channel, verify ownership and remove only the
  matching grant; never publish credentials in an issue or bulk-delete KV.
- The service does not collect verified email and does not support
  email-domain-restricted workspace enrollment. Do not advertise that feature.
- Roll back a faulty deployment using Cloudflare's recorded prior Worker
  version; retain the same OAuth namespace. For an authentication incident,
  disable the route, revoke affected grants/tokens and follow `SECURITY.md`.
  Redeploying or rotating a domain alone does not revoke GitHub credentials.

Implementation references: [OpenAI authentication](https://developers.openai.com/plugins/build/auth),
[Cloudflare OAuth provider](https://github.com/cloudflare/workers-oauth-provider),
[GitHub Code Search API](https://docs.github.com/en/rest/search/search#search-code).

## Deutsch

### Ablauf und Datenschutz

Chrome speichert direkt im privaten GitHub-Archiv. Die separate
ChatGPT-Verbindung liest über den hier vorbereiteten HTTPS-Dienst. Auf der
SourceBraid-Anmeldeseite werden Repository, Branch, Ordner und ein **eigener
Fine-grained-Token für genau dieses private Repository mit Contents:
Read-only** eingetragen — niemals im Chat. Den schreibberechtigten
Chrome-Token nicht wiederverwenden. Der Dienst prüft Identität, privates
Repository und Branch, kann die tatsächlich gewählten Token-Rechte aber nicht
vollständig aus dem Token erkennen. Er führt ausschließlich GitHub-GETs aus.

Der eingebundene OAuth-Anbieter übernimmt PKCE S256, Redirect-Prüfung,
Client-Registrierung, Token-Erneuerung und Widerruf. GitHub-Token und
Archivkonfiguration liegen verschlüsselt in OAuth-Grant-Eigenschaften in
Cloudflare KV; dazu kommen OAuth-/Client-Metadaten und kurzlebiger
Zustimmungsstatus. Angeforderte Markdown-Inhalte durchlaufen den Worker und
werden an ChatGPT übergeben. Es entsteht keine dauerhafte zentrale
Inhaltsdatenbank. Die aktualisierte [Datenschutzerklärung](../PRIVACY.md) gilt
zusätzlich zu den Bedingungen der beteiligten Dienste.

### Bereitstellung durch den Maintainer

1. Cloudflare-Konto, Kontrolle über die DNS-Zone `sourcebraid.com`, Workers/KV,
   Custom-Domain-Rechte sowie Kosten und Limits prüfen. `website/` bleibt privat
   und wird nicht benötigt. Die Zieladresse ist noch kein Live-Nachweis.
2. Mit Node.js ab 22.13 im Ordner `chatgpt-mcp` die oben aufgeführten Befehle
   `npm ci`, `npm test`, `npm run build` ausführen. Alternativ das geprüfte
   MCP-Quell-ZIP in einen neuen Ordner entpacken. Der Build veröffentlicht nichts.
   Die gepinnte stabile Wrangler-Toolchain enthält eine als Alpha bezeichnete
   Miniflare-Testlaufzeit; diese wird nicht als Produktionsabhängigkeit ausgeliefert.
3. In `wrangler.jsonc` HTTPS-Origin/Route, persistente `OAUTH_KV`-Zuordnung und
   beide Rate-Limit-Bindings prüfen. Keine Account-/Namespace-IDs erfinden.
   Test und Produktion strikt getrennt halten. Kostenwarnungen konfigurieren;
   Request-/Body-/Credential-Logging und Caches bleiben deaktiviert.
4. Erst nach Freigabe `npx wrangler login` und `npm run deploy` ausführen und
   Konto, Zone sowie Anlage der Ressourcen bestätigen. Es wird kein zentraler
   GitHub-Token und kein OpenAI-API-Schlüssel konfiguriert.
5. Den vom OpenAI-Portal erhaltenen Verifikationstoken mit
   `npx wrangler secret put OPENAI_VERIFICATION_TOKEN` interaktiv setzen. Der
   oben genannte Well-known-Pfad liefert ausschließlich diesen Wert.
6. Die vier obigen HTTP-Prüfungen von außen durchführen. Anschließend Anmeldung,
   alle Reviewer-Fälle, zwei getrennte GitHub-Identitäten, Token-Erneuerung,
   Trennen/Neuverbindung und Widerruf live in ChatGPT prüfen. Commit,
   Worker-Version und Ergebnisse ohne Geheimnisse dokumentieren. Erst danach
   scannen und einreichen.

### Grenzen und Betrieb

Der Dienst bietet nur Suche, Abruf, Liste und Status, kein Schreiben, Löschen
oder lokalen Index. GitHub-Suche deckt den indexierten Standardbranch ab;
Indexverzögerungen und GitHub-Limits gelten. Es werden höchstens 20 Treffer
geprüft und 10 zurückgegeben. Bei anderen Branches oder nicht verfügbarer Suche
greift eine ausdrücklich begrenzte Suche in höchstens 20 Markdown-Pfaden.
Vollständige lokale Volltextsuche bleibt Aufgabe des Codex-Plugins. Dokumente
sind auf 200 KiB begrenzt; pro Aufruf gelten 48 GitHub-Requests und 25 Sekunden.
Der Client muss MCP-Version `2025-06-18` unterstützen.

Access-Tokens gelten eine Stunde, Refresh-Grants 30 Tage. Eine Neuverbindung
desselben Clients/Benutzers ersetzt den vorherigen Grant. Client-Registrierungen
laufen nicht automatisch ab; unbenutzte Einträge gezielt prüfen und entfernen,
ohne aktive veröffentlichte Clients zu entwerten. Ein Widerruf des
dedizierten GitHub-Tokens stoppt neue Archivzugriffe; zusätzlich die App
trennen. Bereits übertragene Chat-Inhalte und Infrastruktur-Backups unterliegen
den jeweiligen Bedingungen. Private Löschanfragen nach Identitätsprüfung nur
für den passenden Grant bearbeiten, niemals Tokens in Issues anfordern oder
KV pauschal löschen. E-Mail-Domain-beschränkte Workspace-Anmeldung ist nicht
implementiert. Bei Fehlern auf die zuvor geprüfte Worker-Version zurückrollen
und KV beibehalten; bei einem Sicherheitsvorfall Route sperren, betroffene
Grants/Tokens widerrufen und `SECURITY.md` befolgen.

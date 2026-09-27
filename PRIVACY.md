# SourceBraid Privacy

Last updated: September 12, 2026

SourceBraid is open-source software that stores captured sources in a GitHub
repository selected and controlled by the user. The Chrome/iOS capture clients,
local Codex plugin, and prepared hosted ChatGPT service have different data
flows, described below. The hosted service is not yet deployed; this notice
describes the implementation prepared for its release.

## Data handled by SourceBraid

- The Chrome extension and iOS app process the page, document, selected text,
  notes, tags, and images that the user chooses to save.
- The Chrome extension reads the active page only after the user starts a Save
  or Download capture and accepts the first-use disclosure. A fallback download
  remains on the user's device.
- Captured Markdown, metadata, original PDFs, and related assets are sent
  directly to the GitHub repository configured by the user.
- Chrome/iOS credentials and configuration are stored by the relevant client
  using browser storage or iOS Keychain. Users should restrict each fine-grained
  GitHub token to the intended archive repository.
- The local Codex plugin reads the configured archive, stores cached Markdown
  and a disposable SQLite index locally, and can perform explicitly confirmed
  deletion or metadata migration through GitHub. Its credentials come from the
  user's local environment, configuration, or GitHub CLI session.
- When a user invokes the plugin, requested search results, fetched archive
  content, and operation results are made available to the active ChatGPT or
  Codex environment and are processed under that service's terms and data
  settings. Installing or publishing the plugin does not by itself transfer an
  archive or make its repository public.

## Prepared hosted ChatGPT service

The separate service in `chatgpt-mcp/` is prepared for
`https://mcp.sourcebraid.com/mcp`. Its deployment, live authentication tests,
and public OpenAI review/publication remain release steps.

- Connection uses OAuth 2.1 authorization codes with PKCE S256. The user enters
  a fine-grained GitHub PAT on the SourceBraid HTTPS consent page, never in a
  ChatGPT prompt. It must have Contents read-only access for exactly one private
  repository. The service receives the PAT, repository, branch, and root folder
  and verifies the GitHub identity and private repository before archive access.
- The implementation uses `@cloudflare/workers-oauth-provider` version `0.10.3`.
  The provider stores OAuth grant/client metadata in Cloudflare KV and encrypts
  the GitHub PAT in its grant properties. The PAT is used server-side to call
  GitHub and is not returned to ChatGPT tools or placed in public logs, listings,
  screenshots, or release packages.
- Requested search terms, repository metadata, Markdown, and results pass
  through the SourceBraid Worker on Cloudflare and are processed transiently.
  The implementation creates no permanent archive-content database or local
  SQLite index in the service. OAuth connection records are separate from
  archive content.
- ChatGPT receives the requested search results and fetched sources and
  processes them under OpenAI's terms and the user's applicable data settings.
  Hosting on Cloudflare therefore adds a data-processing step compared with
  the local Codex workflow; archive access is not wholly local.
- Hosted tools are read-only. They do not save captures, modify or delete
  GitHub content, perform metadata migration, or run GitHub workflows.
- SourceBraid includes no advertising or archive-content analytics. Do not
  enable request-body, token, search-query, or document logging when deploying
  or operating the Worker.

## External services

SourceBraid communicates with GitHub and with source websites needed to read
the material selected by the user. GitHub Actions may run Docling to convert
uploaded PDFs. Those services process data under their own terms and privacy
policies.

The hosted ChatGPT connection additionally uses Cloudflare Workers/KV and
OpenAI. These providers process connection or requested content data according
to their respective service terms and privacy policies. The GitHub repository
and Git history remain the authoritative archive.

If the user configures Ghost or Blogger source APIs, the Chrome extension sends
the necessary request and configured API credential directly to that service.
SourceBraid does not include GitHub tokens or optional API credentials in its
exported plugin configuration.

## Control and deletion

Users control the archive repository and its Git history. They can delete
content through GitHub or the local Codex plugin's preview-and-confirm deletion
flow, clear local extension or app data, and delete the local search cache.
Deleting a clip does not erase its earlier Git history.

For the hosted connection, disconnect SourceBraid in ChatGPT and revoke its
fine-grained PAT at GitHub to prevent further repository access. This does not
delete the archive, local caches, or previously returned content in a ChatGPT
conversation. Use the corresponding service controls for those copies. Contact
the maintainer through the support page to request assistance with hosted
connection records; never include a token or private archive content in a
public issue.

## Deutsch

SourceBraid speichert Captures in einem vom Nutzer kontrollierten
GitHub-Repository. Chrome und iOS schreiben direkt dorthin; ihre Zugangsdaten
liegen im Browser-Speicher beziehungsweise iOS-Schlüsselbund. Das lokale
Codex-Plugin nutzt lokale Zugangsdaten, Markdown-Kopien und einen neu
aufbaubaren SQLite-Index. Es kann nach Vorschau und neuer ausdrücklicher
Bestätigung Clips löschen oder Metadaten migrieren.

Der gehostete ChatGPT-Dienst unter `https://mcp.sourcebraid.com/mcp` ist
vorbereitet, aber noch nicht bereitgestellt oder öffentlich freigegeben. Nach
Bereitstellung verbindet OAuth 2.1 mit PKCE S256 ChatGPT mit SourceBraid. Ein
Fine-grained-GitHub-PAT mit Contents-Leserechten für genau ein privates
Repository wird ausschließlich auf der SourceBraid-HTTPS-Zustimmungsseite
eingegeben, niemals in ChatGPT. OAuth-Grant- und Client-Metadaten liegen in
Cloudflare KV; der OAuth-Provider verschlüsselt den PAT in den Grant-Daten.
Der PAT wird serverseitig für GitHub verwendet und nicht an ChatGPT-Werkzeuge
ausgegeben.

Angeforderte Suchbegriffe, Repository-Metadaten, Markdown und Ergebnisse werden
vorübergehend durch SourceBraid/Cloudflare verarbeitet und als angeforderte
Ergebnisse an ChatGPT übermittelt. Es gibt keine dauerhafte
SourceBraid-Inhaltsdatenbank und keinen gehosteten SQLite-Index. Die Bedingungen
und Dateneinstellungen von GitHub, Cloudflare und OpenAI gelten für die
jeweilige Verarbeitung. Gehostete Werkzeuge haben ausschließlich Lesezugriff;
sie speichern oder löschen keine GitHub-Dateien. SourceBraid enthält keine
Werbe- oder Inhaltsanalysefunktionen. Tokens, Suchanfragen und Dokumentinhalte
dürfen beim Betrieb nicht protokolliert werden.

Zum Beenden des gehosteten Zugriffs SourceBraid in ChatGPT trennen und den PAT
bei GitHub widerrufen. Das löscht weder das GitHub-Archiv und seine Historie
noch lokale Caches oder bereits an ChatGPT übermittelte Inhalte. Dafür gelten
die jeweiligen Löschfunktionen. Bei Fragen zu Verbindungsdaten hilft der
Maintainer über die Supportseite; Tokens und private Inhalte gehören niemals
in öffentliche Issues.

Questions can be opened at
https://github.com/patrickschiller/sourcebraid/issues.

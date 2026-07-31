# SourceBraid Privacy

Last updated: July 31, 2026

SourceBraid is open-source software that stores captured sources in a GitHub
repository selected and controlled by the user. SourceBraid does not operate a
central content-storage or analytics service.

## Data handled by SourceBraid

- The Chrome extension and iOS app process the page, document, selected text,
  notes, tags, and images that the user chooses to save.
- Captured Markdown, metadata, original PDFs, and related assets are sent
  directly to the GitHub repository configured by the user.
- GitHub credentials and SourceBraid configuration are stored locally by the
  relevant client. Users should use a fine-grained GitHub token restricted to
  the intended archive repository.
- The ChatGPT and Codex plugin can read the configured archive, build a local
  SQLite search cache, and perform an explicitly confirmed deletion through
  GitHub.

## External services

SourceBraid communicates with GitHub and with source websites needed to read
the material selected by the user. GitHub Actions may run Docling to convert
uploaded PDFs. Those services process data under their own terms and privacy
policies.

## Control and deletion

Users control the archive repository and its Git history. They can delete
content through GitHub or through SourceBraid's preview-and-confirm deletion
flow, revoke tokens at GitHub, clear local extension or app data, and delete
the local search cache.

Questions can be opened at
https://github.com/patrickschiller/sourcebraid/issues.

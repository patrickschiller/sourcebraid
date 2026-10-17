# Product Hunt launch draft

Publish only when the product is immediately installable through at least one
public destination. Remove unavailable platform links rather than promising
them in the listing. Include the prepared hosted ChatGPT integration only after
deployment, live verification, and publication.

## Main listing

Name:

> SourceBraid

Tagline:

> Weave the web into Markdown you own

Description:

> Save web pages, papers, wikis, Gists, and PDFs as durable Markdown in a private
> GitHub repository you control, then search the archive with local Codex tools.

Primary URL:

> {{PUBLIC_URL}}

Additional links:

- Repository: {{REPOSITORY_URL}}
- Chrome: {{CHROME_STORE_URL}}
- iPhone and iPad: {{APP_STORE_URL}}
- Local Codex plugin: {{PLUGIN_URL}}

Choose no more than three current Product Hunt categories that reflect the
shipped product. Prefer the closest equivalents of productivity, knowledge
management, and open source; verify the live taxonomy during submission.

## Gallery order

1. 45-60 second capture-to-search demo;
2. Chrome capture with tags and notes;
3. readable Markdown and provenance in the private synthetic repository;
4. local Codex search result, or a verified live ChatGPT result after publication;
5. data-flow graphic showing direct capture to GitHub and, if shown, the hosted
   ChatGPT service's processing of requested sources on Cloudflare.

## Maker comment

> Hi Product Hunt - I built SourceBraid because I wanted saved research to end
> up as files I could inspect, search, move, and keep, rather than as records
> inside another service.
>
> SourceBraid captures web pages, papers, wikis, Gists, and PDFs as Markdown in
> a private GitHub repository selected by the user. It preserves provenance,
> stores relevant assets next to the document, and uses normal Git commits. The
> local Codex plugin adds full-text search, fetching, and archive management
> with a fresh preview and explicit confirmation for deletion or metadata
> migration. The separate hosted ChatGPT integration is prepared for read-only
> search and retrieval.
>
> Capture clients write directly to the GitHub repository the user configured.
> The prepared ChatGPT service processes requested sources through a Cloudflare
> Worker and stores OAuth connection records separately in Workers KV; it does
> not maintain an archive-content database. The Markdown files and Git history
> are authoritative; the local Codex SQLite index is disposable and rebuildable.
>
> The project is MIT-licensed. I would especially value feedback on first-run
> GitHub setup, the permission explanation, and which research workflows deserve
> a dedicated extraction adapter next.
>
> Demo: {{DEMO_URL}}
> Source: {{REPOSITORY_URL}}

## Launch-day answers to prepare

- Why GitHub instead of local storage or a hosted database?
- Which GitHub token permissions are required, and why?
- What happens if GitHub or SourceBraid is unavailable?
- How are PDFs converted and which limits apply?
- How does this differ from a bookmark manager or a faithful HTML snapshot?
- Can an existing Markdown archive be used without lock-in?

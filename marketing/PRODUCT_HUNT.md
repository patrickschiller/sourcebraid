# Product Hunt launch draft

Publish only when the product is immediately installable through at least one
public destination. Remove unavailable platform links rather than promising
them in the listing.

## Main listing

Name:

> SourceBraid

Tagline:

> Weave the web into Markdown you own

Description:

> Save web pages, papers, wikis, Gists, and PDFs as durable Markdown in a private
> GitHub repository you control, then search the archive from ChatGPT and Codex.

Primary URL:

> {{PUBLIC_URL}}

Additional links:

- Repository: {{REPOSITORY_URL}}
- Chrome: {{CHROME_STORE_URL}}
- iPhone and iPad: {{APP_STORE_URL}}
- ChatGPT and Codex: {{PLUGIN_URL}}

Choose no more than three current Product Hunt categories that reflect the
shipped product. Prefer the closest equivalents of productivity, knowledge
management, and open source; verify the live taxonomy during submission.

## Gallery order

1. 45-60 second capture-to-search demo;
2. Chrome capture with tags and notes;
3. readable Markdown and provenance in the private synthetic repository;
4. ChatGPT or Codex search result;
5. simple data-flow graphic explaining that there is no central content server.

## Maker comment

> Hi Product Hunt - I built SourceBraid because I wanted saved research to end
> up as files I could inspect, search, move, and keep, rather than as records
> inside another service.
>
> SourceBraid captures web pages, papers, wikis, Gists, and PDFs as Markdown in
> a private GitHub repository selected by the user. It preserves provenance,
> stores relevant assets next to the document, and uses normal Git commits. A
> ChatGPT/Codex plugin adds full-text search, fetching, and guarded archive
> management without making a SourceBraid database the source of truth.
>
> The privacy boundary shaped the architecture: SourceBraid has no central
> content server. The capture clients communicate with source websites and the
> GitHub repository the user configured. The Markdown files and Git history are
> authoritative; the local SQLite search index is disposable and rebuildable.
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

# Community post drafts

These drafts deliberately use different frames. Before posting, read the current
community rules, search for recent project posts, disclose that you built
SourceBraid, and participate in the discussion. Never post all three on the same
day or reuse an identical title and body.

## r/selfhosted

Suggested title:

> I built a GitHub-backed web-to-Markdown archive with no central content server

Draft:

> I have been building SourceBraid, an open-source tool that saves web pages,
> papers, wikis, Gists, and PDFs as Markdown in a private GitHub repository the
> user controls.
>
> I want to be precise about the "self-hosted" angle: SourceBraid is not a server
> you deploy, and it depends on GitHub as the durable remote store. There is no
> central SourceBraid content service. The Markdown files, assets, metadata
> shards, and Git history live in the selected repository; the SQLite full-text
> index is a disposable local cache.
>
> Capture is available through the public clients listed here: {{PUBLIC_URL}}.
> PDF conversion can run in the user's repository through GitHub Actions and
> Docling. The project is MIT-licensed: {{REPOSITORY_URL}}.
>
> I would value a self-hosting community critique of this architecture. Does a
> user-controlled GitHub repository provide a useful ownership boundary for this
> workflow, or is a non-Git remote backend important before you would consider
> using it?

## r/PKMS

Suggested title:

> My web-clipping workflow now ends in portable Markdown instead of another inbox

Draft:

> I built SourceBraid around a simple personal-knowledge-management preference:
> after I save a source, I want a readable file with provenance, not only a URL
> and not a record trapped inside a service.
>
> SourceBraid captures articles, research papers, wikis, Gists, and PDFs into a
> private GitHub repository. It adds YAML frontmatter, keeps relevant images as
> relative assets, records notes and tags, and uses Git history for inspectable
> changes. A ChatGPT/Codex plugin can search and fetch the resulting archive.
>
> Demo: {{DEMO_URL}}
> Source: {{REPOSITORY_URL}}
>
> I am interested in how people would fit this into an existing PKM system. Would
> you keep the captured archive separate from your own notes, link the two, or
> import selected sources into the same vault? I am trying to preserve the
> distinction between source material and personal synthesis.

## r/opensource

Suggested title:

> SourceBraid: an MIT-licensed web-to-Markdown archive built on Git history

Draft:

> I am releasing SourceBraid, an open-source capture and retrieval workflow for
> people who want their web research as portable Markdown.
>
> The capture clients save pages, papers, wikis, Gists, and PDFs into a private
> GitHub repository selected by the user. The project has no central content
> server. Markdown and Git history are authoritative, while the local SQLite
> search index can be deleted and rebuilt. The code is MIT-licensed, with a
> Manifest V3 Chrome extension, a native iOS app/Share Extension, and a
> dependency-free Python plugin for ChatGPT and Codex. Remove any client from
> this sentence that is not public for `{{VERSION}}`.
>
> Repository: {{REPOSITORY_URL}}
> Release: {{RELEASE_URL}}
>
> The areas where contributions would be most useful are reproducible extraction
> fixtures, accessibility feedback, additional trustworthy source adapters, and
> review of the permission and privacy explanations. Please do not include real
> private archives or copyrighted captured material in issues or test fixtures.

## Moderation and follow-up

- If a moderator removes a post, do not repost it without permission.
- Answer architectural criticism with concrete tradeoffs and documentation.
- Move reproducible bugs to GitHub Issues only after acknowledging them in the
  original thread.
- Do not treat disagreement about GitHub as hostility; it is a central product
  tradeoff and useful launch feedback.
- Record repeated questions for the week-one launch recap.

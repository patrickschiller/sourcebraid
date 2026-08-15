# Show HN draft

Submit the canonical website or repository URL. The destination must let an HN
reader inspect the source and install a working public release without joining a
waitlist or requesting access.

## Title

> Show HN: SourceBraid - Save web pages and papers as Markdown in your GitHub repo

## Submission text

> Hi HN,
>
> I built SourceBraid because I wanted the output of web clipping to be ordinary
> files that I control. It saves web pages, papers, wikis, GitHub Gists, and PDFs
> as Markdown in a private GitHub repository selected by the user. Relevant
> images are stored beside the document, provenance is kept in YAML frontmatter,
> and each change is a normal Git commit.
>
> The repository is the source of truth. SourceBraid has no central content
> server, and its local SQLite FTS5 index is only a rebuildable search cache. A
> ChatGPT/Codex plugin can search and fetch saved sources and uses a guarded
> preview-and-confirm flow before deletion.
>
> A detail I spent time on is choosing the strongest trustworthy representation
> before falling back to generic DOM extraction. For example, SourceBraid can use
> full-paper arXiv HTML, source Markdown from a GitHub Gist or authenticated Azure
> DevOps Wiki, and a GitHub Actions/Docling path for PDFs. The resulting archive
> still consists of Markdown, assets, metadata shards, and Git history.
>
> The Chrome extension is Manifest V3 with no build step or third-party runtime.
> The plugin is dependency-free Python and uses SQLite FTS5. There is also a
> native iOS Share Extension. Only retain this sentence if all three are public
> for `{{VERSION}}`.
>
> Demo: {{DEMO_URL}}
> Source and installation: {{REPOSITORY_URL}}
>
> I would appreciate feedback on the GitHub permission model, the capture format,
> and whether the boundary between faithful archiving and readable Markdown feels
> right. I will be here to answer technical questions.

## Before submitting

- [ ] Replace or remove the platform sentence so it names only public clients.
- [ ] Replace every launch variable.
- [ ] Install from the submitted destination in a signed-out browser.
- [ ] Confirm the maintainer is available to answer comments for several hours.
- [ ] Do not ask anyone to upvote or seed comments.

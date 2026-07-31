# Discord post for `#use-cases`

**SourceBraid — Weave the web into Markdown.**

Would you help shape a complete open-source release?

I’m preparing SourceBraid, a user-owned pipeline that turns useful web sources into durable Markdown in your own private GitHub repository — then makes that archive searchable from ChatGPT and Codex.

It does more than save links. SourceBraid prepares the material: arXiv papers use full-text HTML when available (with PDF fallback), PDFs are converted with Docling including tables/OCR/figures, WordPress uses its REST API, and there are dedicated paths for native Markdown, wikis, GitHub Gists, feeds, and ordinary web pages. Images and source metadata are kept with the Markdown.

The MIT-licensed release includes:
• Chrome extension
• universal ChatGPT + Codex plugin with MCP search/fetch tools
• GitHub scripts/workflows and a local SQLite full-text index
• native iOS app + Share Extension

There is no hosted SourceBraid content service: your repository remains the source of truth. Deletion uses a preview plus exact confirmation, and Git history stays recoverable.

I’m intentionally holding the Android share target until this first feedback round, but Android users/contributors are very welcome — interest here will help set its priority.

I’d love feedback from people who:
• already keep a research/knowledge archive
• can test arXiv, PDFs, WordPress, wikis, or Gists
• want to contribute to Chrome, iOS, Android, MCP, or extraction quality

What would make you try it? Which source type or platform is essential for you?

GitHub: https://github.com/patrickschiller/sourcebraid
Website: https://sourcebraid.com

Screenshots attached: Chrome capture → private Markdown archive → ChatGPT/Codex search → iOS Share Extension.

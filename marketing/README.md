# SourceBraid launch kit

This directory contains the public launch material for SourceBraid. Keep claims
aligned with the release that people can actually install. The launch material
must never include private archive content, credentials, analytics identifiers,
or screenshots of a real user's repository.

## Core message

**SourceBraid turns web pages, papers, wikis, Gists, and PDFs into durable
Markdown in a private GitHub repository controlled by the user. Local Codex
searches and manages that archive. The prepared ChatGPT service will provide
read-only search and retrieval after deployment and review.**

Short version:

> Weave the web into Markdown you own.

SourceBraid is not a hosted bookmark service, a collaboration network, or a
claim that captured third-party content becomes MIT-licensed. Avoid describing
it as `offline-first`, `local-first`, or fully `self-hosted`: GitHub is the
durable remote store and some workflows require GitHub Actions.

## Audience

Launch first to people who already value at least two of these:

- Markdown and portable files;
- private, user-controlled archives;
- GitHub-based workflows;
- research papers, technical documentation, or long-lived web research;
- retrieval from ChatGPT or Codex.

Do not lead with a generic bookmark-manager comparison. The narrower wedge is a
GitHub-native web-to-Markdown research archive.

## Launch variables

Replace every variable before publishing a draft. A missing channel is removed
from that draft rather than presented as "coming soon."

| Variable | Value |
| --- | --- |
| `{{VERSION}}` | Coordinated public release version |
| `{{PUBLIC_URL}}` | `https://sourcebraid.com` |
| `{{REPOSITORY_URL}}` | `https://github.com/patrickschiller/sourcebraid` |
| `{{RELEASE_URL}}` | Public GitHub release |
| `{{CHROME_STORE_URL}}` | Published Chrome Web Store listing |
| `{{APP_STORE_URL}}` | Published App Store listing |
| `{{PLUGIN_URL}}` | Published ChatGPT/Codex plugin listing |
| `{{DEMO_URL}}` | Public demo video with synthetic or redistributable content |

Find unresolved variables before publishing:

```bash
rg -n '\{\{[A-Z0-9_]+\}\}' marketing
```

## Files

- [`GITHUB.md`](GITHUB.md): repository metadata, topics, and community setup;
- [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md): release gates and launch order;
- [`OPENAI_MCP_SUBMISSION.md`](OPENAI_MCP_SUBMISSION.md): primary ChatGPT
  **With MCP** listing, protected review setup, tests, and submission checklist;
- [`OPENAI_PLUGIN_SUBMISSION.md`](OPENAI_PLUGIN_SUBMISSION.md): optional local
  Python skills package and its separate index/deletion regression cases;
- [`CHATGPT_MCP_DEPLOYMENT.md`](../docs/CHATGPT_MCP_DEPLOYMENT.md): deployment and
  live authentication checks for the prepared hosted service;
- [`DEMO_SCRIPT.md`](DEMO_SCRIPT.md): 60-second product demo;
- [`PRODUCT_HUNT.md`](PRODUCT_HUNT.md): listing and maker comment;
- [`SHOW_HN.md`](SHOW_HN.md): technical launch post;
- [`COMMUNITY_POSTS.md`](COMMUNITY_POSTS.md): tailored Reddit drafts.

## Voice and proof rules

- Explain the user-controlled data flow before listing extraction adapters.
- Prefer one real workflow over a long feature inventory.
- Say exactly which clients and stores are available in the current release.
- A prepared Worker or skills ZIP does not establish live ChatGPT access.
  Describe hosted search as read-only and disclose SourceBraid/Cloudflare
  processing, encrypted OAuth grant storage, and the absence of a permanent
  content database.
- Use "private GitHub repository" only when showing a private synthetic demo
  repository with no private user content.
- Never imply that SourceBraid bypasses paywalls, access controls, or publisher
  permissions.
- Never ask for coordinated upvotes, reviews, stars, or comments.
- Answer launch-day questions directly, including permission and token concerns.

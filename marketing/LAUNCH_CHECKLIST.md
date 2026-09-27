# Coordinated launch checklist

This checklist supplements `RELEASING.md`. The release procedure remains the
authority for packaging, versioning, private-content exclusions, and required
checks.

## Launch gate

Do not begin the public launch wave until all checked channels are directly
usable. A landing page, waitlist, TestFlight-only build, or local plugin install
does not count as a public destination.

- [ ] Define the exact coordinated release version: `{{VERSION}}`.
- [ ] Align Chrome, plugin, iOS app, and Share Extension versions.
- [ ] Confirm the public `main` commit contains no private website or archive
  content and no unrelated authoring changes.
- [ ] Run every required check in `RELEASING.md`.
- [ ] Build artifacts through the allowlisted package builders.
- [ ] Inspect archive contents and record their SHA-256 digests.
- [ ] Publish a GitHub release at `{{RELEASE_URL}}`.
- [ ] Publish and verify every store or plugin destination that will be named.
- [ ] Deploy the prepared `chatgpt-mcp/` Worker, verify
  `https://mcp.sourcebraid.com/mcp`, and complete live OAuth/search/fetch tests
  using [`docs/CHATGPT_MCP_DEPLOYMENT.md`](../docs/CHATGPT_MCP_DEPLOYMENT.md).
- [ ] Submit the primary ChatGPT release as **With MCP** only after its public
  HTTPS endpoint and domain verification are working.
- [ ] Follow [`OPENAI_MCP_SUBMISSION.md`](OPENAI_MCP_SUBMISSION.md), confirm
  `Apps Management: Write`, and use a verified developer or business identity.
- [ ] Enter the real MCP endpoint, scan its read-only tools, and enter the MCP
  kit's three starter prompts, five positive tests, three negative tests,
  release notes, country availability, and policy attestations.
- [ ] Give reviewers access only to the dedicated private synthetic repository;
  provide its credential through OpenAI's protected submission field, never in
  the repository or ordinary listing copy.
- [ ] Restrict the hosted review token to Contents read-only for exactly one
  private repository seeded from the synthetic review ZIP. Enter PATs only on
  the SourceBraid HTTPS consent page, never into a ChatGPT prompt.
- [ ] Verify Cloudflare/OAuth data handling against `PRIVACY.md`; no content,
  query, or credential logging is enabled.
- [ ] Treat the optional local skills package as a separate runtime path; do
  not advertise local index or deletion tools as hosted ChatGPT features.
- [ ] Complete one clean installation from each public destination.
- [ ] Complete first-run GitHub setup using a new private synthetic repository.
- [ ] Save one HTML source and one PDF, then verify Markdown, frontmatter,
  assets, index metadata, and Git history.
- [ ] Search the synthetic archive from the published plugin path.
- [ ] Verify privacy, terms, support, and repository links from every listing.
- [ ] Verify English and German user-facing documentation remain aligned.

## Launch assets

- [ ] Record the workflow in `DEMO_SCRIPT.md` using synthetic or clearly
  redistributable content.
- [ ] Export a captioned 16:9 video and a readable silent GIF or short MP4.
- [ ] Prepare Chrome Web Store screenshots showing capture, repository output,
  and search rather than decorative branding alone.
- [ ] Prepare localized App Store screenshots for English and German.
- [ ] Verify all screenshots use synthetic repository names, notes, tags, and
  content, and contain no tokens, account identifiers, or private user data.
- [ ] Replace all launch variables and run:

  ```bash
  rg -n '\{\{[A-Z0-9_]+\}\}' marketing
  ```

- [ ] Have another person follow the public installation instructions without
  private maintainer context.

## Soft launch

- [ ] Recruit 15-25 testers from the initial audience, without public upvote or
  review requests.
- [ ] Ask each tester to complete installation, first capture, and first search.
- [ ] Record friction by step, not only general impressions.
- [ ] Fix release-blocking permission, onboarding, and data-loss risks.
- [ ] Collect permission before quoting any feedback publicly.
- [ ] Enable GitHub Discussions and publish the welcome discussion.

## Public launch order

Stagger posts so the maintainer can answer every substantive question.

1. Publish the GitHub release and canonical website update.
2. Verify store and plugin pages from a signed-out browser.
3. Publish the demo and the technical launch article.
4. Post Show HN while available for live discussion.
5. Post to one relevant Reddit community with its tailored draft.
6. Launch on Product Hunt on a separate day.
7. Post to the remaining communities only when there is a genuine audience fit.
8. Submit accurate listings to AlternativeTo and suitable open-source
   directories after the canonical release URLs are stable.

Do not cross-post identical text, ask anyone to coordinate votes, or post to
communities whose self-promotion rules prohibit the submission.

## Launch-day response desk

- [ ] Reserve two focused response windows in both European and US waking hours.
- [ ] Keep concise answers ready for GitHub token scope, `<all_urls>`, PDF
  conversion, private repositories, local deletion safety, and the hosted
  SourceBraid/Cloudflare processing step without a permanent content database.
- [ ] Convert reproducible defects into Issues; keep broad questions in
  Discussions.
- [ ] Publish corrections visibly if a listing or post overstates a capability.
- [ ] Never request access to a user's private archive for ordinary support.

## Measurement

Use aggregate, privacy-respecting signals. The primary launch outcome is a
successful first capture, not GitHub stars.

| Funnel step | Minimum signal |
| --- | --- |
| Discovery | Website visits, repository visitors, store impressions |
| Intent | Install-link clicks or store product-page views |
| Install | Store installs or plugin installs |
| Activation | First successful capture into the selected repository |
| Value | First successful archive search |
| Retention | A second capture within seven days |

Where product instrumentation is not available, use store analytics, GitHub
traffic, opt-in tester reports, and privacy-preserving aggregate website data.
Do not collect captured URLs, titles, notes, tags, repository names, or search
queries for launch measurement.

## Week-one follow-up

- [ ] Publish a transparent recap: what worked, what confused people, and what
  will change next.
- [ ] Triage support and defects before starting another promotion wave.
- [ ] Update installation copy where repeated questions reveal ambiguity.
- [ ] Compare activation by destination, not vanity traffic alone.
- [ ] Thank contributors and testers only with their permission.
- [ ] Choose the next content artifact from observed user questions.

# SourceBraid 1.0.1 publishing plan

[Deutsch](PUBLISHING_CHECKLIST.de.md). Audited September 28, 2026 at public
commit `bb7c77ab18b3908d324a4a8e43056d574e60fbde`.
This operational checklist supplements [RELEASING.md](../RELEASING.md).
Checked boxes represent completed checks; unchecked account/store items mean
unverified, not proof that those accounts or listings do not exist.

Recommended sequence: install and test locally, submit Chrome, then deploy
and validate the ChatGPT service while Chrome is under review. Publish each
channel after approval; announce the combined launch once every advertised
installation link works. This plan does not require a new iOS release.

## Verified baseline

- [x] `git pull --ff-only origin main`: already current; no new commits.
- [x] Reviewed the latest commit against its parent: 60 changed files. Chrome
  moves from 0.7.1 to 1.0.1, adds DE/EN metadata, explicit data consent and
  token-free plugin configuration export. `downloads` permission is removed;
  host access explicitly covers HTTP, HTTPS and local files. Archive paths and
  local index boundaries are hardened. Read-only Cloudflare MCP, a repository
  marketplace and release/review kits are new.
- [x] 23 capture, 63 Python and 33 remote-MCP tests passed.
- [x] Worker dry-run build passed using dependencies already installed locally.
- [x] Reproducible release bundle passed content checks and 24 checksums.
  `RELEASE_MANIFEST.json` records the commit above and unchanged release inputs.
- [x] [GitHub Release checks](https://github.com/patrickschiller/sourcebraid/actions/runs/36350019080)
  passed for this commit.
- [x] Chrome listing/reviewer copy and required image types exist: two
  1280×800 screenshots, a 440×280 promo image and a 128×128 icon.
- [x] Local CLI/catalog inspection found no SourceBraid entry; add the repository
  marketplace before installing the local plugin.
- [x] Homepage and public privacy/terms links returned HTTP 200.
- [ ] **Fix HTTPS blocker:** `https://mcp.sourcebraid.com/health` currently fails
  certificate hostname validation, confirmed using Python and curl. No live
  health/OAuth success is established. Keep TLS verification enabled.
- [ ] **Correct launch claims:** `PRODUCT_HUNT.md`, `COMMUNITY_POSTS.md`,
  `DEMO_SCRIPT.md` and `GITHUB.md` still contain claims about no central content
  service. Hosted ChatGPT requests pass through SourceBraid/Cloudflare. Do not
  attribute local full-text indexing or deletion to hosted ChatGPT.
- [ ] Publish the final release commit/tag and GitHub release. Remote queries
  currently returned no tags or releases.

The existing local `.gitignore` change was preserved. The builder's clean check
covers **release inputs**, not the entire worktree. Final publication requires
a clean public checkout under `RELEASING.md`. No iOS build, real Chrome workflow
or live ChatGPT test was performed here. Automated packaging checks do not
replace visual inspection of screenshots.

## 1. Set up this computer — together

- [ ] Install the complete local Codex plugin from the reviewed repository root:

  ```bash
  codex plugin marketplace add .
  codex plugin add sourcebraid@sourcebraid
  ```

  Both commands are supported by the installed CLI. Start a new chat afterward;
  restart the desktop app if necessary. Repository marketplaces are separate
  from the public directory.
  [OpenAI packaging documentation](https://developers.openai.com/plugins/build/plugins).

- [ ] Select a dedicated private test archive, extract the checked
  `sourcebraid-review-fixture-v1.0.1.zip` there and commit/push only its six
  synthetic files. This makes the “portable weave” search reproducible.
  Replace `OWNER` and `TEST_REPO` below; authenticate using `gh auth login` or the documented token
  environment variables:

  ```bash
  python3 codex-plugin/sourcebraid/scripts/sourcebraid.py config \
    --repo-slug OWNER/TEST_REPO --branch main --root-folder web-clips
  python3 codex-plugin/sourcebraid/scripts/sourcebraid.py index build
  python3 codex-plugin/sourcebraid/scripts/sourcebraid.py search "portable weave"
  ```

- [ ] Test search and fetch in a new chat. The complete local plugin needs
  Python, its local index and GitHub authentication.
  [Installation guide](../docs/CHATGPT_PLUGIN.md).
- [ ] Open `chrome://extensions`, enable Developer mode and load
  `chrome-extension/sourcebraid` using “Load unpacked.”
- [ ] Test consent, HTML capture with images, notes/tags, Markdown fallback and
  token-free configuration export against the synthetic archive.
- [ ] Test synthetic public and local PDFs, enable file-URL access for local
  files, and verify GitHub Actions conversion through final Markdown/images.
  Record the date and results.

## 2. Google Chrome Web Store

- [ ] **Patrick:** Select the publisher account, complete registration/payment,
  confirm contact email and enable 2FA.
  [Registration](https://developer.chrome.com/docs/webstore/register),
  [account setup](https://developer.chrome.com/docs/webstore/set-up-account),
  [2FA](https://developer.chrome.com/docs/webstore/program-policies/two-step-verification).
- [ ] **Patrick:** Complete trader/non-trader declarations and any identity or
  contact verification based on the actual situation.
  [Google requirements](https://developer.chrome.com/docs/webstore/program-policies/trader-verification-faq).
- [ ] **Together:** Prepare a dedicated private Chrome review repository. Its
  PAT needs Contents read/write; workflow write access only when installing
  PDF support. Supply access solely in the designated reviewer field.
  [Test instructions](https://developer.chrome.com/docs/webstore/cws-dashboard-test-instructions).
- [ ] **Codex + Patrick:** Upload the checked Chrome ZIP in the
  [developer dashboard](https://chrome.google.com/webstore/devconsole); use
  [DE/EN listing copy](../chrome-extension/STORE_LISTING.md), the prepared
  images and public support/privacy links.
  [Image requirements](https://developer.chrome.com/docs/webstore/images).
- [ ] **Together:** Check single-purpose, data categories, remote-code answer
  and each permission justification against actual behavior. HTTP/HTTPS access
  remains broad; file access supports local PDFs.
  [Privacy fields](https://developer.chrome.com/docs/webstore/cws-dashboard-privacy).
- [ ] **Patrick:** Select countries and public visibility, then submit. If
  publication is deferred, publish within 30 days of approval.
  [Publishing](https://developer.chrome.com/docs/webstore/publish).
- [ ] **Together:** After approval, verify a fresh store installation and the
  capture/PDF workflow; record the live listing URL.

Google reviews may take days to weeks; broad host permissions can extend review.
Avoid promising a launch date before approval.
[Review process](https://developer.chrome.com/docs/webstore/review-process).

## 3. ChatGPT and the public OpenAI Plugins Directory

The prepared primary route is **With MCP / Universal**: hosted read-only
`search`, `fetch`, `sourcebraid_list` and `sourcebraid_status`. The optional
skills ZIP alone does not connect ChatGPT to an archive.

- [ ] **Patrick:** Verify publisher identity and `Apps Management: Write`.
  [Submission](https://developers.openai.com/plugins/deploy/submission).
- [ ] **Patrick:** Select the Cloudflare account, domain and spending limits.
- [ ] **Codex + Patrick:** Follow the [deployment runbook](../docs/CHATGPT_MCP_DEPLOYMENT.md)
  for Worker, KV and custom domain; fix the TLS certificate. Do not put a user's
  GitHub PAT in global Worker variables.
- [ ] **Together:** Verify public HTTPS, health, OAuth metadata and the expected
  unauthenticated 401 response. Health alone does not establish archive access.
- [ ] **Together:** Populate a separate private OpenAI review archive from the
  fixture ZIP. Create a PAT with Contents read-only for that repository. Never
  reuse Chrome's write token or place tokens in chats, screenshots or public files.
- [ ] **Together:** Enable ChatGPT developer mode and connect MCP; availability
  depends on account/workspace policy.
  [Official testing flow](https://developers.openai.com/plugins/deploy/connect-chatgpt).
- [ ] **Together:** Pass all five positive and three negative live cases in the
  [MCP submission kit](OPENAI_MCP_SUBMISSION.md): status, list, search, fetch,
  summary; denied deletion, foreign/outside-root paths and revoked credentials.
  Also verify refresh, reconnect and isolation between two users' archives.
  Malicious instructions embedded in a synthetic source must remain source
  data and must not trigger credential disclosure or unrelated network calls.
- [ ] **Codex:** Record date, Worker/commit version and outcomes; capture any
  required ChatGPT demo from the real synthetic workflow.
- [ ] **Patrick + Codex:** Complete domain verification, tool scan, listing,
  protected reviewer access, countries, attestations and release notes in the
  portal. Submit for review and publish after approval.
  [Submission flow](https://developers.openai.com/plugins/deploy/submission).
- [ ] **Together:** Verify installation from the public directory, record the
  live URL and revoke temporary review access after review.

## 4. Artifacts and final launch

Checked local artifacts are in `dist/sourcebraid-release-v1.0.1/`:

| File | Use |
| --- | --- |
| `sourcebraid-chrome-v1.0.1.zip` | Google upload |
| `sourcebraid-chatgpt-mcp-v1.0.1.zip` | Worker source for deployment |
| `sourcebraid-review-fixture-v1.0.1.zip` | Three synthetic sources plus index shards |
| `sourcebraid-plugin-skills-v1.0.1.zip` | Optional local skills; no hosted MCP |
| `RELEASE_MANIFEST.json`, `SHA256SUMS` | Commit provenance and integrity |

- [ ] Align final DE/EN changes and commit with DCO sign-off. Recheck relevant
  tests/artifacts from the final clean commit. Keep unrelated local work out of
  the release.
- [ ] Publish reviewed tag `v1.0.1` and the GitHub release with matching artifacts;
  only then advertise tag-bound plugin installation.
- [ ] Replace draft links/claims with verified destinations and behavior. Keep
  private website sources and real archives out of the public release.
- [ ] Pass fresh installations for each released channel, then use the
  [launch checklist](LAUNCH_CHECKLIST.md) for public announcements.

Next joint step: install the local plugin and Chrome extension and complete a
synthetic capture-to-search workflow. Account checks for Google, OpenAI and
Cloudflare can proceed in parallel.

# GitHub launch metadata

Repository: `patrickschiller/sourcebraid`

## About section

Description:

> Weave the web into durable Markdown in your own GitHub repository.

Website:

> https://sourcebraid.com

The social preview should use
`assets/branding/sourcebraid-social-card.png` and must be checked at desktop and
mobile sizes before launch.

## Topics

Use this initial topic set:

```text
web-clipper
markdown
read-it-later
web-archiving
personal-knowledge-management
knowledge-base
browser-extension
chrome-extension
ios
github
privacy
mcp-server
codex-plugin
full-text-search
pdf-to-markdown
```

Apply the set after authenticating `gh` as a repository administrator:

```bash
gh repo edit patrickschiller/sourcebraid \
  --add-topic web-clipper \
  --add-topic markdown \
  --add-topic read-it-later \
  --add-topic web-archiving \
  --add-topic personal-knowledge-management \
  --add-topic knowledge-base \
  --add-topic browser-extension \
  --add-topic chrome-extension \
  --add-topic ios \
  --add-topic github \
  --add-topic privacy \
  --add-topic mcp-server \
  --add-topic codex-plugin \
  --add-topic full-text-search \
  --add-topic pdf-to-markdown
```

The order above starts with user intent and moves toward implementation details.
Do not add `self-hosted`, `local-first`, or `offline-first` unless the product
contract changes enough to make those expectations accurate.

Review topics for every coordinated public release and once per quarter. Remove
a topic when the corresponding user-facing behavior is no longer supported.
Add a topic only when it describes a shipped, documented capability. Twice a
year, compare the vocabulary used by adjacent web-clipping and archiving
projects; do not copy irrelevant implementation topics merely because they are
popular.

## Repository features

Before the public launch:

- apply and verify the documented topic set on the live repository;
- enable GitHub Discussions;
- retain Issues for actionable bugs and feature work;
- create Discussion categories `Announcements`, `Ideas`, `Q&A`, and
  `Show and tell`;
- pin a welcome discussion explaining when to use Discussions versus Issues;
- publish the coordinated GitHub release and attach the allowlisted artifacts;
- verify the README's primary install links point to published destinations;
- verify the English and German READMEs describe the same available clients.

Suggested welcome discussion title:

> Welcome to SourceBraid: questions, workflows, and ideas

Suggested welcome text:

> SourceBraid is an open-source web-to-Markdown archive built around files and
> Git history that the user controls. Use Q&A for setup questions, Ideas for
> early product discussion, and Show and tell for workflows you have built.
> Please use Issues for reproducible bugs and scoped implementation requests.
> Do not post access tokens, private repository names, or captured content that
> you do not have permission to share.

## Release description template

```markdown
# SourceBraid {{VERSION}}

SourceBraid saves web pages, papers, wikis, Gists, and PDFs as portable Markdown
in a private GitHub repository controlled by the user. This coordinated release
includes the supported capture clients and ChatGPT/Codex archive tools listed
below.

## Install

- Chrome: {{CHROME_STORE_URL}}
- iPhone and iPad: {{APP_STORE_URL}}
- ChatGPT and Codex plugin: {{PLUGIN_URL}}

Remove any installation line whose destination is not public for this release.

## Highlights

- [Three verified, user-visible highlights for this exact release]

## Privacy and permissions

SourceBraid has no central content server. Capture clients write to the GitHub
repository selected by the user. Review the permissions and data flow in the
[privacy notice](https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md).

## Checks

- `node --test tests/capture-utils.test.js`
- `python3 -m unittest discover -s tests -p "test_*.py"`
- unsigned iOS simulator build
- public release safety and artifact inspection
```

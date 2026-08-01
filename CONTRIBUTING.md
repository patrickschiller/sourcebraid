# Contributing to SourceBraid

Thanks for helping people turn web sources into durable, user-owned Markdown.
SourceBraid is open source under the MIT License, and we welcome bug reports,
design discussions, documentation improvements, tests, and pull requests.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Developer Certificate of Origin (DCO)

SourceBraid does not use a Contributor License Agreement. Instead, every commit
in a pull request must be signed off under the
[Developer Certificate of Origin 1.1](https://developercertificate.org/). The
sign-off certifies that you wrote the contribution, or otherwise have the right
to submit it under the project's license.

Create signed-off commits with:

```bash
git commit -s
```

This appends a trailer to the commit message:

```text
Signed-off-by: Your Name <your.email@example.com>
```

Use a name by which you can be identified. The DCO check runs on every commit
in a pull request and blocks merging when a sign-off is missing. If you forgot
it, use `git commit --amend -s` for the latest commit or
`git rebase --signoff <base>` for a series of commits.

## Reporting issues

- **Bugs:** use the GitHub bug-report template and include reproducible steps,
  expected and actual behavior, SourceBraid version, operating system, browser
  or iOS version, and sanitized logs where relevant.
- **Security vulnerabilities:** do not open a public issue, discussion, or pull
  request. Follow [SECURITY.md](SECURITY.md).
- **Feature ideas:** open a feature request before starting a large change so
  scope and design can be discussed first.

Never include access tokens, cookies, private repository contents, captured
articles, personal data, or other material you do not have permission to share
in issues, fixtures, screenshots, or pull requests.

## Working on a change

1. Fork the public repository and create a focused branch from `main`.
2. Read the [README](README.md), [AGENTS.md](AGENTS.md), and the code around the
   area you intend to change.
3. Keep one logical change per pull request. Discuss broad architectural,
   storage-format, permission, or privacy changes in an issue first.
4. Add or update tests for behavioral changes.
5. Run the checks relevant to your change.
6. Sign off every commit with `git commit -s`.
7. Open a pull request against `main` and explain why the change is useful.

## Development checks

Run the JavaScript and Python suites from the repository root:

```bash
node --test tests/capture-utils.test.js
python3 -m unittest discover -s tests -p "test_*.py"
```

The Chrome extension uses Manifest V3 and has no build step. Load
`chrome-extension/sourcebraid` as an unpacked extension for manual browser
testing. The iOS app and Share Extension require Xcode; see
[ios/README.md](ios/README.md) for build commands.

The website is maintained separately from the public release. Maintainers with
access to its private source can validate it with:

```bash
npm --prefix website ci
npm --prefix website test
```

## Pull request expectations

- Explain the problem, the chosen approach, and user-visible effects.
- Link the relevant issue or discussion when one exists.
- Keep permissions minimal and call out any new host, GitHub, Keychain, or
  network access.
- Use synthetic, redistributable fixtures. Do not commit a real SourceBraid
  archive or third-party article body as test data.
- Keep the Chrome, iOS, ChatGPT/Codex plugin, and archive formats compatible
  when a shared contract changes.
- Ensure tests and the DCO check are green before requesting review.

## Coding guidelines

- Keep the browser extension dependency-free unless a dependency has a clear,
  documented benefit. Preserve Manifest V3 compatibility.
- Keep plugin scripts compatible with Python's standard library unless a new
  dependency is explicitly justified and documented.
- Store credentials only through the existing browser storage, environment, or
  Keychain mechanisms. Never log or persist tokens in repository content.
- Preserve source provenance and avoid fabricating titles, authors, dates, or
  canonical URLs during Markdown conversion.
- Prefer focused changes over unrelated refactors.

## License of contributions

By submitting a contribution, you license it under the project's
[MIT License](LICENSE) and certify the
[Developer Certificate of Origin](https://developercertificate.org/) through
your `Signed-off-by` line. No copyright assignment is required; contributors
retain ownership of their work.

# Contributing to SourceBraid

Thanks for helping make durable, user-owned web archives easier to build.

## Good first contributions

- test a source adapter against real public pages;
- improve Markdown fidelity or metadata extraction;
- report an inaccessible PDF, WordPress, wiki, or feed;
- improve Chrome, iOS, ChatGPT, or Codex setup instructions; or
- help design the Android share target after the first feedback round.

Please open an issue before starting a large change. Do not include private
archive content, access tokens, cookies, or copyrighted source material in
issues, fixtures, screenshots, or pull requests.

## Development checks

Run the JavaScript and Python suites:

```bash
node --test tests/capture-utils.test.js
python3 -m unittest discover -s tests -p "test_*.py"
```

Validate the plugin:

```bash
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py \
  codex-plugin/sourcebraid
```

The Chrome extension has no build step. iOS development requires Xcode.

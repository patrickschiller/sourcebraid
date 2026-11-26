# Build SourceBraid for Firefox

This source archive contains the original JavaScript, HTML, CSS, localization
files, icons, and the original and bundled PDF workflow resources. It also includes the Python scripts
used to package the extension and its Firefox manifest settings.

Extract the source ZIP and run this command from its root with Python 3.10 or
later.

```bash
python3 scripts/build_firefox_package.py --output dist/sourcebraid-firefox.zip
```

The builder copies the allowlisted files from `chrome-extension/sourcebraid`
and applies `firefox-extension/manifest-overrides.json` to the shared manifest.
The override sets the version of the Firefox add-on independently of Chrome.
The build requires only the Python standard library and runs offline. It does
not transpile, bundle, or minify JavaScript. The bundled Python and YAML files
are resources the extension can copy to the user's GitHub archive for PDF
conversion in GitHub Actions.

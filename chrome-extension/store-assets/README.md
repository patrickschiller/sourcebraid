# Chrome Web Store assets

These assets are generated from `source/render.html` at exact Chrome Web Store
dimensions. The capture composition embeds the actual extension popup with
synthetic settings, tags and notes. The archive composition uses the actual
`SourceBraidCore` Markdown, clip-path and shard-path builders. The surrounding
article and archive frame are illustrative demo layouts, not a live account.
No real archive data, tokens or user browser profile are used.

Render with Node.js and Playwright (including its Chromium browser) installed:

```sh
node scripts/render_chrome_store_assets.mjs
```

If Playwright is installed outside the project, set `SOURCEBRAID_PLAYWRIGHT`
to its absolute module path. `SOURCEBRAID_CHROMIUM` can select an existing
Chromium executable. The script starts a temporary localhost server,
uses a fresh headless browser, writes only the three PNGs here, and closes both
processes. Rendering dependencies are not included in the extension package.

Die Bilder zeigen ausschließlich synthetische Daten. Das echte Popup und die
tatsächlichen Markdown- und Pfadfunktionen erzeugen die Produktansichten;
Artikel und Repository-Rahmen sind als Demo gestaltete Ansichten. Der Renderer
verwendet ein frisches Browserprofil und keine persönlichen Zugangsdaten.

Render query values:

- `?scene=capture` at 1280 × 800
- `?scene=archive` at 1280 × 800
- `?scene=promo` at 440 × 280

#!/usr/bin/env node
// Render synthetic store compositions with the real extension popup and Markdown builder.
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.SOURCEBRAID_PLAYWRIGHT || "playwright");
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const assetRoot = resolve(root, "chrome-extension/store-assets");
const types = { html: "text/html", css: "text/css", js: "text/javascript", png: "image/png" };
const server = createServer(async (request, response) => {
  try {
    const path = resolve(root, `.${new URL(request.url, "http://localhost").pathname}`);
    const allowed = [resolve(root, "chrome-extension/sourcebraid"), resolve(assetRoot, "source")];
    if (!allowed.some((directory) => path.startsWith(`${directory}${sep}`))) {
      response.writeHead(404).end();
      return;
    }
    response.setHeader("Content-Type", types[path.split(".").pop()] || "application/octet-stream");
    response.end(await readFile(path));
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((accept, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", accept);
});
let browser;
try {
  browser = await chromium.launch({ headless: true,
    ...(process.env.SOURCEBRAID_CHROMIUM ? { executablePath: process.env.SOURCEBRAID_CHROMIUM } : {})
  });
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await page.addInitScript(() => {
    globalThis.chrome = {
      storage: { local: { get: async (defaults) => ({ ...defaults,
        githubOwner: "you", githubRepo: "sourcebraid-archive", githubToken: "synthetic-demo-token",
        dataDisclosureAcceptedVersion: "1"
      }) } },
      tabs: { query: async () => [{ id: 42, title: "Building a durable, local-first knowledge archive", url: "https://example.com/research/local-first-knowledge" }] }
    };
  });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const origin = `http://127.0.0.1:${server.address().port}`;
  for (const [scene, width, height, filename] of [
    ["capture", 1280, 800, "sourcebraid-chrome-capture-1280x800.png"],
    ["archive", 1280, 800, "sourcebraid-private-archive-1280x800.png"],
    ["promo", 440, 280, "sourcebraid-promo-440x280.png"]
  ]) {
    await page.setViewportSize({ width, height });
    await page.goto(`${origin}/chrome-extension/store-assets/source/render.html?scene=${scene}`);
    await page.evaluate(() => document.fonts.ready);
    if (scene === "capture") {
      const popup = page.frameLocator("iframe");
      await popup.locator("#tags").fill("knowledge, local-first, research");
      await popup.locator("#notes").fill("Useful source for the open-source launch plan.");
    }
    await page.screenshot({ path: resolve(assetRoot, filename) });
    console.log(`${filename}: ${width}x${height}`);
  }
  if (errors.length) throw new Error(errors.join("\n"));
} finally {
  await browser?.close();
  await new Promise((accept) => server.close(accept));
}

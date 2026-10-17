/* SourceBraid's offline Mermaid adapter. This file is app-owned, not archive content. */
(() => {
  "use strict";
  const german = document.documentElement.lang === "de";
  const message = {
    error: german
      ? "Dieses Mermaid-Diagramm kann nicht dargestellt werden. Der originale Quelltext bleibt verfügbar."
      : "This Mermaid diagram could not be rendered. Its original source remains available.",
    limit: german
      ? "Dieses Diagramm überschreitet die Vorschaugrenze. Der originale Quelltext bleibt verfügbar."
      : "This diagram exceeds the preview limit. Its original source remains available.",
    ready: german ? "Auf diesem Gerät dargestellt." : "Rendered on this device."
  };
  const media = matchMedia("(prefers-color-scheme: dark)");
  let running;
  let sequence = 0;

  function initialize() {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      suppressErrorRendering: true,
      maxTextSize: 20000,
      maxEdges: 200,
      logLevel: "fatal",
      theme: media.matches ? "dark" : "default",
      fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
      htmlLabels: false,
      flowchart: { htmlLabels: false, useMaxWidth: true },
      // Archive config/directives must never lower the app's security boundaries.
      secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize", "maxEdges",
        "suppressErrorRendering", "htmlLabels", "flowchart", "fontFamily",
        "themeCSS", "dompurifyConfig"]
    });
    mermaid.parseError = () => {};
  }

  function safeSVG(markup) {
    const parsed = new DOMParser().parseFromString(markup, "image/svg+xml");
    const svg = parsed.documentElement;
    if (svg.localName !== "svg" || parsed.querySelector("parsererror")) throw new Error("Invalid SVG");
    // Mermaid strict mode sanitizes its output. Enforce our own smaller image-only
    // boundary as well: no HTML labels, navigation, embedded/external media or scripts.
    svg.querySelectorAll("script, foreignObject, iframe, object, embed, image, video, audio").forEach(node => node.remove());
    svg.querySelectorAll("a").forEach(node => node.replaceWith(...node.childNodes));
    for (const node of [svg, ...svg.querySelectorAll("*")]) {
      for (const attribute of [...node.attributes]) {
        const name = attribute.name.toLowerCase();
        const value = attribute.value.trim();
        if (name.startsWith("on") ||
            ((name === "href" || name === "xlink:href") && !value.startsWith("#"))) {
          node.removeAttribute(attribute.name);
        }
      }
    }
    return document.importNode(svg, true);
  }

  async function render(force) {
    initialize();
    let total = 0;
    let rendered = 0;
    const figures = [...document.querySelectorAll("figure[data-mermaid]")];
    for (let index = 0; index < figures.length; index++) {
      const figure = figures[index];
      if (!force && figure.dataset.mermaidRendered === "true") continue;
      const preview = figure.querySelector(".mermaid-preview");
      const status = figure.querySelector(".mermaid-status");
      const details = figure.querySelector("details");
      const source = figure.querySelector("code").textContent;
      total += source.length;
      preview.replaceChildren();
      preview.hidden = true;
      details.open = true;
      figure.dataset.mermaidRendered = "false";
      if (index >= 12 || source.length > 20000 || total > 100000 || source.split("\n").length > 300) {
        status.textContent = message.limit;
        continue;
      }
      // A unique, disposable container prevents failed renders from leaving SVG
      // error elements in the article or contaminating the following diagram.
      const scratch = document.createElement("div");
      scratch.style.cssText = "position:absolute;left:-100000px;top:0;width:1000px;visibility:hidden";
      document.body.append(scratch);
      try {
        const result = await mermaid.render(`sourcebraid-mermaid-${++sequence}`, source, scratch);
        preview.append(safeSVG(result.svg));
        preview.hidden = false;
        details.open = false;
        status.textContent = message.ready;
        figure.dataset.mermaidRendered = "true";
        rendered++;
      } catch (_) {
        status.textContent = message.error;
      } finally {
        scratch.remove();
      }
    }
    return rendered;
  }

  globalThis.SourceBraidMermaid = {
    renderAll(force = false) {
      if (running) return running;
      running = render(force).finally(() => { running = undefined; });
      return running;
    }
  };
  initialize();
  media.addEventListener("change", () => {
    globalThis.SourceBraidMermaid.renderAll(true).catch(() => {});
  });
})();

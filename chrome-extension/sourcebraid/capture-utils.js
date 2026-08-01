(function initializeSourceBraidCore(global) {
  const api = {
    buildDocument,
    buildGitHubPath,
    buildIndexPath,
    collectMarkdownImageAssets,
    localDateStamp,
    normalizeMarkdownUrls,
    normalizeRootFolder,
    normalizeSourceMarkdown,
    parseArxivUrl,
    parseAzureDevOpsWikiUrl,
    parsePdfSourceUrl,
    parseGistUrl,
    rewriteMarkdownImageUrls,
    rewriteMarkdownLinkUrls,
    slugify,
    urlHash,
    yamlQuote
  };

  global.SourceBraidCore = api;
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }

  function buildDocument(data) {
    const frontmatter = {
      title: data.title,
      url: data.url,
      source: data.site,
      author: data.author,
      authors: data.authors,
      abstract: data.abstract,
      published: data.published,
      modified: data.modified,
      doi: data.doi,
      arxiv_id: data.arxivId,
      arxiv_version: data.arxivVersion,
      journal: data.journal,
      subjects: data.subjects,
      html_url: data.htmlUrl,
      pdf_url: data.pdfUrl,
      platform: data.platform,
      organization: data.organization,
      project: data.project,
      wiki: data.wiki,
      wiki_page_id: data.wikiPageId,
      wiki_path: data.wikiPath,
      revision: data.revision,
      gist_id: data.gistId,
      gist_files: data.gistFiles,
      captured_at: data.capturedAt,
      capture_date: data.capturedDate,
      capture_method: data.captureMethod,
      source_type: data.sourceType,
      content_format: data.contentFormat,
      conversion_status: data.conversionStatus,
      converter: data.converter,
      pdf_path: data.pdfPath,
      source_tags: data.sourceTags,
      tags: data.tags
    };

    const lines = ["---"];
    for (const [key, value] of Object.entries(frontmatter)) {
      if (Array.isArray(value)) {
        if (value.length) {
          lines.push(`${key}: [${value.map((item) => yamlQuote(item)).join(", ")}]`);
        }
      } else if (value !== undefined && value !== null && value !== "") {
        lines.push(`${key}: ${yamlQuote(value)}`);
      }
    }
    lines.push("---", "");

    if (data.description && data.includeDescription !== false) {
      lines.push(`> ${data.description}`, "");
    }

    if (data.featuredImage && !String(data.body || "").includes(data.featuredImage)) {
      lines.push(`![Featured image](${data.featuredImage})`, "");
    }

    if (data.notes) {
      lines.push("<!-- clipper-notes-start -->", "## Notes", "", data.notes, "", "<!-- clipper-notes-end -->", "");
    }

    if (data.includeTitle !== false) {
      lines.push(`# ${data.title}`, "");
    }
    lines.push(String(data.body || "").trim(), "");
    return lines.join("\n");
  }

  function buildGitHubPath({ rootFolder, capturedDate, url, title }) {
    const date = capturedDate || localDateStamp();
    const [year, month] = date.split("-");
    const hostname = safeHostname(url) || "document";
    const slug = slugify(title || "document").slice(0, 80);
    const hash = urlHash(url || title || "document");
    const root = normalizeRootFolder(rootFolder);
    return `${root}/${year}/${month}/${date}-${hostname}-${slug}-${hash}.md`;
  }

  function buildIndexPath({ rootFolder, url }) {
    const root = normalizeRootFolder(rootFolder);
    return `${root}/index/${urlHash(url || "document").slice(0, 2)}.jsonl`;
  }

  function normalizeSourceMarkdown(markdown, title, baseUrl) {
    let body = String(markdown || "").replace(/^\uFEFF/, "").trim();
    body = stripFrontmatter(body);
    body = normalizeMarkdownUrls(body, baseUrl);

    const heading = body.match(/^#\s+(.+?)\s*(?:\n+|$)/);
    if (heading && comparableText(heading[1]) === comparableText(title)) {
      body = body.slice(heading[0].length).trim();
    }

    return body.replace(/\n{4,}/g, "\n\n\n").trim();
  }

  function stripFrontmatter(value) {
    if (!/^---\s*\n/.test(value)) {
      return value;
    }

    const end = value.indexOf("\n---", 4);
    if (end < 0) {
      return value;
    }

    const after = value.slice(end + 4);
    return after.replace(/^\s*\n/, "").trim();
  }

  function normalizeMarkdownUrls(markdown, baseUrl) {
    if (!baseUrl) {
      return String(markdown || "");
    }

    return String(markdown || "").replace(/(!?\[[^\]]*\]\()([^\s)>]+)([^)]*\))/g, (match, prefix, target, suffix) => {
      const unwrapped = target.replace(/^<|>$/g, "");
      if (!unwrapped || /^(?:#|data:|blob:|mailto:|tel:|javascript:)/i.test(unwrapped)) {
        return match;
      }

      try {
        return `${prefix}${new URL(unwrapped, baseUrl).href}${suffix}`;
      } catch (_error) {
        return match;
      }
    });
  }

  function collectMarkdownImageAssets(markdown, primaryImageUrl, maxImages = 12) {
    const candidates = [];
    if (primaryImageUrl) {
      candidates.push({ url: primaryImageUrl, alt: "Featured image", width: 0, height: 0 });
    }

    const pattern = /!\[([^\]]*)\]\(([^\s)>]+)(?:\s+[^)]*)?\)/g;
    for (const match of String(markdown || "").matchAll(pattern)) {
      const url = match[2].replace(/^<|>$/g, "");
      if (url && !/^(?:data|blob):/i.test(url)) {
        candidates.push({ url, alt: match[1].trim(), width: 0, height: 0 });
      }
    }

    const seen = new Set();
    return candidates.filter((image) => {
      if (seen.has(image.url)) {
        return false;
      }
      seen.add(image.url);
      return true;
    }).slice(0, maxImages);
  }

  function localDateStamp(date = new Date()) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function normalizeRootFolder(value) {
    return String(value || "web-clips")
      .trim()
      .replace(/^\/+|\/+$/g, "")
      .replace(/\/{2,}/g, "/") || "web-clips";
  }

  function parseArxivUrl(value) {
    try {
      const url = new URL(value);
      const hostname = url.hostname.toLowerCase();
      if (hostname !== "arxiv.org" && hostname !== "www.arxiv.org" && hostname !== "ar5iv.labs.arxiv.org") {
        return null;
      }

      const match = url.pathname.match(/^\/(abs|html|pdf)\/((?:[a-z-]+(?:\.[A-Z]{2})?\/\d{7}|\d{4}\.\d{4,5}))(v\d+)?(?:\.pdf)?\/?$/i);
      if (!match) {
        return null;
      }

      return {
        kind: match[1].toLowerCase(),
        id: match[2],
        version: match[3] ? Number(match[3].slice(1)) : null,
        versionedId: `${match[2]}${match[3] || ""}`
      };
    } catch (_error) {
      return null;
    }
  }

  function parseAzureDevOpsWikiUrl(value) {
    try {
      const url = new URL(value);
      if (url.hostname.toLowerCase() !== "dev.azure.com") {
        return null;
      }

      const parts = url.pathname.split("/").filter(Boolean);
      const wikiIndex = parts.indexOf("_wiki");
      if (wikiIndex < 2 || parts[wikiIndex + 1] !== "wikis" || !parts[wikiIndex + 2]) {
        return null;
      }

      const pathPageId = /^\d+$/.test(parts[wikiIndex + 3] || "") ? parts[wikiIndex + 3] : "";
      const queryPageId = url.searchParams.get("pageId") || "";
      const pageId = pathPageId || (/^\d+$/.test(queryPageId) ? queryPageId : "");
      if (!pageId) {
        return null;
      }

      return {
        organization: parts[0],
        project: parts[1],
        wikiIdentifier: decodeURIComponent(parts[wikiIndex + 2]),
        pageId,
        title: decodeURIComponent(parts[wikiIndex + 4] || ""),
        pagePath: url.searchParams.get("pagePath") || ""
      };
    } catch (_error) {
      return null;
    }
  }

  function parsePdfSourceUrl(value) {
    try {
      const url = new URL(String(value || ""));
      if (!["http:", "https:", "file:"].includes(url.protocol)) {
        return null;
      }

      return {
        url: url.href,
        protocol: url.protocol,
        isLocal: url.protocol === "file:",
        hasPdfExtension: /\.pdf$/i.test(url.pathname)
      };
    } catch (_error) {
      return null;
    }
  }

  function parseGistUrl(value) {
    try {
      const url = new URL(value);
      if (url.hostname.toLowerCase() !== "gist.github.com") {
        return null;
      }

      const parts = url.pathname.split("/").filter(Boolean);
      const idIndex = parts.findIndex((part) => /^[a-f0-9]{5,}$/i.test(part));
      if (idIndex < 0) {
        return null;
      }

      return {
        owner: idIndex > 0 ? parts[idIndex - 1] : "",
        id: parts[idIndex],
        revision: /^[a-f0-9]{7,}$/i.test(parts[idIndex + 1] || "") ? parts[idIndex + 1] : ""
      };
    } catch (_error) {
      return null;
    }
  }

  function rewriteMarkdownImageUrls(markdown, resolver) {
    return String(markdown || "").replace(/(!\[[^\]]*\]\()([^\s)>]+)([^)]*\))/g, (match, prefix, target, suffix) => {
      const unwrapped = target.replace(/^<|>$/g, "");
      const replacement = resolver(unwrapped);
      return replacement ? `${prefix}${replacement}${suffix}` : match;
    });
  }

  function rewriteMarkdownLinkUrls(markdown, resolver) {
    return String(markdown || "").replace(/(^|[^!])(\[[^\]]+\]\()([^\s)>]+)([^)]*\))/gm, (match, before, prefix, target, suffix) => {
      const unwrapped = target.replace(/^<|>$/g, "");
      const replacement = resolver(unwrapped);
      return replacement ? `${before}${prefix}${replacement}${suffix}` : match;
    });
  }

  function urlHash(value) {
    let hash = 0x811c9dc5;
    const text = String(value || "");
    for (let index = 0; index < text.length; index += 1) {
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 0x01000193);
    }
    return (hash >>> 0).toString(16).padStart(8, "0").slice(0, 6);
  }

  function slugify(value) {
    return String(value || "document")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "document";
  }

  function yamlQuote(value) {
    return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
  }

  function safeHostname(value) {
    try {
      return new URL(value).hostname.replace(/^www\./, "");
    } catch (_error) {
      return "";
    }
  }

  function comparableText(value) {
    return String(value || "")
      .replace(/[*_`~]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .toLocaleLowerCase();
  }
})(globalThis);

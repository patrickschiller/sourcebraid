const Core = globalThis.SourceBraidCore;

if (!Core) {
  throw new Error("SourceBraidCore was not loaded before content.js.");
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "ping") {
    sendResponse({ ok: true });
    return true;
  }

  if (message?.type === "capture-markdown") {
    captureMarkdown(message)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message || String(error) }));
    return true;
  }

  if (message?.type === "fetch-authenticated-image") {
    fetchAuthenticatedImage(message.url)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message || String(error) }));
    return true;
  }

  return false;
});

async function captureMarkdown(options) {
  const metadata = collectMetadata();
  const adapterSettings = options.adapterSettings || {};
  let article = await tryArxivHtml(metadata);

  if (article?.pdfFallback) {
    return {
      pdfFallback: {
        ...article.pdfFallback,
        tags: options.tags || [],
        notes: options.notes || "",
        capturedAt: metadata.capturedAt,
        capturedDate: metadata.capturedDate
      }
    };
  }

  if (!article) {
    article = await tryAzureDevOpsWiki(metadata);
  }

  if (!article) {
    article = await tryGitHubGist(metadata);
  }

  if (!article) {
    article = await tryDirectMarkdown(metadata);
  }

  if (!article && metadata.wordpressApiUrl) {
    article = await tryWordPressApi(metadata.wordpressApiUrl, metadata);
  }

  if (!article) {
    article = await tryForemApi(metadata);
  }

  if (!article) {
    article = await tryGhostApi(metadata, adapterSettings);
  }

  if (!article) {
    article = await tryBloggerApi(metadata, adapterSettings);
  }

  if (!article) {
    article = await trySyndicationFeeds(metadata);
  }

  if (!article) {
    article = extractFromDocument(metadata);
  }

  const markdownBody = article.markdown
    ? Core.normalizeSourceMarkdown(article.markdown, article.title, article.url)
    : htmlToMarkdown(article.html, article.contentUrl || article.url);
  const images = article.markdown
    ? Core.collectMarkdownImageAssets(markdownBody, article.featuredImage || metadata.primaryImage, article.maxImages)
    : collectImageAssets(article.html, article.contentUrl || article.url, article.featuredImage || metadata.primaryImage, article.maxImages);
  if (article.authenticatedImages) {
    const authenticatedHosts = new Set(article.authenticatedImageHosts || []);
    images.forEach((image) => {
      try {
        const imageUrl = new URL(image.url);
        if (imageUrl.origin === location.origin || authenticatedHosts.has(imageUrl.hostname.toLowerCase())) {
          image.fetch_mode = "tab-authenticated";
        }
      } catch (_error) {
        // Invalid image URLs will be skipped by the regular asset fetcher.
      }
    });
  }
  const sourceType = article.sourceType || "article";
  const contentFormat = article.contentFormat || (article.markdown ? "markdown" : "html");
  const markdown = Core.buildDocument({
    ...metadata,
    ...article,
    body: markdownBody,
    featuredImage: article.featuredImage || metadata.primaryImage,
    sourceType,
    contentFormat,
    tags: options.tags || [],
    notes: options.notes || ""
  });
  const path = Core.buildGitHubPath({
    rootFolder: options.rootFolder || "web-clips",
    capturedDate: metadata.capturedDate,
    url: article.url,
    title: article.title
  });
  const indexEntry = {
    title: article.title,
    url: article.url,
    path,
    date: metadata.capturedDate,
    published: article.published || metadata.published || "",
    modified: article.modified || metadata.modified || "",
    tags: options.tags || [],
    source_tags: article.sourceTags || [],
    source: article.site || metadata.site,
    capture_method: article.captureMethod,
    source_type: sourceType,
    content_format: contentFormat,
    captured_at: metadata.capturedAt
  };

  for (const key of ["authors", "doi", "arxiv_id", "arxiv_version", "journal", "subjects", "html_url", "pdf_url"]) {
    const camelKey = key.replace(/_([a-z])/g, (_match, letter) => letter.toUpperCase());
    const value = article[camelKey];
    if (value !== undefined && value !== null && value !== "" && (!Array.isArray(value) || value.length)) {
      indexEntry[key] = value;
    }
  }
  Object.assign(indexEntry, article.indexMetadata || {});

  return {
    markdown,
    path,
    indexEntry,
    images
  };
}

async function tryArxivHtml(metadata) {
  const parsed = Core.parseArxivUrl(metadata.pageUrl);
  if (!parsed || parsed.kind !== "abs") {
    return null;
  }

  const metaValues = (name) => Array.from(document.querySelectorAll(`meta[name='${name}']`))
    .map((node) => cleanText(node.getAttribute("content") || ""))
    .filter(Boolean);
  const title = metaValues("citation_title")[0] || metadata.title.replace(/^\[[^\]]+\]\s*/, "");
  const displayAuthors = Array.from(document.querySelectorAll(".authors a"))
    .map((node) => cleanText(node.textContent))
    .filter(Boolean);
  const authors = displayAuthors.length ? displayAuthors : metaValues("citation_author");
  const arxivId = metaValues("citation_arxiv_id")[0] || parsed.id;
  const requestedVersion = parsed.version;
  const historyVersions = Array.from(document.querySelectorAll(".submission-history, .submission-history + *"))
    .flatMap((node) => Array.from(node.textContent.matchAll(/\[v(\d+)\]/g), (match) => Number(match[1])));
  const arxivVersion = requestedVersion || (historyVersions.length ? Math.max(...historyVersions) : null);
  const versionedId = `${arxivId}${arxivVersion ? `v${arxivVersion}` : ""}`;
  const canonicalUrl = `https://arxiv.org/abs/${requestedVersion ? versionedId : arxivId}`;
  const htmlUrl = `https://arxiv.org/html/${versionedId}`;
  const pdfUrl = arxivVersion
    ? `https://arxiv.org/pdf/${versionedId}`
    : metaValues("citation_pdf_url")[0] || `https://arxiv.org/pdf/${arxivId}`;
  const doiValue = metaValues("citation_doi")[0] || document.querySelector("a[href*='doi.org']")?.getAttribute("href") || "";
  const doi = cleanText(doiValue).replace(/^https?:\/\/(?:dx\.)?doi\.org\//i, "");
  const subjects = Array.from(document.querySelectorAll(".subjects .primary-subject, .subjects .tag"))
    .map((node) => cleanText(node.textContent))
    .filter(Boolean);
  const journal = cleanText(document.querySelector("td.tablecell.jref, .jref")?.textContent || "");
  const abstract = cleanText(document.querySelector("blockquote.abstract")?.textContent.replace(/^Abstract:\s*/i, "") || metadata.description);

  const paperMetadata = {
    ...metadata,
    title,
    description: "",
    abstract,
    author: authors[0] || metadata.author,
    authors,
    published: (metaValues("citation_date")[0] || metadata.published).replace(/^(\d{4})\/(\d{2})\/(\d{2})$/, "$1-$2-$3"),
    modified: (metaValues("citation_online_date")[0] || metadata.modified).replace(/^(\d{4})\/(\d{2})\/(\d{2})$/, "$1-$2-$3"),
    site: "arXiv",
    url: canonicalUrl,
    arxivId,
    arxivVersion,
    doi,
    journal,
    subjects,
    sourceTags: subjects,
    htmlUrl,
    pdfUrl,
    sourceType: "paper",
    contentFormat: "html"
  };

  try {
    const response = await fetchResource(htmlUrl, { Accept: "text/html" });
    if (!response.ok || !response.contentType.toLowerCase().includes("text/html")) {
      return { pdfFallback: { ...paperMetadata, sourceUrl: canonicalUrl, url: pdfUrl } };
    }

    const doc = new DOMParser().parseFromString(response.text, "text/html");
    const paper = doc.querySelector("article.ltx_document, .ltx_document");
    if (!paper) {
      return { pdfFallback: { ...paperMetadata, sourceUrl: canonicalUrl, url: pdfUrl } };
    }

    const clone = paper.cloneNode(true);
    clone.querySelectorAll([
      "script",
      "style",
      "nav",
      ".ltx_page_header",
      ".ltx_page_footer",
      ".ltx_title_document",
      ".ltx_authors",
      ".ltx_role_affiliation",
      ".ltx_role_keywords",
      ".ltx_keywords"
    ].join(",")).forEach((node) => node.remove());

    return {
      ...paperMetadata,
      captureMethod: "arxiv-html",
      contentUrl: htmlUrl,
      maxImages: 40,
      html: clone.innerHTML
    };
  } catch (_error) {
    return { pdfFallback: { ...paperMetadata, sourceUrl: canonicalUrl, url: pdfUrl } };
  }
}

async function tryAzureDevOpsWiki(metadata) {
  const parsed = Core.parseAzureDevOpsWikiUrl(metadata.pageUrl);
  if (!parsed) {
    return null;
  }

  const rendered = document.querySelector(".markdown-content.markdown-render-area, .markdown-content");
  if (!rendered) {
    return null;
  }

  const pagePathLinks = Array.from(document.querySelectorAll("a[href*='pagePath=']"))
    .map((link) => {
      try {
        return new URL(link.href, location.href).searchParams.get("pagePath") || "";
      } catch (_error) {
        return "";
      }
    })
    .filter(Boolean);
  const wikiPath = parsed.pagePath || pagePathLinks[pagePathLinks.length - 1] || "";
  const pathTitle = wikiPath.split("/").filter(Boolean).pop() || "";
  const title = cleanText(parsed.title || pathTitle || metadata.title.replace(/\s+-\s+(?:Overview|Wiki)$/i, ""));
  const canonicalUrl = canonicalAzureWikiUrl(metadata.pageUrl, parsed, title);
  const apiUrl = new URL(
    `/${encodeURIComponent(parsed.organization)}/${encodeURIComponent(parsed.project)}/_apis/wiki/wikis/${encodeURIComponent(parsed.wikiIdentifier)}/pages/${encodeURIComponent(parsed.pageId)}`,
    location.origin
  );
  apiUrl.searchParams.set("includeContent", "true");
  apiUrl.searchParams.set("api-version", "7.1");

  let markdown = "";
  let revision = "";
  let captureMethod = "azure-devops-wiki-api";
  const editor = document.querySelector("textarea[aria-label*='supports markdown']");
  try {
    const response = await fetch(apiUrl.href, {
      method: "GET",
      credentials: "include",
      cache: "no-store",
      headers: { Accept: "application/json" }
    });
    if (response.ok) {
      const result = await response.json();
      if (typeof result?.content === "string" && result.content.trim()) {
        markdown = result.content;
        revision = (response.headers.get("etag") || "").replace(/^W\//, "").replace(/^"|"$/g, "");
      }
    }
  } catch (_error) {
    // The editor or rendered wiki body below are fallbacks for restricted sessions.
  }
  if (!markdown && editor?.value?.trim()) {
    markdown = editor.value;
    captureMethod = "azure-devops-wiki-editor";
  }

  const common = {
    ...metadata,
    title,
    description: "",
    url: canonicalUrl,
    site: "Azure DevOps Wiki",
    platform: "azure-devops",
    organization: parsed.organization,
    project: parsed.project,
    wiki: parsed.wikiIdentifier,
    wikiPageId: parsed.pageId,
    wikiPath,
    revision,
    modified: selectAttr("time[datetime]", "datetime") || metadata.modified || metadata.published,
    sourceType: "wiki",
    authenticatedImages: true,
    maxImages: 40,
    indexMetadata: compactObject({
      platform: "azure-devops",
      organization: parsed.organization,
      project: parsed.project,
      wiki: parsed.wikiIdentifier,
      wiki_page_id: parsed.pageId,
      wiki_path: wikiPath,
      revision
    })
  };

  if (markdown) {
    return {
      ...common,
      captureMethod,
      contentFormat: "markdown",
      markdown: normalizeAzureWikiMarkdown(markdown, rendered, canonicalUrl, parsed, wikiPath)
    };
  }

  const originalImages = Array.from(rendered.querySelectorAll("img"));
  const clone = rendered.cloneNode(true);
  Array.from(clone.querySelectorAll("img")).forEach((image, index) => {
    const source = originalImages[index]?.currentSrc || originalImages[index]?.getAttribute("src") || "";
    if (source) {
      image.setAttribute("src", normalizeUrl(source, canonicalUrl));
    }
  });
  clone.querySelectorAll("script, style, nav, button, form, iframe, noscript, svg, .toc-container").forEach((node) => node.remove());
  return {
    ...common,
    captureMethod: "azure-devops-wiki-dom",
    contentFormat: "html",
    html: clone.innerHTML
  };
}

async function tryGitHubGist(metadata) {
  const parsed = Core.parseGistUrl(metadata.pageUrl);
  if (!parsed) {
    return null;
  }

  try {
    const response = await chrome.runtime.sendMessage({
      type: "fetch-gist",
      gistId: parsed.id,
      revision: parsed.revision
    });
    if (!response?.ok || !response.gist?.files) {
      return null;
    }

    const gist = response.gist;
    const files = [];
    for (const file of Object.values(gist.files)) {
      let content = typeof file.content === "string" ? file.content : "";
      if (file.truncated && file.raw_url) {
        const raw = await chrome.runtime.sendMessage({ type: "fetch-gist-raw", url: file.raw_url });
        if (raw?.ok) {
          content = raw.text;
        }
      }
      files.push({ ...file, content });
    }

    if (!files.length) {
      return null;
    }

    const title = cleanText(gist.description || files[0].filename || `GitHub Gist ${parsed.id}`);
    const sections = files.map((file) => {
      const isMarkdown = file.language === "Markdown" || /\.(?:md|markdown|mdown)$/i.test(file.filename || "");
      const body = isMarkdown
        ? Core.normalizeSourceMarkdown(file.content, files.length === 1 ? title : "", file.raw_url || gist.html_url)
        : fencedCode(file.content, file.language || file.filename?.split(".").pop() || "");
      return files.length === 1 ? body : `## ${file.filename}\n\n${body}`;
    });
    const owner = gist.owner?.login || parsed.owner || "";
    const gistFiles = files.map((file) => file.filename).filter(Boolean);

    return {
      ...metadata,
      title,
      description: files.length === 1 ? gist.description || "" : `${files.length} files`,
      author: owner,
      published: gist.created_at || metadata.published,
      modified: gist.updated_at || metadata.modified,
      url: gist.html_url || `https://gist.github.com/${owner ? `${owner}/` : ""}${parsed.id}`,
      site: "GitHub Gist",
      platform: "github-gist",
      gistId: parsed.id,
      gistFiles,
      revision: gist.history?.[0]?.version || parsed.revision || "",
      sourceType: "gist",
      contentFormat: "markdown",
      captureMethod: "github-gist-api",
      authenticatedImages: true,
      authenticatedImageHosts: [
        "gist.githubusercontent.com",
        "user-images.githubusercontent.com",
        "private-user-images.githubusercontent.com"
      ],
      maxImages: 40,
      markdown: sections.join("\n\n").trim(),
      indexMetadata: compactObject({
        platform: "github-gist",
        gist_id: parsed.id,
        gist_files: gistFiles,
        revision: gist.history?.[0]?.version || parsed.revision || ""
      })
    };
  } catch (_error) {
    return null;
  }
}

function canonicalAzureWikiUrl(value, parsed, title) {
  const url = new URL(value);
  url.hash = "";
  if (/\/\d+(?:\/|$)/.test(url.pathname)) {
    url.search = "";
    return url.href;
  }
  return `${url.origin}/${encodeURIComponent(parsed.organization)}/${encodeURIComponent(parsed.project)}/_wiki/wikis/${encodeURIComponent(parsed.wikiIdentifier)}/${encodeURIComponent(parsed.pageId)}/${encodeURIComponent(title)}`;
}

function normalizeAzureWikiMarkdown(markdown, rendered, baseUrl, parsed, wikiPath) {
  const attachmentUrls = new Map();
  rendered.querySelectorAll("img").forEach((image) => {
    const absolute = normalizeUrl(image.currentSrc || image.getAttribute("src"), baseUrl);
    try {
      const url = new URL(absolute);
      const path = url.searchParams.get("path");
      if (path) {
        attachmentUrls.set(path, url.href);
        attachmentUrls.set(path.replace(/^\//, ""), url.href);
      }
    } catch (_error) {
      // Keep unmatched Markdown image targets unchanged.
    }
  });

  let body = String(markdown || "")
    .replace(/^\s*\[\[_(?:TOC|TOSP)_\]\]\s*$/gim, "")
    .replace(/^\s*:::\s*mermaid\s*$([\s\S]*?)^\s*:::\s*$/gim, (_match, diagram) => `\n\`\`\`mermaid\n${diagram.trim()}\n\`\`\`\n`);
  body = Core.rewriteMarkdownImageUrls(body, (target) => {
    let decoded = target;
    try {
      decoded = decodeURIComponent(target);
    } catch (_error) {
      // Use the original target if it is not URI encoded.
    }
    return attachmentUrls.get(decoded) || attachmentUrls.get(decoded.replace(/^\//, "")) || "";
  });
  body = Core.rewriteMarkdownLinkUrls(body, (target) =>
    azureWikiPageLink(target, parsed, wikiPath, baseUrl)
  );
  return body.trim();
}

function azureWikiPageLink(target, parsed, wikiPath, baseUrl) {
  if (!target || /^(?:https?:|mailto:|tel:|data:|blob:|#)/i.test(target)) {
    return "";
  }
  if (/^\/?\.attachments\//i.test(target)) {
    return "";
  }

  const [pathPart, fragment = ""] = target.split("#", 2);
  let pagePath = "";
  try {
    pagePath = decodeURIComponent(pathPart);
  } catch (_error) {
    pagePath = pathPart;
  }
  if (!pagePath.startsWith("/")) {
    const baseParts = String(wikiPath || "/").split("/").filter(Boolean).slice(0, -1);
    for (const part of pagePath.split("/")) {
      if (!part || part === ".") {
        continue;
      }
      if (part === "..") {
        baseParts.pop();
      } else {
        baseParts.push(part);
      }
    }
    pagePath = `/${baseParts.join("/")}`;
  }
  pagePath = pagePath.replace(/\.md$/i, "");

  const url = new URL(
    `/${encodeURIComponent(parsed.organization)}/${encodeURIComponent(parsed.project)}/_wiki/wikis/${encodeURIComponent(parsed.wikiIdentifier)}`,
    baseUrl
  );
  url.searchParams.set("pagePath", pagePath);
  if (fragment) {
    url.searchParams.set("anchor", fragment);
  }
  return url.href;
}

function fencedCode(content, language) {
  const body = String(content || "").replace(/\n+$/, "");
  const longest = Math.max(3, ...Array.from(body.matchAll(/`+/g), (match) => match[0].length + 1));
  const fence = "`".repeat(longest);
  const safeLanguage = String(language || "").toLowerCase().replace(/[^a-z0-9_+.-]/g, "");
  return `${fence}${safeLanguage}\n${body}\n${fence}`;
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([_key, item]) =>
    item !== undefined && item !== null && item !== "" && (!Array.isArray(item) || item.length)
  ));
}

function collectMetadata() {
  const canonical = selectAttr("link[rel='canonical']", "href") || location.href;
  const wordpressApiUrl =
    selectAttr("link[rel='alternate'][type='application/json']", "href") ||
    selectAttr("link[rel='https://api.w.org/']", "href");
  const generator = cleanText(selectAttr("meta[name='generator']", "content"));

  return {
    title: cleanText(
      selectAttr("meta[property='og:title']", "content") ||
      document.title ||
      location.hostname
    ),
    description: cleanText(
      selectAttr("meta[name='description']", "content") ||
      selectAttr("meta[property='og:description']", "content") ||
      ""
    ),
    author: cleanText(
      selectAttr("meta[name='author']", "content") ||
      selectAttr("meta[property='article:author']", "content") ||
      ""
    ),
    published:
      selectAttr("meta[property='article:published_time']", "content") ||
      selectAttr("time[datetime]", "datetime") ||
      "",
    modified: selectAttr("meta[property='article:modified_time']", "content") || "",
    site: cleanText(selectAttr("meta[property='og:site_name']", "content") || location.hostname),
    url: canonical,
    pageUrl: location.href,
    generator,
    primaryImage: normalizeUrl(
      selectAttr("meta[property='og:image']", "content") ||
      selectAttr("meta[name='twitter:image']", "content"),
      canonical
    ),
    capturedAt: new Date().toISOString(),
    capturedDate: Core.localDateStamp(),
    wordpressApiUrl: normalizeUrl(wordpressApiUrl, location.href),
    feedUrls: collectFeedUrls(),
    bloggerBlogId: findBloggerId("blog"),
    bloggerPostId: findBloggerId("post")
  };
}

async function tryWordPressApi(apiUrl, fallbackMetadata) {
  try {
    const response = await fetchResource(apiUrl, { Accept: "application/json" });
    if (!response.ok) {
      return null;
    }

    const post = JSON.parse(response.text);
    if (!post?.content?.rendered) {
      return null;
    }

    return {
      title: cleanText(htmlToPlainText(post.title?.rendered) || fallbackMetadata.title),
      description: cleanText(htmlToPlainText(post.excerpt?.rendered) || fallbackMetadata.description),
      author: fallbackMetadata.author,
      published: post.date || fallbackMetadata.published,
      modified: post.modified || fallbackMetadata.modified,
      url: post.link || fallbackMetadata.url,
      captureMethod: "wordpress-rest",
      html: post.content.rendered
    };
  } catch (_error) {
    return null;
  }
}

async function tryDirectMarkdown(metadata) {
  try {
    const response = await fetchResource(metadata.pageUrl, {
      Accept: "text/markdown, text/html;q=0.1"
    });
    const contentType = response.contentType.split(";")[0].trim().toLowerCase();
    if (!response.ok || !["text/markdown", "text/x-markdown", "application/markdown"].includes(contentType)) {
      return null;
    }

    const markdown = response.text.trim();
    if (markdown.length < 40 || /<html[\s>]/i.test(markdown.slice(0, 500))) {
      return null;
    }

    const isHashnode = /hashnode/i.test(metadata.generator) || /\.hashnode\.dev$/i.test(location.hostname);
    return {
      ...metadata,
      captureMethod: isHashnode ? "hashnode-markdown" : "source-markdown",
      markdown
    };
  } catch (_error) {
    return null;
  }
}

async function tryForemApi(metadata) {
  const isForem = location.hostname === "dev.to" || /forem|dev community/i.test(metadata.generator);
  if (!isForem) {
    return null;
  }

  const parts = new URL(metadata.pageUrl).pathname.split("/").filter(Boolean);
  if (parts.length !== 2) {
    return null;
  }

  try {
    const endpoint = `${location.origin}/api/articles/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
    const response = await fetchResource(endpoint, {
      Accept: "application/vnd.forem.api-v1+json"
    });
    if (!response.ok) {
      return null;
    }

    const post = JSON.parse(response.text);
    if (!post?.body_markdown) {
      return null;
    }

    return {
      ...metadata,
      title: cleanText(post.title || metadata.title),
      description: cleanText(post.description || metadata.description),
      author: cleanText(post.user?.name || metadata.author),
      published: post.published_timestamp || post.published_at || metadata.published,
      modified: post.edited_at || metadata.modified,
      url: post.url || metadata.url,
      featuredImage: post.cover_image || post.social_image || metadata.primaryImage,
      sourceTags: normalizeTagList(post.tags || post.tag_list),
      captureMethod: "forem-api",
      markdown: post.body_markdown
    };
  } catch (_error) {
    return null;
  }
}

async function tryGhostApi(metadata, settings) {
  const apiUrl = String(settings.ghostApiUrl || "").replace(/\/+$/, "");
  const key = String(settings.ghostContentApiKey || "").trim();
  if (!apiUrl || !key) {
    return null;
  }

  const slug = new URL(metadata.pageUrl).pathname.split("/").filter(Boolean).pop();
  if (!slug) {
    return null;
  }

  try {
    const endpoint = `${apiUrl}/posts/slug/${encodeURIComponent(slug)}/?key=${encodeURIComponent(key)}&include=authors,tags`;
    const response = await fetchResource(endpoint, {
      Accept: "application/json",
      "Accept-Version": "v5.0"
    });
    if (!response.ok) {
      return null;
    }

    const post = JSON.parse(response.text)?.posts?.[0];
    if (!post?.html) {
      return null;
    }
    if (post.url && comparableUrl(post.url) !== comparableUrl(metadata.url)) {
      return null;
    }

    return {
      ...metadata,
      title: cleanText(post.title || metadata.title),
      description: cleanText(post.excerpt || post.custom_excerpt || metadata.description),
      author: cleanText(post.primary_author?.name || post.authors?.[0]?.name || metadata.author),
      published: post.published_at || metadata.published,
      modified: post.updated_at || metadata.modified,
      url: post.url || metadata.url,
      featuredImage: post.feature_image || metadata.primaryImage,
      sourceTags: (post.tags || []).map((tag) => cleanText(tag.name)).filter(Boolean),
      captureMethod: "ghost-content-api",
      html: post.html
    };
  } catch (_error) {
    return null;
  }
}

async function tryBloggerApi(metadata, settings) {
  const isBlogger = /blogger/i.test(metadata.generator) || /\.blogspot\./i.test(location.hostname);
  if (!isBlogger || !metadata.bloggerBlogId || !metadata.bloggerPostId) {
    return null;
  }

  try {
    const endpoint = new URL(
      `https://www.googleapis.com/blogger/v3/blogs/${encodeURIComponent(metadata.bloggerBlogId)}/posts/${encodeURIComponent(metadata.bloggerPostId)}`
    );
    if (settings.bloggerApiKey) {
      endpoint.searchParams.set("key", settings.bloggerApiKey);
    }

    const response = await fetchResource(endpoint.href, { Accept: "application/json" });
    if (!response.ok) {
      return null;
    }

    const post = JSON.parse(response.text);
    if (!post?.content) {
      return null;
    }

    return {
      ...metadata,
      title: cleanText(post.title || metadata.title),
      author: cleanText(post.author?.displayName || metadata.author),
      published: post.published || metadata.published,
      modified: post.updated || metadata.modified,
      url: post.url || metadata.url,
      sourceTags: normalizeTagList(post.labels),
      captureMethod: "blogger-api",
      html: post.content
    };
  } catch (_error) {
    return null;
  }
}

async function trySyndicationFeeds(metadata) {
  for (const feed of metadata.feedUrls.slice(0, 4)) {
    try {
      const response = await fetchResource(feed.url, {
        Accept: "application/feed+json, application/atom+xml, application/rss+xml, application/xml;q=0.9, text/xml;q=0.8"
      });
      if (!response.ok) {
        continue;
      }

      const article = response.contentType.includes("json") || feed.type.includes("json")
        ? articleFromJsonFeed(response.text, metadata)
        : articleFromXmlFeed(response.text, metadata);
      if (article) {
        return article;
      }
    } catch (_error) {
      // Try the next advertised feed.
    }
  }
  return null;
}

function articleFromJsonFeed(text, metadata) {
  const feed = JSON.parse(text);
  const item = (feed.items || []).find((candidate) => feedItemMatches(candidate.url || candidate.external_url || candidate.id, candidate.title, metadata));
  if (!item || (!item.content_html && !item.content_text)) {
    return null;
  }

  const base = {
    ...metadata,
    title: cleanText(item.title || metadata.title),
    description: cleanText(item.summary || metadata.description),
    author: cleanText(item.authors?.[0]?.name || feed.authors?.[0]?.name || metadata.author),
    published: item.date_published || metadata.published,
    modified: item.date_modified || metadata.modified,
    url: item.url || metadata.url,
    featuredImage: item.image || item.banner_image || metadata.primaryImage,
    sourceTags: normalizeTagList(item.tags),
    captureMethod: "json-feed"
  };
  return item.content_html ? { ...base, html: item.content_html } : { ...base, markdown: plainTextToMarkdown(item.content_text) };
}

function articleFromXmlFeed(text, metadata) {
  const xml = new DOMParser().parseFromString(text, "application/xml");
  if (xml.querySelector("parsererror")) {
    return null;
  }

  const isAtom = xml.documentElement.localName.toLowerCase() === "feed";
  const candidates = Array.from(xml.getElementsByTagName(isAtom ? "entry" : "item"));
  const item = candidates.find((candidate) => {
    const link = xmlFeedLink(candidate, isAtom);
    return feedItemMatches(link, directChildText(candidate, "title"), metadata);
  });
  if (!item) {
    return null;
  }

  const encoded = firstTagText(item, ["content:encoded"]);
  const atomContent = isAtom ? directChild(item, "content") : null;
  const description = firstTagText(item, isAtom ? ["summary"] : ["description"]);
  const content = encoded || atomContent?.textContent || (description.length >= 600 ? description : "");
  if (!content) {
    return null;
  }

  const authorNode = directChild(item, "author");
  const author = isAtom
    ? directChildText(authorNode, "name")
    : firstTagText(item, ["dc:creator", "author"]);
  const categories = Array.from(item.getElementsByTagName("category"))
    .map((node) => node.getAttribute("term") || node.textContent)
    .map(cleanText)
    .filter(Boolean);

  return {
    ...metadata,
    title: cleanText(directChildText(item, "title") || metadata.title),
    description: cleanText(description || metadata.description),
    author: cleanText(author || metadata.author),
    published: firstTagText(item, isAtom ? ["published", "updated"] : ["pubDate", "dc:date"]) || metadata.published,
    modified: firstTagText(item, isAtom ? ["updated"] : ["dc:date"]) || metadata.modified,
    url: xmlFeedLink(item, isAtom) || metadata.url,
    sourceTags: categories,
    captureMethod: isAtom ? "atom-feed" : "rss-feed",
    ...(looksLikeHtml(content) ? { html: content } : { markdown: plainTextToMarkdown(content) })
  };
}

function collectFeedUrls() {
  const supportedTypes = new Set([
    "application/feed+json",
    "application/rss+xml",
    "application/atom+xml",
    "application/xml",
    "text/xml"
  ]);
  const seen = new Set();
  return Array.from(document.querySelectorAll("link[rel~='alternate'][href]"))
    .map((link) => ({
      url: normalizeUrl(link.getAttribute("href"), location.href),
      type: (link.getAttribute("type") || "").toLowerCase()
    }))
    .filter((feed) => supportedTypes.has(feed.type) && feed.url && !seen.has(feed.url) && seen.add(feed.url));
}

function findBloggerId(kind) {
  const capitalized = `${kind[0].toUpperCase()}${kind.slice(1)}Id`;
  const lower = `${kind}Id`;
  const selectors = [
    `meta[itemprop='${lower}']`,
    `meta[name='${lower}']`,
    `meta[property='${lower}']`,
    `[data-${kind}-id]`
  ];
  for (const selector of selectors) {
    const node = document.querySelector(selector);
    const value = node?.getAttribute("content") || node?.getAttribute(`data-${kind}-id`);
    if (/^\d+$/.test(value || "")) {
      return value;
    }
  }

  const source = document.documentElement.innerHTML;
  const match = source.match(new RegExp(`["'](?:${lower}|${capitalized})["']\\s*:\\s*["']?(\\d+)`, "i"));
  return match?.[1] || "";
}

function feedItemMatches(url, title, metadata) {
  if (url && comparableUrl(url) === comparableUrl(metadata.url)) {
    return true;
  }
  return cleanText(title).toLocaleLowerCase() === cleanText(metadata.title).toLocaleLowerCase();
}

function comparableUrl(value) {
  try {
    const url = new URL(value, location.href);
    url.hash = "";
    url.search = "";
    url.pathname = url.pathname.replace(/\/+$/, "") || "/";
    return url.href;
  } catch (_error) {
    return String(value || "");
  }
}

function xmlFeedLink(item, isAtom) {
  if (!isAtom) {
    return cleanText(directChildText(item, "link") || directChildText(item, "guid"));
  }
  const links = Array.from(item.children).filter((node) => node.localName === "link");
  return links.find((node) => !node.getAttribute("rel") || node.getAttribute("rel") === "alternate")?.getAttribute("href") || "";
}

function directChild(node, localName) {
  return node ? Array.from(node.children).find((child) => child.localName === localName) || null : null;
}

function directChildText(node, localName) {
  return cleanText(directChild(node, localName)?.textContent || "");
}

function firstTagText(node, names) {
  for (const name of names) {
    const localName = name.includes(":") ? name.split(":").pop() : name;
    const candidate = node.getElementsByTagName(name)[0] || node.getElementsByTagNameNS("*", localName)[0];
    if (candidate?.textContent) {
      return candidate.textContent.trim();
    }
  }
  return "";
}

function looksLikeHtml(value) {
  return /<(?:p|div|h[1-6]|ul|ol|blockquote|pre|table|figure|img|a)\b/i.test(value);
}

function plainTextToMarkdown(value) {
  return String(value || "").replace(/\r\n?/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

function normalizeTagList(value) {
  if (Array.isArray(value)) {
    return value.map(cleanText).filter(Boolean);
  }
  return String(value || "").split(",").map(cleanText).filter(Boolean);
}

async function fetchAuthenticatedImage(value) {
  const url = new URL(String(value || ""), location.href);
  const sourceHost = location.hostname.toLowerCase();
  const targetHost = url.hostname.toLowerCase();
  const isAzureWikiAsset = sourceHost === "dev.azure.com" && url.origin === location.origin;
  const isGitHubGistAsset = sourceHost === "gist.github.com" && [
    "gist.githubusercontent.com",
    "user-images.githubusercontent.com",
    "private-user-images.githubusercontent.com"
  ].includes(targetHost);
  if (!isAzureWikiAsset && !isGitHubGistAsset) {
    throw new Error("Authenticated image host is not allowed for this source page.");
  }

  const response = await fetch(url.href, {
    method: "GET",
    credentials: "include",
    cache: "no-store",
    headers: { Accept: "image/*" }
  });
  if (!response.ok) {
    throw new Error(`Authenticated image fetch failed: ${response.status} ${response.statusText}`);
  }

  const contentType = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (contentType && !contentType.startsWith("image/")) {
    throw new Error(`Authenticated resource is not an image: ${contentType}`);
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  if (!bytes.byteLength) {
    throw new Error("Authenticated image response was empty.");
  }
  if (bytes.byteLength > 8 * 1024 * 1024) {
    throw new Error("Authenticated image is larger than 8 MB.");
  }

  return {
    ok: true,
    contentType: contentType || "image/png",
    base64: bytesToBase64(bytes)
  };
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary);
}

async function fetchResource(url, headers = {}) {
  const response = await chrome.runtime.sendMessage({
    type: "fetch-resource",
    request: { url, headers }
  });
  if (!response || response.error) {
    throw new Error(response?.error || "Resource fetch failed.");
  }
  return response;
}

function extractFromDocument(metadata) {
  const candidate =
    document.querySelector("article") ||
    document.querySelector("main") ||
    document.querySelector("[role='main']") ||
    document.body;

  const clone = candidate.cloneNode(true);
  clone.querySelectorAll("script, style, nav, aside, form, iframe, noscript, svg").forEach((node) => {
    node.remove();
  });

  return {
    ...metadata,
    captureMethod: "dom-readable",
    html: clone.innerHTML
  };
}

function htmlToMarkdown(html, baseUrl) {
  const doc = new DOMParser().parseFromString(`<main>${html}</main>`, "text/html");
  normalizeCodeBlocks(doc);
  return markdownChildren(doc.body.firstElementChild, { baseUrl }).replace(/\n{3,}/g, "\n\n").trim();
}

function normalizeCodeBlocks(root) {
  root.querySelectorAll("pre.EnlighterJSRAW").forEach((pre) => {
    const code = root.createElement("code");
    code.textContent = pre.textContent;
    pre.textContent = "";
    pre.append(code);
  });
}

function collectImageAssets(html, baseUrl, primaryImageUrl, maxImages = 12) {
  const doc = new DOMParser().parseFromString(`<main>${html}</main>`, "text/html");
  const candidates = [];

  if (primaryImageUrl) {
    candidates.push({
      url: primaryImageUrl,
      alt: "Featured image",
      width: 0,
      height: 0
    });
  }

  doc.querySelectorAll("img").forEach((image) => {
    const src =
      image.getAttribute("src") ||
      image.getAttribute("data-src") ||
      image.getAttribute("data-lazy-src") ||
      largestSrcsetUrl(image.getAttribute("srcset") || image.getAttribute("data-srcset"));
    const url = normalizeUrl(src, baseUrl);

    if (!url || shouldSkipImage(url, image)) {
      return;
    }

    candidates.push({
      url,
      alt: cleanText(image.getAttribute("alt") || image.getAttribute("title") || ""),
      width: Number(image.getAttribute("width") || 0),
      height: Number(image.getAttribute("height") || 0)
    });
  });

  const seen = new Set();
  return candidates
    .filter((image) => {
      if (seen.has(image.url)) {
        return false;
      }
      seen.add(image.url);
      return true;
    })
    .slice(0, maxImages);
}

function largestSrcsetUrl(srcset) {
  if (!srcset) {
    return "";
  }

  return srcset
    .split(",")
    .map((candidate) => candidate.trim().split(/\s+/)[0])
    .filter(Boolean)
    .pop() || "";
}

function shouldSkipImage(url, image) {
  if (/^(data|blob):/i.test(url)) {
    return true;
  }

  const width = Number(image.getAttribute("width") || 0);
  const height = Number(image.getAttribute("height") || 0);
  if (width > 0 && height > 0 && (width < 80 || height < 80)) {
    return true;
  }

  return /\/(avatar|logo|icon|spinner|tracking|pixel)[^/]*\.(gif|png|jpg|jpeg|webp|svg)([?#].*)?$/i.test(url);
}

function markdownChildren(node, context) {
  return Array.from(node.childNodes)
    .map((child) => markdownNode(child, context))
    .join("");
}

function markdownNode(node, context) {
  if (node.nodeType === Node.TEXT_NODE) {
    return node.textContent.replace(/\s+/g, " ");
  }

  if (node.nodeType !== Node.ELEMENT_NODE) {
    return "";
  }

  const tag = node.tagName.toLowerCase();
  const text = () => markdownChildren(node, context).trim();
  const plain = () => cleanText(node.textContent);

  if (tag === "math") {
    const tex = node.getAttribute("alttext") ||
      node.querySelector("annotation[encoding='application/x-tex']")?.textContent ||
      plain();
    if (!tex) {
      return "";
    }
    const display = node.getAttribute("display") === "block" || Boolean(node.closest(".ltx_equation, .ltx_equationgroup"));
    return display ? `\n\n$$\n${tex}\n$$\n\n` : `$${tex}$`;
  }

  if (/^h[1-6]$/.test(tag)) {
    if (node.classList.contains("ltx_title_abstract")) {
      return `\n\n## ${plain()}\n\n`;
    }
    const level = Number(tag.slice(1));
    return `\n\n${"#".repeat(Math.min(level + 1, 6))} ${plain()}\n\n`;
  }

  switch (tag) {
    case "p":
      return `\n\n${text()}\n\n`;
    case "br":
      return "\n";
    case "strong":
    case "b":
      return `**${text()}**`;
    case "em":
    case "i":
      return `_${text()}_`;
    case "code":
      if (node.parentElement?.tagName.toLowerCase() === "pre") {
        return node.textContent.replace(/\n+$/, "");
      }
      return `\`${plain().replace(/`/g, "\\`")}\``;
    case "pre":
      return `\n\n\`\`\`\n${node.textContent.replace(/\n+$/, "")}\n\`\`\`\n\n`;
    case "blockquote":
      return `\n\n${text().split("\n").map((line) => `> ${line}`).join("\n")}\n\n`;
    case "ul":
      return `\n${listItems(node, context, "-")}\n`;
    case "ol":
      return `\n${listItems(node, context, "1.")}\n`;
    case "li":
      return `${text()}\n`;
    case "a": {
      const href = normalizeUrl(node.getAttribute("href"), context.baseUrl);
      const label = text() || href;
      return href ? `[${label}](${href})` : label;
    }
    case "img": {
      const src = normalizeUrl(node.getAttribute("src"), context.baseUrl);
      const alt = cleanText(node.getAttribute("alt") || "");
      return src ? `![${alt}](${src})` : "";
    }
    case "sup":
      return `<sup>${text()}</sup>`;
    case "sub":
      return `<sub>${text()}</sub>`;
    case "table":
      return `\n\n${tableToMarkdown(node, context)}\n\n`;
    case "figure":
      return `\n\n${text()}\n\n`;
    case "figcaption":
      return `\n\n*${text()}*\n\n`;
    case "div":
    case "section":
    case "article":
    case "main":
    case "span":
    case "thead":
    case "tbody":
    case "tr":
    case "td":
    case "th":
      return markdownChildren(node, context);
    default:
      return markdownChildren(node, context);
  }
}

function listItems(listNode, context, marker) {
  return Array.from(listNode.children)
    .filter((child) => child.tagName.toLowerCase() === "li")
    .map((item) => `${marker} ${markdownChildren(item, context).trim().replace(/\n+/g, "\n  ")}`)
    .join("\n");
}

function tableToMarkdown(table, context) {
  const rows = Array.from(table.querySelectorAll("tr")).map((row) =>
    Array.from(row.children).map((cell) => markdownChildren(cell, context).trim().replace(/\n+/g, " "))
  );

  if (!rows.length) {
    return "";
  }

  const header = rows[0];
  const separator = header.map(() => "---");
  const body = rows.slice(1);
  return [header, separator, ...body]
    .map((row) => `| ${row.map(escapeTableCell).join(" |")} |`)
    .join("\n");
}

function escapeTableCell(value) {
  return value.replace(/\|/g, "\\|");
}

function selectAttr(selector, attr) {
  return document.querySelector(selector)?.getAttribute(attr) || "";
}

function normalizeUrl(value, baseUrl) {
  if (!value) {
    return "";
  }

  try {
    return new URL(value, baseUrl || location.href).href;
  } catch (_error) {
    return value;
  }
}

function htmlToPlainText(html) {
  if (!html) {
    return "";
  }
  return new DOMParser().parseFromString(html, "text/html").body.textContent || "";
}

function cleanText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

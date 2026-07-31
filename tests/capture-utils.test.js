const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const Core = require("../capture-utils.js");

test("buildGitHubPath keeps the configured root and local capture date", () => {
  assert.equal(
    Core.buildGitHubPath({
      rootFolder: "/knowledge//clips/",
      capturedDate: "2026-07-18",
      url: "https://www.example.com/posts/hello",
      title: "Hällo, Markdown!"
    }),
    "knowledge/clips/2026/07/2026-07-18-example.com-hallo-markdown-477df9.md"
  );
});

test("buildIndexPath assigns the same URL to a stable metadata shard", () => {
  assert.equal(
    Core.buildIndexPath({
      rootFolder: "/knowledge//clips/",
      url: "https://www.example.com/posts/hello"
    }),
    "knowledge/clips/index/47.jsonl"
  );
});

test("normalizeSourceMarkdown removes source frontmatter and a duplicate H1", () => {
  const result = Core.normalizeSourceMarkdown(
    "---\ntitle: Original\n---\n# Example article\n\nRead [more](/more).\n\n![Plot](images/plot.png)",
    "Example article",
    "https://example.com/posts/example"
  );

  assert.equal(
    result,
    "Read [more](https://example.com/more).\n\n![Plot](https://example.com/posts/images/plot.png)"
  );
});

test("collectMarkdownImageAssets deduplicates normalized Markdown images", () => {
  assert.deepEqual(
    Core.collectMarkdownImageAssets(
      "![One](https://img.example/a.png)\n![Again](https://img.example/a.png)\n![Two](https://img.example/b.jpg)",
      "https://img.example/cover.jpg"
    ).map((image) => image.url),
    [
      "https://img.example/cover.jpg",
      "https://img.example/a.png",
      "https://img.example/b.jpg"
    ]
  );
});

test("buildDocument emits conversion metadata and preserves marked notes", () => {
  const markdown = Core.buildDocument({
    title: "Queued PDF",
    url: "https://example.com/file.pdf",
    site: "example.com",
    capturedAt: "2026-07-18T10:00:00Z",
    capturedDate: "2026-07-18",
    captureMethod: "pdf-docling-pending",
    sourceType: "pdf",
    contentFormat: "pdf",
    conversionStatus: "pending",
    converter: "docling",
    pdfPath: "web-clips/2026/07/assets/clip/source.pdf",
    tags: ["research"],
    notes: "Keep this context.",
    body: "Pending"
  });

  assert.match(markdown, /conversion_status: "pending"/);
  assert.match(markdown, /pdf_path: "web-clips\/2026\/07\/assets\/clip\/source\.pdf"/);
  assert.match(markdown, /<!-- clipper-notes-start -->[\s\S]*Keep this context\.[\s\S]*<!-- clipper-notes-end -->/);
});

test("parseArxivUrl recognizes abstract, HTML, PDF, versions, and legacy IDs", () => {
  assert.deepEqual(Core.parseArxivUrl("https://arxiv.org/abs/2311.02462v5"), {
    kind: "abs",
    id: "2311.02462",
    version: 5,
    versionedId: "2311.02462v5"
  });
  assert.equal(Core.parseArxivUrl("https://arxiv.org/html/2311.02462").kind, "html");
  assert.equal(Core.parseArxivUrl("https://arxiv.org/pdf/hep-th/9901001.pdf").id, "hep-th/9901001");
  assert.equal(Core.parseArxivUrl("https://example.com/abs/2311.02462"), null);
});

test("parsePdfSourceUrl recognizes remote and local PDF sources", () => {
  assert.deepEqual(Core.parsePdfSourceUrl("file:///Users/example/Downloads/paper.pdf"), {
    url: "file:///Users/example/Downloads/paper.pdf",
    protocol: "file:",
    isLocal: true,
    hasPdfExtension: true
  });
  assert.deepEqual(Core.parsePdfSourceUrl("https://example.com/download?id=42"), {
    url: "https://example.com/download?id=42",
    protocol: "https:",
    isLocal: false,
    hasPdfExtension: false
  });
  assert.equal(Core.parsePdfSourceUrl("chrome://pdf-internals/"), null);
});

test("buildDocument emits scientific paper metadata", () => {
  const markdown = Core.buildDocument({
    title: "Example paper",
    url: "https://arxiv.org/abs/2311.02462v5",
    site: "arXiv",
    authors: ["Ada Example", "Lin Example"],
    abstract: "A useful abstract.",
    arxivId: "2311.02462",
    arxivVersion: 5,
    doi: "10.48550/arXiv.2311.02462",
    subjects: ["Artificial Intelligence (cs.AI)"],
    htmlUrl: "https://arxiv.org/html/2311.02462v5",
    pdfUrl: "https://arxiv.org/pdf/2311.02462v5",
    sourceType: "paper",
    contentFormat: "html",
    body: "## Abstract\n\nA useful abstract."
  });

  assert.match(markdown, /authors: \["Ada Example", "Lin Example"\]/);
  assert.match(markdown, /arxiv_id: "2311\.02462"/);
  assert.match(markdown, /arxiv_version: "5"/);
  assert.match(markdown, /source_type: "paper"/);
});

test("parseAzureDevOpsWikiUrl recognizes friendly and query-based page URLs", () => {
  assert.deepEqual(
    Core.parseAzureDevOpsWikiUrl(
      "https://dev.azure.com/bag-soviaframework/SoviaFramework/_wiki/wikis/SoviaFramework.wiki/6841/ChatControl"
    ),
    {
      organization: "bag-soviaframework",
      project: "SoviaFramework",
      wikiIdentifier: "SoviaFramework.wiki",
      pageId: "6841",
      title: "ChatControl",
      pagePath: ""
    }
  );

  const queryRoute = Core.parseAzureDevOpsWikiUrl(
    "https://dev.azure.com/example/project-id/_wiki/wikis/wiki-id?pagePath=%2FDocs%2FStart&pageId=42"
  );
  assert.equal(queryRoute.pageId, "42");
  assert.equal(queryRoute.pagePath, "/Docs/Start");
  assert.equal(Core.parseAzureDevOpsWikiUrl("https://example.com/_wiki/wikis/test/1"), null);
});

test("parseGistUrl recognizes owner, gist ID, and revisions", () => {
  assert.deepEqual(
    Core.parseGistUrl("https://gist.github.com/octocat/6cad326836d38bd3a7ae/0123456789abcdef"),
    {
      owner: "octocat",
      id: "6cad326836d38bd3a7ae",
      revision: "0123456789abcdef"
    }
  );
  assert.equal(Core.parseGistUrl("https://github.com/octocat/repo"), null);
});

test("rewriteMarkdownImageUrls changes images without touching normal links", () => {
  const markdown = "![Diagram](/.attachments/diagram.png)\n\n[Documentation](/docs/start)";
  const result = Core.rewriteMarkdownImageUrls(markdown, (url) =>
    url === "/.attachments/diagram.png" ? "https://dev.azure.com/image.png" : ""
  );
  assert.equal(
    result,
    "![Diagram](https://dev.azure.com/image.png)\n\n[Documentation](/docs/start)"
  );
});

test("rewriteMarkdownLinkUrls changes links without touching images", () => {
  const markdown = "[Wiki page](/docs/start)\n\n![Diagram](/.attachments/diagram.png)";
  const result = Core.rewriteMarkdownLinkUrls(markdown, (url) =>
    url === "/docs/start" ? "https://dev.azure.com/wiki?pagePath=/docs/start" : ""
  );
  assert.equal(
    result,
    "[Wiki page](https://dev.azure.com/wiki?pagePath=/docs/start)\n\n![Diagram](/.attachments/diagram.png)"
  );
});

test("buildDocument emits wiki and gist metadata", () => {
  const markdown = Core.buildDocument({
    title: "Wiki page",
    url: "https://dev.azure.com/example/project/_wiki/wikis/docs/42/Page",
    platform: "azure-devops",
    organization: "example",
    project: "project",
    wiki: "docs",
    wikiPageId: "42",
    wikiPath: "/Docs/Page",
    revision: "abc123",
    sourceType: "wiki",
    gistFiles: ["README.md", "example.js"],
    body: "Content"
  });

  assert.match(markdown, /platform: "azure-devops"/);
  assert.match(markdown, /wiki_page_id: "42"/);
  assert.match(markdown, /wiki_path: "\/Docs\/Page"/);
  assert.match(markdown, /gist_files: \["README\.md", "example\.js"\]/);
});

test("GitHub saves reject an unavailable target repository before reading archive paths", async () => {
  const requests = [];
  const context = {
    TextEncoder,
    URL,
    chrome: { runtime: { onMessage: { addListener() {} } } },
    fetch: async (url) => {
      requests.push(url);
      return {
        ok: false,
        status: 404,
        statusText: "Not Found",
        async json() { return { message: "Not Found" }; }
      };
    },
    globalThis: null,
    importScripts() {}
  };
  context.globalThis = context;
  context.SourceBraidCore = Core;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "background.js"), "utf8"), context);

  await assert.rejects(
    context.ensureGitHubRepository({ owner: "missing-owner", repo: "missing-repo", token: "test-token" }),
    /GitHub repository missing-owner\/missing-repo was not found or the token cannot access it\./
  );
  assert.deepEqual(requests, ["https://api.github.com/repos/missing-owner/missing-repo"]);
});

test("DeepMind blog capture excludes cover and related-post cards", () => {
  function section({ heading = "", text = "", classes = "", media = false } = {}) {
    const clone = {
      textContent: text,
      outerHTML: `<section>${text}</section>`,
      querySelector(selector) { return selector === "img, video" && media ? {} : null; },
      querySelectorAll() { return []; }
    };
    return {
      tagName: "SECTION",
      textContent: text,
      matches(selector) { return selector === ".section-cover" && classes.includes("section-cover"); },
      querySelector(selector) {
        if (selector === "h1, h2, h3" && heading) return { textContent: heading };
        if (selector === "h1" && classes.includes("has-h1")) return {};
        return null;
      },
      cloneNode() { return { ...clone }; }
    };
  }

  const content = {
    nodes: [],
    append(node) { this.nodes.push(node); },
    get textContent() { return this.nodes.map((node) => node.textContent).join(" "); },
    get innerHTML() { return this.nodes.map((node) => node.outerHTML).join(""); }
  };
  const articleText = "Article paragraph. ".repeat(40);
  const context = {
    URL,
    Node: { TEXT_NODE: 3, ELEMENT_NODE: 1 },
    chrome: { runtime: { onMessage: { addListener() {} } } },
    document: {
      querySelector(selector) {
        return selector === "main" ? {
          children: [
            section({ heading: "Example", text: "Cover", classes: "section-cover has-h1" }),
            section({ text: articleText }),
            section({ heading: "Related posts", text: "Related card" })
          ]
        } : null;
      },
      createElement() { return content; }
    },
    globalThis: null
  };
  context.globalThis = context;
  context.SourceBraidCore = Core;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "content.js"), "utf8"), context);

  const result = context.tryGoogleDeepMindBlog({
    pageUrl: "https://deepmind.google/blog/example/",
    title: "Example"
  });
  assert.equal(result.captureMethod, "google-deepmind-dom");
  assert.match(result.html, /Article paragraph/);
  assert.doesNotMatch(result.html, /Cover|Related card/);
});

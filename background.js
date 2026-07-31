importScripts("capture-utils.js");

const Core = globalThis.SourceBraidCore;
const MAX_TEXT_RESPONSE_BYTES = 5 * 1024 * 1024;
const MAX_PDF_BYTES = 25 * 1024 * 1024;
const PDF_WORKFLOW_FILES = [
  "requirements-docling.txt",
  "scripts/convert_pdfs.py",
  "scripts/push_with_retry.py",
  ".github/workflows/convert-pdfs.yml"
];

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "fetch-resource") {
    fetchResource(message.request)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message || String(error) }));
    return true;
  }

  if (message?.type === "probe-resource") {
    probeResource(message.url)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message || String(error) }));
    return true;
  }

  if (message?.type === "fetch-gist") {
    fetchGist(message.gistId, message.revision)
      .then(sendResponse)
      .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
    return true;
  }

  if (message?.type === "fetch-gist-raw") {
    fetchGistRaw(message.url)
      .then(sendResponse)
      .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
    return true;
  }

  if (message?.type === "download-markdown") {
    downloadMarkdown(message, sendResponse);
    return true;
  }

  if (message?.type === "save-to-github") {
    saveToGitHub(message.settings, message.clip)
      .then(sendResponse)
      .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
    return true;
  }

  if (message?.type === "save-pdf-to-github") {
    savePdfToGitHub(message.settings, message.pdf)
      .then(sendResponse)
      .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
    return true;
  }

  return false;
});

async function fetchResource(request) {
  const url = validateRemoteUrl(request?.url);
  const headers = sanitizeFetchHeaders(request?.headers);
  const response = await fetch(url, {
    method: "GET",
    credentials: "omit",
    redirect: "follow",
    cache: "no-store",
    headers
  });
  const declaredSize = Number(response.headers.get("content-length") || 0);
  if (declaredSize > MAX_TEXT_RESPONSE_BYTES) {
    throw new Error(`Resource response is larger than ${MAX_TEXT_RESPONSE_BYTES / 1024 / 1024} MB.`);
  }

  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_TEXT_RESPONSE_BYTES) {
    throw new Error(`Resource response is larger than ${MAX_TEXT_RESPONSE_BYTES / 1024 / 1024} MB.`);
  }

  return {
    ok: response.ok,
    status: response.status,
    statusText: response.statusText,
    url: response.url,
    contentType: response.headers.get("content-type") || "",
    text
  };
}

async function probeResource(value) {
  const url = validateRemoteUrl(value);
  let response = await fetch(url, {
    method: "HEAD",
    credentials: "omit",
    redirect: "follow",
    cache: "no-store"
  });

  if (!response.ok && [403, 405, 501].includes(response.status)) {
    response = await fetch(url, {
      method: "GET",
      credentials: "omit",
      redirect: "follow",
      cache: "no-store",
      headers: { Range: "bytes=0-0" }
    });
  }

  return {
    ok: response.ok,
    status: response.status,
    url: response.url,
    contentType: response.headers.get("content-type") || "",
    contentLength: Number(response.headers.get("content-length") || 0)
  };
}

async function fetchGist(value, revisionValue) {
  const gistId = String(value || "").trim();
  if (!/^[a-f0-9]{5,}$/i.test(gistId)) {
    throw new Error("Invalid GitHub Gist ID.");
  }

  const revision = String(revisionValue || "").trim();
  if (revision && !/^[a-f0-9]{7,}$/i.test(revision)) {
    throw new Error("Invalid GitHub Gist revision.");
  }
  const endpoint = `https://api.github.com/gists/${encodeURIComponent(gistId)}${revision ? `/${encodeURIComponent(revision)}` : ""}`;
  let headers = await gistRequestHeaders("application/vnd.github+json");
  let response = await fetch(endpoint, {
    method: "GET",
    credentials: "omit",
    cache: "no-store",
    headers
  });
  if ([401, 403].includes(response.status) && headers.Authorization) {
    headers = await gistRequestHeaders("application/vnd.github+json", false);
    response = await fetch(endpoint, { method: "GET", credentials: "omit", cache: "no-store", headers });
  }
  const text = await limitedResponseText(response, 10 * 1024 * 1024, "Gist API response");
  if (!response.ok) {
    throw new Error(`Could not read GitHub Gist: ${response.status} ${response.statusText}`);
  }
  const gist = JSON.parse(text);
  return {
    ok: true,
    gist: {
      id: gist.id,
      html_url: gist.html_url,
      files: gist.files,
      owner: gist.owner ? { login: gist.owner.login } : null,
      public: gist.public,
      created_at: gist.created_at,
      updated_at: gist.updated_at,
      description: gist.description,
      history: Array.isArray(gist.history) && gist.history[0] ? [{ version: gist.history[0].version }] : []
    }
  };
}

async function fetchGistRaw(value) {
  const url = new URL(validateRemoteUrl(value));
  if (url.hostname.toLowerCase() !== "gist.githubusercontent.com") {
    throw new Error("Unsupported GitHub Gist raw-content host.");
  }

  let headers = await gistRequestHeaders("text/plain");
  let response = await fetch(url.href, {
    method: "GET",
    credentials: "omit",
    cache: "no-store",
    headers
  });
  if ([401, 403].includes(response.status) && headers.Authorization) {
    headers = await gistRequestHeaders("text/plain", false);
    response = await fetch(url.href, { method: "GET", credentials: "omit", cache: "no-store", headers });
  }
  const text = await limitedResponseText(response, MAX_TEXT_RESPONSE_BYTES, "Gist raw response");
  if (!response.ok) {
    throw new Error(`Could not read GitHub Gist file: ${response.status} ${response.statusText}`);
  }
  return { ok: true, text };
}

async function gistRequestHeaders(accept, includeToken = true) {
  const stored = await chrome.storage.local.get({ githubToken: "" });
  return {
    Accept: accept,
    "X-GitHub-Api-Version": "2022-11-28",
    ...(includeToken && stored.githubToken ? { Authorization: `Bearer ${stored.githubToken}` } : {})
  };
}

async function limitedResponseText(response, maxBytes, label) {
  const declaredSize = Number(response.headers.get("content-length") || 0);
  if (declaredSize > maxBytes) {
    throw new Error(`${label} is larger than ${Math.round(maxBytes / 1024 / 1024)} MB.`);
  }
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new Error(`${label} is larger than ${Math.round(maxBytes / 1024 / 1024)} MB.`);
  }
  return text;
}

function validateRemoteUrl(value) {
  const url = new URL(String(value || ""));
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error(`Unsupported URL protocol: ${url.protocol}`);
  }
  return url.href;
}

function sanitizeFetchHeaders(value) {
  const allowed = new Set(["accept", "accept-version"]);
  const headers = {};
  for (const [name, headerValue] of Object.entries(value || {})) {
    if (allowed.has(name.toLowerCase()) && typeof headerValue === "string") {
      headers[name] = headerValue.slice(0, 500);
    }
  }
  return headers;
}

function downloadMarkdown(message, sendResponse) {
  const url = `data:text/markdown;charset=utf-8;base64,${base64EncodeUtf8(message.markdown)}`;

  chrome.downloads.download(
    {
      url,
      filename: message.filename,
      saveAs: false
    },
    (downloadId) => {
      if (chrome.runtime.lastError) {
        sendResponse({ ok: false, error: chrome.runtime.lastError.message });
        return;
      }

      sendResponse({ ok: true, downloadId });
    }
  );
}

async function saveToGitHub(settings, clip) {
  validateGitHubSave(settings, clip);
  await ensureGitHubRepository(settings);

  const indexPath = Core.buildIndexPath({ rootFolder: settings.rootFolder, url: clip.indexEntry?.url });
  const existingIndex = await getContent(settings, indexPath);
  const existingEntry = findIndexEntry(existingIndex?.text || "", clip.indexEntry?.url);

  const imageResult = await persistImages(settings, clip);
  const markdown = rewriteAssetLinks(clip.markdown, imageResult.replacements);
  const indexEntry = {
    ...clip.indexEntry,
    images: imageResult.images
  };

  await putContent({
    settings,
    path: clip.path,
    content: markdown,
    message: `Save web clip: ${indexEntry.title || clip.path}`
  });

  const nextIndex = buildNextIndex(existingIndex?.text || "", indexEntry);

  await putContent({
    settings,
    path: indexPath,
    content: nextIndex,
    sha: existingIndex?.sha,
    message: `Update web clip index: ${indexEntry.title || clip.path}`
  });

  if (existingEntry?.path && existingEntry.path !== clip.path) {
    await removePreviousClip(settings, existingEntry);
  }

  return { ok: true, path: clip.path, indexPath, images: imageResult.images.length };
}

async function savePdfToGitHub(settings, pdf) {
  validatePdfSave(settings, pdf);
  await ensureGitHubRepository(settings);
  await ensurePdfWorkflow(settings);

  const source = Core.parsePdfSourceUrl(pdf.url);
  if (!source || (source.isLocal && !source.hasPdfExtension)) {
    throw new Error("Unsupported PDF URL. Use an HTTP(S) URL or a local file ending in .pdf.");
  }
  if (source.isLocal) {
    await requireLocalFileAccess();
  }

  let response;
  try {
    response = await fetch(source.url, {
      method: "GET",
      credentials: "omit",
      redirect: "follow",
      cache: "no-store",
      headers: { Accept: "application/pdf" }
    });
  } catch (error) {
    if (source.isLocal) {
      throw new Error(`Could not read the local PDF. ${localFileAccessHint()}`);
    }
    throw error;
  }
  if (!response.ok) {
    if (source.isLocal) {
      throw new Error(`Could not read the local PDF. ${localFileAccessHint()}`);
    }
    throw new Error(`Could not download PDF: ${response.status} ${response.statusText}`);
  }

  const contentType = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (contentType && contentType !== "application/pdf" && !looksLikePdfUrl(response.url)) {
    throw new Error(`The URL did not return a PDF (${contentType || "unknown content type"}).`);
  }

  const declaredSize = Number(response.headers.get("content-length") || 0);
  if (declaredSize > MAX_PDF_BYTES) {
    throw new Error(`PDF is larger than the ${MAX_PDF_BYTES / 1024 / 1024} MB extension limit.`);
  }
  const bytes = await response.arrayBuffer();
  if (!bytes.byteLength) {
    throw new Error("The PDF response was empty.");
  }
  if (bytes.byteLength > MAX_PDF_BYTES) {
    throw new Error(`PDF is larger than the ${MAX_PDF_BYTES / 1024 / 1024} MB extension limit.`);
  }

  const title = cleanPdfTitle(pdf.title, response.url);
  const sourceUrl = pdf.sourceUrl || pdf.url;
  const capturedAt = pdf.capturedAt || new Date().toISOString();
  const capturedDate = pdf.capturedDate || Core.localDateStamp();
  const path = Core.buildGitHubPath({
    rootFolder: settings.rootFolder,
    capturedDate,
    url: sourceUrl,
    title
  });
  const clipSlug = basename(path).replace(/\.md$/i, "");
  const pdfPath = `${dirname(path)}/assets/${clipSlug}/source.pdf`;
  const parsedSourceUrl = new URL(sourceUrl);
  const site = pdf.site || (parsedSourceUrl.protocol === "file:" ? "Local PDF" : parsedSourceUrl.hostname.replace(/^www\./, ""));
  const markdown = Core.buildDocument({
    title,
    url: sourceUrl,
    site,
    author: pdf.author,
    authors: pdf.authors,
    abstract: pdf.abstract,
    published: pdf.published,
    modified: pdf.modified,
    doi: pdf.doi,
    arxivId: pdf.arxivId,
    arxivVersion: pdf.arxivVersion,
    journal: pdf.journal,
    subjects: pdf.subjects,
    htmlUrl: pdf.htmlUrl,
    pdfUrl: pdf.pdfUrl || pdf.url,
    capturedAt,
    capturedDate,
    captureMethod: "pdf-docling-pending",
    sourceType: pdf.sourceType || "pdf",
    contentFormat: "pdf",
    conversionStatus: "pending",
    converter: "docling",
    pdfPath,
    tags: pdf.tags || [],
    notes: pdf.notes || "",
    body: "> The original PDF has been uploaded. GitHub Actions will replace this placeholder with Docling Markdown.",
    includeTitle: true
  });
  const indexPath = Core.buildIndexPath({ rootFolder: settings.rootFolder, url: sourceUrl });
  const existingIndex = await getContent(settings, indexPath);
  const existingEntry = findIndexEntry(existingIndex?.text || "", sourceUrl);
  const indexEntry = {
    title,
    url: sourceUrl,
    path,
    date: capturedDate,
    tags: pdf.tags || [],
    source: site,
    capture_method: "pdf-docling-pending",
    source_type: pdf.sourceType || "pdf",
    content_format: "pdf",
    conversion_status: "pending",
    converter: "docling",
    pdf_path: pdfPath,
    captured_at: capturedAt,
    images: []
  };
  for (const [key, value] of Object.entries({
    authors: pdf.authors,
    published: pdf.published,
    modified: pdf.modified,
    doi: pdf.doi,
    arxiv_id: pdf.arxivId,
    arxiv_version: pdf.arxivVersion,
    journal: pdf.journal,
    subjects: pdf.subjects,
    html_url: pdf.htmlUrl,
    pdf_url: pdf.pdfUrl || pdf.url
  })) {
    if (value !== undefined && value !== null && value !== "" && (!Array.isArray(value) || value.length)) {
      indexEntry[key] = value;
    }
  }

  // The PDF is committed last: that push triggers the workflow after its metadata exists.
  await putContent({
    settings,
    path,
    content: markdown,
    message: `Queue PDF web clip: ${title}`
  });
  const nextIndex = buildNextIndex(existingIndex?.text || "", indexEntry);
  await putContent({
    settings,
    path: indexPath,
    content: nextIndex,
    sha: existingIndex?.sha,
    message: `Index queued PDF web clip: ${title}`
  });

  if (existingEntry?.path && existingEntry.path !== path) {
    await removePreviousClip(settings, existingEntry);
  }

  await putContentBase64({
    settings,
    path: pdfPath,
    contentBase64: base64EncodeBytes(bytes),
    message: `Upload PDF for Docling conversion: ${title}`
  });

  return { ok: true, path, indexPath, pdfPath, conversionStatus: "pending" };
}

async function ensurePdfWorkflow(settings) {
  for (const path of PDF_WORKFLOW_FILES) {
    const existing = await getContentRecord(settings, path, false);
    if (existing) {
      continue;
    }

    const packaged = await fetch(chrome.runtime.getURL(path));
    if (!packaged.ok) {
      throw new Error(`Bundled PDF workflow file is unavailable: ${path}`);
    }
    const content = await packaged.text();
    try {
      await putContent({
        settings,
        path,
        content,
        message: `Install SourceBraid PDF support: ${path}`
      });
    } catch (error) {
      if (path.startsWith(".github/workflows/")) {
        throw new Error(`${error.message} The GitHub token also needs Workflows: Read and write to install PDF support.`);
      }
      throw error;
    }
  }
}

function validatePdfSave(settings, pdf) {
  validateGitHubSave(settings, { path: "pending.md", markdown: "pending" });
  if (!pdf?.url) {
    throw new Error("Missing PDF URL.");
  }
}

async function requireLocalFileAccess() {
  const checker = chrome.extension?.isAllowedFileSchemeAccess;
  const allowed = typeof checker === "function" && await checker.call(chrome.extension);
  if (!allowed) {
    throw new Error(`Local PDF access is disabled. ${localFileAccessHint()}`);
  }
}

function localFileAccessHint() {
  return "Open chrome://extensions, select SourceBraid, enable 'Allow access to file URLs', and try again.";
}

function cleanPdfTitle(value, url) {
  const title = String(value || "")
    .replace(/\s+-\s+PDF(?:\s+Viewer)?$/i, "")
    .replace(/\.pdf$/i, "")
    .trim();
  if (title) {
    return title;
  }
  try {
    return decodeURIComponent(basename(new URL(url).pathname)).replace(/\.pdf$/i, "") || "PDF document";
  } catch (_error) {
    return "PDF document";
  }
}

function looksLikePdfUrl(value) {
  try {
    return /\.pdf$/i.test(new URL(value).pathname);
  } catch (_error) {
    return false;
  }
}

async function persistImages(settings, clip) {
  const images = Array.isArray(clip.images) ? clip.images : [];
  const savedImages = [];
  const replacements = [];
  const usedFilenames = new Set();

  for (let index = 0; index < images.length; index += 1) {
    const image = images[index];

    try {
      const asset = await fetchImageAsset(image, clip);
      if (!asset) {
        continue;
      }

      const assetPath = buildAssetPath(settings, clip.path, image, asset.contentType, index, usedFilenames);
      await putContentBase64({
        settings,
        path: assetPath,
        contentBase64: base64EncodeBytes(asset.bytes),
        message: `Save web clip image: ${assetPath}`
      });

      const relativePath = relativeRepoPath(dirname(clip.path), assetPath);
      replacements.push({ from: image.url, to: relativePath });
      savedImages.push({
        url: image.url,
        path: assetPath,
        relative_path: relativePath,
        alt: image.alt || "",
        content_type: asset.contentType
      });
    } catch (error) {
      savedImages.push({
        url: image.url,
        error: error.message || String(error),
        alt: image.alt || ""
      });
    }
  }

  return { images: savedImages, replacements };
}

async function fetchImageAsset(image, clip) {
  const url = image?.url;
  if (!url || /^(data|blob):/i.test(url)) {
    return null;
  }

  if (image.fetch_mode === "tab-authenticated") {
    if (!Number.isInteger(clip?.tabId)) {
      throw new Error("The source tab is unavailable for authenticated image capture.");
    }
    const result = await chrome.tabs.sendMessage(clip.tabId, {
      type: "fetch-authenticated-image",
      url
    });
    if (!result?.ok || !result.base64) {
      throw new Error(result?.error || "Authenticated image capture failed.");
    }
    return {
      bytes: base64DecodeBytes(result.base64),
      contentType: result.contentType || "image/png"
    };
  }

  const response = await fetch(url, { credentials: "omit" });
  if (!response.ok) {
    throw new Error(`image fetch failed: ${response.status} ${response.statusText}`);
  }

  const contentType = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (contentType && !contentType.startsWith("image/")) {
    throw new Error(`not an image response: ${contentType}`);
  }

  const bytes = await response.arrayBuffer();
  if (bytes.byteLength === 0) {
    throw new Error("empty image response");
  }
  if (bytes.byteLength > 8 * 1024 * 1024) {
    throw new Error("image is larger than 8 MB");
  }

  return { bytes, contentType: contentType || "image/jpeg" };
}

function buildAssetPath(settings, clipPath, image, contentType, index, usedFilenames) {
  const [year, month] = clipPathDateParts(clipPath);
  const clipSlug = basename(clipPath).replace(/\.md$/i, "");
  const extension = imageExtension(image.url, contentType);
  const rawName = image.alt || basename(new URL(image.url).pathname).replace(/\.[a-z0-9]+$/i, "") || "image";
  let filename = `${String(index + 1).padStart(2, "0")}-${slugify(rawName).slice(0, 48)}.${extension}`;

  while (usedFilenames.has(filename)) {
    filename = `${String(index + 1).padStart(2, "0")}-${slugify(rawName).slice(0, 42)}-${usedFilenames.size}.${extension}`;
  }
  usedFilenames.add(filename);

  return `${settings.rootFolder}/${year}/${month}/assets/${clipSlug}/${filename}`;
}

function clipPathDateParts(clipPath) {
  const match = clipPath.match(/\/(\d{4})\/(\d{2})\//);
  return match ? [match[1], match[2]] : new Date().toISOString().slice(0, 7).split("-");
}

function imageExtension(url, contentType) {
  const contentTypeMap = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
    "image/svg+xml": "svg",
    "image/avif": "avif"
  };

  if (contentTypeMap[contentType]) {
    return contentTypeMap[contentType];
  }

  try {
    const ext = new URL(url).pathname.match(/\.([a-z0-9]+)$/i)?.[1]?.toLowerCase();
    return ext || "jpg";
  } catch (_error) {
    return "jpg";
  }
}

function rewriteAssetLinks(markdown, replacements) {
  return replacements.reduce((nextMarkdown, replacement) => {
    return nextMarkdown.split(replacement.from).join(replacement.to);
  }, markdown);
}

async function getContent(settings, path) {
  return getContentRecord(settings, path, true);
}

async function getContentRecord(settings, path, decodeText) {
  const url = githubContentsUrl(settings, path, `ref=${encodeURIComponent(settings.branch)}`);
  const response = await githubFetch(settings, url, { method: "GET" });

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    throw new Error(await githubError(response, `Could not read ${path}`));
  }

  const json = await response.json();
  return {
    sha: json.sha,
    text: decodeText && json.content ? base64DecodeUtf8(json.content.replace(/\s/g, "")) : ""
  };
}

async function putContent({ settings, path, content, message, sha }) {
  return putContentBase64({
    settings,
    path,
    contentBase64: base64EncodeUtf8(content),
    message,
    sha
  });
}

async function putContentBase64({ settings, path, contentBase64, message, sha }) {
  let existingSha = sha;

  if (!existingSha) {
    const existing = await getContentRecord(settings, path, false);
    existingSha = existing?.sha;
  }

  const response = await githubFetch(settings, githubContentsUrl(settings, path), {
    method: "PUT",
    body: JSON.stringify({
      message,
      content: contentBase64,
      branch: settings.branch,
      ...(existingSha ? { sha: existingSha } : {})
    })
  });

  if (!response.ok) {
    throw new Error(await githubError(response, `Could not write ${path}`));
  }

  return response.json();
}

function buildNextIndex(existingText, entry) {
  const lines = existingText
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => {
      try {
        const existing = JSON.parse(line);
        return existing.url !== entry.url && existing.path !== entry.path;
      } catch (_error) {
        return false;
      }
    });

  lines.push(JSON.stringify(entry));
  return `${lines.join("\n")}\n`;
}

function findIndexEntry(existingText, url) {
  if (!url) {
    return null;
  }

  for (const line of existingText.split("\n")) {
    try {
      const entry = JSON.parse(line);
      if (entry.url === url) {
        return entry;
      }
    } catch (_error) {
      // Ignore malformed historical index lines while searching for a URL.
    }
  }

  return null;
}

async function removePreviousClip(settings, entry) {
  const paths = [entry.path];
  if (entry.pdf_path) {
    paths.push(entry.pdf_path);
  }
  if (Array.isArray(entry.images)) {
    paths.push(...entry.images.map((image) => image.path).filter(Boolean));
  }

  for (const path of paths) {
    try {
      await deleteContent(settings, path, `Move web clip asset: ${path}`);
    } catch (_error) {
      // A stale asset should not make the new capture fail after the index is updated.
    }
  }
}

async function deleteContent(settings, path, message) {
  const existing = await getContent(settings, path);
  if (!existing?.sha) {
    return;
  }

  const response = await githubFetch(settings, githubContentsUrl(settings, path), {
    method: "DELETE",
    body: JSON.stringify({
      message,
      sha: existing.sha,
      branch: settings.branch
    })
  });

  if (!response.ok && response.status !== 404) {
    throw new Error(await githubError(response, `Could not delete ${path}`));
  }
}

function githubContentsUrl(settings, path, query) {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const base = `https://api.github.com/repos/${encodeURIComponent(settings.owner)}/${encodeURIComponent(settings.repo)}/contents/${encodedPath}`;
  return query ? `${base}?${query}` : base;
}

async function ensureGitHubRepository(settings) {
  const repository = `${settings.owner}/${settings.repo}`;
  const url = `https://api.github.com/repos/${encodeURIComponent(settings.owner)}/${encodeURIComponent(settings.repo)}`;
  const response = await githubFetch(settings, url, { method: "GET" });

  if (response.status === 404) {
    throw new Error(`GitHub repository ${repository} was not found or the token cannot access it.`);
  }
  if (!response.ok) {
    throw new Error(await githubError(response, `Could not access GitHub repository ${repository}`));
  }
}

function githubFetch(settings, url, options = {}) {
  return fetch(url, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${settings.token}`,
      "Content-Type": "application/json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(options.headers || {})
    }
  });
}

async function githubError(response, fallback) {
  try {
    const json = await response.json();
    return `${fallback}: ${response.status} ${json.message || response.statusText}`;
  } catch (_error) {
    return `${fallback}: ${response.status} ${response.statusText}`;
  }
}

function validateGitHubSave(settings, clip) {
  const missing = [];
  if (!settings?.owner) missing.push("owner");
  if (!settings?.repo) missing.push("repo");
  if (!settings?.branch) missing.push("branch");
  if (!settings?.rootFolder) missing.push("root folder");
  if (!settings?.token) missing.push("token");
  if (!clip?.path) missing.push("clip path");
  if (!clip?.markdown) missing.push("clip markdown");

  if (missing.length) {
    throw new Error(`Missing required value: ${missing.join(", ")}.`);
  }
}

function dirname(path) {
  return path.split("/").slice(0, -1).join("/");
}

function basename(path) {
  return path.split("/").pop() || "";
}

function relativeRepoPath(fromDir, toPath) {
  const fromParts = fromDir.split("/").filter(Boolean);
  const toParts = toPath.split("/").filter(Boolean);

  while (fromParts.length && toParts.length && fromParts[0] === toParts[0]) {
    fromParts.shift();
    toParts.shift();
  }

  return [...fromParts.map(() => ".."), ...toParts].join("/");
}

function slugify(value) {
  return Core.slugify(value || "image");
}

function base64DecodeUtf8(value) {
  return new TextDecoder().decode(base64DecodeBytes(value));
}

function base64DecodeBytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function base64EncodeUtf8(value) {
  const bytes = new TextEncoder().encode(value);
  return base64EncodeBytes(bytes);
}

function base64EncodeBytes(value) {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let binary = "";
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }

  return btoa(binary);
}

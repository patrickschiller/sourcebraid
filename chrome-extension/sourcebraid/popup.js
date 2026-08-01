const Core = globalThis.SourceBraidCore;
const saveButton = document.querySelector("#save");
const downloadButton = document.querySelector("#download");
const saveSettingsButton = document.querySelector("#save-settings");
const exportSourceBraidConfigButton = document.querySelector("#export-sourcebraid-config");
const statusBox = document.querySelector("#status");
const titleBox = document.querySelector("#page-title");
const tagsInput = document.querySelector("#tags");
const notesInput = document.querySelector("#notes");
const ownerInput = document.querySelector("#owner");
const repoInput = document.querySelector("#repo");
const branchInput = document.querySelector("#branch");
const rootFolderInput = document.querySelector("#root-folder");
const tokenInput = document.querySelector("#token");
const ghostApiUrlInput = document.querySelector("#ghost-api-url");
const ghostApiKeyInput = document.querySelector("#ghost-api-key");
const bloggerApiKeyInput = document.querySelector("#blogger-api-key");
const settingsPanel = document.querySelector("#settings");
const settingsToggle = document.querySelector("#settings-toggle");

let lastClip = null;

init().catch((error) => {
  setStatus(error.message || String(error), "error");
});

async function init() {
  const tab = await getActiveTab({ optional: true });
  titleBox.textContent = tab?.title || "Current tab";
  await loadSettings();

  settingsToggle.addEventListener("click", () => {
    setSettingsOpen(settingsPanel.hidden);
  });

  saveButton.addEventListener("click", async () => {
    await saveCurrentTab();
  });

  saveSettingsButton.addEventListener("click", async () => {
    await saveSettings();
    setStatus("GitHub settings saved.", "success");
  });

  exportSourceBraidConfigButton.addEventListener("click", async () => {
    await exportSourceBraidConfig();
  });

  downloadButton.addEventListener("click", async () => {
    await downloadLastClip();
  });
}

async function saveCurrentTab() {
  setBusy(true, "Capturing content...");
  let pdfMode = false;

  try {
    const settings = collectSettings();
    validateSettings(settings);
    await persistSettings(settings);

    const tab = await getActiveTab();
    pdfMode = await isPdfTab(tab);
    if (pdfMode) {
      setBusy(true, "Uploading PDF and queuing Docling conversion...");
      const result = await chrome.runtime.sendMessage({
        type: "save-pdf-to-github",
        settings,
        pdf: {
          url: tab.url,
          title: tab.title,
          tags: parseTags(tagsInput.value),
          notes: notesInput.value.trim(),
          capturedAt: new Date().toISOString(),
          capturedDate: localDateStamp()
        }
      });
      if (!result?.ok) {
        throw new Error(result?.error || "PDF upload failed.");
      }
      setStatus(`PDF queued at ${settings.owner}/${settings.repo}:${result.path}`, "success");
      return;
    }

    const clip = await captureCurrentTab(settings);
    if (clip.pdfFallback) {
      pdfMode = true;
      setBusy(true, "arXiv HTML unavailable; uploading PDF for Docling conversion...");
      const result = await chrome.runtime.sendMessage({
        type: "save-pdf-to-github",
        settings,
        pdf: clip.pdfFallback
      });
      if (!result?.ok) {
        throw new Error(result?.error || "arXiv PDF fallback failed.");
      }
      setStatus(`arXiv paper queued for conversion at ${settings.owner}/${settings.repo}:${result.path}`, "success");
      return;
    }
    lastClip = clip;

    setBusy(true, `Uploading ${clip.path}...`);
    if (!hasChromeApi("runtime", "sendMessage")) {
      throw new Error("Chrome runtime API is unavailable. Reload the extension in chrome://extensions.");
    }

    const result = await chrome.runtime.sendMessage({
      type: "save-to-github",
      settings,
      clip
    });

    if (!result?.ok) {
      throw new Error(result?.error || "GitHub upload failed.");
    }

    setStatus(`Saved to ${settings.owner}/${settings.repo}:${clip.path}`, "success");
  } catch (error) {
    const fallbackHint = pdfMode ? "" : " You can use Download Fallback if capture succeeded.";
    setStatus(`${error.message || String(error)}${fallbackHint}`, "error");
  } finally {
    setBusy(false);
  }
}

async function downloadLastClip() {
  setBusy(true, "Capturing fallback Markdown...");

  try {
    const settings = collectSettings();
    const tab = await getActiveTab();
    if (await isPdfTab(tab)) {
      throw new Error("PDF fallback download is not available because Docling runs in GitHub Actions. Use Save to GitHub.");
    }
    const clip = await captureCurrentTab(settings);
    if (clip.pdfFallback) {
      throw new Error("This arXiv paper has no HTML version. Use Save to GitHub for automatic PDF conversion.");
    }
    lastClip = clip;

    downloadMarkdownFile(clip);

    setStatus("Downloaded fallback Markdown.", "success");
  } catch (error) {
    setStatus(error.message || String(error), "error");
  } finally {
    setBusy(false);
  }
}

async function captureCurrentTab(settings) {
  const tab = await getActiveTab();
  if (!tab?.id) {
    throw new Error("No active tab found.");
  }

  await ensureContentScript(tab.id);
  const clip = await sendTabMessage(tab.id, {
    type: "capture-markdown",
    tags: parseTags(tagsInput.value),
    notes: notesInput.value.trim(),
    rootFolder: normalizeRootFolder(settings.rootFolder),
    adapterSettings: {
      ghostApiUrl: settings.ghostApiUrl,
      ghostContentApiKey: settings.ghostContentApiKey,
      bloggerApiKey: settings.bloggerApiKey
    }
  });

  if (clip?.error) {
    throw new Error(clip.error);
  }

  if (!clip?.markdown && !clip?.pdfFallback) {
    throw new Error("The page did not return Markdown content.");
  }

  clip.tabId = tab.id;

  return clip;
}

function downloadMarkdownFile(clip) {
  const filename = clip.path.split("/").pop() || "web-clip.md";
  downloadBlobFile(filename, clip.markdown, "text/markdown;charset=utf-8");
}

function downloadBlobFile(filename, content, type) {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");

  link.href = url;
  link.download = filename;
  link.style.display = "none";
  document.body.append(link);
  link.click();
  link.remove();

  setTimeout(() => {
    URL.revokeObjectURL(url);
  }, 1000);
}

async function ensureContentScript(tabId) {
  if (!hasChromeApi("scripting", "executeScript")) {
    throw new Error("Chrome scripting API is unavailable. Reload the extension in chrome://extensions.");
  }

  try {
    await sendTabMessage(tabId, { type: "ping" });
  } catch (_error) {
    await chrome.scripting.executeScript({
      target: { tabId },
      files: ["capture-utils.js", "content.js"]
    });
  }
}

function sendTabMessage(tabId, message) {
  if (!hasChromeApi("tabs", "sendMessage")) {
    throw new Error("Chrome tabs API is unavailable. Open the clipper from the extension toolbar, not as a standalone HTML file.");
  }

  return chrome.tabs.sendMessage(tabId, message);
}

async function getActiveTab(options = {}) {
  if (!hasChromeApi("tabs", "query")) {
    if (options.optional) {
      return null;
    }
    throw new Error("Chrome tabs API is unavailable. Open the clipper from the extension toolbar, not as a standalone HTML file.");
  }

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function isPdfTab(tab) {
  const source = Core?.parsePdfSourceUrl(tab?.url);
  if (!source) {
    return false;
  }

  if (source.isLocal) {
    return source.hasPdfExtension;
  }

  try {
    if (source.hasPdfExtension) {
      return true;
    }
    const result = await chrome.runtime.sendMessage({ type: "probe-resource", url: source.url });
    return Boolean(result?.contentType?.toLowerCase().startsWith("application/pdf"));
  } catch (_error) {
    return false;
  }
}

async function loadSettings() {
  const defaults = {
    githubOwner: "",
    githubRepo: "",
    githubBranch: "main",
    githubRootFolder: "web-clips",
    githubToken: "",
    ghostApiUrl: "",
    ghostContentApiKey: "",
    bloggerApiKey: ""
  };
  const settings = await storageGet(defaults);
  if (settings.githubRepo === "codex-knowledge") {
    settings.githubRepo = "sourcebraid-private";
    await storageSet({ githubRepo: settings.githubRepo });
  }

  ownerInput.value = settings.githubOwner;
  repoInput.value = settings.githubRepo;
  branchInput.value = settings.githubBranch;
  rootFolderInput.value = settings.githubRootFolder;
  tokenInput.value = settings.githubToken;
  ghostApiUrlInput.value = settings.ghostApiUrl;
  ghostApiKeyInput.value = settings.ghostContentApiKey;
  bloggerApiKeyInput.value = settings.bloggerApiKey;
  setSettingsOpen(!(settings.githubOwner && settings.githubRepo && settings.githubToken));
}

async function saveSettings() {
  const settings = collectSettings();
  await persistSettings(settings);
  setSettingsOpen(!(settings.owner && settings.repo && settings.token));
}

function setSettingsOpen(isOpen) {
  settingsPanel.hidden = !isOpen;
  settingsToggle.setAttribute("aria-expanded", String(isOpen));
}

async function exportSourceBraidConfig() {
  try {
    const settings = collectSettings();
    if (!settings.owner || !settings.repo) {
      throw new Error("Owner/org and repository are required for plugin config export.");
    }

    await persistSettings(settings);

    const config = {
      owner: settings.owner,
      repo: settings.repo,
      branch: settings.branch,
      root_folder: settings.rootFolder
    };

    if (settings.token) {
      config.token = settings.token;
    }

    downloadBlobFile(
      "sourcebraid-config.json",
      `${JSON.stringify(config, null, 2)}\n`,
      "application/json;charset=utf-8"
    );
    setStatus("Downloaded SourceBraid plugin config.", "success");
  } catch (error) {
    setStatus(error.message || String(error), "error");
  }
}

async function persistSettings(settings) {
  await storageSet({
    githubOwner: settings.owner,
    githubRepo: settings.repo,
    githubBranch: settings.branch,
    githubRootFolder: settings.rootFolder,
    githubToken: settings.token,
    ghostApiUrl: settings.ghostApiUrl,
    ghostContentApiKey: settings.ghostContentApiKey,
    bloggerApiKey: settings.bloggerApiKey
  });
}

function collectSettings() {
  return {
    owner: ownerInput.value.trim(),
    repo: repoInput.value.trim(),
    branch: branchInput.value.trim() || "main",
    rootFolder: normalizeRootFolder(rootFolderInput.value),
    token: tokenInput.value.trim(),
    ghostApiUrl: normalizeOptionalUrl(ghostApiUrlInput.value),
    ghostContentApiKey: ghostApiKeyInput.value.trim(),
    bloggerApiKey: bloggerApiKeyInput.value.trim()
  };
}

function validateSettings(settings) {
  const missing = [];
  if (!settings.owner) missing.push("owner/org");
  if (!settings.repo) missing.push("repository");
  if (!settings.token) missing.push("fine-grained PAT");

  if (missing.length) {
    throw new Error(`Missing GitHub setting: ${missing.join(", ")}.`);
  }
}

async function storageGet(defaults) {
  if (hasChromeApi("storage", "local") && typeof chrome.storage.local.get === "function") {
    return chrome.storage.local.get(defaults);
  }

  return {
    githubOwner: localStorage.getItem("githubOwner") || defaults.githubOwner,
    githubRepo: localStorage.getItem("githubRepo") || defaults.githubRepo,
    githubBranch: localStorage.getItem("githubBranch") || defaults.githubBranch,
    githubRootFolder: localStorage.getItem("githubRootFolder") || defaults.githubRootFolder,
    githubToken: localStorage.getItem("githubToken") || defaults.githubToken,
    ghostApiUrl: localStorage.getItem("ghostApiUrl") || defaults.ghostApiUrl,
    ghostContentApiKey: localStorage.getItem("ghostContentApiKey") || defaults.ghostContentApiKey,
    bloggerApiKey: localStorage.getItem("bloggerApiKey") || defaults.bloggerApiKey
  };
}

async function storageSet(values) {
  if (hasChromeApi("storage", "local") && typeof chrome.storage.local.set === "function") {
    await chrome.storage.local.set(values);
    return;
  }

  for (const [key, value] of Object.entries(values)) {
    localStorage.setItem(key, value);
  }
}

function hasChromeApi(namespace, member) {
  const root = globalThis.chrome?.[namespace];
  if (!root) {
    return false;
  }

  if (member === "local") {
    return Boolean(root.local);
  }

  return member ? Boolean(root[member]) : true;
}

function normalizeRootFolder(value) {
  return (value || "web-clips")
    .trim()
    .replace(/^\/+|\/+$/g, "")
    .replace(/\/{2,}/g, "/") || "web-clips";
}

function normalizeOptionalUrl(value) {
  const trimmed = String(value || "").trim().replace(/\/+$/, "");
  if (!trimmed) {
    return "";
  }
  try {
    const url = new URL(trimmed);
    return ["http:", "https:"].includes(url.protocol) ? url.href.replace(/\/+$/, "") : "";
  } catch (_error) {
    return trimmed;
  }
}

function localDateStamp(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseTags(value) {
  return value
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function setBusy(isBusy, message) {
  saveButton.disabled = isBusy;
  downloadButton.disabled = isBusy;
  saveSettingsButton.disabled = isBusy;
  exportSourceBraidConfigButton.disabled = isBusy;
  settingsToggle.disabled = isBusy;
  if (message) {
    setStatus(message);
  }
}

function setStatus(message, variant) {
  statusBox.textContent = message;
  statusBox.className = variant ? `status ${variant}` : "status";
}

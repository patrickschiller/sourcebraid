(function () {
  "use strict";

  var MAX_MARKDOWN_LENGTH = 500000;

  function cleanText(value) {
    return String(value || "")
      .replace(/\u00a0/g, " ")
      .replace(/[ \t\f\v]+/g, " ")
      .trim();
  }

  function absoluteURL(value) {
    if (!value || /^data:/i.test(value) || /^javascript:/i.test(value)) return "";
    try {
      return new URL(value, document.baseURI).href;
    } catch (_) {
      return "";
    }
  }

  function escapeInline(value) {
    return cleanText(value).replace(/([\\`*_{}\[\]])/g, "\\$1");
  }

  function languageFor(pre) {
    var code = pre.querySelector("code");
    var className = (code && code.className) || pre.className || "";
    var match = className.match(/(?:language-|lang-)([a-z0-9_+-]+)/i);
    return match ? match[1] : "";
  }

  function tableMarkdown(table) {
    var rows = Array.from(table.querySelectorAll("tr")).map(function (row) {
      return Array.from(row.querySelectorAll(":scope > th, :scope > td")).map(function (cell) {
        return cleanText(cell.textContent).replace(/\|/g, "\\|");
      });
    }).filter(function (row) { return row.length > 0; });

    if (!rows.length) return "";
    var width = Math.max.apply(null, rows.map(function (row) { return row.length; }));
    rows = rows.map(function (row) {
      while (row.length < width) row.push("");
      return row;
    });
    var separator = Array(width).fill("---");
    return "\n\n| " + rows[0].join(" | ") + " |\n| " + separator.join(" | ") + " |\n" +
      rows.slice(1).map(function (row) { return "| " + row.join(" | ") + " |"; }).join("\n") + "\n\n";
  }

  function childrenMarkdown(node) {
    return Array.from(node.childNodes).map(nodeMarkdown).join("");
  }

  function listMarkdown(list, ordered) {
    var index = 1;
    var lines = Array.from(list.children).filter(function (child) {
      return child.tagName === "LI";
    }).map(function (item) {
      var nested = Array.from(item.children).filter(function (child) {
        return child.tagName === "UL" || child.tagName === "OL";
      });
      var clone = item.cloneNode(true);
      Array.from(clone.querySelectorAll(":scope > ul, :scope > ol")).forEach(function (child) { child.remove(); });
      var marker = ordered ? String(index++) + "." : "-";
      var line = marker + " " + childrenMarkdown(clone).trim().replace(/\n+/g, " ");
      nested.forEach(function (child) {
        var nestedText = listMarkdown(child, child.tagName === "OL").trim().replace(/^/gm, "  ");
        if (nestedText) line += "\n" + nestedText;
      });
      return line;
    });
    return lines.length ? "\n\n" + lines.join("\n") + "\n\n" : "";
  }

  function nodeMarkdown(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return String(node.nodeValue || "").replace(/\s+/g, " ");
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return "";

    var tag = node.tagName;
    var inner = function () { return childrenMarkdown(node); };
    var text = function () { return inner().trim(); };

    if (/^H[1-6]$/.test(tag)) {
      return "\n\n" + "#".repeat(Number(tag.slice(1))) + " " + text() + "\n\n";
    }

    switch (tag) {
      case "P":
        return "\n\n" + text() + "\n\n";
      case "BR":
        return "  \n";
      case "STRONG":
      case "B":
        return text() ? "**" + text() + "**" : "";
      case "EM":
      case "I":
        return text() ? "*" + text() + "*" : "";
      case "S":
      case "DEL":
        return text() ? "~~" + text() + "~~" : "";
      case "A": {
        var href = absoluteURL(node.getAttribute("href"));
        var label = text();
        if (!href) return label;
        return "[" + (label || href) + "](" + href + ")";
      }
      case "IMG": {
        var src = absoluteURL(node.currentSrc || node.getAttribute("src") || node.getAttribute("data-src"));
        return src ? "\n\n![" + escapeInline(node.getAttribute("alt") || "") + "](" + src + ")\n\n" : "";
      }
      case "PRE": {
        var codeText = String(node.textContent || "").replace(/^\n+|\n+$/g, "");
        return codeText ? "\n\n```" + languageFor(node) + "\n" + codeText + "\n```\n\n" : "";
      }
      case "CODE": {
        var inlineCode = cleanText(node.textContent);
        if (!inlineCode) return "";
        var fence = inlineCode.indexOf("`") >= 0 ? "``" : "`";
        return fence + inlineCode + fence;
      }
      case "BLOCKQUOTE":
        return "\n\n" + text().split("\n").map(function (line) { return "> " + line; }).join("\n") + "\n\n";
      case "UL":
        return listMarkdown(node, false);
      case "OL":
        return listMarkdown(node, true);
      case "TABLE":
        return tableMarkdown(node);
      case "HR":
        return "\n\n---\n\n";
      case "FIGCAPTION":
        return text() ? "\n\n_" + text() + "_\n\n" : "";
      case "DD":
        return text() ? "\n: " + text() + "\n" : "";
      case "DT":
        return text() ? "\n**" + text() + "**" : "";
      case "SCRIPT":
      case "STYLE":
      case "NOSCRIPT":
      case "TEMPLATE":
        return "";
      default:
        return inner();
    }
  }

  function rootScore(node) {
    var textLength = cleanText(node.innerText).length;
    var linkLength = Array.from(node.querySelectorAll("a")).reduce(function (sum, link) {
      return sum + cleanText(link.innerText).length;
    }, 0);
    return textLength - (linkLength * 1.5);
  }

  function chooseRoot() {
    var selectors = [
      "article",
      "[itemprop='articleBody']",
      ".entry-content",
      ".post-content",
      ".article-content",
      ".post-body",
      "main",
      "[role='main']"
    ];
    var candidates = [];
    selectors.forEach(function (selector) {
      document.querySelectorAll(selector).forEach(function (node) {
        if (cleanText(node.innerText).length >= 200 && candidates.indexOf(node) < 0) candidates.push(node);
      });
    });
    if (!candidates.length) return document.body;
    return candidates.sort(function (left, right) { return rootScore(right) - rootScore(left); })[0];
  }

  function chooseGoogleDeepMindRoot() {
    if (location.hostname.toLowerCase() !== "deepmind.google" || location.pathname.indexOf("/blog/") !== 0) {
      return null;
    }
    var main = document.querySelector("main");
    if (!main) return null;

    var content = document.createElement("div");
    Array.from(main.children).some(function (section) {
      if (section.tagName !== "SECTION") return false;
      var heading = cleanText((section.querySelector("h1, h2, h3") || {}).textContent || "");
      if (/^related posts$/i.test(heading)) return true;
      if (section.matches(".section-cover") || section.querySelector("h1")) return false;
      var clone = section.cloneNode(true);
      clone.querySelectorAll([
        "script", "style", "nav", "aside", "form", "iframe", "noscript", "svg", "button", "[aria-label='Share']"
      ].join(",")).forEach(function (node) { node.remove(); });
      if (cleanText(clone.textContent).length >= 40 || clone.querySelector("img, video")) content.appendChild(clone);
      return false;
    });
    return cleanText(content.textContent).length >= 500 ? content : null;
  }

  var specializedRoot = chooseGoogleDeepMindRoot();
  var root = specializedRoot || chooseRoot();
  var captureMethod = specializedRoot ? "google-deepmind-dom" : "dom-readable";
  if (!root) return JSON.stringify({ title: document.title || "", url: location.href, markdown: "", captureMethod: captureMethod });

  var clone = root.cloneNode(true);
  clone.querySelectorAll([
    "script", "style", "noscript", "template", "nav", "aside", "footer", "form", "button", "dialog",
    "svg", "canvas", "iframe", "[aria-hidden='true']", "[hidden]", ".advertisement", ".ads", ".ad",
    ".cookie", ".newsletter", ".social-share", ".share-buttons", ".related-posts", ".comments"
  ].join(",")).forEach(function (node) { node.remove(); });

  var markdown = childrenMarkdown(clone)
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, MAX_MARKDOWN_LENGTH);
  var heading = document.querySelector("article h1, main h1, h1");
  var title = cleanText(heading && heading.textContent) || cleanText(document.title);

  return JSON.stringify({
    title: title,
    url: location.href,
    markdown: markdown,
    captureMethod: captureMethod
  });
})();

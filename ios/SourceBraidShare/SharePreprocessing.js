// Safari calls `run` on this global object before presenting the Share
// Extension. It must be an object, rather than a constructor whose `run`
// method only exists on its prototype.
var ExtensionPreprocessingJS = {
  run: function(arguments) {
    var selection = window.getSelection ? window.getSelection().toString() : "";
    var article = document.querySelector("article") || document.querySelector("main") || document.body;
    var articleText = article && article.innerText ? article.innerText.slice(0, 500000) : "";

    arguments.completionFunction({
      url: document.location.href,
      title: document.title || "",
      selectedText: selection.slice(0, 500000),
      articleText: articleText,
      images: sourceBraidImages(article)
    });
  }
};

function sourceBraidImages(article) {
  if (!article || typeof article.querySelectorAll !== "function") {
    return [];
  }

  var images = [];
  var seen = {};
  var nodes = article.querySelectorAll("img");
  for (var index = 0; index < nodes.length && images.length < 12; index += 1) {
    var image = nodes[index];
    var url = sourceBraidImageURL(image);
    if (!url || seen[url] || sourceBraidShouldSkipImage(url, image)) {
      continue;
    }
    seen[url] = true;

    var figure = typeof image.closest === "function" ? image.closest("figure") : null;
    var captionNode = figure && typeof figure.querySelector === "function"
      ? figure.querySelector("figcaption")
      : null;
    images.push({
      url: url,
      alt: sourceBraidLimitedText(image.alt || image.getAttribute("alt") || image.getAttribute("title") || ""),
      caption: sourceBraidLimitedText(captionNode && captionNode.innerText ? captionNode.innerText : "")
    });
  }
  return images;
}

function sourceBraidImageURL(image) {
  var candidates = [
    image.currentSrc,
    image.src,
    image.getAttribute("src"),
    image.getAttribute("data-src"),
    image.getAttribute("data-lazy-src"),
    sourceBraidLargestSrcset(image.getAttribute("srcset") || image.getAttribute("data-srcset"))
  ];
  for (var index = 0; index < candidates.length; index += 1) {
    var candidate = candidates[index];
    if (typeof candidate === "string" && /^https?:\/\//i.test(candidate)) {
      return candidate;
    }
  }
  return "";
}

function sourceBraidLargestSrcset(value) {
  if (!value) {
    return "";
  }
  var candidates = value.split(",");
  var last = candidates[candidates.length - 1] || "";
  return last.trim().split(/\s+/)[0] || "";
}

function sourceBraidShouldSkipImage(url, image) {
  var width = Number(image.getAttribute("width") || image.naturalWidth || 0);
  var height = Number(image.getAttribute("height") || image.naturalHeight || 0);
  if (width > 0 && height > 0 && (width < 80 || height < 80)) {
    return true;
  }
  return /\/(?:avatar|logo|icon|spinner|tracking|pixel)[^/]*\.(?:gif|png|jpe?g|webp|svg)(?:[?#].*)?$/i.test(url);
}

function sourceBraidLimitedText(value) {
  return String(value || "").trim().slice(0, 2000);
}

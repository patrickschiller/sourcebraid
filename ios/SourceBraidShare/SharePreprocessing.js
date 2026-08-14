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
      articleText: articleText
    });
  }
};

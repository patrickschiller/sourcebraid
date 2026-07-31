var ExtensionPreprocessingJS = function() {};

ExtensionPreprocessingJS.prototype = {
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

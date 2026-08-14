import json
import subprocess
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY_ROOT / "ios" / "SourceBraidShare" / "SharePreprocessing.js"


class SafariSharePreprocessingTests(unittest.TestCase):
    def test_exposes_a_global_object_that_returns_page_details(self):
        program = r"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8");
const sandbox = {
  window: {
    getSelection: () => ({ toString: () => "Selected excerpt" }),
    location: { href: "https://example.com/article" }
  },
  document: {
    title: "Example article",
    location: { href: "https://example.com/article" },
    querySelector: (selector) => selector === "article"
      ? { innerText: "Readable page text" }
      : null
  }
};
vm.createContext(sandbox);
vm.runInContext(source, sandbox);
if (typeof sandbox.ExtensionPreprocessingJS?.run !== "function") {
  throw new Error("ExtensionPreprocessingJS must expose run()");
}
sandbox.ExtensionPreprocessingJS.run({
  completionFunction: (value) => process.stdout.write(JSON.stringify(value))
});
"""
        result = subprocess.run(
            ["node", "-e", program, str(SCRIPT)],
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertEqual(
            json.loads(result.stdout),
            {
                "url": "https://example.com/article",
                "title": "Example article",
                "selectedText": "Selected excerpt",
                "articleText": "Readable page text",
            },
        )


if __name__ == "__main__":
    unittest.main()

"""Offline regression tests for native GitHub Wiki navigation conversion."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from prepare_github_wiki import prepare, rewrite_markdown


class PublisherTest(unittest.TestCase):
    def setUp(self) -> None:
        self.working = tempfile.TemporaryDirectory(prefix="github-wiki-links-")
        self.addCleanup(self.working.cleanup)
        self.root = Path(self.working.name)
        self.wiki = self.root / "docs" / "wiki"
        self.wiki.mkdir(parents=True)
        (self.wiki / "Home.md").write_text("# Home\n", encoding="utf-8")
        (self.wiki / "Getting-started.md").write_text("# Getting started\n", encoding="utf-8")
        (self.wiki / "guide-index.json").write_text("{}\n", encoding="utf-8")
        (self.root / "README.md").write_text("# Readme\n", encoding="utf-8")

    def test_github_wiki_slug_not_raw_markdown(self) -> None:
        markdown = (
            "[Start](Getting-started.md) and [section](./Getting-started.md#setup)\n"
            "[Index](guide-index.json) and [README](../../README.md)\n"
            "[External](https://docs.github.com/en)\n"
        )
        actual = rewrite_markdown(markdown, self.wiki / "Home.md", self.wiki, "nyameko/demo")
        self.assertIn("[Start](https://github.com/nyameko/demo/wiki/Getting-started)", actual)
        self.assertIn(
            "[section](https://github.com/nyameko/demo/wiki/Getting-started#setup)", actual
        )
        self.assertIn(
            "[Index](https://github.com/nyameko/demo/blob/dev/docs/wiki/guide-index.json)",
            actual,
        )
        self.assertIn("[README](https://github.com/nyameko/demo/blob/dev/README.md)", actual)
        self.assertIn("[External](https://docs.github.com/en)", actual)
        self.assertNotIn("](Getting-started.md)", actual)

    def test_code_is_preserved_and_source_unmodified(self) -> None:
        source = (
            "# Home\n"
            "[Start](Getting-started.md)\n"
            "`[inline](Getting-started.md)`\n"
            "```md\n[in fence](Getting-started.md)\n```\n"
        )
        (self.wiki / "Home.md").write_text(source, encoding="utf-8")
        dest = self.root / "native"
        self.assertEqual(prepare(self.wiki, dest, "nyameko/demo"), 2)
        output = (dest / "Home.md").read_text(encoding="utf-8")
        self.assertIn("[Start](https://github.com/nyameko/demo/wiki/Getting-started)", output)
        self.assertIn("`[inline](Getting-started.md)`", output)
        self.assertIn(
            "```md\n[in fence](Getting-started.md)\n```",
            output,
        )
        self.assertEqual((self.wiki / "Home.md").read_text(encoding="utf-8"), source)

    def test_broken_and_traversal_links_fail_closed(self) -> None:
        with self.assertRaises(FileNotFoundError):
            rewrite_markdown("[bad](Missing.md)", self.wiki / "Home.md", self.wiki, "nyameko/demo")
        with self.assertRaises(ValueError):
            rewrite_markdown(
                "[bad](../../../etc/passwd)", self.wiki / "Home.md", self.wiki, "nyameko/demo"
            )


if __name__ == "__main__":
    unittest.main()

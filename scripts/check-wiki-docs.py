#!/usr/bin/env python3
"""Check reviewable wiki pages and deterministic Guide discovery index. No network."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
WIKI = ROOT / "docs" / "wiki"
REPO = "nyameko/infra-hpc-qc-k8s"
SOURCE_PREFIXES = tuple(
    f"https://github.com/{REPO}/blob/{branch}/" for branch in ("dev", "main")
)
LINK = re.compile(r"\]\(([^)\s]+)")
pages = sorted(p for p in WIKI.glob("*.md") if p.name != "_Sidebar.md")
index = {
    "schema": "qc-guide-document-index/v1",
    "repository": REPO,
    "source_root": "docs/wiki",
    "public": True,
    "description": "Discovery index only; verify source commit, deployment and permissions before use.",
    "pages": [
        {
            "slug": p.stem,
            "title": p.stem.replace("-", " "),
            "source_path": f"docs/wiki/{p.name}",
            "source_url": f"https://github.com/{REPO}/blob/dev/docs/wiki/{p.name}",
            "wiki_url": f"https://github.com/{REPO}/wiki/{p.stem}",
        }
        for p in pages
    ],
}
expected = json.dumps(index, indent=2, ensure_ascii=False) + "\n"
target = WIKI / "guide-index.json"
if "--write" in sys.argv:
    target.write_text(expected, encoding="utf-8")
elif not target.exists() or target.read_text(encoding="utf-8") != expected:
    sys.exit("guide-index.json is stale; run python scripts/check-wiki-docs.py --write")
errors = []
for md in sorted(WIKI.glob("*.md")):
    source = md.read_text(encoding="utf-8")
    if md.name != "_Sidebar.md" and not source.startswith("# "):
        errors.append(f"{md}: first line must be an H1")
    for match in LINK.finditer(source):
        link = unquote(match.group(1).split("#", 1)[0])
        if not link or link.startswith(("mailto:", "data:")):
            continue
        if link.startswith(SOURCE_PREFIXES):
            prefix = next(p for p in SOURCE_PREFIXES if link.startswith(p))
            path = ROOT / link.removeprefix(prefix)
            if not path.is_file():
                errors.append(f"{md}: missing source {link}")
        elif "://" not in link:
            path = (md.parent / link).resolve()
            if not path.is_file() or not path.is_relative_to(ROOT.resolve()):
                errors.append(f"{md}: missing local link {link}")
if errors:
    sys.exit("\n".join(errors))
print(f"Verified {len(pages)} wiki pages and Guide index for {REPO}")

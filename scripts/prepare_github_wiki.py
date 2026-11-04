#!/usr/bin/env python3
"""Prepare native GitHub Wiki pages from reviewable repository Markdown.

Repository Markdown keeps relative .md links. Native Wiki navigation uses page
slugs without .md; copying the source unmodified can link to raw Markdown.
Only change the published copy; leave the reviewed Git source untouched.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

LINK = re.compile(r'(?<!!)\[([^\]\n]+)\]\(([^)\s]+)(\s+"[^"\n]*")?\)')
TICK = re.escape(chr(96))
INLINE_CODE = re.compile(r"(" + TICK + r"+[^" + TICK + r"\n]*" + TICK + r"+)")


def rewrite_markdown(
    source: str, page: Path, source_root: Path, repository: str, branch: str = "dev"
) -> str:
    """Turn local Wiki links into rendered Wiki navigation or source links."""
    source_root = source_root.resolve()
    repository_root = source_root.parent.parent
    pages = {p.name for p in source_root.glob("*.md")}

    def convert(match: re.Match[str]) -> str:
        target = match.group(2)
        if urlsplit(target).scheme or target.startswith(("//", "#", "/")):
            return match.group(0)
        file_part, marker, fragment = target.partition("#")
        if not file_part:
            return match.group(0)
        candidate = (page.parent / unquote(file_part)).resolve()
        if not candidate.is_relative_to(repository_root):
            raise ValueError(f"Link outside repository: {page}: {target}")
        if not candidate.is_file():
            raise FileNotFoundError(f"Broken link in {page}: {target}")
        if candidate.parent == source_root and candidate.name in pages:
            url = f"https://github.com/{repository}/wiki/{quote(candidate.stem, safe='-_.~')}"
        else:
            relative = candidate.relative_to(repository_root).as_posix()
            url = f"https://github.com/{repository}/blob/{branch}/{quote(relative, safe='/._-')}"
        if marker:
            url += "#" + fragment
        return f"[{match.group(1)}]({url}{match.group(3) or ''})"

    output = []
    fenced = False
    for line in source.splitlines(keepends=True):
        if line.lstrip().startswith((chr(96) * 3, "~~~")):
            fenced = not fenced
            output.append(line)
        elif fenced:
            output.append(line)
        else:
            parts = INLINE_CODE.split(line)
            output.append(
                "".join(
                    LINK.sub(convert, part) if index % 2 == 0 else part
                    for index, part in enumerate(parts)
                )
            )
    return "".join(output)


def prepare(source: Path, destination: Path, repository: str, branch: str = "dev") -> int:
    source = source.resolve()
    if not (source / "Home.md").is_file():
        raise FileNotFoundError(f"Missing Wiki Home.md under {source}")
    destination.mkdir(parents=True, exist_ok=True)
    count = 0
    for page in sorted(source.glob("*.md")):
        raw = page.read_text(encoding="utf-8")
        rendered = rewrite_markdown(raw, page, source, repository, branch)
        (destination / page.name).write_text(rendered, encoding="utf-8")
        count += 1
    print(f"Prepared {count} GitHub Wiki pages with rendered links for {repository}")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", default="dev")
    options = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", options.repo):
        parser.error("--repo must be owner/repository")
    prepare(options.source, options.destination, options.repo, options.branch)


if __name__ == "__main__":
    main()

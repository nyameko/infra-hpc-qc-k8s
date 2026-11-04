#!/usr/bin/env bash
set -euo pipefail
mode="${1:-publish}"
if [[ "$mode" != "publish" && "$mode" != "--dry-run" ]]; then
  echo "Usage: bash scripts/publish-github-wiki.sh [--dry-run]" >&2; exit 2
fi
root="$(git rev-parse --show-toplevel)"
cd "$root"
if [[ ! -f docs/wiki/Home.md ]]; then echo "Missing docs/wiki/Home.md" >&2; exit 1; fi
remote="https://github.com/nyameko/infra-hpc-qc-k8s.wiki.git"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
echo "Cloning wiki (authentication is handled by your configured Git credential helper)"
git clone --quiet "$remote" "$temp/wiki"
find docs/wiki -maxdepth 1 -type f -name '*.md' -print0 | while IFS= read -r -d '' file; do cp "$file" "$temp/wiki/$(basename "$file")"; done
git -C "$temp/wiki" add -- '*.md'
git -C "$temp/wiki" status --short
if git -C "$temp/wiki" diff --cached --quiet; then echo "No changes"; exit 0; fi
git -C "$temp/wiki" diff --cached --stat
if [[ "$mode" == "--dry-run" ]]; then echo "Dry run: nothing committed or pushed"; exit 0; fi
git -C "$temp/wiki" commit -m "docs(wiki): synchronize reviewed repository wiki source"
git -C "$temp/wiki" push origin HEAD
echo "Published: https://github.com/nyameko/infra-hpc-qc-k8s/wiki"

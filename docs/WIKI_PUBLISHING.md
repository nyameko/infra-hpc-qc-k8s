# Wiki publication and editorial policy

The authoritative reviewable source for this GitHub Wiki is `docs/wiki/*.md` in this repository. The native GitHub Wiki is a **different Git repository** (`https://github.com/nyameko/infra-hpc-qc-k8s.wiki.git`); the repository contents API does not publish there automatically. Do not describe a documentation PR as a published wiki.

## Publish after review

1. Merge the documentation PR according to normal branch and review rules.
2. Create an initial page from the GitHub Wiki tab if the wiki Git remote has not been initialized.
3. In a clean, authenticated operator environment run `bash scripts/publish-github-wiki.sh --dry-run` and review the file names and diff. Do not embed a personal token in the URL or shell history.
4. Run `bash scripts/publish-github-wiki.sh` after review, then visit [the native wiki](https://github.com/nyameko/infra-hpc-qc-k8s/wiki) and verify Home, sidebar, links and code blocks render.
5. Link the published Git commit and article paths to the documentation PR or release evidence.

This script copies managed Markdown pages without deleting independently maintained wiki pages. Review stale pages manually. Publish is a deliberate human action, not an automatic release side effect.

## ArchWiki-inspired editorial conventions

Use descriptive nouns in titles; begin with scope and prerequisites; explain actual commands with exact run context and required permissions; prefer small task-oriented sections and stable internal links. Distinguish **Note**, **Warning**, **Tip** and **Status** in plain Markdown; distinguish implemented, tested live, experimental, proposed and deprecated claims. Cite the owning source file, test or release evidence. Prefer commands that are copyable, safe by default, and explain side effects. Never present sensitive inventory as public reference topology.

## Assistant/agent retrieval rules

Index page title, repository, audience, updated source revision, feature status and relative links. A matching public documentation snippet is not authorization to execute it. Cite its source and version; ask for minimal non-sensitive diagnostics; do not invent endpoints or assume a live feature based only on a design doc. Escalate contradictory claims to maintainers and open an issue with links and an observable reproduction.

## Automatic publishing from `dev`

The `.github/workflows/publish-github-wiki.yml` workflow publishes reviewed `docs/wiki/*.md` pages on changes merged into `dev` (and supports a manual dispatch from `dev` when available). It first validates the Guide index and local links, sets up a secure short-lived `GITHUB_TOKEN` Git credential helper, runs the existing publisher in dry-run mode, then publishes. No ChatGPT, OpenAI, Anthropic, QPU or inference API key is required.

**Before the first run**, enable repository Wiki in Settings → General → Features and create/save one `Home` page from the Wiki tab. The underlying `.wiki.git` remote does not exist until that initial save. Repository Actions must permit `contents: write` for the job. Do not add a PAT unless the repository/organization policy requires an alternative and it has been security-reviewed.

After each reviewed `dev` wiki edit is merged, inspect Actions → Publish GitHub Wiki and then check the actual Wiki Home/sidebar. It publishes from **`dev`**, so articles must distinguish source/development behavior from live deployment. To republish manually, authenticate Git via `gh auth login` and `gh auth setup-git`, check out `dev`, and run `bash scripts/publish-github-wiki.sh --dry-run` followed by `bash scripts/publish-github-wiki.sh`. A manual `workflow_dispatch` may not appear in the Actions UI until the workflow also exists on the default branch; automatic `push: dev` is sufficient.

This job does not erase unrelated Wiki pages. Reviewers should verify source SHA/version links, redact private material and use Wiki Git history for recovery. Publication does not enable a live RAG backend or grant permission to run documented commands.

## Rendered Wiki links (publisher fix)

In the Git repository, relative Markdown links such as `[Getting started](Getting-started.md)` navigate between `docs/wiki/` files. In the **native GitHub Wiki**, that same `.md` link can open raw source instead of an HTML-rendered page. The canonical page URL omits the extension: `https://github.com/nyameko/infra-hpc-qc-k8s/wiki/Getting-started` (when such a page exists).

The publish script now invokes `scripts/prepare_github_wiki.py` to rewrite local Wiki page links **only in the copied publication**, preserving readable source Markdown. The transform converts recognized local Wiki pages into full rendered Wiki URLs and non-Wiki local files, including `guide-index.json`, into `blob/dev` source links. External links, Markdown code examples and original checked-in files remain unchanged. Missing local links abort publication. PR validation runs offline regression tests and generates a full preview without publishing; the real Wiki push occurs only after the reviewed change is merged into `dev`.

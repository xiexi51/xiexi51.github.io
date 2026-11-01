# Maintain this homepage from a personal computer

Use PowerShell 7, Git, and GitHub CLI. `master` contains the editable source;
`gh-pages` contains the generated public website. Keep your working copy on
`master`. The publication script uses a separate worktree and never force-pushes.

## One-time setup on Windows x64

```powershell
git clone https://github.com/xiexi51/xiexi51.github.io.git
cd xiexi51.github.io
pwsh -File bin/setup-windows.ps1
```

The setup script installs isolated tools in the sibling `.homepage-tools`
directory. It does not change the global PATH or Ruby file associations. The
three runtime downloads have SHA-256 checks. It uses Ruby 3.3.5, Bundler 2.5.7,
Node 22.9.0, Python 3.10.11, Jekyll 4.3.4, and PurgeCSS 6.0.0. Ruby and Node
packages are locked; Python constraints record the tested dependency versions.
ExecJS uses Node, so the unsupported Windows `mini_racer` dependency is unnecessary.
The CSS stage uses the PurgeCSS API to avoid the v6 CLI's duplicated output paths
on Windows.

Keep `.homepage-tools` alongside the checkout, or pass `-ToolsRoot` to each script.
GitHub authentication is separate: use your own existing GitHub CLI login. No
A6000 credentials, GPU, Conda installation, or server files are needed.

## Edit, build, and publish from this computer

1. Pull `master` normally before editing. Add/edit a Markdown file in `_news`.
2. Commit your source. For a local publication, add `[skip ci]` to the commit
   message so the automatic source deployment cannot race this local build.
3. Build the clean source commit, inspect `_site`, then push the source and publish:

```powershell
git add _news
git commit -m "Update homepage news [skip ci]"
pwsh -File bin/build-windows.ps1
git push origin master
pwsh -File bin/publish-windows.ps1
```

The build script records the source commit and SHA-256 of every generated file
in the ignored `.jekyll-cache/local-build.json`. Publication rejects dirty source,
a stale/modified build, or a source commit that is not the current GitHub `master`.
It adds a normal commit to the latest `gh-pages` and retains its history. If
someone publishes concurrently, a rejected push is safe: fetch and retry rather
than force-pushing. Publication worktrees remain under `.homepage-tools` for review.

For a preview of uncommitted edits, run `bin/build-windows.ps1 -AllowUncommitted`.
That preview cannot be published. To inspect locally, serve `_site` over HTTP
using your preferred static server; opening HTML as `file://` will break root URLs.

Alternatively omit `[skip ci]` and let the configured `Deploy site` Action build
and publish. Do not run the local publication at the same time. The Action now
uses the recorded runtime versions and does not force-push. Its Linux execution
uses Ubuntu 24.04 because Ruby 3.3.5 is unavailable on the newer Ubuntu 26.04
runner image. Template Docker/Lighthouse/link
workflows may also run and have their own optional credentials/checks.
For a build-only Action check, manually run `Deploy site` with `publish` unchecked.

Do not use the legacy Docker startup as a lock-preserving build: its entrypoint
deletes `Gemfile.lock`. The old `bin/deploy` also uses a force push; prefer the new
publication script or the updated Action.

## Recovery checkpoints

The 2026-11-01 reconciliation retained both histories with the A6000 content:

- `backup/a6000-master-20261101`: `f5b79ff91f8f7eeef09d1e4c7eaab82f25ff9bda`
- `backup/github-master-20261101`: `2d529ab3d7c09c4b2785e4e2c5a5ff606216a658`
- `backup/gh-pages-20261101`: `0c02a16e63d37c0c52c5ab5a2d0e1d731eb1d2f7`
- Merge: `7f8972909deac354eba30cb929b6e59350da18cf`, with a tree identical to
  the A6000 snapshot. The current ICLR RTop-K entry and PDF link were retained.

The clearly marked deployment test is `_news/test_personal_computer_20261101.md`.
Remove that source file and repeat the normal build/publication to remove the test.
The A6000 working copy was not switched or changed during this migration; sync it
before using it again, to avoid publishing stale content.

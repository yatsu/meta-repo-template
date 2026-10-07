# CLAUDE.md

This repository is a template for meta-repo workspaces: a parent repository that clones several independent
repositories under `repos/` and provides `just` recipes and agent instructions for working across them.
This file guides development of the template itself and is never copied into user workspaces.

## Files

Everything under `template/` ships to users; `install.sh` copies it into a workspace.
Files at the repository root are for developing the template and are not installed.

- `install.sh`: copies `template/` into a target directory without overwriting existing files, and appends
  missing entries from `template/.gitignore` to the target's `.gitignore`.
- `template/justfile`: thin wrappers only. Each recipe calls `scripts/<name>.sh "$@"` (`set positional-arguments`).
  The comment above a recipe is its `just --list` description.
- `template/scripts/_lib.sh`: shared helpers (manifest parsing, name validation, worktree sets, base records, colors).
  Every script sources it. A worktree branch's base is stored in git config as `branch.<branch>.meta-base`.
  `wt-new` symlinks `worktrees/<branch>/.claude/settings.json` to the root `.claude/settings.json` (Claude Code reads
  that file only from its start directory); `wt-rm` removes it and does not report it as a leftover file.
  The justfile exports `META_INVOCATION_DIR` (`invocation_directory()`); `pick_branch` uses it so that the `wt-*`
  scripts take the branch from the current worktree set and treat all arguments as repo names there.
  `wt-new` and `wt-rm` always require an explicit branch.
  `wt-merge` moves only the local base branch ref (`update-ref` with the expected old value, fast-forward only) and
  never pushes; `wt-push-base` pushes it without forcing. Neither is auto-allowed in `.claude/settings.json`.
- `template/scripts/*.sh`: one script per recipe, except that `wt-diff`, `wt-diff-head`, and `wt-diff-pr` share
  `wt-diff.sh` (mode as the first argument) and `wt-status` is `status.sh -w`.
- `template/repos.txt`: the manifest, `<name> <git-url> [branch]` per line, `#` comments. Ships with examples only.
  A `-` URL marks a local-only repo that `bootstrap` never clones. Decide whether to fetch by the repo's actual
  `origin` remote (`has_origin`), not by the manifest URL, since a local-only repo may still have one.
- `template/AGENTS-meta-repo.md`: instructions users adopt as their workspace's CLAUDE.md or AGENTS.md.
- `template/.claude/settings.json`: allows read-only recipes without prompts in user workspaces.
- `template/.gitignore`: entries merged into the workspace's `.gitignore`, never copied as a file.
- `README.md`: user documentation.
- `mise.toml`, `.editorconfig`, `.shellcheckrc`, `.markdownlint.yaml`: development tooling. Users are not required to use mise.

## Conventions

- Everything shipped is written in English: code, comments, messages, and docs.
- Runtime dependencies are limited to `git`, `bash`, and `just` (`install.sh`: `git` and `bash` only).
  Do not add `yq`, `jq`, Python, mise, or similar.
- Scripts must run on bash 3.2 (macOS default): no `mapfile`, associative arrays, `${var,,}`, or `&>>`.
  Expand possibly empty arrays as `${arr[@]+"${arr[@]}"}`.
- Format shell scripts with `shfmt`, which reads its settings (4-space indent) from `.editorconfig`.
- Start scripts with `set -euo pipefail` and `source "$(dirname "$0")/_lib.sh"`.
- Loop over the manifest with `while read -r ... <&3; do ... done 3< <(read_manifest)` so commands inside
  the loop (git, user commands) cannot consume the manifest from stdin.
- Validate repo-name arguments with `validate_names "$@"` and filter with `selected "$name" "$@"`.
- Per-repository failures warn and continue; the script exits non-zero at the end.
- Never discard user work by default: skip dirty repositories, fast-forward only, require `--force` to remove.
- `status` must stay offline.

## When changing recipes

Keep these in sync whenever a recipe is added, removed, or changes behavior:

- `template/justfile` (recipe and its description comment)
- the "Commands" section in `README.md`
- the "Commands" section in `template/AGENTS-meta-repo.md`, which is how agents in user workspaces learn the recipes
- `template/.claude/settings.json`, if the recipe is read-only and safe to auto-allow

New files under `template/` are picked up by `install.sh` automatically. If one should not be copied as-is
(like `.gitignore`), handle it explicitly in `install.sh`.

## Verification

Format and lint:

```bash
shfmt -w install.sh template/scripts/*.sh
```

```bash
shellcheck -x install.sh template/scripts/*.sh
```

Smoke-test in a scratch directory, never in this repository: run `install.sh` into a new directory and into an
existing one with its own `.gitignore` and a conflicting file, then create local bare
repositories as remotes (`git init --bare -b main`), list them in `repos.txt` with `file://` URLs, and exercise
every recipe, including the failure paths (unknown repo name, dirty repository, existing worktree, nested worktree sets, missing base, `--force`).

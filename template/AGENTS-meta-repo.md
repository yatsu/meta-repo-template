# Meta-repo workspace

This directory is a meta-repo for working across multiple repositories.
It holds no application code; each repository is cloned into `repos/<name>/`.

<!-- Fill in "Repositories" and "Cross-repo changes" for your workspace.
     Leave repo-internal details (build steps, etc.) to each repository's own CLAUDE.md or AGENTS.md. -->

## Repositories

The list lives in `repos.txt`. Each repository's own CLAUDE.md or AGENTS.md applies when working inside it.

| repo     | role                | depends on                        |
| -------- | ------------------- | --------------------------------- |
| `<name>` | <what it provides>  | <repos or services it depends on> |

## Cross-repo changes

<!-- Example: change the provider side (infrastructure, library, API) first, then update the consumers.
     List what must stay in sync across repos (versions, config keys, API schemas) and where each lives. -->

## Rules

- Run git commands against an explicit repository: `git -C repos/<name> ...`.
  A bare `git` at the root operates on this meta-repo itself.
- Keep commits and PRs per repository. For changes spanning repositories, link the related PRs in each PR description.
- Build, test, and lint each repository from its own root, following its own instructions.
- `repos/` and `worktrees/` are not tracked by the meta-repo. Only root-level files, `scripts/`, and agent config directories belong in meta-repo commits.
- Run `just status` before and after a task to check each repository's branch and uncommitted changes.

## Commands

Workspace operations are `just` recipes, run from the meta-repo root. `just --list` shows them all.
Recipes that take `[repo...]` target every repository in `repos.txt` when no names are given,
and fail if a name is not listed there. A failure in one repository does not stop the others;
the recipe exits non-zero at the end if any repository failed.

- `just status [repo...]`: Show each repository's branch, number of uncommitted changes, and ahead/behind counts against its upstream.
  Read-only and offline, so counts reflect the last fetch. Use it freely to orient yourself.
- `just sync [repo...]`: Fetch every repository, then fast-forward pull those with no uncommitted changes.
  Repositories with local changes or no upstream are only fetched. Never merges or rebases.
- `just bootstrap [repo...]`: Clone repositories listed in `repos.txt` that are missing from `repos/`. Existing clones are skipped.
- `just add <name> <url> [branch]`: Append a repository to `repos.txt` and clone it. Ask the user before adding repositories.
- `just exec '<cmd>' [repo...]`: Run a shell command at the root of each repository, for example `just exec 'git log -1 --oneline'`.
  Prefer it over hand-written loops for read-only checks across repositories.
- `just wt-new <branch> [repo[@base]...]`: Create a worktree on `<branch>` for each repository under `worktrees/<branch>/<repo>/`
  (`feature/foo` becomes `worktrees/feature/foo/<repo>/`). Uses the branch if it exists; otherwise forks it from the base:
  `repo@<base>` if given, else the branch set in `repos.txt`, else the remote's default branch. Bases can differ per
  repository, e.g. `just wt-new feature/foo repo-a repo-b@v2`. The base is recorded in git config as
  `branch.<branch>.meta-base`; for an existing branch or worktree, `repo@<base>` only updates the record.
  No upstream is set; push with `git push -u origin <branch>`.
  Running it again for the same branch adds worktrees for the repositories that do not have one yet.
  Fails if the set would be nested inside another set or contain one (e.g. `feature` while `feature/foo` exists).
- `just wt-status <branch> [repo...]`: Same as `just status`, for the worktrees of `<branch>`, plus a BASE column with each
  repository's recorded base and ahead/behind counts against it (`(unknown)` when no base is recorded).
- `just wt-list`: List existing worktree sets by branch name, with the repositories in each.
- `just wt-rm <branch> [--force]`: Remove the worktrees of `<branch>` and any parent directories left empty. Branches are kept.
  Worktrees with uncommitted changes are skipped unless `--force` is given; only use `--force` when the user asks.
  Other files in `worktrees/<branch>/` are never deleted and are reported as kept.

## Parallel work with worktrees

- When the session's working directory is under `worktrees/<branch>/`, edit files only there.
  Leave `repos/` alone; other work may be using it.
- Repositories in one set may have different bases. Before rebasing, comparing, or opening a pull request, check the
  BASE column of `just wt-status <branch>` and target that branch (e.g. `gh pr create --base v2`), not `main` by default.
  If a base shows `(unknown)`, ask the user which branch to target.
- Check status with `just wt-status <branch>` and clean up with `just wt-rm <branch>` once the branches are pushed or merged.

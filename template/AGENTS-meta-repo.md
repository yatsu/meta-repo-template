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

Workspace operations are `just` recipes. `just --list` shows them all. Run them from the meta-repo root or from
`worktrees/<branch>/`, never from inside a repository: `just` uses the nearest justfile, so a repository with its own
justfile hides these recipes (if you must, use `just --justfile <meta-repo root>/justfile <recipe>`).
Recipes that take `[repo...]` target every repository in `repos.txt` when no names are given,
and fail if a name is not listed there. A failure in one repository does not stop the others;
the recipe exits non-zero at the end if any repository failed.

- `just status [repo...]`: Show each repository's branch, number of uncommitted changes, and ahead/behind counts against its upstream.
  Read-only and offline, so counts reflect the last fetch. Use it freely to orient yourself.
- `just sync [repo...]`: Fetch every repository, then fast-forward pull those with no uncommitted changes.
  Repositories with local changes or no upstream are only fetched; repositories without an `origin` remote are skipped.
  Never merges or rebases.
- `just bootstrap [repo...]`: Clone repositories listed in `repos.txt` that are missing from `repos/`. Existing clones are skipped.
  Repositories with `-` as the URL are local-only: they are never cloned, and a missing one must be placed by the user.
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
- `just wt-status [branch] [repo...]`: Same as `just status`, for the worktrees of `<branch>`, plus a BASE column with each
  repository's recorded base and ahead/behind counts against it (`(unknown)` when no base is recorded).
- `just wt-log [branch] [repo...]`: List the commits each worktree has on top of its recorded base.
- `just wt-diff [branch] [repo...] [--stat]`: Diff from each worktree's base (merge base) to its working tree,
  uncommitted changes included. Use it to review everything a task changed.
- `just wt-diff-head [branch] [repo...] [--stat]`: Uncommitted changes in each worktree, staged or not (`git diff HEAD`).
- `just wt-diff-pr [branch] [repo...] [--stat]`: The diff a pull request against each worktree's base would show
  (committed changes only). Check it before opening pull requests.
  None of the diffs include untracked files; check `git status` for those.
- `just wt-exec [branch] '<cmd>' [repo...]`: Run a shell command in each worktree, with `BASE` and `BASE_REF` set to the
  recorded base and the ref to compare against (empty if unknown), and no pager.
  Prefer it over hand-written loops, and never hard-code `main` as the base.
- `just wt-merge [branch] [repo...]`: Merge each worktree's branch into its recorded base branch locally, fast-forward
  only. Only the local base branch moves; nothing is checked out and nothing is pushed. Refuses per repository when the
  worktree has uncommitted changes, the base is not a branch, the branch does not contain the base (rebase first, as the
  message says), the local base and `origin/<base>` have diverged, or the base is checked out somewhere.
- `just wt-push-base [branch] [repo...]`: Push each worktree's local base branch to origin, listing the commits first.
  Never forces; refuses when origin has commits the local base lacks. Run it only when the user asks to push.
- `just wt-list`: List existing worktree sets by branch name, with the repositories in each.
- `just wt-rm <branch> [--force]`: Remove the worktrees of `<branch>` and any parent directories left empty.
  Deletes a branch only if it has no commits on top of its recorded base and was never pushed; other branches are kept.
  Worktrees with uncommitted changes are skipped unless `--force` is given; only use `--force` when the user asks.
  Other files in `worktrees/<branch>/` are never deleted and are reported as kept.

## Parallel work with worktrees

- When the session's working directory is under `worktrees/<branch>/`, edit files only there.
  Leave `repos/` alone; other work may be using it.
- `[branch]` in the `wt-*` recipes above is taken from the current directory when it is inside `worktrees/<branch>/`.
  Omit it there (`just wt-diff-pr --stat`, `just wt-log repo-a`); any arguments are then repository names.
  Outside `worktrees/`, `[branch]` is required.
- Repositories in one set may have different bases. Before rebasing, comparing, or opening a pull request, check the
  BASE column of `just wt-status` and target that branch (e.g. `gh pr create --base v2`), not `main` by default.
  If a base shows `(unknown)`, ask the user which branch to target.
- Check status with `just wt-status` and clean up with `just wt-rm <branch>` (from the meta-repo root) once the branches
  are pushed or merged.

## Finishing a task

A worktree set ends in one of two ways. Which one is the user's decision: follow their instruction, and ask when it is
not clear. Do not open pull requests, merge, or push without being asked.

### Pull requests (the base is a long-lived branch)

Typical when the bases are branches like `main` or `v2`. For each repository with commits (`just wt-log`):

1. Review with `just wt-diff-pr` and check `git status` for untracked files.
2. Push the worktree branch: `git push -u origin <branch>`.
3. Open a pull request against the recorded base from `just wt-status`, e.g. `gh pr create --base v2`, and link the
   related pull requests of the other repositories in each description.

### Merging into a pull-request branch (the base is itself a feature branch)

Some tasks are slices of a larger change. The user creates the set from a feature branch that already has, or will
have, its own pull request, e.g. `just wt-new feature/big-part1 repo-a@feature/big`. The work is finished by merging
the worktree branch into that feature branch locally, not by opening a pull request for the worktree branch:

1. Review with `just wt-diff-pr` (here it shows exactly what will land on the base) and commit everything.
2. Run `just wt-merge`. It fast-forwards the local `feature/big` to the worktree branch and does not push.
3. If it reports that the base has commits the branch lacks, rebase the worktree branch onto the ref it names
   (`git rebase origin/feature/big` or `git rebase feature/big`) and run `just wt-merge` again. The worktree branch has
   not been pushed, so rebasing it is safe; if it has been pushed, ask first.
4. If it reports that the local base and `origin/<base>` have diverged, stop and show the user the commits from the
   suggested `git log` command. Do not reset or rewrite the local base yourself.
5. Push only when the user asks: `just wt-push-base`. Until then, `just wt-status` keeps showing the commits as ahead of
   `origin/<base>`, and `just wt-rm` keeps the worktree branch.
6. After the push, `just wt-rm <branch>` deletes the worktree branch, because its commits are now in the base.

Several sets can be merged into the same feature branch one after another; a later one is rebased onto the local base
(`git rebase feature/big`) when `just wt-merge` asks for it. Never check out the base branch under `repos/` to merge.

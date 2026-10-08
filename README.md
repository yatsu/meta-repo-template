# meta-repo template

A workspace template for making changes across multiple repositories with coding agents such as Claude Code.

The meta-repo itself contains no application code, only:

- the list of managed repositories (`repos.txt`)
- scripts to operate on them (`justfile`, `scripts/`)
- cross-repo instructions for agents (`AGENTS-meta-repo.md`, `.claude/`)

Managed repositories are plain `git clone`s under `repos/`, excluded from the meta-repo's git via `.gitignore`.

This repository is not used as the workspace itself. Clone it anywhere and run `install.sh`, which copies the files under `template/` into your workspace. A workspace ends up looking like this:

```text
.
├── AGENTS-meta-repo.md   # agent instructions to adopt as CLAUDE.md or AGENTS.md
├── repos.txt             # list of managed repositories
├── justfile              # commands
├── scripts/              # implementations called from the justfile
├── .claude/              # Claude Code project settings
├── .gitignore            # ignores repos/ and worktrees/
├── repos/<name>/         # cloned repositories (untracked)
└── worktrees/<branch>/<name>/   # worktrees for parallel work (untracked)
```

## Requirements

- `git`
- `bash` (works with bash 3.2, the macOS default)
- [`just`](https://just.systems/man/en/packages.html)

## Getting started

Clone this template to a temporary location:

```bash
git clone <this-template-url> /tmp/meta-repo-template
```

Install it into your workspace. The directory is created if it does not exist, and it can also be an existing repository:

```bash
/tmp/meta-repo-template/install.sh ~/src/my-workspace
```

`install.sh` never overwrites files. Files that already exist in the workspace are skipped and reported, and
entries missing from `.gitignore` are appended to it.

Then, in the workspace:

1. Adopt the agent instructions as described in [Agent instructions](#agent-instructions).
2. List the repositories you want in `repos.txt` (or add them with `just add <name> <url>`).
3. Run `just bootstrap` to clone them into `repos/`.
4. Fill in "Repositories" and "Cross-repo changes" in the adopted instructions.
5. Start `claude` (or another agent) at the root.

## Agent instructions

`AGENTS-meta-repo.md` holds the instructions agents need in the workspace. They tell agents:

- how the workspace is laid out and how to run git against the right repository
- what each `just` recipe does and when to use it, so agents use the recipes instead of ad-hoc loops
- how to work inside a worktree set

Put them where your agent reads project instructions. Pick one:

- **Claude Code only**: if the workspace has no `CLAUDE.md` yet, make it the `CLAUDE.md`.

    ```bash
    mv AGENTS-meta-repo.md CLAUDE.md
    ```

- **Claude Code and other agents** (Codex, Cursor, etc.): if the workspace has neither `CLAUDE.md` nor `AGENTS.md`,
  make it `AGENTS.md` and have `CLAUDE.md` import it. Claude Code does not read `AGENTS.md` by default when a
  `CLAUDE.md` exists, so the import keeps both working.

    ```bash
    mv AGENTS-meta-repo.md AGENTS.md && printf '@AGENTS.md\n' > CLAUDE.md
    ```

- **Existing instructions**: if the workspace already has a `CLAUDE.md` or `AGENTS.md`, append the contents of
  `AGENTS-meta-repo.md` to it and delete `AGENTS-meta-repo.md`.

When you add or change recipes, update the "Commands" section of the adopted file as well.

## Commands

- `just bootstrap [repo...]`: Clone repositories that are not cloned yet. Local-only repositories are reported if missing.
- `just sync [repo...]`: Fetch, then fast-forward pull repositories without uncommitted changes.
- `just status [repo...]`: Show branch, uncommitted changes, and ahead/behind counts (no network access).
- `just exec '<cmd>' [repo...]`: Run a command at the root of each repository.
- `just add <name> <url> [branch]`: Append a repository to `repos.txt` and clone it.
- `just wt-new <branch> [repo[@base]...]`: Create same-branch worktrees grouped under `worktrees/<branch>/`, optionally forking each repository from a different base.
- `just wt-status [branch] [repo...]`: Show the status of a worktree set, including each repository's base and ahead/behind counts against it.
- `just wt-log [branch] [repo...]`: List the commits each worktree has on top of its base.
- `just wt-diff [branch] [repo...] [--stat]`: Show changes since the base, uncommitted changes included.
- `just wt-diff-head [branch] [repo...] [--stat]`: Show uncommitted changes, staged or not (like `git diff HEAD`).
- `just wt-diff-pr [branch] [repo...] [--stat]`: Show the diff a pull request against the base would show (committed changes only).
- `just wt-exec [branch] '<cmd>' [repo...]`: Run a command in each worktree, with `BASE` and `BASE_REF` set.
- `just wt-merge [branch] [repo...]`: Fast-forward each worktree's local base branch to the worktree branch, without pushing.
- `just wt-push-base [branch] [repo...]`: Push each worktree's local base branch to origin (never forced).
- `just wt-list`: List worktree sets and the repositories in each.
- `just wt-rm <branch> [--force]`: Remove a worktree set, and delete branches that were never committed to or pushed.

When `[repo...]` is omitted, every repository in `repos.txt` is targeted.

## Parallel work with worktrees

```bash
just wt-new feature/foo repo-a repo-b
```

With `repo-a`, `repo-b`, and `repo-c` in `repos.txt`, the workspace then looks like this (`justfile`, `scripts/`, and other files omitted):

```text
.
├── AGENTS.md
├── CLAUDE.md
├── repos.txt
├── repos/
│   ├── repo-a/              # main checkout, still on its original branch
│   ├── repo-b/
│   └── repo-c/
└── worktrees/
    └── feature/
        └── foo/             # worktree set for branch feature/foo
            ├── repo-a/      # worktree of repos/repo-a on branch feature/foo
            └── repo-b/      # worktree of repos/repo-b on branch feature/foo
```

Only the repositories named on the command line get a worktree; `repo-c` is left out here.
Each worktree shares its git objects with the clone under `repos/`, so creating one is fast and takes little disk space.
The branch name is used as the path as is, so `feature/foo` becomes the nested directories `feature/foo/`.
Another branch gets its own directory, for example `worktrees/fix/bar/` from `just wt-new fix/bar repo-c`.
One worktree set cannot sit inside another, so `just wt-new feature` fails while `feature/foo` exists, and vice versa.
`just wt-rm` also removes parent directories that become empty, such as `worktrees/feature/`.
Branches live in the repositories under `repos/`, not in the worktrees, so they survive the removal.
`just wt-rm` deletes a branch only when it is unused: no commits on top of its recorded base and never pushed
(no upstream and no `origin/<branch>`), as with a repository you only read. Branches with commits, pushed branches,
and branches without a recorded base are kept, and each decision is printed.
Other files in the branch directory, such as plans or notes, are never deleted; `just wt-rm` lists them as kept.

Start the agent for that task inside the branch directory:

```bash
cd worktrees/feature/foo && claude
```

Because `worktrees/<branch>/` sits inside the meta-repo, an agent started there still loads the workspace's root instructions
(`CLAUDE.md`, `AGENTS.md`) and Claude Code skills in `.claude/skills/`. Claude Code reads the shared `.claude/settings.json`
only from the directory it starts in, so `just wt-new` links `worktrees/<branch>/.claude/settings.json` to the workspace's
file, and `just wt-rm` removes the link again. A `settings.json` you put there yourself is never replaced or removed.
No upstream is configured, so push the first time with `git push -u origin <branch>`.

### Base branches

A new branch is forked from its base, chosen per repository in this order:

1. the base given on the command line as `repo@<base>`
2. the branch given for the repository in `repos.txt`
3. the remote's default branch

Repositories can use different bases in the same set. Here `repo-a` is forked from `main` (its default) and
`repo-b` from `v2`:

```bash
just wt-new feature/foo repo-a repo-b@v2
```

`<base>` is looked up as `origin/<base>` first, then as a local branch, tag, or commit.
The base is recorded in each repository's git config as `branch.<branch>.meta-base`, and `just wt-status` shows it:

```text
REPO    BRANCH       CHANGES  BASE        UPSTREAM
repo-a  feature/foo  clean    main +2 -0  (none)
repo-b  feature/foo  clean    v2 +1 -0    (none)
```

Open each pull request against the recorded base (for example `gh pr create --base v2` in `repo-b`).
For a branch that already exists or already has a worktree, `repo@<base>` only updates the record.
The record is removed together with the branch when the branch is deleted.

### Working inside a worktree set

Inside `worktrees/<branch>/` (or any directory below it), the `wt-status`, `wt-log`, `wt-diff`, `wt-diff-head`,
`wt-diff-pr`, and `wt-exec` recipes take the branch from the current directory, so it can be omitted. Any arguments
are then repository names:

```bash
cd worktrees/feature/foo
```

```bash
just wt-diff-pr repo-a --stat
```

Outside `worktrees/`, pass the branch as the first argument. `wt-new` and `wt-rm` always take it explicitly.

Run the recipes from the workspace root or from `worktrees/<branch>/`, not from inside a repository: `just` uses the
nearest justfile, so a repository that has its own justfile hides these recipes. From there, pass the workspace's
justfile explicitly, for example `just --justfile ../../../justfile wt-log` from `worktrees/fix/repo-a/`.

### Reviewing changes

These recipes look at every worktree of a set, each against its own base:

| Recipe | Compares | Same as, per worktree |
| ------ | -------- | --------------------- |
| `just wt-log <branch>` | commits on top of the base | `git log --oneline <base>..HEAD` |
| `just wt-diff <branch>` | the base to the working tree | `git diff $(git merge-base <base> HEAD)` |
| `just wt-diff-head <branch>` | `HEAD` to the working tree | `git diff HEAD` |
| `just wt-diff-pr <branch>` | the base to `HEAD` | `git diff <base>...HEAD` |

`<base>` is the recorded base, preferring `origin/<base>`. `wt-diff` and `wt-diff-pr` start from the merge base, so
commits added to the base after the branch was forked do not show up. Add `--stat` for a per-file summary, and
repository names to limit the output. As with `git diff`, untracked files do not appear until they are added.

For anything else, `just wt-exec` runs a command in each worktree with `BASE` (for example `v2`) and `BASE_REF`
(for example `origin/v2`) set, and without a pager:

```bash
just wt-exec feature/foo 'git status --short'
```

```bash
just wt-exec feature/foo 'git log --stat "$BASE_REF..HEAD"'
```

### Walkthrough: one pull request per repository

The usual case. A task touches `api` (based on `main`) and `web` (based on its `v2` line), and each repository gets
its own pull request.

Create the worktree set, choosing the base per repository:

```bash
just wt-new feature/login api web@v2
```

Start an agent for the task inside it. The `wt-*` recipes run there need no branch argument:

```bash
cd worktrees/feature/login && claude
```

While working, or when done, review each repository against its own base:

```bash
just wt-status
```

```text
REPO  BRANCH         CHANGES  BASE        UPSTREAM
api   feature/login  clean    main +2 -0  (none)
web   feature/login  clean    v2 +1 -0    (none)
```

```bash
just wt-diff-pr --stat
```

`wt-diff-pr` shows what the pull requests will contain; `wt-diff` also includes uncommitted changes, and
`wt-diff-head` shows only those. Then push each branch and open a pull request against its recorded base:

```bash
git -C api push -u origin feature/login && (cd api && gh pr create --base main)
```

```bash
git -C web push -u origin feature/login && (cd web && gh pr create --base v2)
```

Once the pull requests are merged, remove the set from the workspace root. Pushed branches are kept:

```bash
just wt-rm feature/login
```

### Walkthrough: merging slices into a feature branch locally

A larger change lives on `feature/big`, which already has (or will get) its own pull request in each repository.
The work is split into slices, and each slice is merged into `feature/big` locally instead of getting a pull request.

Create a set for the first slice, based on the feature branch:

```bash
just wt-new feature/big-part1 api@feature/big web@feature/big
```

The worktree branch name cannot sit below the base: git does not allow `feature/big` and `feature/big/part1` together,
so use a name like `feature/big-part1`.

Work and commit inside `worktrees/feature/big-part1/` as usual, review with `just wt-diff-pr`, then merge:

```bash
just wt-merge
```

`wt-merge` fast-forwards the local `feature/big` branch to the worktree branch in each repository. It changes no
checkout and pushes nothing, so `wt-status` keeps counting the commits against `origin/feature/big`:

```text
REPO  BRANCH             CHANGES  BASE               UPSTREAM
api   feature/big-part1  clean    feature/big +3 -0  (none)
web   feature/big-part1  clean    feature/big +1 -0  (none)
```

It refuses for a repository, and leaves it unchanged, when:

- the worktree has uncommitted changes;
- the base has commits the worktree branch lacks, for example a slice merged earlier or a push by someone else.
  Rebase the worktree branch onto the ref it names (`git rebase feature/big` or `git rebase origin/feature/big`)
  and run `just wt-merge` again;
- the local `feature/big` and `origin/feature/big` have diverged; it prints a `git log` command to inspect both sides;
- `feature/big` is checked out somewhere, for example under `repos/`.

More slices (`feature/big-part2`, ...) are merged into the same local `feature/big` the same way. When you want the
result on the remote, push explicitly. `wt-push-base` lists the commits and pushes without forcing:

```bash
just wt-push-base
```

```text
REPO  BRANCH             CHANGES  BASE               UPSTREAM
api   feature/big-part1  clean    feature/big +0 -0  (none)
web   feature/big-part1  clean    feature/big +0 -0  (none)
```

The slice's commits are now in `origin/feature/big`, so removing the set also deletes the worktree branches:

```bash
just wt-rm feature/big-part1
```

## Local repositories

`repos.txt` can also list repositories that live on your machine, in two ways.

**Clone from a local path.** Any path `git clone` accepts works as the URL:

```text
baz  /Users/me/src/baz
qux  ../qux
```

`just bootstrap` clones a copy into `repos/<name>/` whose `origin` is the original repository, so `sync`,
`wt-new`, and `wt-status` work as with a hosted remote. Keep in mind:

- Relative paths are resolved from the workspace root. `~` is not expanded, and paths cannot contain spaces.
- Changes reach the original repository only by pushing. Git refuses a push to the branch that is checked out
  in a non-bare repository, so push feature branches, or keep the original as a bare repository.

**Local-only.** Use `-` as the URL to use a repository in place without cloning it, including one with no remote:

```text
notes  -
```

Move or create the repository at `repos/notes/` yourself; `just bootstrap` never clones it and reports it while it
is missing. If the repository has no `origin`, `just sync` skips it and `just wt-new` forks new branches from the
branch currently checked out in `repos/notes/`.

## Design choices

- **No symlinks**: Claude Code resolves symlinks to their real path before looking for `CLAUDE.md` in parent directories, so a session started inside a symlinked repository does not load the root `CLAUDE.md`.
- **No submodules**: this template assumes repositories you develop yourself, where pinning commits is unnecessary. Submodules add detached HEADs and pointer updates, which make branch operations by agents error-prone.
- **Not built on `--add-dir`**: `CLAUDE.md` files in added directories are not loaded by default, and there is no place to keep cross-repo rules.

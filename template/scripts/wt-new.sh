#!/usr/bin/env bash
# Create git worktrees on the same branch across repos, grouped under worktrees/<branch>/<repo>/.
# A "/" in the branch name creates nested directories (worktrees/feature/foo/<repo>/).
# Checks out the branch if it exists; otherwise creates it from the upstream default branch.
# usage: wt-new.sh <branch> [repo...]   (defaults to every cloned repo)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ $# -ge 1 ]] || die "usage: wt-new.sh <branch> [repo...]"
branch=$1
shift
validate_names "$@"
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid branch name: $branch"

wt_root="$WORKTREES_DIR/$branch"

# Sets map to nested directories, so one set must not sit inside another
# (e.g. worktrees/feature/<repo>/ and worktrees/feature/foo/<repo>/).
while IFS= read -r existing; do
    if [[ $branch == "$existing"/* ]]; then
        die "worktrees/$branch would be inside the worktree set worktrees/$existing"
    elif [[ $existing == "$branch"/* ]]; then
        die "worktrees/$branch would contain the worktree set worktrees/$existing"
    fi
done < <(list_wt_sets)

mkdir -p "$wt_root"

failed=0
while read -r name _url manifest_branch <&3; do
    selected "$name" "$@" || continue
    src="$REPOS_DIR/$name"
    dst="$wt_root/$name"
    if ! is_git_dir "$src"; then
        warn "$name: not cloned, skipping"
        continue
    fi
    if [[ -e $dst ]]; then
        echo "${C_DIM}skip${C_RESET}  $name (${dst#"$ROOT"/} exists)"
        continue
    fi

    info "$name -> ${dst#"$ROOT"/} [$branch]"
    if git -C "$src" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$src" worktree add --quiet "$dst" "$branch" || {
            failed=1
            continue
        }
        continue
    fi

    git -C "$src" fetch --quiet origin 2>/dev/null || warn "$name: fetch failed, using local refs"
    if [[ $manifest_branch != "-" ]] && git -C "$src" rev-parse --verify --quiet "origin/$manifest_branch" >/dev/null; then
        start="origin/$manifest_branch"
    elif start=$(git -C "$src" rev-parse --abbrev-ref --verify --quiet origin/HEAD); then
        :
    else
        start=HEAD
    fi
    # No upstream is set; use `git push -u origin <branch>` on the first push
    git -C "$src" worktree add --quiet --no-track -b "$branch" "$dst" "$start" || {
        failed=1
        continue
    }
    echo "  ${C_DIM}from $start${C_RESET}"
done 3< <(read_manifest)

prune_empty_dirs "$wt_root"
[[ -d $wt_root ]] && echo "worktree ready: ${wt_root#"$ROOT"/}"
exit "$failed"

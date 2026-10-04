#!/usr/bin/env bash
# Remove the worktrees under worktrees/<branch>/. Branches are kept.
# Worktrees with uncommitted changes are only removed with --force.
# Other files in the directory are kept and reported.
# usage: wt-rm.sh <branch> [--force]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ $# -ge 1 ]] || die "usage: wt-rm.sh <branch> [--force]"
branch=$1
force=""
[[ ${2:-} == "--force" ]] && force="--force"

wt_root="$WORKTREES_DIR/$branch"
wt_set_exists "$branch" || die "no worktree set for $branch (see: just wt-list)"

failed=0
for dst in "$wt_root"/*/; do
    dst=${dst%/}
    [[ -e $dst/.git ]] || continue
    name=$(basename "$dst")
    src="$REPOS_DIR/$name"
    if [[ -z $force ]] && is_dirty "$dst"; then
        warn "$name: has uncommitted changes, skipping (use --force to discard)"
        failed=1
        continue
    fi
    info "remove ${dst#"$ROOT"/}"
    git -C "$src" worktree remove $force "$dst" || failed=1
done

prune_empty_dirs "$wt_root"

# Files that are not worktrees (plans, notes) are never deleted; point them out instead.
if [[ -d $wt_root ]]; then
    while IFS= read -r entry; do
        [[ -e $entry/.git ]] && continue
        suffix=""
        [[ -d $entry ]] && suffix="/"
        warn "kept ${entry#"$ROOT"/}$suffix (not a worktree)"
    done < <(find "$wt_root" -mindepth 1 -maxdepth 1 | sort)
fi

exit "$failed"

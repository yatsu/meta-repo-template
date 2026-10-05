#!/usr/bin/env bash
# Remove the worktrees under worktrees/<branch>/.
# Worktrees with uncommitted changes are only removed with --force.
# A removed worktree's branch is deleted too when it is unused: no commits on top of its recorded
# base and never pushed. Branches with commits, pushed branches, and branches without a base are kept.
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

# Delete BRANCH in repo SRC if it holds nothing beyond its base; otherwise report why it is kept.
cleanup_branch() {
    local src=$1 br=$2 base base_ref ahead
    if git -C "$src" rev-parse --verify --quiet "$br@{upstream}" >/dev/null ||
        git -C "$src" show-ref --verify --quiet "refs/remotes/origin/$br"; then
        echo "  ${C_DIM}kept branch $br (pushed)${C_RESET}"
        return
    fi
    base=$(get_base "$src" "$br")
    if [[ -z $base ]] || ! base_ref=$(resolve_base_ref "$src" "$base"); then
        echo "  ${C_DIM}kept branch $br (base unknown)${C_RESET}"
        return
    fi
    ahead=$(git -C "$src" rev-list --count "$base_ref..$br")
    if [[ $ahead != 0 ]]; then
        echo "  ${C_DIM}kept branch $br ($ahead commit(s) on top of $base)${C_RESET}"
        return
    fi
    # The branch has no commits of its own, so -D loses nothing even if HEAD is elsewhere
    if git -C "$src" branch --quiet -D "$br"; then
        echo "  ${C_DIM}deleted branch $br (no commits on top of $base, not pushed)${C_RESET}"
    else
        warn "${src##*/}: could not delete branch $br"
    fi
}

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
    wt_branch=$(git -C "$dst" symbolic-ref --short -q HEAD || true)
    git -C "$src" worktree remove $force "$dst" || {
        failed=1
        continue
    }
    [[ -n $wt_branch ]] && cleanup_branch "$src" "$wt_branch"
done

wt_set_exists "$branch" || unlink_settings "$branch"
prune_empty_dirs "$wt_root"

# Files that are not worktrees (plans, notes) are never deleted; point them out instead.
if [[ -d $wt_root ]]; then
    while IFS= read -r entry; do
        [[ -e $entry/.git ]] && continue
        [[ $entry == "$wt_root/.claude" ]] && is_managed_settings_dir "$branch" && continue
        suffix=""
        [[ -d $entry ]] && suffix="/"
        warn "kept ${entry#"$ROOT"/}$suffix (not a worktree)"
    done < <(find "$wt_root" -mindepth 1 -maxdepth 1 | sort)
fi

exit "$failed"

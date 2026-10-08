#!/usr/bin/env bash
# Push each worktree's local base branch (as updated by wt-merge) to origin, never forcing.
# Repos without an origin remote are skipped.
# Lists the commits about to be pushed, and refuses when origin has commits the local base lacks.
# usage: wt-push-base.sh [branch] [repo...]   (branch defaults to the set containing the invocation directory)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

pick_branch "$@"
shift "$BRANCH_ARGC"
branch=$BRANCH
validate_names "$@"
wt_set_exists "$branch" || die "no worktree set for $branch (see: just wt-list)"
color=$(git_color)

failed=0
while read -r name dir <&3; do
    if ! load_base "$dir"; then
        warn "$name: base unknown (set with: just wt-new $branch $name@<base>)"
        failed=1
        continue
    fi
    info "$name: push $BASE"
    local_ref="refs/heads/$BASE"
    if ! git -C "$dir" show-ref --verify --quiet "$local_ref"; then
        echo "  ${C_DIM}no local $BASE; nothing to push (merge with: just wt-merge)${C_RESET}"
        continue
    fi
    # Local-only repositories have nothing to push to; that is not an error
    if ! has_origin "$dir"; then
        echo "  ${C_DIM}no origin remote; skipped${C_RESET}"
        continue
    fi
    git -C "$dir" fetch --quiet origin || {
        warn "$name: fetch failed"
        failed=1
        continue
    }
    remote_ref="refs/remotes/origin/$BASE"
    if git -C "$dir" show-ref --verify --quiet "$remote_ref"; then
        if [[ $(git -C "$dir" rev-parse "$remote_ref") == $(git -C "$dir" rev-parse "$local_ref") ]]; then
            echo "  ${C_DIM}up to date${C_RESET}"
            continue
        fi
        if ! git -C "$dir" merge-base --is-ancestor "$remote_ref" "$local_ref"; then
            warn "$name: origin/$BASE has commits not in local $BASE; reconcile before pushing" \
                "(inspect: git -C ${dir#"$ROOT"/} log --oneline --left-right origin/$BASE...$BASE)"
            failed=1
            continue
        fi
        git -C "$dir" --no-pager log --color="$color" --oneline "$remote_ref..$local_ref"
    else
        echo "  ${C_YELLOW}origin/$BASE does not exist; pushing creates it${C_RESET}"
    fi
    git -C "$dir" push --quiet origin "$local_ref:$local_ref" || {
        warn "$name: push failed"
        failed=1
        continue
    }
    echo "  pushed $BASE"
done 3< <(wt_worktrees "$branch" "$@")

exit "$failed"

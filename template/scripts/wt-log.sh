#!/usr/bin/env bash
# List the commits each worktree in a set has on top of its recorded base.
# usage: wt-log.sh [branch] [repo...]   (branch defaults to the set containing the invocation directory)
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
    info "$name: commits since $BASE"
    out=$(git -C "$dir" --no-pager log --color="$color" --oneline "$BASE_REF..HEAD") || {
        failed=1
        continue
    }
    if [[ -n $out ]]; then
        printf '%s\n' "$out"
    else
        echo "  ${C_DIM}(no commits)${C_RESET}"
    fi
done 3< <(wt_worktrees "$branch" "$@")

exit "$failed"

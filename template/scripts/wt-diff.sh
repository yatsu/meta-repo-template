#!/usr/bin/env bash
# Show a diff for each worktree in a set. Backs the wt-diff, wt-diff-head, and wt-diff-pr recipes:
#   base: from the merge base with the recorded base to the working tree, uncommitted changes included
#   head: uncommitted changes, staged or not (git diff HEAD)
#   pr:   from the merge base to HEAD, i.e. what a pull request against the base shows
# As with git diff, untracked files never appear.
# usage: wt-diff.sh <base|head|pr> [branch] [repo...] [--stat]
#   (branch defaults to the set containing the invocation directory)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ $# -ge 1 ]] || die "usage: wt-diff.sh <base|head|pr> [branch] [repo...] [--stat]"
mode=$1
shift
pick_branch "$@"
shift "$BRANCH_ARGC"
branch=$BRANCH
case $mode in
base | head | pr) ;;
*) die "unknown mode: $mode" ;;
esac
opts=()
repos=()
for arg in "$@"; do
    case $arg in
    --stat) opts+=(--stat) ;;
    -*) die "unknown option: $arg" ;;
    *) repos+=("$arg") ;;
    esac
done
validate_names ${repos[@]+"${repos[@]}"}
wt_set_exists "$branch" || die "no worktree set for $branch (see: just wt-list)"
color=$(git_color)

failed=0
while read -r name dir <&3; do
    if [[ $mode == head ]]; then
        info "$name: uncommitted changes"
        range=(HEAD)
    elif load_base "$dir"; then
        mb=$(git -C "$dir" merge-base "$BASE_REF" HEAD) || {
            warn "$name: no common history with $BASE_REF"
            failed=1
            continue
        }
        if [[ $mode == base ]]; then
            info "$name: changes since $BASE, including uncommitted"
            range=("$mb")
        else
            info "$name: $BASE...HEAD"
            range=("$mb" HEAD)
        fi
    else
        warn "$name: base unknown (set with: just wt-new $branch $name@<base>)"
        failed=1
        continue
    fi
    out=$(git -C "$dir" --no-pager diff --color="$color" ${opts[@]+"${opts[@]}"} "${range[@]}") || {
        failed=1
        continue
    }
    if [[ -n $out ]]; then
        printf '%s\n' "$out"
    else
        echo "  ${C_DIM}(no changes)${C_RESET}"
    fi
done 3< <(wt_worktrees "$branch" ${repos[@]+"${repos[@]}"})

exit "$failed"

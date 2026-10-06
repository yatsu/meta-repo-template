#!/usr/bin/env bash
# Run a shell command in each worktree of a set. Keeps going if one fails.
# The command sees BASE and BASE_REF (empty if no base is recorded) and runs without a pager.
# usage: wt-exec.sh [branch] <command> [repo...]   (branch defaults to the set containing the invocation directory)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

pick_branch "$@"
shift "$BRANCH_ARGC"
branch=$BRANCH
[[ $# -ge 1 ]] || die "usage: wt-exec.sh [branch] <command> [repo...]"
cmd=$1
shift
validate_names "$@"
wt_set_exists "$branch" || die "no worktree set for $branch (see: just wt-list)"

failed=()
while read -r name dir <&3; do
    load_base "$dir" || true
    info "$name: $cmd"
    (cd "$dir" && BASE="$BASE" BASE_REF="$BASE_REF" GIT_PAGER=cat bash -c "$cmd") </dev/null || failed+=("$name")
done 3< <(wt_worktrees "$branch" "$@")

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "${C_RED}failed:${C_RESET} ${failed[*]}" >&2
    exit 1
fi

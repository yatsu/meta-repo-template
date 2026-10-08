#!/usr/bin/env bash
# List worktree sets by branch name, with the repos that have a worktree in each.
# usage: wt-list.sh
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

while IFS= read -r branch; do
    repos=()
    for dir in "$WORKTREES_DIR/$branch"/*/; do
        dir=${dir%/}
        [[ -e $dir/.git ]] && repos+=("$(basename "$dir")")
    done
    table_row "$branch" "${repos[*]}"
done < <(list_wt_sets) | print_table

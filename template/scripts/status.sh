#!/usr/bin/env bash
# Show branch, uncommitted changes, and ahead/behind counts for each repo.
# Does not touch the network; run `just sync` first for up-to-date counts.
# usage: status.sh [-w branch] [repo...]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

base="$REPOS_DIR"
if [[ ${1:-} == "-w" ]]; then
    [[ -n ${2:-} ]] || die "usage: status.sh -w <branch> [repo...]"
    wt_set_exists "$2" || die "no worktree set for $2 (see: just wt-list)"
    base="$WORKTREES_DIR/$2"
    shift 2
fi
validate_names "$@"

fmt="%-24s %-32s %-10s %s\n"
# shellcheck disable=SC2059
printf "$fmt" REPO BRANCH CHANGES UPSTREAM
while read -r name _url _branch <&3; do
    selected "$name" "$@" || continue
    dir="$base/$name"
    if ! is_git_dir "$dir"; then
        # A worktree set may cover only some repos, so skip the missing ones
        [[ $base != "$REPOS_DIR" ]] && continue
        # shellcheck disable=SC2059
        printf "$fmt" "$name" "-" "-" "(missing)"
        continue
    fi
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD || echo "(detached $(git -C "$dir" rev-parse --short HEAD))")
    changes=$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')
    [[ $changes == 0 ]] && changes="clean"
    if counts=$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null); then
        read -r behind ahead <<<"$counts"
        upstream="$(git -C "$dir" rev-parse --abbrev-ref '@{u}') +$ahead -$behind"
    else
        upstream="(none)"
    fi
    # shellcheck disable=SC2059
    printf "$fmt" "$name" "$branch" "$changes" "$upstream"
done 3< <(read_manifest)

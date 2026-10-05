#!/usr/bin/env bash
# Show branch, uncommitted changes, and ahead/behind counts for each repo.
# With -w, also show each worktree's recorded base and ahead/behind against it.
# Does not touch the network; run `just sync` first for up-to-date counts.
# usage: status.sh [-w branch] [repo...]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

root_dir="$REPOS_DIR"
wt_mode=""
if [[ ${1:-} == "-w" ]]; then
    [[ -n ${2:-} ]] || die "usage: status.sh -w <branch> [repo...]"
    wt_set_exists "$2" || die "no worktree set for $2 (see: just wt-list)"
    root_dir="$WORKTREES_DIR/$2"
    wt_mode=1
    shift 2
fi
validate_names "$@"

fmt="%-24s %-32s %-10s %s\n"
header=(REPO BRANCH CHANGES UPSTREAM)
if [[ -n $wt_mode ]]; then
    fmt="%-24s %-32s %-10s %-24s %s\n"
    header=(REPO BRANCH CHANGES BASE UPSTREAM)
fi
# shellcheck disable=SC2059
printf "$fmt" "${header[@]}"
while read -r name _url _branch <&3; do
    selected "$name" "$@" || continue
    dir="$root_dir/$name"
    if ! is_git_dir "$dir"; then
        # A worktree set may cover only some repos, so skip the missing ones
        [[ -n $wt_mode ]] && continue
        # shellcheck disable=SC2059
        printf "$fmt" "$name" "-" "-" "(missing)"
        continue
    fi
    current=$(git -C "$dir" symbolic-ref --short -q HEAD || true)
    branch=${current:-"(detached $(git -C "$dir" rev-parse --short HEAD))"}
    changes=$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')
    [[ $changes == 0 ]] && changes="clean"
    if counts=$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null); then
        read -r behind ahead <<<"$counts"
        upstream="$(git -C "$dir" rev-parse --abbrev-ref '@{u}') +$ahead -$behind"
    else
        upstream="(none)"
    fi
    if [[ -z $wt_mode ]]; then
        # shellcheck disable=SC2059
        printf "$fmt" "$name" "$branch" "$changes" "$upstream"
        continue
    fi
    base=""
    [[ -n $current ]] && base=$(get_base "$dir" "$current")
    if [[ -z $base ]]; then
        base_info="(unknown)"
    elif base_ref=$(resolve_base_ref "$dir" "$base") &&
        counts=$(git -C "$dir" rev-list --left-right --count "$base_ref...HEAD" 2>/dev/null); then
        read -r behind ahead <<<"$counts"
        base_info="$base +$ahead -$behind"
    else
        base_info="$base (not found)"
    fi
    # shellcheck disable=SC2059
    printf "$fmt" "$name" "$branch" "$changes" "$base_info" "$upstream"
done 3< <(read_manifest)

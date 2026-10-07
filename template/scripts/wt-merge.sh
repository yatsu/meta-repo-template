#!/usr/bin/env bash
# Merge each worktree's branch into its recorded base branch locally, fast-forward only, without pushing.
# Only the local base branch ref moves; no checkout is touched. Push it afterwards with wt-push-base.
# Refuses (per repo) when the worktree has uncommitted changes, when the base is not a branch, when the
# branch does not contain the tip of the base (rebase first), or when the base is checked out somewhere.
# usage: wt-merge.sh [branch] [repo...]   (branch defaults to the set containing the invocation directory)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

pick_branch "$@"
shift "$BRANCH_ARGC"
branch=$BRANCH
validate_names "$@"
wt_set_exists "$branch" || die "no worktree set for $branch (see: just wt-list)"

failed=0
while read -r name dir <&3; do
    if ! load_base "$dir"; then
        warn "$name: base unknown (set with: just wt-new $branch $name@<base>)"
        failed=1
        continue
    fi
    info "$name: $branch -> $BASE (local)"
    if is_dirty "$dir"; then
        warn "$name: has uncommitted changes; commit or stash them first"
        failed=1
        continue
    fi
    if has_origin "$dir"; then
        git -C "$dir" fetch --quiet origin || warn "$name: fetch failed, using local refs"
    fi
    if ! base_is_branch "$dir" "$BASE"; then
        warn "$name: base $BASE is not a branch; nothing to merge into"
        failed=1
        continue
    fi
    head=$(git -C "$dir" rev-parse HEAD)
    local_ref="refs/heads/$BASE"
    old=$(git -C "$dir" rev-parse --verify --quiet "$local_ref" || true)

    remote_ref="refs/remotes/origin/$BASE"
    has_remote=""
    git -C "$dir" show-ref --verify --quiet "$remote_ref" && has_remote=1
    # Unpushed commits on the local base that origin lacks and origin commits the local base lacks
    # cannot be fixed by a rebase here; the user has to reconcile the local base first.
    if [[ -n $old && -n $has_remote ]] &&
        ! git -C "$dir" merge-base --is-ancestor "$remote_ref" "$local_ref" &&
        ! git -C "$dir" merge-base --is-ancestor "$local_ref" "$remote_ref"; then
        warn "$name: local $BASE and origin/$BASE have diverged; reconcile local $BASE first" \
            "(inspect: git -C ${dir#"$ROOT"/} log --oneline --left-right origin/$BASE...$BASE)"
        failed=1
        continue
    fi

    # Fast-forward only: the branch must already contain the base, both on origin and locally
    behind=""
    if [[ -n $has_remote ]] && ! git -C "$dir" merge-base --is-ancestor "$remote_ref" HEAD; then
        behind="origin/$BASE"
    fi
    if [[ -n $old ]] && ! git -C "$dir" merge-base --is-ancestor "$local_ref" HEAD; then
        behind="$BASE"
    fi
    if [[ -n $behind ]]; then
        warn "$name: $behind has commits not in $branch; rebase first: git -C ${dir#"$ROOT"/} rebase $behind"
        failed=1
        continue
    fi
    if [[ $old == "$head" ]]; then
        echo "  ${C_DIM}already merged${C_RESET}"
        continue
    fi
    if where=$(checked_out_at "$dir" "$BASE"); then
        warn "$name: $BASE is checked out at ${where#"$ROOT"/}; merge there or switch that checkout away"
        failed=1
        continue
    fi

    from=${old:-$(git -C "$dir" rev-parse --verify --quiet "refs/remotes/origin/$BASE" || true)}
    count=$(git -C "$dir" rev-list --count ${from:+"$from.."}HEAD)
    # An empty old value makes update-ref fail if the branch appeared in the meantime
    git -C "$dir" update-ref -m "wt-merge: fast-forward to $branch" "$local_ref" "$head" "$old" || {
        failed=1
        continue
    }
    echo "  merged $count commit(s) into local $BASE; not pushed (push with: just wt-push-base)"
done 3< <(wt_worktrees "$branch" "$@")

exit "$failed"

#!/usr/bin/env bash
# Merge each worktree's branch into its recorded base branch locally, fast-forward only, without pushing.
# Works on local refs only and never fetches: repos/ may be developed without syncing with origin.
# If the base is checked out in the repo's main checkout (repos/<repo>) and that checkout has no
# uncommitted changes, it is fast-forwarded there, so its files show the merged code. Otherwise only
# the local base branch ref moves. Push it afterwards with wt-push-base.
# Refuses (per repo) when the worktree has uncommitted changes, when the base is not a branch, when the
# branch does not contain the tip of the local base (rebase first), when repos/<repo> has the base
# checked out with uncommitted changes, or when another worktree has the base checked out.
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
    if ! base_is_branch "$dir" "$BASE"; then
        warn "$name: base $BASE is not a branch; nothing to merge into"
        failed=1
        continue
    fi
    head=$(git -C "$dir" rev-parse HEAD)
    local_ref="refs/heads/$BASE"
    old=$(git -C "$dir" rev-parse --verify --quiet "$local_ref" || true)

    # Local only, no fetch: the target is the local base branch. Only when it does not exist yet is it
    # created from the branch, which must then contain the (last fetched) origin/<base>.
    target_ref=$local_ref
    [[ -n $old ]] || target_ref="refs/remotes/origin/$BASE"
    behind=""
    if ! git -C "$dir" merge-base --is-ancestor "$target_ref" HEAD; then
        behind=${target_ref#refs/heads/}
        behind=${behind#refs/remotes/}
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

    from=$(git -C "$dir" rev-parse "$target_ref")
    count=$(git -C "$dir" rev-list --count ${from:+"$from.."}HEAD)

    push_hint=""
    has_origin "$dir" && push_hint="; not pushed (push with: just wt-push-base)"

    if where=$(checked_out_at "$dir" "$BASE"); then
        main=$(cd "$REPOS_DIR/$name" && pwd -P)
        shown=${where#"$(cd "$ROOT" && pwd -P)"/}
        if [[ $(cd "$where" && pwd -P) != "$main" ]]; then
            warn "$name: $BASE is checked out in another worktree ($shown); merge there or switch it away"
            failed=1
            continue
        fi
        # Untracked files are fine; git refuses the merge if it would overwrite one
        if [[ -n $(git -C "$where" status --porcelain --untracked-files=no) ]]; then
            warn "$name: $BASE is checked out at $shown with uncommitted changes; commit or stash them first"
            failed=1
            continue
        fi
        git -C "$where" merge --ff-only --quiet "$head" || {
            warn "$name: fast-forward of $shown failed"
            failed=1
            continue
        }
        echo "  merged $count commit(s) into $BASE, updating the checkout at $shown$push_hint"
        continue
    fi
    # An empty old value makes update-ref fail if the branch appeared in the meantime
    git -C "$dir" update-ref -m "wt-merge: fast-forward to $branch" "$local_ref" "$head" "$old" || {
        failed=1
        continue
    }
    echo "  merged $count commit(s) into local $BASE$push_hint"
done 3< <(wt_worktrees "$branch" "$@")

exit "$failed"

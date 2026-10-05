#!/usr/bin/env bash
# Create git worktrees on the same branch across repos, grouped under worktrees/<branch>/<repo>/.
# A "/" in the branch name creates nested directories (worktrees/feature/foo/<repo>/).
# Checks out the branch if it exists. Otherwise creates it from <base> when given as repo@<base>,
# else from the branch set in repos.txt, else from the upstream default branch.
# The base is recorded as branch.<branch>.meta-base in each repo's git config. For a repo that
# already has the branch or the worktree, repo@<base> only updates the record.
# Also links worktrees/<branch>/.claude/settings.json to the workspace's .claude/settings.json.
# usage: wt-new.sh <branch> [repo[@base]...]   (defaults to every cloned repo)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ $# -ge 1 ]] || die "usage: wt-new.sh <branch> [repo[@base]...]"
branch=$1
shift
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid branch name: $branch"

# Split repo@base arguments. Repo names cannot contain "@", so split at the first one.
names=()
bases=()
for arg in "$@"; do
    base=""
    if [[ $arg == *@* ]]; then
        base=${arg#*@}
        [[ -n $base ]] || die "missing base after @: $arg"
    fi
    names+=("${arg%%@*}")
    bases+=("$base")
done
validate_names ${names[@]+"${names[@]}"}

explicit_base() {
    local i
    for ((i = 0; i < ${#names[@]}; i++)); do
        if [[ ${names[i]} == "$1" ]]; then
            echo "${bases[i]}"
            return
        fi
    done
}

wt_root="$WORKTREES_DIR/$branch"

# Sets map to nested directories, so one set must not sit inside another
# (e.g. worktrees/feature/<repo>/ and worktrees/feature/foo/<repo>/).
while IFS= read -r existing; do
    if [[ $branch == "$existing"/* ]]; then
        die "worktrees/$branch would be inside the worktree set worktrees/$existing"
    elif [[ $existing == "$branch"/* ]]; then
        die "worktrees/$branch would contain the worktree set worktrees/$existing"
    fi
done < <(list_wt_sets)

mkdir -p "$wt_root"

failed=0
while read -r name _url manifest_branch <&3; do
    selected "$name" ${names[@]+"${names[@]}"} || continue
    src="$REPOS_DIR/$name"
    dst="$wt_root/$name"
    requested=$(explicit_base "$name")
    if ! is_git_dir "$src"; then
        warn "$name: not cloned, skipping"
        continue
    fi
    if [[ -e $dst ]]; then
        echo "${C_DIM}skip${C_RESET}  $name (${dst#"$ROOT"/} exists)"
        if [[ -n $requested ]]; then
            set_base "$src" "$branch" "$requested"
            echo "  ${C_DIM}base recorded as $requested${C_RESET}"
        fi
        continue
    fi

    info "$name -> ${dst#"$ROOT"/} [$branch]"
    if git -C "$src" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$src" worktree add --quiet "$dst" "$branch" || {
            failed=1
            continue
        }
        # The branch keeps its history; an explicit base only updates the record
        if [[ -n $requested ]]; then
            set_base "$src" "$branch" "$requested"
            echo "  ${C_DIM}existing branch, base recorded as $requested${C_RESET}"
        else
            recorded=$(get_base "$src" "$branch")
            echo "  ${C_DIM}existing branch, base: ${recorded:-not recorded (set with: just wt-new $branch $name@<base>)}${C_RESET}"
        fi
        continue
    fi

    if has_origin "$src"; then
        git -C "$src" fetch --quiet origin 2>/dev/null || warn "$name: fetch failed, using local refs"
    fi
    if [[ -n $requested ]]; then
        base=$requested
        start=$(resolve_base_ref "$src" "$base") || {
            warn "$name: base not found: $base"
            failed=1
            continue
        }
    elif [[ $manifest_branch != "-" ]] && git -C "$src" rev-parse --verify --quiet "refs/remotes/origin/$manifest_branch" >/dev/null; then
        base=$manifest_branch
        start="origin/$base"
    elif start=$(git -C "$src" rev-parse --abbrev-ref --verify --quiet origin/HEAD); then
        base=${start#origin/}
    else
        start=HEAD
        base=$(git -C "$src" symbolic-ref --short -q HEAD || true)
    fi
    # No upstream is set; use `git push -u origin <branch>` on the first push
    git -C "$src" worktree add --quiet --no-track -b "$branch" "$dst" "$start" || {
        failed=1
        continue
    }
    [[ -n $base ]] && set_base "$src" "$branch" "$base"
    echo "  ${C_DIM}from $start${C_RESET}"
done 3< <(read_manifest)

if wt_set_exists "$branch"; then
    link_settings "$branch"
    echo "worktree ready: ${wt_root#"$ROOT"/}"
else
    unlink_settings "$branch"
    prune_empty_dirs "$wt_root"
fi
exit "$failed"

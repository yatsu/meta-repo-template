# shellcheck shell=bash
# Shared helpers sourced by every script. Keep compatible with bash 3.2 (macOS default).
# Variables defined here are used by the scripts that source this file.
# shellcheck disable=SC2034

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${MANIFEST:-$ROOT/repos.txt}"
REPOS_DIR="$ROOT/repos"
WORKTREES_DIR="$ROOT/worktrees"

if [[ -t 1 ]]; then
    C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m' C_YELLOW=$'\e[33m' C_RESET=$'\e[0m'
else
    C_BOLD='' C_DIM='' C_RED='' C_YELLOW='' C_RESET=''
fi

die() {
    echo "${C_RED}error:${C_RESET} $*" >&2
    exit 1
}
warn() { echo "${C_YELLOW}warn:${C_RESET} $*" >&2; }
info() { echo "${C_BOLD}==>${C_RESET} $*"; }

# Print repos.txt as "name url branch" lines. A missing branch is printed as "-".
read_manifest() {
    [[ -f $MANIFEST ]] || die "manifest not found: $MANIFEST"
    sed -e 's/[[:space:]]#.*$//' -e 's/^#.*$//' "$MANIFEST" |
        awk 'NF { print $1, $2, (NF >= 3 ? $3 : "-") }'
}

manifest_has() {
    local name=$1 n _rest
    while read -r n _rest; do
        [[ $n == "$name" ]] && return 0
    done < <(read_manifest)
    return 1
}

# Fail unless every given repo name is listed in repos.txt.
validate_names() {
    local name
    for name in "$@"; do
        manifest_has "$name" || die "unknown repo: $name (not in ${MANIFEST#"$ROOT"/})"
    done
}

# selected NAME [FILTER...]: true if FILTER is empty or contains NAME.
selected() {
    local name=$1 f
    shift
    [[ $# -eq 0 ]] && return 0
    for f in "$@"; do
        [[ $f == "$name" ]] && return 0
    done
    return 1
}

is_git_dir() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

is_dirty() { [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]]; }

# A worktree set is the directory worktrees/<branch>/, holding one worktree per repo.
# Branch names containing "/" become nested directories, e.g. worktrees/feature/foo/.

# Print the branch names of existing worktree sets, one per line.
list_wt_sets() {
    [[ -d $WORKTREES_DIR ]] || return 0
    # Repo worktrees are the directories containing a .git file; do not descend into them.
    find "$WORKTREES_DIR" -mindepth 2 -type d -exec sh -c 'test -e "$1/.git"' _ {} \; -prune -print |
        while IFS= read -r dir; do
            dir=$(dirname "$dir")
            echo "${dir#"$WORKTREES_DIR"/}"
        done | sort -u
}

wt_set_exists() {
    local b
    while IFS= read -r b; do
        [[ $b == "$1" ]] && return 0
    done < <(list_wt_sets)
    return 1
}

# Remove DIR and then its parents while they are empty, stopping at worktrees/.
prune_empty_dirs() {
    local dir=$1
    while [[ $dir == "$WORKTREES_DIR"/* ]] && rmdir "$dir" 2>/dev/null; do
        dir=$(dirname "$dir")
    done
}

# The base branch of a worktree branch (what it was forked from and what PRs should target)
# is recorded per repo in git config as branch.<branch>.meta-base.
get_base() { git -C "$1" config --get "branch.$2.meta-base" || true; }
set_base() { git -C "$1" config "branch.$2.meta-base" "$3"; }

# Print the ref to compare against for base BASE in repo DIR:
# origin/BASE if it exists, otherwise BASE itself (local branch, tag, or commit).
resolve_base_ref() {
    local dir=$1 base=$2
    if git -C "$dir" rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null; then
        echo "origin/$base"
    elif git -C "$dir" rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
        echo "$base"
    else
        return 1
    fi
}

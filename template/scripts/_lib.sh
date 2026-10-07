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

# A "-" URL in repos.txt marks a local-only repo: bootstrap does not clone it,
# and the user places the repository at repos/<name>/ themselves.
is_local_only() { [[ $1 == "-" ]]; }

has_origin() { git -C "$1" remote get-url origin >/dev/null 2>&1; }

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

# Claude Code reads the shared .claude/settings.json only from the directory it starts in, so each
# worktree set gets a relative symlink to the workspace's file: worktrees/<branch>/.claude/settings.json.
settings_link_target() {
    local branch=$1 up="../../" part
    # One "../" for .claude and one for worktrees, plus one per component of the branch name
    local IFS=/
    for part in $branch; do
        up="../$up"
    done
    echo "$up.claude/settings.json"
}

link_settings() {
    local branch=$1 dir="$WORKTREES_DIR/$1/.claude"
    [[ -f $ROOT/.claude/settings.json ]] || return 0
    [[ -e $dir/settings.json || -L $dir/settings.json ]] && return 0
    mkdir -p "$dir"
    ln -s "$(settings_link_target "$branch")" "$dir/settings.json"
}

is_settings_link() {
    local link="$WORKTREES_DIR/$1/.claude/settings.json"
    [[ -L $link && $(readlink "$link") == "$(settings_link_target "$1")" ]]
}

# True if worktrees/<branch>/.claude holds nothing but the link from link_settings.
is_managed_settings_dir() {
    is_settings_link "$1" && [[ $(find "$WORKTREES_DIR/$1/.claude" -mindepth 1 | wc -l) -eq 1 ]]
}

# Remove the symlink created by link_settings; a file the user put there is left alone.
unlink_settings() {
    local branch=$1 dir="$WORKTREES_DIR/$1/.claude"
    if is_settings_link "$branch"; then
        rm "$dir/settings.json"
        rmdir "$dir" 2>/dev/null || true
    fi
}

# Print "name dir" for each repo (in repos.txt order) that has a worktree in worktrees/<branch>/,
# limited to the given repos if any. Named repos without a worktree are reported.
wt_worktrees() {
    local branch=$1 name _url _branch dir
    shift
    while read -r name _url _branch; do
        selected "$name" "$@" || continue
        dir="$WORKTREES_DIR/$branch/$name"
        if [[ -e $dir/.git ]]; then
            echo "$name $dir"
        elif [[ $# -gt 0 ]]; then
            warn "$name: no worktree in worktrees/$branch/"
        fi
    done < <(read_manifest)
}

# Set BASE (e.g. v2) and BASE_REF (e.g. origin/v2) for the worktree at DIR from the recorded base
# of its current branch. Fails, leaving both empty, when no usable base is recorded.
load_base() {
    local current
    BASE="" BASE_REF=""
    current=$(git -C "$1" symbolic-ref --short -q HEAD) || return 1
    BASE=$(get_base "$1" "$current")
    [[ -n $BASE ]] || return 1
    BASE_REF=$(resolve_base_ref "$1" "$BASE") || {
        BASE_REF=""
        return 1
    }
}

# --color value for git output captured in a variable but printed to this script's stdout.
git_color() { if [[ -t 1 ]]; then echo always; else echo never; fi; }

# Print the worktree set that contains the directory just was invoked from (META_INVOCATION_DIR,
# exported by the justfile), or fail when it is outside every set.
current_wt_set() {
    local dir wt b
    [[ -n ${META_INVOCATION_DIR:-} && -d $META_INVOCATION_DIR && -d $WORKTREES_DIR ]] || return 1
    dir=$(cd "$META_INVOCATION_DIR" && pwd -P)
    wt=$(cd "$WORKTREES_DIR" && pwd -P)
    while IFS= read -r b; do
        case "$dir/" in "$wt/$b/"*)
            echo "$b"
            return 0
            ;;
        esac
    done < <(list_wt_sets)
    return 1
}

# Pick the worktree set for a wt-* script. Inside worktrees/<branch>/ the branch comes from the
# invocation directory and the arguments are left as they are (a leading copy of that branch name
# is skipped); elsewhere the first argument is the branch.
# Sets BRANCH, and BRANCH_ARGC to the number of arguments the caller should shift.
pick_branch() {
    local inferred
    if inferred=$(current_wt_set); then
        BRANCH=$inferred BRANCH_ARGC=0
        if [[ ${1:-} == "$inferred" ]]; then
            BRANCH_ARGC=1
        elif [[ -n ${1:-} ]] && ! manifest_has "$1" && wt_set_exists "$1"; then
            die "running inside worktrees/$inferred/; run from the workspace root to use the set $1"
        fi
    else
        [[ -n ${1:-} ]] || die "missing <branch> (or run inside worktrees/<branch>/)"
        BRANCH=$1 BRANCH_ARGC=1
    fi
}

# True if BASE exists as a branch in repo DIR, locally or on origin (not just a tag or commit).
base_is_branch() {
    git -C "$1" show-ref --verify --quiet "refs/heads/$2" ||
        git -C "$1" show-ref --verify --quiet "refs/remotes/origin/$2"
}

# Print the path of the worktree (or main checkout) where BRANCH is checked out in repo DIR, if any.
checked_out_at() {
    local dir=$1 branch=$2 line path=""
    while IFS= read -r line; do
        case $line in
        "worktree "*) path=${line#worktree } ;;
        "branch refs/heads/$branch")
            echo "$path"
            return 0
            ;;
        esac
    done < <(git -C "$dir" worktree list --porcelain)
    return 1
}

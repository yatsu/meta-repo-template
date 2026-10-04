#!/usr/bin/env bash
# Run a shell command at the root of each repo. Keeps going if one fails.
# usage: exec.sh <command> [repo...]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ $# -ge 1 ]] || die "usage: exec.sh <command> [repo...]"
cmd=$1
shift
validate_names "$@"

failed=()
while read -r name _url _branch <&3; do
    selected "$name" "$@" || continue
    dir="$REPOS_DIR/$name"
    is_git_dir "$dir" || {
        warn "$name: not cloned"
        continue
    }
    info "$name: $cmd"
    (cd "$dir" && bash -c "$cmd") </dev/null || failed+=("$name")
done 3< <(read_manifest)

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "${C_RED}failed:${C_RESET} ${failed[*]}" >&2
    exit 1
fi

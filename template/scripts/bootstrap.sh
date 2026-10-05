#!/usr/bin/env bash
# Clone repos listed in repos.txt that are not yet present under repos/.
# Local-only repos (URL "-") are never cloned; a missing one is reported.
# usage: bootstrap.sh [repo...]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

validate_names "$@"
mkdir -p "$REPOS_DIR"

failed=0
while read -r name url branch <&3; do
    selected "$name" "$@" || continue
    dir="$REPOS_DIR/$name"
    if is_git_dir "$dir"; then
        if is_local_only "$url"; then
            echo "${C_DIM}skip${C_RESET}  $name (local-only, present)"
        else
            echo "${C_DIM}skip${C_RESET}  $name (already cloned)"
        fi
        continue
    fi
    if [[ -e $dir ]]; then
        warn "$name: $dir exists but is not a git repository, skipping"
        failed=1
        continue
    fi
    if is_local_only "$url"; then
        warn "$name: local-only repo is missing; move or create the repository at ${dir#"$ROOT"/}/"
        continue
    fi
    args=()
    [[ $branch != "-" ]] && args=(--branch "$branch")
    info "clone $name <- $url${args[1]+ (${args[1]})}"
    git clone ${args[@]+"${args[@]}"} "$url" "$dir" || {
        warn "$name: clone failed"
        failed=1
    }
done 3< <(read_manifest)

exit "$failed"

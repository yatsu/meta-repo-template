#!/usr/bin/env bash
# Fetch each repo, then fast-forward pull if it has no uncommitted changes.
# usage: sync.sh [repo...]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

validate_names "$@"

failed=0
while read -r name _url _branch <&3; do
    selected "$name" "$@" || continue
    dir="$REPOS_DIR/$name"
    if ! is_git_dir "$dir"; then
        warn "$name: not cloned (run: just bootstrap $name)"
        continue
    fi
    info "$name"
    git -C "$dir" fetch --prune --quiet || {
        warn "$name: fetch failed"
        failed=1
        continue
    }
    if is_dirty "$dir"; then
        echo "  ${C_YELLOW}dirty${C_RESET}: fetched only"
        continue
    fi
    if ! git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        echo "  ${C_DIM}no upstream${C_RESET}: fetched only"
        continue
    fi
    git -C "$dir" pull --ff-only --quiet || {
        warn "$name: fast-forward failed (diverged?)"
        failed=1
    }
done 3< <(read_manifest)

exit "$failed"

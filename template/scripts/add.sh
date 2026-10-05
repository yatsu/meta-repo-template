#!/usr/bin/env bash
# Append a repo to repos.txt and clone it. With URL "-", the repo is local-only and not cloned.
# usage: add.sh <name> <url> [branch]
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[[ $# -ge 2 && $# -le 3 ]] || die "usage: add.sh <name> <url> [branch]"
name=$1 url=$2 branch=${3:-}
[[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid name: $name (use [A-Za-z0-9._-])"
manifest_has "$name" && die "$name is already in ${MANIFEST#"$ROOT"/}"

# Avoid joining lines when the file lacks a trailing newline
[[ -s $MANIFEST && -n $(tail -c 1 "$MANIFEST") ]] && echo >>"$MANIFEST"
echo "$name $url${branch:+ $branch}" >>"$MANIFEST"
info "added $name to ${MANIFEST#"$ROOT"/}"

"$(dirname "$0")/bootstrap.sh" "$name"

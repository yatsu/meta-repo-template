#!/usr/bin/env bash
# Install the meta-repo template into a directory.
# Copies template/ without overwriting existing files and appends missing .gitignore entries.
# usage: install.sh <target-dir>
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd -P)/template"

if [[ -t 1 ]]; then
    C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m' C_YELLOW=$'\e[33m' C_RESET=$'\e[0m'
else
    C_BOLD='' C_DIM='' C_RED='' C_YELLOW='' C_RESET=''
fi
die() {
    echo "${C_RED}error:${C_RESET} $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "usage: install.sh <target-dir>"
[[ -d $SRC ]] || die "template directory not found: $SRC"
TEMPLATE_REPO="$(dirname "$SRC")"
inside_template() {
    case "$1/" in "$TEMPLATE_REPO"/*) return 0 ;; esac
    return 1
}
target=$1
[[ $target == /* ]] || target="$PWD/$target"
inside_template "$target" && die "target must be outside the template repository: $target"
created=""
[[ -d $target ]] || {
    mkdir -p "$target"
    created=1
}
DEST="$(cd "$target" && pwd -P)"
# Catch symlinks that resolve into the template repository
if inside_template "$DEST"; then
    [[ -n $created ]] && rmdir "$target"
    die "target must be outside the template repository: $DEST"
fi

echo "${C_BOLD}Installing into $DEST${C_RESET}"

skipped=()
while IFS= read -r -d '' rel <&3; do
    rel=${rel#./}
    [[ $rel == ".gitignore" || $(basename "$rel") == ".DS_Store" ]] && continue
    if [[ -e $DEST/$rel ]]; then
        echo "${C_YELLOW}skip${C_RESET}    $rel (exists)"
        skipped+=("$rel")
        continue
    fi
    mkdir -p "$(dirname "$DEST/$rel")"
    cp -p "$SRC/$rel" "$DEST/$rel"
    echo "${C_DIM}create${C_RESET}  $rel"
done 3< <(cd "$SRC" && find . -type f -print0 | sort -z)

# Append .gitignore entries that are not already present, keeping existing content.
missing=()
while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    if [[ ! -f $DEST/.gitignore ]] || ! grep -qxF -- "$line" "$DEST/.gitignore"; then
        missing+=("$line")
    fi
done <"$SRC/.gitignore"
if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ -s $DEST/.gitignore && -n $(tail -c 1 "$DEST/.gitignore") ]]; then
        echo >>"$DEST/.gitignore"
    fi
    {
        [[ -s $DEST/.gitignore ]] && echo
        echo "# meta-repo"
        printf '%s\n' "${missing[@]}"
    } >>"$DEST/.gitignore"
    echo "${C_DIM}update${C_RESET}  .gitignore (+${#missing[@]} entries)"
else
    echo "${C_DIM}keep${C_RESET}    .gitignore (entries already present)"
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
    echo
    echo "${C_YELLOW}Some files already existed and were left untouched.${C_RESET}"
    echo "Compare them with $SRC and merge by hand if needed."
fi

cat <<EOF

${C_BOLD}Next steps${C_RESET} (see README.md in the template for details):
  1. Adopt AGENTS-meta-repo.md as the workspace's CLAUDE.md or AGENTS.md.
  2. List your repositories in repos.txt.
  3. Run 'just bootstrap' in $DEST.
EOF
if ! git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  The target is not a git repository yet; run 'git init' there if you want to track the workspace."
fi

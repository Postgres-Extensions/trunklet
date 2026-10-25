#!/usr/bin/env bash

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}"' ERR

# Source common library functions (error, die, debug)
PGXNTOOL_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$PGXNTOOL_DIR/lib.sh"

# Use rev-parse, not [ -d .git ]: in a worktree .git is a file, not a directory,
# so the old check would wrongly re-run `git init` inside a valid working tree.
git rev-parse --git-dir >/dev/null 2>&1 || git init

if ! git diff --cached --exit-code; then
    echo "Git repository is not clean; please commit and try again." >&2
    exit 1
fi

safecreate () {
    file=$1
    shift
    if [ -e $file ]; then
        echo "$file already exists"
    else
        echo "Creating $file"
        echo $@ > $file
        git add $file
    fi
}

safecp () {
    [ $# -eq 2 ] || exit 1
    local src=$1
    local dest=$2
    if [ -e $dest ]; then
        echo $dest already exists
    else
        echo Copying $src to $dest and adding to git
        cp $src $dest
        git add $dest
    fi
}

# =============================================================================
# SETUP FILES
# =============================================================================
# SETUP_FILES and SETUP_SYMLINKS are defined in lib.sh
# These are also used by update-setup-files.sh for sync updates.
# =============================================================================

# Copy tracked setup files (defined in lib.sh)
for entry in "${SETUP_FILES[@]}"; do
    src="pgxntool/${entry%%:*}"
    dest="${entry##*:}"
    # Create parent directory if needed
    mkdir -p "$(dirname "$dest")"
    safecp "$src" "$dest"
done

# Create tracked symlinks (defined in lib.sh)
for entry in "${SETUP_SYMLINKS[@]}"; do
    dest="${entry%%:*}"
    target="${entry##*:}"
    mkdir -p "$(dirname "$dest")"
    if [ ! -e "$dest" ]; then
        echo "Creating symlink $dest -> $target"
        ln -s "$target" "$dest"
        git add "$dest"
    else
        echo "$dest already exists"
    fi
done

# META.in.json and Makefile are NOT in SETUP_FILES because users heavily customize them
safecp pgxntool/META.in.json META.in.json
safecreate Makefile include pgxntool/base.mk

make META.json
git add META.json

mkdir -p sql test/sql src
git status

echo "If you won't be creating C code then you can:

rmdir src

If everything looks good then

git commit -am 'Add pgxntool (https://github.com/Postgres-Extensions/pgxntool/tree/release)'"

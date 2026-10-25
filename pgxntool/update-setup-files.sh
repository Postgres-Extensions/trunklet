#!/usr/bin/env bash
#
# update-setup-files.sh - Update files that were initially copied by setup.sh
#
# This script handles the 3-way merge of setup files after a pgxntool subtree
# update. It compares the old pgxntool version, new pgxntool version, and
# user's current file to determine the appropriate action:
#
#   1. If pgxntool didn't change the file: skip (nothing to do)
#   2. If user hasn't modified the file: auto-update
#   3. If both changed: 3-way merge with conflict markers
#
# Usage: update-setup-files.sh <old-pgxntool-commit>
#
# The old commit is the pgxntool subtree commit BEFORE the sync.

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}"' ERR

PGXNTOOL_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$PGXNTOOL_DIR/lib.sh"

# SETUP_FILES and SETUP_SYMLINKS are defined in lib.sh

# =============================================================================
# Functions
# =============================================================================

usage() {
    echo "Usage: $0 <old-pgxntool-commit>"
    echo
    echo "Updates setup files after a pgxntool subtree sync."
    echo
    echo "Arguments:"
    echo "  old-pgxntool-commit  The pgxntool commit hash BEFORE the sync"
    exit 1
}

# Get file content from a specific commit
# Usage: get_old_content <commit> <path-in-pgxntool>
get_old_content() {
    local commit=$1
    local path=$2
    git show "${commit}:pgxntool/${path}" 2>/dev/null
}

# Get current file content from pgxntool directory
# Usage: get_new_content <path-in-pgxntool>
get_new_content() {
    local path=$1
    cat "pgxntool/${path}" 2>/dev/null
}

# Process a single setup file
# Usage: process_file <source> <dest> <old_commit>
process_file() {
    local source=$1
    local dest=$2
    local old_commit=$3

    # Get the three versions
    local old_content new_content user_content

    old_content=$(get_old_content "$old_commit" "$source") || {
        debug 20 "Could not get old version of $source (new file in pgxntool?)"
        old_content=""
    }

    new_content=$(get_new_content "$source") || {
        error "Could not read pgxntool/$source"
        return 1
    }

    # Check if destination exists
    if [[ ! -e "$dest" ]]; then
        echo "  $dest: creating (file was missing)"
        cp "pgxntool/$source" "$dest"
        return 0
    fi

    user_content=$(cat "$dest")

    # Step 1: Did pgxntool change this file?
    if [[ "$old_content" == "$new_content" ]]; then
        debug 30 "$dest: pgxntool unchanged, skipping"
        return 0
    fi

    # Step 2: Did user modify their copy?
    if [[ "$user_content" == "$old_content" ]]; then
        echo "  $dest: updated (you hadn't modified it)"
        cp "pgxntool/$source" "$dest"
        return 0
    fi

    # Step 3: Both changed - need 3-way merge
    echo "  $dest: attempting 3-way merge..."

    # Create temp files for git merge-file
    local tmp_old tmp_new
    tmp_old=$(mktemp)
    tmp_new=$(mktemp)
    trap "rm -f '$tmp_old' '$tmp_new'" RETURN

    echo "$old_content" > "$tmp_old"
    echo "$new_content" > "$tmp_new"

    # git merge-file modifies the first file in place
    # Returns 0 on clean merge, >0 if conflicts (but still writes result)
    if git merge-file -L "yours" -L "old pgxntool" -L "new pgxntool" \
        "$dest" "$tmp_old" "$tmp_new"; then
        echo "  $dest: merged cleanly (please review)"
    else
        echo "  $dest: CONFLICTS - resolve manually"
    fi
}

# Process a symlink
# Usage: process_symlink <dest> <target>
process_symlink() {
    local dest=$1
    local target=$2

    if [[ -L "$dest" ]]; then
        local current_target
        current_target=$(readlink "$dest")
        if [[ "$current_target" == "$target" ]]; then
            debug 30 "$dest: symlink unchanged"
        else
            echo "  $dest: symlink points to '$current_target', expected '$target'"
            echo "         (not auto-fixing - please check manually)"
        fi
    elif [[ -e "$dest" ]]; then
        echo "  $dest: exists but is not a symlink (expected symlink to $target)"
    else
        echo "  $dest: creating symlink to $target"
        ln -s "$target" "$dest"
    fi
}

# =============================================================================
# Main
# =============================================================================

[[ $# -eq 1 ]] || usage

old_commit=$1

# Verify we're in a git repo with pgxntool subtree.
# Use rev-parse, not [ -d .git ]: in a worktree .git is a file, not a directory.
[[ -d "pgxntool" ]] || die 1 "pgxntool directory not found. Run from project root."
git rev-parse --git-dir >/dev/null 2>&1 || die 1 "Not in a git repository."

# Verify the old commit is valid
if ! git cat-file -e "${old_commit}^{commit}" 2>/dev/null; then
    die 1 "Invalid commit: $old_commit"
fi

echo "Checking setup files for updates..."
echo

# Process regular files
for entry in "${SETUP_FILES[@]}"; do
    source="${entry%%:*}"
    dest="${entry##*:}"
    process_file "$source" "$dest" "$old_commit"
done

# Process symlinks
for entry in "${SETUP_SYMLINKS[@]}"; do
    dest="${entry%%:*}"
    target="${entry##*:}"
    process_symlink "$dest" "$target"
done

# Prune pgxntool's own dev-only dirs (.github/, .claude/) that the subtree pull
# re-introduces but that don't belong in a consuming project (see lib.sh).
prune_pgxntool_dev_dirs

echo
echo "Done. Review changes with 'git diff' and commit when ready."

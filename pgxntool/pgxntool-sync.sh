#!/usr/bin/env bash
#
# pgxntool-sync.sh - Pull the latest pgxntool via git subtree and reconcile setup files
#
# This performs the two steps needed to update pgxntool inside a project:
#
#   1. git subtree pull -P pgxntool ...   (update the embedded pgxntool copy)
#   2. update-setup-files.sh <old-commit> (3-way merge files setup.sh copied out,
#                                           like .gitignore and test/deps.sql)
#
# It is invoked by the `make pgxntool-sync` targets, but can also be run directly
# so you never need make to update pgxntool.
#
# Usage: pgxntool-sync.sh [<repo> [<ref>]]
#
#   repo  Git URL (or path) to pull pgxntool from. Defaults to the canonical
#         pgxntool repository.
#   ref   Branch, tag, or commit to pull. Defaults to the `release` tag, which
#         always points at the latest released version.
#
# Run from the root of your project (the directory containing pgxntool/).

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}"' ERR

PGXNTOOL_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$PGXNTOOL_DIR/lib.sh"

# Canonical source for pgxntool. `release` is a floating tag that the release
# process force-moves to each new version, so it always names the latest
# released version -- exactly what a plain sync should track.
DEFAULT_REPO="https://github.com/Postgres-Extensions/pgxntool.git"
DEFAULT_REF="release"

repo=${1:-$DEFAULT_REPO}
ref=${2:-$DEFAULT_REF}

# We must run from the project root: git subtree pull operates on the pgxntool/
# prefix and update-setup-files.sh resolves paths relative to the current dir.
[[ -d "pgxntool" ]] || die 1 "pgxntool directory not found. Run from your project root."
# Use rev-parse, not [ -d .git ]: in a worktree .git is a file, not a directory.
git rev-parse --git-dir >/dev/null 2>&1 || die 1 "Not in a git repository. Run from your project root."

# The old commit is the pgxntool subtree HEAD before the pull; update-setup-files.sh
# needs it as the merge base for files that were copied out of pgxntool.
old_commit=$(git log -1 --format=%H -- pgxntool/)

git subtree pull -P pgxntool --squash -m "Pull pgxntool from $repo $ref" "$repo" "$ref"

"$PGXNTOOL_DIR/update-setup-files.sh" "$old_commit"

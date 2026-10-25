#!/usr/bin/env bash
# pgxntool/run-test-build.sh - Prepare test/build/ for the test-build target
#
# Sets up the generated sql/ directory and ensures expected/*.out files exist
# so pg_regress can run without aborting on missing files.
#
# Usage: run-test-build.sh TESTDIR
#
# Called by the test-build target in base.mk before running installcheck.

set -e

TESTDIR="${1:?Usage: run-test-build.sh TESTDIR}"
BUILD_DIR="$TESTDIR/build"
SQL_DIR="$BUILD_DIR/sql"
EXPECTED_DIR="$BUILD_DIR/expected"

mkdir -p "$SQL_DIR"
mkdir -p "$EXPECTED_DIR"

# Verify .sql files exist. This script is only called when test-build is
# enabled, so missing files indicate a misconfiguration.
files=("$BUILD_DIR"/*.sql)
if [ ! -f "${files[0]}" ]; then
	echo "ERROR: no .sql files found in $BUILD_DIR/" >&2
	exit 1
fi

# Sync .sql files to sql/ directory for pg_regress.
# --checksum: compare by content, not size+mtime. rsync's default "quick check"
#   assumes equal size+mtime means files are identical, which isn't safe here —
#   builds can produce identical-sized files with different content. Checksum
#   comparison also avoids unnecessary writes that could trigger antivirus.
# --times: preserve source mtimes on destination files so make's dependency
#   tracking works correctly.
# --delete: remove files from sql/ that no longer exist in build/.
# --include/--exclude: select only *.sql from the directory source
#   (--delete requires a directory transfer, not individual file arguments).
rsync -r --checksum --times --delete --include='*.sql' --exclude='*' "$BUILD_DIR/" "$SQL_DIR/"

# Create empty expected/*.out files for .sql tests (if not already present).
# pg_regress requires an expected file to exist for each test; without it
# pg_regress stops immediately rather than running the test and showing the diff.
for file in "$BUILD_DIR"/*.sql; do
	out="$EXPECTED_DIR/$(basename "$file" .sql).out"
	[ -f "$out" ] || touch "$out"
done

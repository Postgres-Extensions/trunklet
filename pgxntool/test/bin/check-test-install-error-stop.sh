#!/usr/bin/env bash
#
# check-test-install-error-stop.sh - Ensure test/install/*.sql files deal
# with ON_ERROR_STOP
#
# A file fails only if it neither includes test/pgxntool/psql.sql (which sets
# ON_ERROR_STOP) nor has any `\set ON_ERROR_STOP` or `\unset ON_ERROR_STOP`
# command. A file that touches ON_ERROR_STOP at all, to any value, is assumed
# to know what it's doing.
#
# Why: test/install/*.sql files run in pg_regress's own self-comparing entry
# (see the test/install comments in base.mk), so there's no real diff. The
# only thing that still fails the build is psql exiting non-zero, which needs
# ON_ERROR_STOP; without it a hard SQL error is swallowed (issue #97).
#
# Usage: check-test-install-error-stop.sh <testdir>

set -o errexit -o errtrace -o pipefail

BASEDIR=$(dirname "$0")
source "$BASEDIR/../../lib.sh"

if [ $# -ne 1 ]; then
  die 1 "Usage: check-test-install-error-stop.sh <testdir>"
fi

testdir="$1"
install_dir="$testdir/install"
missing=()

# Succeeds if $1 includes psql.sql or sets/unsets ON_ERROR_STOP. Both patterns
# are anchored to line start so a SQL comment like `-- \set ON_ERROR_STOP on`
# doesn't count.
handles_error_stop() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^[[:space:]]*\\(include_relative|include|ir|i)[[:space:]]+.*psql\.sql ]] ||
       [[ "$line" =~ ^[[:space:]]*\\(un)?set[[:space:]]+ON_ERROR_STOP([[:space:]]|$) ]]; then
      return 0
    fi
  done < "$1"
  return 1
}

for f in "$install_dir"/*.sql; do
  [ -f "$f" ] || continue
  handles_error_stop "$f" || missing+=("$f: never sets ON_ERROR_STOP")
done

if [ "${#missing[@]}" -gt 0 ]; then
  error "the following test/install/*.sql files don't set ON_ERROR_STOP:"
  printf '  %s\n' "${missing[@]}" >&2
  error "test/install files run in their own self-comparing pg_regress entry" \
    "(see the test/install comments in base.mk) -- without ON_ERROR_STOP, a" \
    "hard SQL error is silently swallowed instead of failing the build."
  die 1 "Add '\\set ON_ERROR_STOP on' near the top of the file, or include" \
    "test/pgxntool/psql.sql (which sets it)."
fi

# vi: expandtab ts=2 sw=2

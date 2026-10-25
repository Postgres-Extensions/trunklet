#!/usr/bin/env bash
#
# check-stale-expected.sh - Catch orphaned/unexpected test/expected/ files
#
# test/expected/*.out must mirror test/sql/*.sql 1:1 (likewise
# test/build/expected/*.out vs test/build/*.sql, when test-build is in use).
# It's easy to leave a stale .out behind after renaming or removing a .sql
# file; this makes `make test` fail loudly instead of letting it linger
# unnoticed.
#
# test/install/ is NOT checked here: its expected output lives alongside the
# .sql files (test/install/foo.out), not in a separate expected/
# subdirectory, so there's no 1:1 directory mirror to compare.
#
# pg_regress supports up to 10 alternate expected-output files per test
# (test.out, test_0.out .. test_9.out - see get_alternative_expectfile() in
# pg_regress.c), tried in turn when the primary doesn't match. See the case
# block below for how that's recognized and the tradeoff involved.
#
# expected/ is also checked for files that aren't *.out at all -- there's no
# legitimate reason for anything else to live there (stray editor swap
# files, .orig files from a botched merge, etc.). This is a distinct
# failure class from an orphaned .out file: different message, different
# exit code (see below), and independently disable-able via
# PGXNTOOL_CHECK_EXPECTED_FILE_TYPES=no.
#
# Exit code is a bitmask so the two failure classes can be told apart:
#   1 - one or more orphaned .out files (no corresponding .sql)
#   2 - one or more unexpected non-.out files in expected/
#   3 - both
#
# Usage: check-stale-expected.sh <testdir> [check-file-types]
#        check-file-types: yes|no (default yes) -- controls the non-*.out
#        file check described above. Taken as a positional argument (rather
#        than an environment variable) so it's easy to vary directly in a
#        test loop instead of having to set/unset an env var around each
#        invocation.

set -o errexit -o errtrace -o pipefail

BASEDIR=$(dirname "$0")
source "$BASEDIR/../../lib.sh"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  die 1 "Usage: check-stale-expected.sh <testdir> [check-file-types]"
fi

testdir="$1"
failed=0

check_file_types=$(printf '%s' "${2:-yes}" | tr '[:upper:]' '[:lower:]')

# Usage: check_pair <sql_dir> <expected_dir>
check_pair() {
  local sqldir="$1" expdir="$2"
  local f base

  [ -d "$expdir" ] || return 0

  for f in "$expdir"/*; do
    # Without nullglob, this glob is left as the literal unexpanded pattern
    # string when $expdir has no entries at all; skip that non-existent
    # "file" rather than treating it as real input.
    [ -f "$f" ] || continue

    case "$f" in
      *.out)
        base=$(basename "$f" .out)
        case "$base" in
          # pg_regress supports up to 10 alternate expected-output files
          # per test (test.out, test_0.out .. test_9.out -- see
          # get_alternative_expectfile() in pg_regress.c), so a trailing
          # _N here doesn't necessarily mean an orphaned file. Recognizing
          # this is pure string matching -- it doesn't require checking
          # whether a file exists -- so the suffix is stripped unconditionally,
          # leaving exactly one existence check per file (below) rather than
          # one to recognize the pattern and a second to validate it.
          # Tradeoff: a real test literally named e.g. foo_1.sql (with no
          # foo.sql at all) would be misidentified as an alternate file for
          # a nonexistent "foo" and incorrectly flagged as stale. Accepted
          # as a vanishingly rare edge case.
          *_[0-9])
            base=${base%_*}
            ;;
        esac

        if [ ! -f "$sqldir/$base.sql" ]; then
          error "$f has no corresponding $sqldir/$base.sql"
          (( failed |= 1 ))
        fi
        ;;
      *)
        if [ "$check_file_types" = yes ]; then
          error "unexpected non-.out file in $expdir: $f"
          (( failed |= 2 ))
        fi
        ;;
    esac
  done
}

check_pair "$testdir/sql" "$testdir/expected"
check_pair "$testdir/build" "$testdir/build/expected"

exit "$failed"

# vi: expandtab ts=2 sw=2

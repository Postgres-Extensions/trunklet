#!/usr/bin/env bash
# pgxntool/verify-results-pgtap.sh - Check pgtap results before 'make results'
#
# Scans pgtap output files for failures and plan mismatches, then checks
# regression.diffs as a fallback, ignoring entries for tests that have no
# expected output yet. Exits non-zero if any problems are found.
#
# Usage: verify-results-pgtap.sh TESTOUT
#
# Called by the verify-results target in base.mk (pgtap mode).

set -e

TESTOUT="${1:?Usage: verify-results-pgtap.sh TESTOUT}"

# Check for pgtap failures in result files (excluding TODO items)
failed=0
for f in "$TESTOUT"/results/*.out; do
	[ -f "$f" ] || continue
	if grep -q '^not ok' "$f"; then
		notok=$(grep '^not ok' "$f" | grep -v '# TODO' || true)
		if [ -n "$notok" ]; then
			echo "ERROR: pgtap failure detected in $f"
			echo "$notok"
			failed=1
		fi
	fi
	if grep -q 'Looks like you planned' "$f"; then
		echo "ERROR: pgtap plan mismatch in $f"
		grep 'Looks like you planned' "$f"
		failed=1
	fi
done
if [ $failed -ne 0 ]; then
	echo
	echo "pgtap failures detected. Cannot run 'make results'."
	exit 1
fi

# Also check regression.diffs (output mismatch even if pgtap all passed).
#
# A test whose output matched ANY of its expected files - including a
# pg_regress _N.out alternate - is left out of regression.diffs entirely, so
# every block in here is a test that matched none of them. The one exception
# is a test that has no expected output yet: pg_regress aborts outright on a
# missing expected file, so base.mk touches an empty test/expected/<name>.out
# for every test/sql/*.sql lacking one, and diffing actual output against that
# placeholder always reports a difference. Blocking on that is unwinnable -
# seeding that first expected file is precisely what `make results` is for -
# so those blocks are skipped here.
diffs="$TESTOUT/regression.diffs"

# pg_regress truncates regression.diffs at startup and deletes it again on a
# clean finish with nothing to report, so an empty one means it died before
# comparing anything - an unreachable server, an interrupt. Whatever is in
# results/ is then left over from some earlier run, and base.mk's `.IGNORE:
# installcheck` means `make results` gets here anyway, so blessing it would
# bless stale output.
if [ -e "$diffs" ] && [ ! -s "$diffs" ]; then
	echo "ERROR: pg_regress did not complete. Cannot run 'make results'."
	echo "$diffs is empty, so nothing was actually compared;"
	echo "anything in $TESTOUT/results/ is left over from an earlier run."
	exit 1
fi

if [ -s "$diffs" ]; then
	# pg_regress heads each block with "diff <opts> <expected> <results>" (see
	# results_differ() in pg_regress.c), then appends the diff itself. Only
	# those headers and diff hunk headers can start with "diff " or "@@ "
	# unprefixed; every line carrying file content is prefixed with ' ', '+',
	# '-' or '\'. A block whose hunks all read "@@ -0,0 +N,M @@" was diffed
	# against an empty expected file, i.e. that placeholder. Anything that
	# fits none of those shapes is something this has no business
	# interpreting, so it blocks the whole file.
	#
	# Hunk headers only exist in unified diffs. PostgreSQL 12 was the first
	# to write them (11 and older use -C3 context diffs), so on those every
	# block lands in the blocked pile - the same refusal `make results` gave
	# before any of this existed.
	classified=$(awk '
		function flush(   status) {
			if (results == "") return
			status = (hunks > 0 && unblessed) ? "unblessed" : "regression"
			print status "\t" results
		}
		/^diff /   { flush(); results = $NF; unblessed = 1; hunks = 0; next }
		/^@@ /     { hunks++; if ($0 !~ /^@@ -0,0 /) unblessed = 0; next }
		/^[ +-]/   { next }
		/^\\/      { next }
		/^$/       { next }
		           { unrecognized = 1 }
		END        { flush(); if (unrecognized) print "unrecognized\t" FILENAME }
	' "$diffs")

	blocked=
	blessable=
	while IFS="$(printf '\t')" read -r status file; do
		case $status in
		unblessed)
			# An unblessed file holding a hard SQL error is not a passing test
			# the pgtap scan above was merely quiet about: ON_ERROR_STOP aborts
			# the script, so pgtap emits neither 'not ok' nor its plan-mismatch
			# line. Blessing that would make the error the baseline.
			#
			# pg_regress feeds psql on stdin, so a failing statement in the
			# test file itself reports as "ERROR:  ..." at column 0, while one
			# inside an \i'd file (setup.sql, finish.sql) reports as
			# "psql:test/pgxntool/setup.sql:3: ERROR:  ...". Matching either
			# position, and psql's own two spaces after the severity, keeps a
			# passing test whose description merely mentions "ERROR:" out of it.
			if [ -r "$file" ] && ! grep -qE '(^|: )ERROR:  ' "$file"; then
				blessable="$blessable  $file
"
				continue
			fi
			;;
		unrecognized)
			blocked="$blocked  (unrecognized content in $file)
"
			continue
			;;
		esac
		blocked="$blocked  $file
"
	done <<EOF
$classified
EOF

	# Nothing recognizable in a non-empty regression.diffs: refuse to guess.
	[ -n "$classified" ] || blocked="  (unrecognized $diffs content)
"

	if [ -n "$blocked" ]; then
		echo "ERROR: Tests are failing. Cannot run 'make results'."
		echo "Fix test failures first, then run 'make results'."
		echo
		echo "Failing tests:"
		printf '%s' "$blocked"
		echo
		echo "See $diffs for details:"
		cat "$diffs"
		exit 1
	fi

	echo "NOTE: these tests have no expected output yet; 'make results' will create it:"
	printf '%s' "$blessable"
fi

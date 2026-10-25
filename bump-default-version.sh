#!/usr/bin/env bash
#
# bump-default-version.sh - Set default_version in one or more .control files
#
# Usage: bump-default-version.sh <new_version> <control_file> [<control_file> ...]
#
# Rewrites each control file's default_version line to <new_version>, preserving
# everything else on that line (e.g. a trailing comment) and leaving the rest of
# the file untouched.

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}"' ERR

BASEDIR=$(dirname "${BASH_SOURCE[0]}")
source "$BASEDIR/lib.sh"

if [ $# -lt 2 ]; then
  die 1 "Usage: $0 <new_version> <control_file> [<control_file> ...]"
fi

new_version="$1"
shift
# C locale so the character ranges below mean ASCII.
export LC_ALL=C
case "$new_version" in
  ''|*[!A-Za-z0-9.-]*) die 1 "Invalid version '$new_version': must be non-empty and contain only letters, digits, '.' and '-'" ;;
esac

tmp_file=$(mktemp "${TMPDIR:-/tmp}/bump-default-version.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT

for control_file in "$@"; do
  [ -f "$control_file" ] || die 2 "Control file '$control_file' not found"

  # Same one-line-only requirement control.mk.sh enforces when reading
  # default_version -- keeps writing and reading in agreement about what a
  # valid control file looks like. grep -c exits 1 for zero matches (not an
  # error); 2+ is a real failure.
  grep_rc=0
  count=$(grep -cE "^[[:space:]]*default_version[[:space:]]*=" "$control_file" 2>"$tmp_file") || grep_rc=$?
  if [ "$grep_rc" -gt 1 ]; then
    die 2 "grep failed (exit $grep_rc) reading '$control_file': $(cat "$tmp_file")"
  fi
  if [ "$count" -ne 1 ]; then
    die 2 "Expected exactly one default_version line in '$control_file', found $count"
  fi

  # Both expressions keep the assignment prefix and anything after the value
  # (e.g. a trailing comment), and always re-quote with single quotes.
  #  1. Quoted value ('x' or "x").
  #  2. Bare value; can't re-match expression 1's output since it requires a
  #     non-quote first character.
  sed -E \
    -e "s/^([[:space:]]*default_version[[:space:]]*=[[:space:]]*)(['\"])[^'\"]*\\2/\\1'${new_version}'/" \
    -e "s/^([[:space:]]*default_version[[:space:]]*=[[:space:]]*)[^'\"[:space:]#][^[:space:]#]*/\\1'${new_version}'/" \
    "$control_file" > "$tmp_file"
  if ! grep -E "^[[:space:]]*default_version[[:space:]]*=" "$tmp_file" | grep -qF "'${new_version}'"; then
    die 2 "Could not rewrite the default_version line in '$control_file'"
  fi
  # Copy back into the existing file instead of mv-ing over it: mktemp
  # creates 0600, and mv would carry that mode onto the control file.
  cat "$tmp_file" > "$control_file"
  echo "Set default_version = '${new_version}' in $control_file"
done

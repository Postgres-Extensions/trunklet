#!/usr/bin/env bash
#
# meta.mk.sh - Generate Makefile variables from META.json
#
# This script parses META.json (PGXN distribution metadata) and generates
# Make variables for the distribution name and version.
#
# Usage: meta.mk.sh <META.json>
#
# Output (to stdout, meant to be redirected to meta.mk):
#   PGXN := <distribution_name>
#   PGXNVERSION := <distribution_version>
#
# Note: Extension-specific variables (like EXTENSION_*_VERSION) are generated
# by control.mk.sh from .control files, not from META.json. This is because
# META.json specifies PGXN distribution metadata, while .control files specify
# what PostgreSQL actually uses.

set -o errexit -o errtrace -o pipefail

BASEDIR=$(dirname "$0")
source "$BASEDIR/lib.sh"

JSON_SH=$BASEDIR/JSON.sh

trap 'error "Error on line ${LINENO}"' ERR

META=$1
if [ -z "$META" ]; then
  die 1 "Usage: meta.mk.sh <META.json>"
fi

if [ ! -f "$META" ]; then
  die 2 "META.json file '$META' not found"
fi

#function to get value of specified key
#returns empty string if not found
#warning - does not validate key format (supplied as parameter) in any way, simply returns empty string for malformed queries too
#usage: VAR=$(getkey foo.bar) #get value of "bar" contained within "foo"
#       VAR=$(getkey foo[4].bar) #get value of "bar" contained in the array "foo" on position 4
#       VAR=$(getkey [4].foo) #get value of "foo" contained in the root unnamed array on position 4
_getkey() {
    #reformat key string (parameter) to what JSON.sh uses
    KEYSTRING=$(sed -e 's/\[/\"\,/g' -e 's/^\"\,/\[/g' -e 's/\]\./\,\"/g' -e 's/\./\"\,\"/g' -e '/^\[/! s/^/\[\"/g' -e '/\]$/! s/$/\"\]/g' <<< "$@")
    #extract the key value
    FOUT=$(grep -F "$KEYSTRING" <<< "$JSON_PARSED")
    FOUT="${FOUT#*$'\t'}"
    FOUT="${FOUT#*\"}"
    FOUT="${FOUT%\"*}"
    echo "$FOUT"
}

getkey() {
  out=$(_getkey "$@")
  [ -n "$out" ] || die 2 "key $@ not found in $META"
  echo $out
}

JSON_PARSED=$(cat "$META" | $JSON_SH -l)

# Validate meta-spec version
spec_version=$(getkey meta-spec.version)
[ "$spec_version" == "1.0.0" ] || die 2 "Unknown meta-spec/version: $spec_version"

# Output distribution name and version
echo "PGXN := $(getkey name)"
echo "PGXNVERSION := $(getkey version)"

# vi: expandtab ts=2 sw=2

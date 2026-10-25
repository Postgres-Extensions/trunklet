#!/usr/bin/env bash

# Build META.json from META.in.json template
#
# WHY META.in.json EXISTS:
# META.in.json serves as a template that:
# 1. Shows all possible PGXN metadata fields (both required and optional) with comments
# 2. Can have empty placeholder fields like "key": "" or "key": [ "", "" ]
# 3. Users edit this to fill in their extension's metadata
#
# WHY WE GENERATE META.json:
# The reason we generate META.json from a template is to eliminate empty fields that
# are optional; PGXN.org gets upset about them. In the future it's possible we'll do
# more here (for example, if we added more info to the template we could use it to
# generate control files).
#
# WHY WE COMMIT META.json:
# PGXN.org requires META.json to be present in submitted distributions. We choose
# to commit it to git instead of manually adding it to distributions for simplicity
# (and since it generally only changes once for each new version).

set -e

BASEDIR=$(dirname "$0")
source "$BASEDIR/lib.sh"

[ $# -eq 2 ] || die 2 Invalid number of arguments $#

in=$1
out=$2

# Ensure we can safely rewrite the file
[ `head -n1 $in` == '{' ] || die 2 First line of $in must be '{'

cat << _PRE_ > $out
{
    "X_WARNING": "AUTO-GENERATED FILE, DO NOT MODIFY!",
    "X_WARNING": "Generated from $in by $0",

_PRE_

# Pattern is meant to match ': "" ,' or ': [ "", ' where spaces are optional.
# This is to strip things like '"key": "",' and '"key": [ "", "" ]'.
#
# NOTE! We intentionally don't match ': ""', to support '"X_end": ""'
tail -n +2 $in | egrep -v ':\s*(\[\s*)?""\s*,' >> $out

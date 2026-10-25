#!/usr/bin/env bash
#
# control.mk.sh - Generate Makefile rules from PostgreSQL extension control files
#
# This script parses .control files to extract extension metadata (particularly
# default_version) and generates Make variables and rules for building versioned
# SQL files.
#
# Usage: control.mk.sh <control_file> [<control_file> ...]
#
# Output (to stdout, meant to be redirected to control.mk):
#   EXTENSIONS += <ext_name>
#   EXTENSION_SQL_FILES += sql/<ext_name>.sql
#   EXTENSION_<ext_name>_VERSION := <version>
#   EXTENSION_<ext_name>_VERSION_FILE = sql/<ext_name>--<version>.sql
#   EXTENSION__CURRENT_VERSION__FILES += $(EXTENSION_<ext_name>_VERSION_FILE)
#   <rules for generating versioned SQL files>
#
# Why control files instead of META.json?
#   META.json's "provides" section specifies versions for PGXN distribution metadata.
#   But PostgreSQL uses the control file's default_version to determine which
#   versioned SQL file to load. These can differ (e.g., PGXN distribution version
#   might be updated independently of extension version). Using the control file
#   ensures the generated SQL files match what PostgreSQL expects.

set -o errexit -o errtrace -o pipefail

BASEDIR=$(dirname "$0")
source "$BASEDIR/lib.sh"

# Extract default_version from a PostgreSQL extension control file
# Usage: get_control_default_version <control_file>
# Errors if:
#   - Control file doesn't exist
#   - default_version is not specified (pgxntool requires it)
#   - Multiple default_version lines exist
get_control_default_version() {
  local control_file="$1"

  if [ ! -f "$control_file" ]; then
    die 2 "Control file '$control_file' not found"
  fi

  # Count default_version lines
  local count
  count=$(grep -cE "^[[:space:]]*default_version[[:space:]]*=" "$control_file" 2>/dev/null) || count=0

  if [ "$count" -eq 0 ]; then
    die 2 "default_version not specified in '$control_file'. PostgreSQL allows extensions without a default_version, but pgxntool requires it to generate versioned SQL files."
  fi

  if [ "$count" -gt 1 ]; then
    die 2 "Multiple default_version lines found in '$control_file'. Control files must have exactly one default_version."
  fi

  # Extract the version value
  # Handles: default_version = '1.0', default_version = "1.0", trailing comments
  local version=$(grep -E "^[[:space:]]*default_version[[:space:]]*=" "$control_file" | \
    sed -e "s/^[^=]*=[[:space:]]*//" \
        -e "s/[[:space:]]*#.*//" \
        -e "s/^['\"]//;s/['\"]$//" )

  if [ -z "$version" ]; then
    die 2 "Could not parse default_version value from '$control_file'"
  fi

  echo "$version"
}

# Main: process each control file passed as argument
if [ $# -eq 0 ]; then
  die 1 "Usage: control.mk.sh <control_file> [<control_file> ...]"
fi

for control_file in "$@"; do
  ext=$(basename "$control_file" .control)
  version=$(get_control_default_version "$control_file")

  echo "EXTENSIONS += $ext"
  echo "EXTENSION_SQL_FILES += sql/${ext}.sql"
  echo "EXTENSION_${ext}_VERSION := ${version}"
  echo "EXTENSION_${ext}_VERSION_FILE	= sql/${ext}--\$(EXTENSION_${ext}_VERSION).sql"
  echo "EXTENSION__CURRENT_VERSION__FILES		+= \$(EXTENSION_${ext}_VERSION_FILE)"
  echo "\$(EXTENSION_${ext}_VERSION_FILE): sql/${ext}.sql ${control_file}"
  # Single redirect via a subshell, not `>` truncate followed by `>>` append:
  # if this rule ever runs twice in the same `make` invocation (e.g. reached
  # through two different dependency chains under parallel make), the `>>`
  # form doubles the file's content instead of overwriting it.
  echo "	@(echo '/* DO NOT EDIT - AUTO-GENERATED FILE */'; cat sql/${ext}.sql) > \$(EXTENSION_${ext}_VERSION_FILE)"
  echo
done

# vi: expandtab ts=2 sw=2

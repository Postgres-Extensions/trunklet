#!/usr/bin/env bash
#
# pgtle.sh - Generate pg_tle registration SQL for PostgreSQL extensions
#
# Part of pgxntool: https://github.com/Postgres-Extensions/pgxntool
#
# SYNOPSIS
#   pgtle.sh --extension EXTNAME [--pgtle-version VERSION]
#   pgtle.sh --get-dir VERSION
#   pgtle.sh --get-version
#   pgtle.sh --run
#
# DESCRIPTION
#   Generates pg_tle (Trusted Language Extensions) registration SQL from
#   a pgxntool-based PostgreSQL extension. Reads the extension's .control
#   file and SQL files, wrapping them for pg_tle deployment in managed
#   environments like AWS RDS and Aurora.
#
#   pg_tle enables extension installation without filesystem access by
#   storing extension code in database tables. This script converts
#   traditional PostgreSQL extensions into pg_tle-compatible SQL.
#
# OPTIONS
#   --extension NAME
#       Extension name (required). Must match a .control file basename
#       in the current directory.
#
#   --pgtle-version RANGE
#       Generate for one pg_tle version range only (optional).
#       Must be exactly one of: 1.0.0-1.4.0, 1.4.0-1.5.0, or 1.5.0+
#       A plain pg_tle version (e.g. 1.5.2) is rejected, with a hint naming
#       the range it falls in.
#       Default: Generate all supported versions
#
#   --get-dir VERSION
#       Returns the directory path for the given pg_tle version.
#       Format: VERSION is a version string like "1.5.2"
#       Output: Directory path like "pg_tle/1.5.0+", "pg_tle/1.4.0-1.5.0", or "pg_tle/1.0.0-1.4.0"
#       This option is used by make to determine which directory to use
#
#   --get-version
#       Returns the installed pg_tle version from the database.
#       Output: Version string like "1.5.2" or empty if not installed
#       Exit status: 0 if pg_tle is installed, 1 if not installed
#
#   --run
#       Runs the generated pg_tle registration SQL files. This option:
#       - Detects the installed pg_tle version from the database
#       - Determines the appropriate directory using --get-dir logic
#       - Executes all SQL files in that directory via psql
#       - Assumes PG* environment variables are configured for psql
#
# VERSION NOTATION
#   X.Y.Z+       Works on pg_tle >= X.Y.Z
#   X.Y.Z-A.B.C  Works on pg_tle >= X.Y.Z and < A.B.C
#
#   Note the boundary conditions:
#     1.5.0+       means >= 1.5.0 (includes 1.5.0)
#     1.4.0-1.5.0  means >= 1.4.0 and < 1.5.0 (excludes 1.5.0)
#     1.0.0-1.4.0  means >= 1.0.0 and < 1.4.0 (excludes 1.4.0)
#
# SUPPORTED VERSIONS
#   1.0.0-1.4.0  pg_tle 1.0.0 through 1.3.x (no uninstall function, no schema parameter)
#   1.4.0-1.5.0  pg_tle 1.4.0 through 1.4.x (has uninstall function, no schema parameter)
#   1.5.0+       pg_tle 1.5.0 and later (has uninstall function, schema parameter support)
#
# EXAMPLES
#   # Generate all versions (default)
#   pgtle.sh --extension myext
#
#   # Generate only for pg_tle 1.5+
#   pgtle.sh --extension myext --pgtle-version 1.5.0+
#
#   # Get directory for a specific pg_tle version
#   pgtle.sh --get-dir 1.5.2
#   # Output: pg_tle/1.5.0+
#
#   pgtle.sh --get-dir 1.4.2
#   # Output: pg_tle/1.4.0-1.5.0
#
#   # Get installed pg_tle version from database
#   pgtle.sh --get-version
#   # Output: 1.5.2 (or empty if not installed)
#
#   # Run generated pg_tle registration SQL files
#   pgtle.sh --run
#
# OUTPUT
#   Creates files in version-specific subdirectories:
#     pg_tle/1.0.0-1.4.0/{extension}.sql
#     pg_tle/1.4.0-1.5.0/{extension}.sql
#     pg_tle/1.5.0+/{extension}.sql
#
#   Each file contains:
#     - All versions of the extension
#     - All upgrade paths between versions
#     - Default version configuration
#     - Complete installation instructions
#
#   For --get-dir: Outputs the directory path to stdout.
#
#   For --get-version: Outputs the installed pg_tle version to stdout, or empty if not installed.
#
#   For --run: Executes SQL files and outputs progress messages to stderr.
#
# REQUIREMENTS
#   - Must run from extension directory (where .control files are)
#   - Extension must use only trusted languages (PL/pgSQL, SQL, PL/Perl, etc.)
#   - No C code (module_pathname not supported by pg_tle)
#   - Versioned SQL files must exist: sql/{ext}--{version}.sql
#
# EXIT STATUS
#   0   Success
#   1   Error (missing files, validation failure, C code detected, etc.)
#
# SEE ALSO
#   pgxntool/README.asc, "pg_tle Support" section - Complete user guide
#   https://github.com/aws/pg_tle - pg_tle documentation
#

set -eo pipefail

# Source common library functions (error, die, debug)
PGXNTOOL_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$PGXNTOOL_DIR/lib.sh"

# Constants
PGTLE_DELIMITER='$_pgtle_wrap_delimiter_$'
PGTLE_VERSIONS=("1.0.0-1.4.0" "1.4.0-1.5.0" "1.5.0+")

# Supported pg_tle version ranges and their capabilities
# Use a function instead of associative array for compatibility with bash < 4.0
get_pgtle_capability() {
    local version="$1"
    case "$version" in
        "1.0.0-1.4.0")
            echo "no_uninstall_no_schema"
            ;;
        "1.4.0-1.5.0")
            echo "has_uninstall_no_schema"
            ;;
        "1.5.0+")
            echo "has_uninstall_has_schema"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Global variables (populated from control file)
EXTENSION=""
DEFAULT_VERSION=""
COMMENT=""
REQUIRES=""
SCHEMA=""
MODULE_PATHNAME=""
VERSION_FILES=()
UPGRADE_FILES=()

debug 30 "Global arrays initialized: VERSION_FILES=${#VERSION_FILES[@]}, UPGRADE_FILES=${#UPGRADE_FILES[@]}"
PGTLE_VERSION=""  # Empty = generate all
GET_DIR_VERSION=""  # For --get-dir option

# Arrays (populated from SQL discovery)
VERSION_FILES=()
UPGRADE_FILES=()

# Parse and validate a version string
# Extracts numeric version (major.minor.patch) from version strings
# Handles versions with suffixes like "1.5.0alpha1", "2.0beta", "1.2.3dev"
# Returns: numeric version string (e.g., "1.5.0") or exits with error
parse_version() {
    local version="$1"

    if [ -z "$version" ]; then
        die 1 "Version string is empty"
    fi

    # Extract numeric version part (major.minor.patch)
    # Matches: 1.5.0, 1.5, 10.2.1alpha, 2.0beta1, etc.
    # Pattern: start of string, then digits, dot, digits, optionally (dot digits), then anything
    local numeric_version
    if [[ "$version" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        numeric_version="${BASH_REMATCH[1]}"
    else
        die 1 "Cannot parse version string: '$version'
       Expected format: major.minor[.patch][suffix]
       Examples: 1.5.0, 1.5, 2.0alpha1, 10.2.3dev"
    fi

    # Ensure we have at least major.minor (add .0 if needed)
    if [[ ! "$numeric_version" =~ \. ]]; then
        die 1 "Invalid version format: '$version' (need at least major.minor)"
    fi

    # If we only have major.minor, add .0 for patch
    if [[ ! "$numeric_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        numeric_version="${numeric_version}.0"
    fi

    echo "$numeric_version"
}

# Convert version string to comparable integer
# Takes a numeric version string (major.minor.patch) and converts to integer
# Example: "1.5.0" -> 1005000
# Encoding scheme: major * 1000000 + minor * 1000 + patch
# This limits each component to 0-999 to prevent overflow
version_to_number() {
    local version="$1"

    # Parse major.minor.patch
    local major minor patch
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
    else
        die 1 "version_to_number: Invalid numeric version format: '$version'"
    fi

    # Check for overflow in encoding scheme
    # Each component must be < 1000 to fit in the allocated space
    if [ "$major" -ge 1000 ]; then
        die 1 "version_to_number: Major version too large: $major (max 999)
       Version: $version"
    fi
    if [ "$minor" -ge 1000 ]; then
        die 1 "version_to_number: Minor version too large: $minor (max 999)
       Version: $version"
    fi
    if [ "$patch" -ge 1000 ]; then
        die 1 "version_to_number: Patch version too large: $patch (max 999)
       Version: $version"
    fi

    # Convert to comparable number: major * 1000000 + minor * 1000 + patch
    echo $(( major * 1000000 + minor * 1000 + patch ))
}

# Get directory for a given pg_tle version
# Takes a version string like "1.5.2" and returns the directory path
# Handles versions with suffixes (e.g., "1.5.0alpha1")
# Returns: "pg_tle/1.0.0-1.4.0", "pg_tle/1.4.0-1.5.0", or "pg_tle/1.5.0+"
get_version_dir() {
    local version="$1"

    if [ -z "$version" ]; then
        die 1 "Version required for --get-dir (got empty string)"
    fi

    # Parse and validate version
    local numeric_version
    numeric_version=$(parse_version "$version")

    # Check if the original version has a pre-release suffix
    # Pre-release versions (alpha, beta, rc, dev) are considered BEFORE the release
    # Example: 1.4.0alpha1 comes BEFORE 1.4.0, so it should use the 1.0.0-1.4.0 range
    local has_prerelease=0
    if [[ "$version" =~ (alpha|beta|rc|dev) ]]; then
        has_prerelease=1
    fi

    # Convert versions to comparable numbers
    local version_num
    local threshold_1_4_num
    local threshold_1_5_num
    version_num=$(version_to_number "$numeric_version")
    threshold_1_4_num=$(version_to_number "1.4.0")
    threshold_1_5_num=$(version_to_number "1.5.0")

    # Compare and return appropriate directory:
    # < 1.4.0 -> 1.0.0-1.4.0
    # >= 1.4.0 and < 1.5.0 -> 1.4.0-1.5.0
    # >= 1.5.0 -> 1.5.0+
    #
    # Special handling for pre-release versions:
    # If version equals a threshold but has a pre-release suffix, treat it as less than that threshold
    # Example: 1.4.0alpha1 is treated as < 1.4.0, so it uses 1.0.0-1.4.0
    if [ "$version_num" -lt "$threshold_1_4_num" ]; then
        echo "pg_tle/1.0.0-1.4.0"
    elif [ "$version_num" -eq "$threshold_1_4_num" ] && [ "$has_prerelease" -eq 1 ]; then
        # Pre-release of 1.4.0 is considered < 1.4.0
        echo "pg_tle/1.0.0-1.4.0"
    elif [ "$version_num" -lt "$threshold_1_5_num" ]; then
        echo "pg_tle/1.4.0-1.5.0"
    elif [ "$version_num" -eq "$threshold_1_5_num" ] && [ "$has_prerelease" -eq 1 ]; then
        # Pre-release of 1.5.0 is considered < 1.5.0
        echo "pg_tle/1.4.0-1.5.0"
    else
        echo "pg_tle/1.5.0+"
    fi
}

# Die unless $1 is exactly one of PGTLE_VERSIONS. If it parses as a plain
# pg_tle version instead, name the range --get-dir puts it in. --get-dir runs
# as a child process because get_version_dir relies on errexit to stop on a
# parse failure, and errexit is suspended inside an if condition.
validate_pgtle_range() {
    local range="$1"
    local r
    for r in "${PGTLE_VERSIONS[@]}"; do
        [ "$range" = "$r" ] && return 0
    done

    local msg="invalid pg_tle version range: '$range'
       Valid ranges: ${PGTLE_VERSIONS[*]}"
    local dir
    if dir=$("${BASH_SOURCE[0]}" --get-dir "$range" 2>/dev/null); then
        msg="$msg
       '$range' looks like a pg_tle version; did you mean ${dir#pg_tle/}?"
    fi
    die 1 "$msg"
}

# Get pg_tle version from installed extension
# Returns version string or empty if not installed
get_pgtle_version() {
    psql --no-psqlrc --tuples-only --no-align --command "SELECT extversion FROM pg_extension WHERE extname = 'pg_tle';" 2>/dev/null | tr -d '[:space:]' || echo ""
}

# Run pg_tle registration SQL files
# Detects installed pg_tle version and runs appropriate SQL files
run_pgtle_sql() {
    echo "Running pg_tle registration SQL files..." >&2
    
    # Get version from installed extension
    local pgtle_version=$(get_pgtle_version)
    if [ -z "$pgtle_version" ]; then
        die 1 "pg_tle extension is not installed
       Run 'CREATE EXTENSION pg_tle;' first, or use 'make check-pgtle' to verify"
    fi
    
    # Get directory for this version
    local pgtle_dir=$(get_version_dir "$pgtle_version")
    if [ -z "$pgtle_dir" ]; then
        die 1 "Failed to determine pg_tle directory for version $pgtle_version"
    fi
    
    echo "Using pg_tle files for version $pgtle_version (directory: $pgtle_dir)" >&2
    
    # Check if directory exists
    if [ ! -d "$pgtle_dir" ]; then
        die 1 "pg_tle directory $pgtle_dir does not exist
       Run 'make pgtle' first to generate files"
    fi
    
    # Run all SQL files in the directory
    local sql_file
    local found=0
    for sql_file in "$pgtle_dir"/*.sql; do
        if [ -f "$sql_file" ]; then
            found=1
            echo "Running $sql_file..." >&2
            psql --no-psqlrc -v ON_ERROR_STOP=1 --file="$sql_file" || exit 1
        fi
    done
    
    if [ "$found" -eq 0 ]; then
        die 1 "No SQL files found in $pgtle_dir
       Run 'make pgtle' first to generate files"
    fi
    
    echo "pg_tle registration complete" >&2
}

# Main logic
main() {
    # Handle --get-dir, --get-version, --test-function, and --run options first (early exit, before other validation)
    local args=("$@")
    local i=0
    while [ $i -lt ${#args[@]} ]; do
        if [ "${args[$i]}" = "--get-dir" ] && [ $((i+1)) -lt ${#args[@]} ]; then
            get_version_dir "${args[$((i+1))]}"
            exit 0
        elif [ "${args[$i]}" = "--get-version" ]; then
            local version=$(get_pgtle_version)
            if [ -n "$version" ]; then
                echo "$version"
                exit 0
            else
                exit 1
            fi
        elif [ "${args[$i]}" = "--test-function" ] && [ $((i+1)) -lt ${#args[@]} ]; then
            # Hidden option for testing internal functions
            # NOT a supported public interface - used only by the test suite
            # Usage: pgtle.sh --test-function FUNC_NAME [ARGS...]
            local func_name="${args[$((i+1))]}"
            shift $((i+2))  # Remove script name and --test-function and func_name

            # Check if function exists
            if ! declare -f "$func_name" >/dev/null 2>&1; then
                die 1 "Function '$func_name' does not exist"
            fi

            # Call the function with remaining arguments
            "$func_name" "${args[@]:$((i+2))}"
            exit $?
        elif [ "${args[$i]}" = "--run" ]; then
            run_pgtle_sql
            exit 0
        fi
        i=$((i+1))
    done
    
    # Parse other arguments
    parse_args "$@"
    
    validate_environment
    parse_control_file
    discover_sql_files

    if [ -z "$PGTLE_VERSION" ]; then
        # Generate all versions
        for version in "${PGTLE_VERSIONS[@]}"; do
            generate_pgtle_sql "$version"
        done
    else
        # Generate specific version
        generate_pgtle_sql "$PGTLE_VERSION"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --extension)
                EXTENSION="$2"
                shift 2
                ;;
            --pgtle-version)
                validate_pgtle_range "$2"
                PGTLE_VERSION="$2"
                shift 2
                ;;
            --get-dir) # This case should ideally not be hit due to early exit
                GET_DIR_VERSION="$2"
                shift 2
                ;;
            --get-version) # This case should ideally not be hit due to early exit
                shift
                ;;
            --test-function) # Hidden option for testing - not documented, not supported
                shift 2  # Skip function name and --test-function
                ;;
            --run) # This case should ideally not be hit due to early exit
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ -z "$EXTENSION" ] && [ -z "$GET_DIR_VERSION" ]; then
        die 1 "--extension is required (unless using --get-dir, --get-version, --test-function, or --run)"
    fi
}

validate_environment() {
    # Check if control file exists
    if [ ! -f "${EXTENSION}.control" ]; then
        die 1 "Control file not found: ${EXTENSION}.control
       Must run from extension directory"
    fi
}

parse_control_file() {
    local control_file="${EXTENSION}.control"

    echo "Parsing control file: $control_file" >&2

    # Parse key = value or key = 'value' format
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Extract key = value
        if [[ "$line" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Trim trailing comments and whitespace FIRST, then strip quotes.
            # Order matters: stripping quotes before removing comments leaves a rogue
            # trailing quote for values like 'version' # note. See issue #25.
            value="${value%%#*}"  # Remove trailing comments
            # Trim all trailing whitespace (spaces and tabs). The prior %% pattern with
            # a literal space only removed one character; multiple spaces or a tab before
            # the comment (e.g., 'value'   # note or 'value'$'\t'# note) would leave
            # stray whitespace that breaks the quote-strip below.
            if [[ "$value" =~ ^(.*[^[:space:]])[[:space:]]*$ ]]; then
                value="${BASH_REMATCH[1]}"
            else
                value=""
            fi

            # Strip quotes if present (both single and double)
            value="${value#\'}"
            value="${value%\'}"
            value="${value#\"}"
            value="${value%\"}"

            # Store in global variables
            case "$key" in
                default_version) DEFAULT_VERSION="$value" ;;
                comment) COMMENT="$value" ;;
                requires) REQUIRES="$value" ;;
                schema) SCHEMA="$value" ;;
                module_pathname) MODULE_PATHNAME="$value" ;;
            esac
        fi
    done < "$control_file"

    # Validate required fields
    if [ -z "$DEFAULT_VERSION" ]; then
        die 1 "Control file missing default_version"
    fi

    if [ -z "$COMMENT" ]; then
        echo "WARNING: Control file missing comment, using extension name" >&2
        COMMENT="$EXTENSION extension"
    fi

    # Warn about C code
    if [ -n "$MODULE_PATHNAME" ]; then
        cat >&2 <<-EOF
	WARNING: Extension uses module_pathname (C code)
	         pg_tle only supports trusted languages (PL/pgSQL, SQL, etc.)
	         Generated SQL will likely not work
	EOF
    fi

    echo "  default_version: $DEFAULT_VERSION" >&2
    echo "  comment: $COMMENT" >&2
    if [ -n "$REQUIRES" ]; then
        echo "  requires: $REQUIRES" >&2
    fi
    if [ -n "$SCHEMA" ]; then
        echo "  schema: $SCHEMA" >&2
    fi
}

discover_sql_files() {
    echo "Discovering SQL files for extension: $EXTENSION" >&2
    debug 30 "discover_sql_files: Starting discovery for extension: $EXTENSION"

    # Ensure default_version file exists and has content if base file exists
    # This handles the case where make all hasn't generated it yet, or it exists but is empty
    local default_version_file="sql/${EXTENSION}--${DEFAULT_VERSION}.sql"
    local base_file="sql/${EXTENSION}.sql"
    if [ -f "$base_file" ] && ([ ! -f "$default_version_file" ] || [ ! -s "$default_version_file" ]); then
        debug 40 "discover_sql_files: Creating default_version file from base file"
        cp "$base_file" "$default_version_file"
    fi

    # Find versioned files: sql/{ext}--{version}.sql
    # Use find to get proper null-delimited output, then filter out upgrade scripts
    VERSION_FILES=()  # Reset array
    debug 40 "discover_sql_files: Reset VERSION_FILES array"
    while IFS= read -r -d '' file; do
        local basename=$(basename "$file" .sql)
        local dash_count=$(echo "$basename" | grep -o -- "--" | wc -l | tr -d '[:space:]')
        # Skip upgrade scripts (they have 2 dashes)
        if [ "$dash_count" -ne 1 ]; then
            continue
        fi
        # Error on empty version files
        if [ ! -s "$file" ]; then
            die 1 "Empty version file found: $file"
        fi
        VERSION_FILES+=("$file")
    done < <(find sql/ -maxdepth 1 -name "${EXTENSION}--*.sql" -print0 2>/dev/null | sort -zV)

    # Find upgrade scripts: sql/{ext}--{ver1}--{ver2}.sql
    # These have TWO occurrences of "--" in the filename
    UPGRADE_FILES=()  # Reset array
    debug 40 "discover_sql_files: Reset UPGRADE_FILES array"
    while IFS= read -r -d '' file; do
        # Empty upgrade files are allowed (no-op upgrades)
        local basename=$(basename "$file" .sql)
        local dash_count=$(echo "$basename" | grep -o -- "--" | wc -l | tr -d '[:space:]')
        if [ "$dash_count" -eq 2 ]; then
            UPGRADE_FILES+=("$file")
        fi
    done < <(find sql/ -maxdepth 1 -name "${EXTENSION}--*--*.sql" -print0 2>/dev/null | sort -zV)

    if [ ${#VERSION_FILES[@]} -eq 0 ]; then
        die 1 "No versioned SQL files found for $EXTENSION
       Expected pattern: sql/${EXTENSION}--{version}.sql
       Run 'make' first to generate versioned files from sql/${EXTENSION}.sql"
    fi

    echo "  Found ${#VERSION_FILES[@]} version file(s):" >&2
    for f in "${VERSION_FILES[@]}"; do
        echo "    - $f" >&2
    done

    debug 40 "discover_sql_files: Checking UPGRADE_FILES array, count=${#UPGRADE_FILES[@]}"
    if array_not_empty "${#UPGRADE_FILES[@]}"; then
        echo "  Found ${#UPGRADE_FILES[@]} upgrade script(s):" >&2
        debug 30 "discover_sql_files: Iterating over ${#UPGRADE_FILES[@]} upgrade files"
        for f in "${UPGRADE_FILES[@]}"; do
            echo "    - $f" >&2
        done
    else
        debug 30 "discover_sql_files: No upgrade files found"
    fi
}

extract_version_from_filename() {
    local filename="$1"
    local basename=$(basename "$filename" .sql)

    # Match patterns:
    # - ext--1.0.0 → FROM_VERSION=1.0.0, TO_VERSION=""
    # - ext--1.0.0--2.0.0 → FROM_VERSION=1.0.0, TO_VERSION=2.0.0
    # - ext--stable → FROM_VERSION=stable, TO_VERSION="" (pg_tle treats
    #   versions as opaque strings; see check_valid_version_name() in
    #   pg_tle's tleextension.c, which only forbids empty strings, "--",
    #   and leading/trailing "-" — no numeric requirement)
    #
    # Each version segment is [^-]+(-[^-]+)* : one or more non-dash runs
    # joined by single dashes, so a segment can't be empty, start/end with
    # "-", or contain "--" (which is reserved as the FROM/TO delimiter).

    if [[ "$basename" =~ ^${EXTENSION}--([^-]+(-[^-]+)*)(--([^-]+(-[^-]+)*))?$ ]]; then
        FROM_VERSION="${BASH_REMATCH[1]}"
        TO_VERSION="${BASH_REMATCH[4]}"  # Empty for non-upgrade files
        return 0
    else
        die 1 "Cannot parse version from filename: $filename
       Expected format: ${EXTENSION}--{version}.sql or ${EXTENSION}--{ver1}--{ver2}.sql"
    fi
}

validate_delimiter() {
    local sql_file="$1"

    if grep -qF "$PGTLE_DELIMITER" "$sql_file"; then
        die 1 "SQL file contains reserved pg_tle delimiter: $sql_file
       Found: $PGTLE_DELIMITER
       This delimiter is used internally by pgtle.sh to wrap SQL content.
       You must modify your SQL to not contain this string. If this poses a
       serious problem, please open an issue at https://github.com/Postgres-Extensions/pgxntool/issues"
    fi
}

wrap_sql_content() {
    local sql_file="$1"

    validate_delimiter "$sql_file"

    # Output wrapped SQL with proper indentation
    # Empty files are valid (no-op upgrades)
    echo "  ${PGTLE_DELIMITER}"
    cat "$sql_file"
    echo "  ${PGTLE_DELIMITER}"
}

build_requires_array() {
    # Input: "plpgsql, other_ext, another"
    # Output: 'plpgsql', 'other_ext', 'another'

    # Split on comma, trim whitespace, quote each element
    REQUIRES_ARRAY=$(echo "$REQUIRES" | \
        sed 's/[[:space:]]*,[[:space:]]*/\n/g' | \
        sed "s/^[[:space:]]*//;s/[[:space:]]*$//" | \
        sed "s/^/'/;s/$/'/" | \
        paste -sd, -)
}

generate_header() {
    local pgtle_version="$1"
    local output_file="$2"
    local version_count=${#VERSION_FILES[@]}
    local upgrade_count=${#UPGRADE_FILES[@]}

    # Determine version compatibility message
    local compat_msg
    if [[ "$pgtle_version" == *"+"* ]]; then
        local base_version="${pgtle_version%+}"
        compat_msg="--     Works on pg_tle >= ${base_version}"
    else
        local min_version="${pgtle_version%-*}"
        local max_version="${pgtle_version#*-}"
        compat_msg="--     Works on pg_tle >= ${min_version} and < ${max_version}"
    fi

    cat <<EOF
/*
 * Generated by pgxntool/pgtle.sh
 * Extension: ${EXTENSION}
 * Target pg_tle version: ${pgtle_version}
 * Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
 *
 * This file contains complete pg_tle registration for ${EXTENSION}:
 *   - All versions: ${version_count} version(s)
 *   - Upgrade paths: ${upgrade_count} path(s)
 *   - Default version: ${DEFAULT_VERSION}
 *
 * Installation:
 *   Recommended: make run-pgtle
 *   (or: pgxntool/pgtle.sh --run)
 *
 *   This automatically detects your pg_tle version and runs the correct file.
 *
 *   Prerequisites:
 *   - pg_tle extension installed (CREATE EXTENSION pg_tle;)
 *   - pgtle_admin role (GRANT pgtle_admin TO your_username;)
 *
 *   After registration, create the extension:
 *      CREATE EXTENSION ${EXTENSION};
 *
 * Version compatibility:
 *   ${pgtle_version} means:
 *      ${compat_msg#--     }
 */

EOF
}

generate_install_extension() {
    local sql_file="$1"
    local capability="$2"

    # Extract version from filename (must be versioned file: sql/{ext}--{version}.sql)
    extract_version_from_filename "$sql_file"
    local version="$FROM_VERSION"

    echo "-- Install version $version"
    echo "SELECT pgtle.install_extension("
    echo "  '${EXTENSION}',"
    echo "  '${version}',"
    echo "  '${COMMENT}',"
    wrap_sql_content "$sql_file"

    # Build requires array
    if [ -n "$REQUIRES" ]; then
        build_requires_array
        echo "  , ARRAY[${REQUIRES_ARRAY}]"
    else
        echo "  , NULL"
    fi

    # Add schema parameter only for capability version 1.5.0+
    if [ "$capability" = "has_uninstall_has_schema" ]; then
        if [ -n "$SCHEMA" ]; then
            echo "  , '${SCHEMA}'  -- schema parameter (pg_tle 1.5.0+)"
        else
            echo "  , NULL  -- schema parameter (pg_tle 1.5.0+)"
        fi
    fi

    echo ");"
    echo
}

generate_install_extension_version_sql() {
    local sql_file="$1"

    extract_version_from_filename "$sql_file"
    local version="$FROM_VERSION"

    echo "-- Install version $version"
    echo "SELECT pgtle.install_extension_version_sql("
    echo "  '${EXTENSION}',"
    echo "  '${version}',"
    wrap_sql_content "$sql_file"
    echo ");"
    echo
}

generate_install_update_path() {
    local upgrade_file="$1"

    extract_version_from_filename "$upgrade_file"
    local from_ver="$FROM_VERSION"
    local to_ver="$TO_VERSION"

    echo "-- Upgrade path: $from_ver -> $to_ver"
    echo "SELECT pgtle.install_update_path("
    echo "  '${EXTENSION}',"
    echo "  '${from_ver}',"
    echo "  '${to_ver}',"
    wrap_sql_content "$upgrade_file"
    echo ");"
    echo
}

generate_pgtle_sql() {
    local pgtle_version="$1"
    debug 30 "generate_pgtle_sql: Starting for version $pgtle_version, extension $EXTENSION"
    
    # Get capability using function (compatible with bash < 4.0)
    local capability=$(get_pgtle_capability "$pgtle_version")
    local version_dir="pg_tle/${pgtle_version}"
    local output_file="${version_dir}/${EXTENSION}.sql"
    
    # Ensure arrays are initialized (defensive programming)
    # Arrays should already be initialized at top level, but ensure they exist
    debug 40 "generate_pgtle_sql: Checking array initialization"
    debug 30 "generate_pgtle_sql: VERSION_FILES is ${VERSION_FILES+set}, count=${#VERSION_FILES[@]}"
    debug 30 "generate_pgtle_sql: UPGRADE_FILES is ${UPGRADE_FILES+set}, count=${#UPGRADE_FILES[@]}"
    
    if [ -z "${VERSION_FILES+set}" ]; then
        echo "WARNING: VERSION_FILES not set, initializing" >&2
        VERSION_FILES=()
    fi
    if [ -z "${UPGRADE_FILES+set}" ]; then
        echo "WARNING: UPGRADE_FILES not set, initializing" >&2
        UPGRADE_FILES=()
    fi

    # Create version-specific output directory if needed
    mkdir -p "$version_dir"

    echo "Generating: $output_file (pg_tle $pgtle_version)" >&2

    # Generate SQL to file
    {
        generate_header "$pgtle_version" "$output_file"

        cat <<EOF
BEGIN;

EOF

        # Only include uninstall block for pg_tle 1.4.0+ (versions with uninstall support)
        if [ "$capability" != "no_uninstall_no_schema" ]; then
            cat <<EOF
/*
 * Uninstall extension if it exists (idempotent registration)
 * Silently ignore if extension not found
 */
DO \$\$
BEGIN
    PERFORM pgtle.uninstall_extension('${EXTENSION}');
EXCEPTION
    WHEN no_data_found THEN
        -- Extension not registered yet (pg_tle raises P0002, not 42704)
        NULL;
END
\$\$;

EOF
        fi

        # Install base version (first version file)
        if array_not_empty "${#VERSION_FILES[@]}"; then
            generate_install_extension "${VERSION_FILES[0]}" "$capability"
        fi

        # Install additional versions (remaining version files)
        if [ ${#VERSION_FILES[@]} -gt 1 ]; then
            for version_file in "${VERSION_FILES[@]:1}"; do
                generate_install_extension_version_sql "$version_file"
            done
        fi

        # Install all upgrade paths
        local upgrade_count=${#UPGRADE_FILES[@]}
        debug 40 "generate_pgtle_sql: upgrade_count=$upgrade_count"
        if [ "$upgrade_count" -gt 0 ]; then
            debug 30 "generate_pgtle_sql: Processing $upgrade_count upgrade path(s)"
            local i=0
            while [ "$i" -lt "$upgrade_count" ]; do
                debug 50 "generate_pgtle_sql: Processing upgrade file $i: ${UPGRADE_FILES[$i]}"
                generate_install_update_path "${UPGRADE_FILES[$i]}"
                i=$((i + 1))
            done
        else
            debug 30 "generate_pgtle_sql: No upgrade paths to process"
        fi

        cat <<EOF
-- Set default version
SELECT pgtle.set_default_version('${EXTENSION}', '${DEFAULT_VERSION}');

COMMIT;
EOF
    } > "$output_file"

    echo "  ✓ Generated: $output_file" >&2
}

main "$@"


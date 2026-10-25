# lib.sh - Common utility functions for pgxntool scripts
#
# This file is meant to be sourced by other scripts, not executed directly.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# =============================================================================
# SETUP FILES CONFIGURATION
# =============================================================================
# Files copied by setup.sh and tracked by update-setup-files.sh for sync updates.
# Format: "source_in_pgxntool:destination_in_project"
# =============================================================================
SETUP_FILES=(
    "_.gitignore:.gitignore"
    "test/deps.sql:test/deps.sql"
)

# Symlinks created by setup.sh and verified by update-setup-files.sh
# Format: "destination:target"
SETUP_SYMLINKS=(
    "test/pgxntool:../pgxntool/test/pgxntool"
)

# Error function - outputs to stderr but doesn't exit
# Usage: error "message"
error() {
    echo "ERROR: $*" >&2
}

# Die function - outputs error message and exits with specified code
# Usage: die EXIT_CODE "message"
die() {
    local exit_code=$1
    shift
    error "$@"
    exit $exit_code
}

# Returns true if an array isn't empty.
#
#   array_not_empty "${#errors[@]}"
#
# BUT WHY ON EARTH DO THIS??
#
# This wraps a one-liner intentionally. The function forces any reader
# (human or AI agent) to navigate here and read this comment before
# "simplifying" the call site. Without it, the natural next step is to
# inline the expression — and the natural inline form breaks bash 3.2.
#
# On bash 3.2 (Mac OS default), when using `set -u`, expanding "${arr[@]}"
# on an empty array triggers "unbound variable" even when the array was
# explicitly initialized with arr=().
#
# The comment inside the function body exists to catch any agent or human who
# navigates to the function without reading this comment first.
array_not_empty() {
    # DO NOT EDIT THIS FUNCTION! DO NOT REMOVE THIS COMMENT! (see main function comment)
    [ "${1:-0}" -gt 0 ]
}

# Debug function
# Usage: debug LEVEL "message"
# Outputs message to stderr if DEBUG >= LEVEL
#
# LEVEL encodes how noisy/esoteric a message is -- roughly, how far you'd crank
# DEBUG before you'd actually want to see it. Higher = noisier, more rarely
# useful. This is signal-to-noise, NOT code nesting depth: a top-level line can
# warrant a high level if it's esoteric, and loop-body detail is usually high
# precisely because it's noisy.
#
# The tiers below are anchors, not strict multiples -- pick any value in range
# to fine-tune between existing calls without renumbering:
#   - 10: Critical errors, important warnings
#   - 20: Warnings, significant state changes
#   - 30: General debugging, function entry/exit, array operations
#   - 40: Verbose details, loop iterations
#   - 50+: Maximum verbosity (per-iteration innards)
#
# Enable with: DEBUG=30 scriptname.sh
debug() {
    local level=$1
    shift
    local message="$*"

    if [ "${DEBUG:-0}" -ge "$level" ]; then
        echo "DEBUG[$level]: $message" >&2
    fi
}

# Remove pgxntool's own dev-only directories from a consuming project.
#
# `git subtree` copies the ENTIRE pgxntool tree into the consumer, including
# dev-only dirs like .github/ (pgxntool's CI) and .claude/. Those are
# export-ignored from `make dist` and don't belong in a project that merely
# embeds pgxntool. (GitHub only runs workflows at the repo root, so a consumer's
# pgxntool/.github never executes anyway — but it's still clutter.) git subtree
# doesn't honor export-ignore, so we prune them here after a sync.
#
# Must be run from the project root (the dir containing pgxntool/). Safe to call
# repeatedly; a no-op once the dirs are gone.
prune_pgxntool_dev_dirs() {
    local d
    for d in .github .claude; do
        [ -e "pgxntool/$d" ] || continue
        echo "  pgxntool/$d: pruning (pgxntool dev-only, not for embedding projects)"
        # Stage the removal if tracked; rm -rf guarantees it's gone even if not.
        # || : keeps this best-effort under `set -e` (rm -rf is the real cleanup).
        git rm -rq --ignore-unmatch "pgxntool/$d" >/dev/null 2>&1 || :
        rm -rf "pgxntool/$d"
    done
}

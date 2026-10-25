# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CI Monitoring After Every Push

**REQUIRED**: After every `git push`, immediately start a background task to
monitor the CI run for that push. If you pushed to both pgxntool and
pgxntool-test, start a background task for each repo — do not monitor them
sequentially.

The CI monitor lives in the pgxntool-test checkout: run
`bash ../pgxntool-test/.claude/skills/ci/scripts/monitor-ci.sh` (the `/ci`
skill). It monitors both repos and derives the owner from the current repo.
Pass the exact push SHA(s) as positional arguments when available (the
script takes `[repos] [branch] [sha_pgxntool_test] [sha_pgxntool]`, not a
`--commit` flag — see the `/ci` skill for exact usage) — `gh run list
--branch` has a race condition: if two pushes land close together on the
same branch, `--branch` may pick up the wrong run. An exact SHA targets
the push directly and avoids this.

## Scope of This File

**CLAUDE.md is for people USING pgxntool** — extension developers who have embedded
pgxntool into their project via `git subtree`. It documents the build system, available
commands, and how pgxntool works.

**If you are making changes to pgxntool itself**, stop — you are in the wrong place.
See `.claude/` in this directory for developer guidelines. More importantly, pgxntool
development must be done from the **pgxntool-test** repository, not from here. See the
`Development Workflow` section below.

Any agent working in an extension project should always defer to that project's own
CLAUDE.md and instructions over anything stated here.

Guidance that is about PostgreSQL itself rather than about pgxntool lives in
`CLAUDE-POSTGRES.md` instead, so that this file stays about pgxntool.

## Read `CLAUDE-POSTGRES.md`

**`CLAUDE-POSTGRES.md` (next to this file) contains rules you must follow.** The `@` line
below imports it where that is supported; read the file directly if it did not.

@CLAUDE-POSTGRES.md

## Git Commit Guidelines

**IMPORTANT**: When creating commit messages, do not attribute commits to yourself (Claude). Commit messages should reflect the work being done without AI attribution in the message body. The standard Co-Authored-By trailer is acceptable.

## Critical: What This Repo Actually Is

**pgxntool is NOT a standalone project.** It is a meta-framework that exists ONLY to be embedded into PostgreSQL extension projects via `git subtree`. This repo cannot be built, tested, or run directly.

**Think of it like this**: pgxntool is to PostgreSQL extensions what a Makefile template library is to C projects - it's infrastructure code that gets copied into other projects, not a project itself.

## Critical: Directory Purity - NO Temporary Files

**This directory contains ONLY files that get embedded into extension projects.** When extension developers run `git subtree add`, they pull the entire pgxntool directory into their project.

**ABSOLUTE RULE**: NO temporary files, scratch work, or development tools may be added to this directory.

**Examples of what NEVER belongs here:**
- Temporary files (scratch notes, test output, debugging artifacts)
- Development scripts or tools (these go in pgxntool-test/)
- Planning documents (PLAN-*.md files go in pgxntool-test/)
- Any file you wouldn't want in every extension project that uses pgxntool

**CLAUDE.md exception**: CLAUDE.md exists here for AI assistant guidance, but is excluded from distributions via `.gitattributes export-ignore`. Same with `.claude/` directory.

**Why this matters**: Any file you add here will be pulled into hundreds of extension projects via git subtree. Keep this directory lean and clean.

## Development Workflow: Work from pgxntool-test

**CRITICAL**: All development work on pgxntool should be done from the pgxntool-test repository, NOT from this repository.

**For complete development workflow documentation, see:**
https://github.com/Postgres-Extensions/pgxntool-test

## Two-Repository Development Pattern

This codebase uses a two-repository pattern:

1. **pgxntool/** (this repo) - The framework code that gets embedded into extension projects
2. **pgxntool-test** - The test harness that validates pgxntool functionality

**For development and testing workflow, see:**
https://github.com/Postgres-Extensions/pgxntool-test

## How Extension Developers Use pgxntool

Extension projects include pgxntool via git subtree:

```bash
git subtree add -P pgxntool --squash git@github.com:Postgres-Extensions/pgxntool.git release
pgxntool/setup.sh
```

After setup, their Makefile typically contains just:
```makefile
include pgxntool/base.mk
```

## Architecture: Two-Phase Build System

### Phase 1: Meta Generation (`build_meta.sh`)
- Processes `META.in.json` (template with placeholders/empty values)
- Strips lines with empty string values (this incidentally removes some, but not all, `X_comment` placeholder lines)
- Produces clean `META.json`

### Phase 2: Distribution Variable Extraction (`meta.mk.sh`)
- Parses `META.json` (PGXN distribution metadata)
- Generates `meta.mk` with Make variables:
  - `PGXN` - distribution name
  - `PGXNVERSION` - version number
- `base.mk` includes `meta.mk` via `-include`

### Phase 3: Extension Variable Extraction (`control.mk.sh`)
- Parses each `.control` file (what PostgreSQL actually uses), not `META.json`
- Generates `control.mk` with Make variables and rules:
  - `EXTENSIONS` - list of extensions provided
  - `EXTENSION_*_VERSION` - per-extension versions, from each `.control` file's `default_version`
  - `EXTENSION__CURRENT_VERSION__FILES` - the current/most-recent auto-generated versioned SQL file for each extension (not all version files)
  - Rules for generating versioned SQL files
- `base.mk` includes `control.mk` via `-include`

### The Magic of base.mk

`base.mk` provides a complete PGXS-based build system:
- Auto-detects extension SQL files in `sql/`
- Auto-detects C modules in `src/*.c`
- Auto-detects tests in `test/sql/*.sql`
- Auto-generates versioned extension files (`extension--version.sql`)
- Handles Asciidoc → HTML conversion
- Integrates with PGXN distribution format
- Manages git tagging and release packaging

## File Structure for Consumer Projects

Projects using pgxntool follow this layout:
```
project/
├── Makefile                    # include pgxntool/base.mk
├── META.in.json               # Template metadata (customize for your extension)
├── META.json                  # Auto-generated from META.in.json
├── extension.control          # Standard PostgreSQL control file
├── pgxntool/                  # This repo, embedded via git subtree
├── sql/
│   └── extension.sql          # Base extension SQL
├── src/                       # Optional C code (*.c files)
├── test/
│   ├── deps.sql              # Load extension and test dependencies
│   ├── sql/*.sql             # Test SQL files
│   └── expected/*.out        # Expected test outputs
└── doc/                       # Optional docs (*.adoc, *.asciidoc, *.asc)
```

## Commands for Extension Developers (End Users)

These are the commands extension developers use (documented for context):

```bash
make                    # Build extension (generates versioned SQL, docs)
make test              # Full test: testdeps → [test-build] → [install] → installcheck → safeguard checks → show diffs ([...] = when enabled; see Critical Testing Rules)
make results           # Run tests and update expected output files
make html              # Generate HTML from Asciidoc sources
make tag               # Create git tag for current META.json version
make dist              # Create PGXN .zip (auto-tags, places in ../)
make pgtle             # Generate pg_tle registration SQL (see pg_tle Support below)
make check-pgtle       # Check pg_tle installation and report version
make run-pgtle         # Register extensions with pg_tle in the database
make pgxntool-sync     # Update to latest pgxntool via git subtree pull
```

## Testing with pgxntool

### Critical Testing Rules

**NEVER use `make installcheck` directly**. Always use `make test` instead. The `make test` target ensures:
- Correct test dependency installation (`testdeps`, and `test-build` when enabled); `testdeps`' default `pgtap` prerequisite auto-installs pgtap via `pgxn install`, a no-op when `PGXNTOOL_ENABLE_PGXN_INSTALL=no`
- Extension is filesystem-installed before tests run (`install`), unless `PGXNTOOL_ENABLE_FS_INSTALL=no`
- Test comparison via `installcheck`, with diffs shown on failure
- Safeguard checks that fail the run: the stale-expected-file check (orphaned or non-`.out` files in `test/expected/`, run after `pg_regress`), and, when `test/install` is in use, the check that every `test/install/*.sql` file sets `ON_ERROR_STOP`

Note: `make test` intentionally does *not* depend on `clean` — depending on `clean` caused problems with incremental/watch-based builds (see `base.mk`). If your tests need a clean build to pass, that's a sign of a missing dependency elsewhere, not something to fix by adding `clean` back.

**Database Connection Requirement**: PostgreSQL must be running before executing `make test`. If you get connection errors (e.g., "could not connect to server"), stop and ask the user to start PostgreSQL.

**Claude Code MUST NEVER run `make results` or `make results-build`**. Both update test expected output files and require manual human verification of test changes before execution.

**Claude Code MUST NEVER modify files in `test/expected/` or `test/build/expected/`**. These are expected test outputs that define correct behavior and must only be updated through the `make results`/`make results-build` workflows.

The workflow is:
1. Human runs `make test` and examines diffs
2. Human manually verifies changes are correct
3. Human manually runs `make results` to update expected files

### Test Output Mechanics

pgxntool uses PostgreSQL's pg_regress test framework:
- **Actual test output**: Written to `test/results/` directory
- **Expected output**: Stored in `test/expected/` directory
- **Test comparison**: pg_regress compares actual vs expected and generates diffs; `make test` displays them
- **Updating expectations**: `make results` copies `test/results/` → `test/expected/`

When tests fail, examine the diff output carefully. The actual test output in `test/results/` shows what your code produced, while `test/expected/` shows what was expected.

**Exceptions to the above** -- `test-build` and `test/install` (both optional, see `README.asc`) don't follow the `test/results` vs `test/expected` model:

- **test-build** runs first, in its own separate `pg_regress` pass over `test/build/*.sql`, and gates the main suite: if it fails, `test/install`/`test/sql` never run at all. It does compare actual vs expected normally (`test/build/results/` vs `test/build/expected/`) -- use `make results-build` to refresh its expected output, not `make results`.
- **test/install** does NOT get a real diff at all: its actual output is written to the exact same file as its expected output, so a content difference can never fail the build, no matter what changed. The only thing that still fails the build is a hard SQL error, and only if the file has `ON_ERROR_STOP` set (directly, or via `\i test/pgxntool/psql.sql`) -- pgxntool checks for this by default, passing any file that includes `psql.sql` or has its own `\set`/`\unset ON_ERROR_STOP`, whatever the value. If a `test/install/*.sql` file is misbehaving, don't go looking for a diff; check whether it errored, and don't assume a stale-looking `.out` for it means anything.

## Key Implementation Details

### PostgreSQL Version Handling
- `MAJORVER` = version × 10 (e.g., 9.6 → 96, 13 → 130)
- Tests use `--load-language=plpgsql` for versions < 13
- Version detection via `pg_config --version`

### Test System (pg_regress based)
- Tests in `test/sql/*.sql`, outputs compared to `test/expected/*.out`
- Setup via `test/pgxntool/setup.sql` (loads pgTap and deps.sql)
- `.IGNORE: installcheck` allows `make test` to handle errors (show diffs, then exit with error status)
- `make results` updates expected outputs after test runs

### Document Generation
- Auto-detects `asciidoctor` or `asciidoc`
- Generates HTML from `*.adoc`, `*.asciidoc` and `*.asc` in `$(DOC_DIRS)`
- HTML required for `make dist`, optional for `make install`
- Template-based rules via `ASCIIDOC_template`

### Distribution Packaging
- `make dist` creates `../PGXN-VERSION.zip`
- Creates a git tag matching version, unless that tag already exists and points at HEAD (in which case tagging is skipped)
- Uses `git archive` to package
- Validates repo is clean before tagging

### Subtree Sync Support
- `make pgxntool-sync` pulls the latest release (the `release` tag) from the canonical repo
- `pgxntool/pgxntool-sync.sh [<repo> [<ref>]]` does the work and can be run without make
- `make pgxntool-sync-<name>` pulls from the `pgxntool-sync-<name>` variable (`<repo> <ref>`)
- Uses `git subtree pull --squash`, then `update-setup-files.sh` for a 3-way merge of copied files
- Requires clean repo (no uncommitted changes)

### pg_tle Support

pgxntool can generate pg_tle (Trusted Language Extensions) registration SQL for deploying extensions in AWS RDS/Aurora without filesystem access.

**Usage:** `make pgtle` or `make pgtle PGXNTOOL_PGTLE_VERSION=1.5.0+`

**Output:** `pg_tle/{version_range}/{extension}.sql`

**For version range details and API compatibility boundaries, see:** `pgtle_versions.md`

**Installation targets:**

- `make check-pgtle` - Checks if pg_tle is installed and reports the version. Reports the version from `pg_extension` if `CREATE EXTENSION pg_tle` has been run in the database. Errors if pg_tle is not available in the cluster. Assumes `PG*` environment variables are configured.

- `make run-pgtle` - Registers all extensions with pg_tle by executing the generated pg_tle registration SQL files. Requires pg_tle to already be installed in the target database (`CREATE EXTENSION pg_tle;`) -- it does not create the extension itself, and errors out telling you to run `make check-pgtle` if it's missing. Depends on `pgtle`, so it generates the SQL files first if needed. Assumes `PG*` environment variables are configured.

**Version notation:**
- `X.Y.Z+` means >= X.Y.Z
- `X.Y.Z-A.B.C` means >= X.Y.Z and < A.B.C (note boundary)

**Key implementation details:**
- Script: `pgxntool/pgtle.sh` (bash)
- Parses `.control` files for metadata (NOT META.json)
- Fixed delimiter: `$_pgtle_wrap_delimiter_$` (validated not in source)
- Each output file contains ALL versions and ALL upgrade paths
- Multi-extension support (multiple .control files)
- Output directory `pg_tle/` excluded from git
- Depends on `make all` to ensure versioned SQL files exist first
- Only processes versioned files (`sql/{ext}--{version}.sql`), not base files

**SQL file handling:**
- **Version files** (`sql/{ext}--{version}.sql`): Generated automatically by `make all` from base `sql/{ext}.sql` file
- **Upgrade scripts** (`sql/{ext}--{v1}--{v2}.sql`): Created manually by users when adding new extension versions
- The script ensures the default_version file exists if the base file exists (creates it from base file if missing)
- All version files and upgrade scripts are discovered and included in the generated pg_tle registration SQL

**Dependencies:**
Generated files depend on:
- Control file (metadata source)
- All SQL files (sql/{ext}--*.sql) - must run `make all` first
- Generator script itself

**Limitations:**
- No C code support (pg_tle requires trusted languages only)
- PostgreSQL 14.5+ required (pg_tle not available on earlier versions)

## Critical Gotchas

1. **Empty Variables**: If `DOCS` or `MODULES` is empty, base.mk sets to empty to prevent PGXS errors
2. **testdeps Pattern**: Never add recipes to `testdeps` - create separate target and make it a prerequisite
3. **META.json is Generated**: Always edit `META.in.json`, never `META.json` directly
4. **Control File Versions**: No automatic validation that `.control` matches `META.json` version
5. **PGXNTOOL_NO_PGXS_INCLUDE**: Setting this skips PGXS inclusion (for special scenarios)
6. **Distribution Placement**: `.zip` files go in parent directory (`../`) to avoid repo clutter
7. **Never hand-edit an old versioned SQL file**: `sql/{ext}--{version}.sql` is only auto-regenerated by `make` for the extension's *current* `default_version` (from its `.control` file — not `META.json`; see "PGXN Distributions vs. Extensions" in README.asc). Every other `sql/{ext}--{version}.sql` (any version that is no longer current) is a frozen historical record used to test update paths and PostgreSQL-version compatibility — editing one directly silently corrupts that record. If you need to change something after a version has shipped, bump the version and add a `sql/{ext}--{old}--{new}.sql` upgrade script instead; never edit `sql/{ext}--{old}.sql` in place. This applies even though the file carries a generic `DO NOT EDIT - AUTO-GENERATED FILE` header — that header doesn't distinguish "regenerated every build" (current version) from "generated once, now frozen" (every other version). See "Version-Specific SQL Files" in README.asc for the full reasoning, including when it's acceptable to not commit a given version's file at all, and why that should be a plain `rm` rather than a `.gitignore` entry.

## Scripts

Each script at the top level of this repository (pgxntool/) begins with a shebang followed by a short
header comment describing its purpose within the first ~10 lines — read that header
rather than relying on a hand-maintained list here, which would just go stale the same
way this section itself once did. Exception: trivial third-party or one-line utilities
may lack such a header.

## Related Repositories

- **pgxntool-test** - Test harness for validating pgxntool functionality: https://github.com/Postgres-Extensions/pgxntool-test
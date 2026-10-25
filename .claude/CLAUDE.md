# Claude Development Notes

This file contains guidance for Claude Code when working in this repository.
It is excluded from distributions via `.gitattributes export-ignore`.

@../../ai/CLAUDE.md

If that import didn't resolve (`../../ai/CLAUDE.md`, relative to this file,
doesn't exist locally — see https://github.com/Postgres-Extensions/ai),
clone it now per its own first instruction, then re-read it: run `git clone
https://github.com/Postgres-Extensions/ai.git ../ai` from this repo's root
(`pgxntool/`, not from inside `.claude/`) so `ai/` lands as a sibling of
`pgxntool/`.

Also see the `ai/` repo's `PR.md` (`../ai/PR.md` from this repo's root) for
cross-repo conventions not restated below (CI monitoring's general
principle, multi-session PR-ownership hygiene, executable-bit safety, shell
script standards, etc.). This repo pairs with **pgxntool-test**, so the
section below is a deliberate addition specific to that pairing, on top of
those general conventions.

## CI Monitoring After Every Push

Addition specific to this paired repo, on top of the general convention in
`../../ai/CLAUDE.md`: if you pushed to both pgxntool and pgxntool-test,
start a background task for each — do not monitor them sequentially.

## Naming: `PGXNTOOL_` Is API, `_PGXNTOOL_` Is Internal

- `PGXNTOOL_*` variables are user-facing override points: document them in
  README.asc and treat any change as an API change.
- `_PGXNTOOL_*` variables (and `_pgxntool_*` functions) are internal-only,
  including seams that exist so pgxntool-test can stub a script. Internal
  make targets likewise start with `_` (e.g. `_check-stale-expected`), which
  also keeps them out of `make list`.
- Internal variables that predate the convention (`TEST_DEPS`,
  `TEST_SQL_FILES`, `TEST_BUILD_*`, `REGRESS_DBNAME`, `MAJORVER`, `GE91`,
  ..., plus `PGXNTOOL_DIR`, which keeps its bare prefix) stay as they are,
  since consumers may reference them. Don't rename them; give every new
  internal variable the `_PGXNTOOL_` prefix.

pgxntool-test's `test/standard/make-variables.bats` checks every variable
base.mk defines against the classified list in its
`test/lib/pgxntool-variables.txt`, so adding a variable means classifying
it there.

## HISTORY.asc: Sorted Issue Numbers

The "Issues fixed in this release:" line in HISTORY.asc must list issue
numbers in ascending numeric order. Re-sort it whenever you add to it or
resolve a merge conflict in it, e.g. `#21, #55, #87, #90, #108, #115`.

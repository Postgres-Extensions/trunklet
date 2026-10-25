# pgxntool Development Guidelines

**THIS FILE IS FOR PGXNTOOL DEVELOPERS ONLY.**

If you are an extension developer using pgxntool in your project, this file does not
apply to you. See the top-level `CLAUDE.md` instead.

## Critical: Work from pgxntool-test, Not Here

**NEVER make changes to pgxntool directly from this repository.**

pgxntool development must be done from a checkout of **pgxntool-test**, which contains
the full test infrastructure. Working here directly means you cannot run tests, and
any changes you commit cannot be validated before merging.

**Correct workflow:**
1. Clone or use an existing checkout of `pgxntool-test`
2. Work in a worktree: both `pgxntool/` and `pgxntool-test/` will be siblings
3. Make changes to `pgxntool/` from within that pgxntool-test context
4. Run the test suite via `make test` in pgxntool-test before committing

**See:** https://github.com/Postgres-Extensions/pgxntool-test for the full development
workflow.

---

## Makefile Variable Assignment Rules

**RULE: Do not use `:=` (simply expanded) unless you have a specific need for immediate evaluation.**

Use `=` (recursively expanded) for standard variable assignments. Reserve `:=` for cases where the right-hand side must be evaluated exactly once at assignment time — for example, when assigning the result of a `$(call ...)` function that references the variable being set (which would cause infinite recursion with `=`).

When a variable must also override command-line values, combine `override` with `:=` — but only where `override` is genuinely needed.

## Debug Level Rules (lib.sh `debug` function)

`debug LEVEL "msg"` prints when `DEBUG >= LEVEL`. LEVEL encodes how noisy/esoteric a message is — how far you'd crank `DEBUG` before you'd want to see it — **not** code nesting depth. A top-level line can warrant a high level if it's esoteric, and loop-body detail is usually high precisely because it's noisy. Judge by signal-to-noise.

The tiers are anchors, not strict multiples of 10 — any value in range is fine, leaving room to fine-tune between existing calls without renumbering:

- **10**: Critical errors, important warnings
- **20**: Warnings, significant state changes
- **30**: General debugging, function entry/exit, array operations
- **40**: Verbose details, loop iterations
- **50+**: Maximum verbosity (per-iteration innards)

Note: The BATS test helper `debug` function (in `tests/lib/helpers.bash` in pgxntool-test) uses a separate 1–5 scale controlled by `$TESTDEBUG`. The two systems are independent.

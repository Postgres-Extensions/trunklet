# .github/workflows — CI Architecture

## Workflow files

- **`ci.yml`** — main CI for pgxntool pull requests. Runs `check-test-pr` (verifies
  the paired pgxntool-test PR's CI passed), then optionally runs `test` (only for the
  commit-with-no-tests path — see below).
- **`protect-label.yml`** — enforces that only maintainers with write access can apply
  or remove the `commit-with-no-tests` label.

## Normal CI flow (paired test PR exists)

When a pgxntool PR has a corresponding open PR in pgxntool-test with the same branch
name, the `check-test-pr` job polls (up to 20 minutes) for that test PR's CI to
complete and pass. If it passes, pgxntool CI passes — **no tests run here**. Tests run
exactly once, in pgxntool-test's own CI.

## commit-with-no-tests path

When a maintainer applies the `commit-with-no-tests` label (and no paired test PR
exists), the `test` job runs tests directly in pgxntool CI against pgxntool-test/master.
This is the rare exception, not the norm.

## Doc-only bypass

`check-test-pr` checks this first, before the paired-test-PR lookup or the
`commit-with-no-tests` label: if every changed file in the PR is pure
documentation (`*.md`, `*.asc`, `*.adoc`, `*.asciidoc`, anywhere including
under `.claude/`, but never under `.github/` — workflow definitions carry
real behavioral weight regardless of extension), it skips both the paired
branch requirement and the `test` job entirely. `claude-code-review.yml` is
a separate workflow gated by its own `if:` and always still runs.

## Cross-repo reusable workflow — tradeoffs and constraints

The `test` job calls a reusable workflow from pgxntool-test:
```yaml
uses: Postgres-Extensions/pgxntool-test/.github/workflows/run-tests.yml@<ref>
```

GitHub Actions requires the `uses:` ref to be a **static string** — expressions like
`${{ }}` are not supported in the repo/path portion or the `@ref` suffix in practice.

### The @branch → @master ref

While developing on a feature branch where pgxntool-test also has changes, this ref
is set to `@<branch>` so CI can find `run-tests.yml` before it lands on master.

**IMPORTANT**: This ref must be updated to `@master` before pgxntool merges. The
correct merge order is: **pgxntool-test merges first**, then update this ref to
`@master`, then pgxntool merges.

**For Claude**: Do NOT leave a `@<branch>` ref without explicit user approval. The
user merges directly from the PR page — there are no manual steps between merges.
See `.github/workflows/CLAUDE.md` in pgxntool-test for the full picture.

### Changes to run-tests.yml

`run-tests.yml` lives in pgxntool-test and is the single source of truth for all test
steps. If it changes, pgxntool's CI uses `@master` — so it won't see the new version
until pgxntool-test merges. This is acceptable because:
- Changes to `run-tests.yml` require a paired test PR (not commit-with-no-tests)
- When a paired test PR exists, pgxntool's `test` job is skipped anyway
- The two scenarios are mutually exclusive in practice

## Label name

The label `commit-with-no-tests` is defined as a const (`NO_TEST_LABEL`) in `ci.yml`
and as `LABEL` in `protect-label.yml`. The job-level `if:` condition in
`protect-label.yml` must also use the literal string (YAML can't reference JS consts)
— keep these in sync if the label name ever changes.

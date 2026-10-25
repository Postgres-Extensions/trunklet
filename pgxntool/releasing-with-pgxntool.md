# Release Process

Recommended checklist for releasing an extension built on pgxntool. This is
pgxntool's own release process, generalized for a standalone consumer — no
assumptions about which org you're in or what other tooling you have.

This checklist is still a work in progress; expect it to change.

There is no CI automation for PGXN publishing today: every release ends
with a manual upload to PGXN Manager.

## 1. Decide the version number

- pgxntool currently only directly supports version numbers made of
  digits and periods (e.g. `1.2.3`); that's all it's tested with.
- If your distribution provides more than one extension (`META.in.json`'s
  `provides` map has more than one entry — see README.asc's "PGXN
  Distributions vs. Extensions"), decide **per extension** whether that
  extension's own version moves too. The distribution version (top-level
  `META.in.json` `version`) always advances at every release regardless;
  an individual extension's `default_version` only moves if that extension
  actually changed.

## 2. Pre-release checks

- [ ] Working tree clean, on your default branch, in sync with your
      remote.
- [ ] Full test suite green. Prefer `make verify-results` over a plain
      `make test`/`make installcheck` — it inspects `test/regression.diffs`
      directly, which is the only reliably trustworthy gate (older pgxntool
      marks `installcheck` `.IGNORE`, so it can report success even when
      every test failed).
- [ ] Your changelog has something to release — a `STABLE` (or "unreleased
      changes") section with real content. If it's empty, there's nothing
      to release yet.
- [ ] Docs reflect what you're about to ship — nothing added, removed, or
      changed in this release that isn't documented.

## 3. Bump versions and update the changelog (one commit, on a branch)

- For each extension whose version is moving (see step 1): bump
  `default_version` in its `.control` file, run `make` to regenerate its
  versioned SQL file, and finish its
  `sql/<ext>--<last-released-version>--<new-version>.sql[.in]` update
  script — confirm `ALTER EXTENSION ... UPDATE` actually reaches the new
  version from the last one.
- Bump `META.in.json`'s top-level `version` (always) and each moving
  extension's `provides.<ext>.version` entry (leave an unmoved extension's
  entry alone). Never hand-edit `META.json` itself — regenerate it with
  `make META.json`.
- Reorder this release's changelog entries most-important-first: breaking
  changes, then non-breaking behavior changes, then new features, then
  bugfixes.
- If your changelog tracks closed issues in one line (e.g. `Fixes #1, #2,
  #3`), remember GitHub only auto-closes the *first* issue in a
  comma-separated line — close the rest by hand.
- Rename the changelog's top `STABLE` heading to the new version number.
- Commit all of the above together.

## 4. Verify

- [ ] `make verify-results` green.
- [ ] From a clean checkout (or a `git archive` of what you're about to
      tag): `make && make install` builds and installs cleanly, and
      `CREATE EXTENSION` reports the version you expect.

## 5. Open a PR, get it merged, wait for CI

Push the branch and open a PR against your default branch, same as any
other change. Don't push straight to master — that skips whatever CI your
repo relies on. Merge normally once CI is green.

## 6. Tag and build the distribution

Once the version-bump PR is merged and your local checkout has pulled that
merge in:

- `make tag` — creates a git tag from `META.json`'s version and pushes it
  to `origin`. If you release from a fork (so `origin` isn't the canonical
  repo), pass `PGXN_REMOTE=<canonical-remote-name>` to every target in this
  step instead.
- `make dist` — builds `../<dist-name>-<version>.zip` via `git archive` of
  that tag, so only committed files are included.
- `make post-tag-version-bump` — sets `default_version` to a placeholder
  (`stable` by default) so later `make` runs don't overwrite the versioned
  SQL file you just released. Commit the changed `.control` file(s).

## 7. Upload to PGXN (manual)

- [ ] Upload the zip at <https://manager.pgxn.org/>.
- [ ] Confirm it shows up at `https://pgxn.org/dist/<name>/` (indexing can
      take a few minutes).

## If something goes wrong

- CI fails on the release PR: fix and push again on the same branch —
  don't close it and open a new one.
- Wrong content tagged: `make forcetag` moves the tag (= `rmtag` + `tag`).
  Don't do this once the tag has been public a while — moving a published
  tag out from under people is disruptive.
- Tagged/uploaded, but `origin` turned out not to be the canonical remote:
  re-run with `PGXN_REMOTE=<canonical-remote-name>` — a tag pushed to a
  fork does nothing for PGXN.

---

See README.asc's "make targets" section (`tag`, `dist`, `results`) and
"Version-Specific SQL Files" for the full mechanics behind each step above.

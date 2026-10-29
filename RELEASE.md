# RELEASE.md (trunklet-specific notes)

Follow [`../ai/RELEASE.md`](https://github.com/Postgres-Extensions/ai/blob/main/RELEASE.md).

## Step 1: releases 0.0.1 through 0.3.3 are branches, not tags

Each of those releases is a branch on `origin` named exactly the version; the repo has no tags before the first `make tag` release. Where step 1 says to compare against the tag, compare against that version's branch tip instead.

`sql/trunklet--0.2.0.sql`, `sql/trunklet--0.2.1.sql` and `sql/trunklet--0.3.3.sql` were committed after those versions shipped, so step 1 will flag their late last-touch dates. That is the backfill exception it describes, not drift. Each matches `sql/trunklet.sql` on its version branch except that its script-level `SET` commands, including any settings set-back, are now `SET LOCAL` and commented as released with plain `SET`, and the 0.3.3 copy also adds pgxntool's `/* DO NOT EDIT - AUTO-GENERATED FILE */` header line. `sql/trunklet--0.2.1--0.3.0.sql` and `sql/trunklet--0.3.2--0.3.3.sql` were also edited after release, so step 1 will flag them too, and their content intentionally differs from what shipped: both have their `SET` commands (and `0.3.2--0.3.3`'s set-back) changed to `SET LOCAL` with a comment, and `0.3.2--0.3.3` additionally gains the `language__get()` debug-message function that its release branch lacks.

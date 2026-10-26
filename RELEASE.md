# RELEASE.md (trunklet-specific notes)

Follow [`../ai/RELEASE.md`](https://github.com/Postgres-Extensions/ai/blob/main/RELEASE.md). Only the exceptions below are specific to this repo.

## Step 1: releases 0.0.1 through 0.3.3 are branches, not tags

Each of those releases is a branch on `origin` named exactly the version; the repo has no tags before the first `make tag` release. Where step 1 says to compare against the tag, compare against that version's branch tip instead.

`sql/trunklet--0.2.0.sql` and `sql/trunklet--0.2.1.sql` were committed after those versions shipped, copied byte-for-byte from `sql/trunklet.sql` on the `0.2.0` and `0.2.1` branches. Their late last-touch date is the backfill exception step 1 describes, not drift.

/*
 * Installs trunklet once, committed, before the test/sql/ suite runs, so every
 * test file finds it already present (see pgxntool/README.asc's "test/install"
 * and "Update & Upgrade (U&U) Testing" sections). The mode comes from the
 * Makefile's TEST_LOAD_SOURCE / TEST_UPDATE_FROM via PGOPTIONS.
 *
 * This file's output is never compared against anything. Its \set ON_ERROR_STOP
 * makes psql exit non-zero on an error, which fails the run only on PG16+. On
 * PG 9.5-15 a failure surfaces only through the downstream tests.
 */
\set ON_ERROR_STOP on

-- Branches server-side because \if needs psql 10+
DO $body$
DECLARE
  -- No missing_ok: a setting that didn't propagate must fail here
  c_mode CONSTANT text := current_setting('trunklet.test_load_mode');
BEGIN
  IF c_mode = 'fresh' THEN
    CREATE EXTENSION trunklet;
  ELSIF c_mode = 'update' THEN
    EXECUTE format(
      'CREATE EXTENSION trunklet VERSION %L'
      , current_setting('trunklet.test_update_from')
    );
  ELSE
    RAISE EXCEPTION 'unknown trunklet.test_load_mode "%"', c_mode;
  END IF;
END
$body$;

-- Update mode only: update_with_data.sql does the ALTER EXTENSION UPDATE. Branches
-- server-side for the same reason as above.
SELECT CASE current_setting('trunklet.test_load_mode')
    WHEN 'update' THEN 'test/helpers/update_with_data.sql'
    ELSE '/dev/null'
  END AS update_script
\gset
\i :update_script

-- vi: expandtab ts=2 sw=2

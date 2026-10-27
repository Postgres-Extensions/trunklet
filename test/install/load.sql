/*
 * Installs trunklet once, committed, before the test/sql/ suite runs, so every
 * test file finds it already present (see pgxntool/README.asc's "test/install"
 * and "Update & Upgrade (U&U) Testing" sections). The mode comes from the
 * Makefile's TEST_LOAD_SOURCE / TEST_UPDATE_FROM via PGOPTIONS.
 *
 * This file's output is never compared against anything; an error has to abort
 * the run instead.
 */
\set ON_ERROR_STOP on

-- Saved to assert that installing leaves the caller's settings as it found them
SELECT set_config('trunklet.test_before_search_path', current_setting('search_path'), false)
  , set_config('trunklet.test_before_client_min_messages', current_setting('client_min_messages'), false)
;

-- Branches server-side rather than with psql's \if, which needs psql 10+
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

/*
 * Update mode runs ALTER EXTENSION UPDATE in this helper, with data stored
 * first. psql's \if needs psql 10+, so pick the file to \i instead.
 */
SELECT CASE current_setting('trunklet.test_load_mode')
    WHEN 'update' THEN 'test/helpers/update_with_data.sql'
    ELSE '/dev/null'
  END AS update_script
\gset
\i :update_script

DO $body$
BEGIN
  -- Update mode asserts this around ALTER EXTENSION UPDATE in its helper, after changing search_path
  IF current_setting('trunklet.test_load_mode') = 'fresh' THEN
    IF current_setting('search_path') IS DISTINCT FROM current_setting('trunklet.test_before_search_path') THEN
      RAISE EXCEPTION 'CREATE EXTENSION changed search_path from % to %'
        , current_setting('trunklet.test_before_search_path'), current_setting('search_path');
    END IF;
    IF current_setting('client_min_messages') IS DISTINCT FROM current_setting('trunklet.test_before_client_min_messages') THEN
      RAISE EXCEPTION 'CREATE EXTENSION changed client_min_messages from % to %'
        , current_setting('trunklet.test_before_client_min_messages'), current_setting('client_min_messages');
    END IF;
  END IF;
END
$body$;

DO $body$
DECLARE
  v_installed text;
  v_default text;
BEGIN
  IF current_setting('trunklet.test_load_mode') = 'update' THEN
    SELECT extversion INTO v_installed FROM pg_extension WHERE extname = 'trunklet';
    SELECT default_version INTO v_default FROM pg_available_extensions WHERE name = 'trunklet';
    IF v_installed IS DISTINCT FROM v_default THEN
      RAISE EXCEPTION 'trunklet is at version % after ALTER EXTENSION UPDATE, not default_version %'
        , v_installed, v_default
      ;
    END IF;
  END IF;
END
$body$;

-- vi: expandtab ts=2 sw=2

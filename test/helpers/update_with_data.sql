/*
 * Update mode's ALTER EXTENSION UPDATE, run by test/install/load.sql. Stores a
 * test language and templates under TEST_UPDATE_FROM, updates, checks the
 * version and that the templates still process, then removes them and leaves
 * nothing behind, so the suite's expected output matches fresh mode.
 */
CREATE SCHEMA _trunklet_test;
SET search_path = _trunklet_test;
\i test/helpers/language_factory.sql

-- Committed before the update, as stored data would be in production
CREATE TABLE seeded_template_ids AS SELECT get_test_templates() AS ids;

/*
 * An update script must leave the caller's settings as it found them. Reset
 * client_min_messages first: TEST_UPDATE_FROM's own install script may have left
 * it raised, which would hide an update script doing the same.
 */
SET client_min_messages = notice;
SELECT set_config('trunklet.test_before_search_path', current_setting('search_path'), false)
  , set_config('trunklet.test_before_client_min_messages', current_setting('client_min_messages'), false)
;

ALTER EXTENSION trunklet UPDATE;

DO $body$
BEGIN
  IF current_setting('search_path') IS DISTINCT FROM current_setting('trunklet.test_before_search_path') THEN
    RAISE EXCEPTION 'ALTER EXTENSION UPDATE changed search_path from % to %'
      , current_setting('trunklet.test_before_search_path'), current_setting('search_path');
  END IF;
  IF current_setting('client_min_messages') IS DISTINCT FROM current_setting('trunklet.test_before_client_min_messages') THEN
    RAISE EXCEPTION 'ALTER EXTENSION UPDATE changed client_min_messages from % to %'
      , current_setting('trunklet.test_before_client_min_messages'), current_setting('client_min_messages');
  END IF;
END
$body$;

DO $body$
DECLARE
  v_installed text;
  v_default text;
BEGIN
  SELECT extversion INTO v_installed FROM pg_extension WHERE extname = 'trunklet';
  SELECT default_version INTO v_default FROM pg_available_extensions WHERE name = 'trunklet';
  IF v_installed IS DISTINCT FROM v_default THEN
    RAISE EXCEPTION 'trunklet is at version % after ALTER EXTENSION UPDATE, not default_version %'
      , v_installed, v_default
    ;
  END IF;
END
$body$;

-- Updating from before 0.3.0 changes search_path, so qualify from here on

DO $body$
DECLARE
  c_ids CONSTANT int[] := (SELECT ids FROM seeded_template_ids);
  c_parameters CONSTANT text[] := '{}';
  r record;
BEGIN
  -- get_test_templates() stores 'test <version>' as versions 1 and 2 of 'test template'
  FOR r IN
    SELECT format('process(%L, %s, ...)', 'test template', template_version) AS call
        , trunklet.process('test template'::text, template_version, c_parameters) AS actual
        , 'test ' || template_version AS expected
      FROM generate_series(1, 2) template_version
    UNION ALL
    SELECT format('process(template_id %s, ...)', c_ids[template_version])
        , trunklet.process(c_ids[template_version], c_parameters)
        , 'test ' || template_version
      FROM generate_series(1, 2) template_version
  LOOP
    IF r.actual IS DISTINCT FROM r.expected THEN
      RAISE EXCEPTION 'trunklet.% returned %, expected %'
        , r.call, quote_nullable(r.actual), quote_literal(r.expected)
      ;
    END IF;
  END LOOP;
END
$body$;

DO $body$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace = '_trunklet_functions'::regnamespace) THEN
    RAISE EXCEPTION 'no functions in schema _trunklet_functions before template_language__remove()';
  END IF;
END
$body$;

-- The language's functions were created by TEST_UPDATE_FROM's code
SELECT trunklet.template_language__remove(get_test_language_name(), cascade => true);

DO $body$
DECLARE
  c_functions CONSTANT text := (
    SELECT string_agg(oid::regprocedure::text, ', ')
      FROM pg_proc
      WHERE pronamespace = '_trunklet_functions'::regnamespace
  );
BEGIN
  IF c_functions IS NOT NULL THEN
    RAISE EXCEPTION 'template_language__remove() left functions in schema _trunklet_functions'
      USING DETAIL = c_functions
    ;
  END IF;
  IF EXISTS(SELECT 1 FROM _trunklet.language) OR EXISTS(SELECT 1 FROM _trunklet.template) THEN
    RAISE EXCEPTION 'template_language__remove() left rows in _trunklet.language or _trunklet.template';
  END IF;
END
$body$;

-- Back to the never-used state of a fresh install
SELECT setval(pg_get_serial_sequence('_trunklet.language', 'language_id'), 1, false)
  , setval(pg_get_serial_sequence('_trunklet.template', 'template_id'), 1, false)
;
DROP SCHEMA _trunklet_test CASCADE;
RESET search_path;

-- vi: expandtab ts=2 sw=2

\set ECHO none

\i test/helpers/psql.sql

BEGIN;
\i test/helpers/tap_setup.sql

SELECT plan(5);

-- Oldest committed install script; a language and template stored under it must survive the update chain.
CREATE EXTENSION trunklet VERSION '0.2.0';
-- 0.2.0's install script leaves search_path = pg_catalog
SET search_path = tap;
SELECT trunklet.template_language__add(
  'update_test'
  , 'text', 'text'
  , 'LANGUAGE sql', 'SELECT replace($1, ''X'', $2)'
  , 'LANGUAGE sql', 'SELECT $1'
);
SELECT trunklet.template__add('update_test', 'update_test_t', 'a X b');

ALTER EXTENSION trunklet UPDATE TO 'stable';
-- The update chain also leaves search_path altered
SET search_path = tap;
SELECT pass('update 0.2.0 -> stable');
SELECT is(
    trunklet.process('update_test_t', 'Y'::text)
    , 'a Y b'
    , 'stored template still processes after update'
);
SELECT is(
    trunklet.process(
      (SELECT template_id FROM _trunklet.template WHERE template_name = 'update_test_t')
      , 'Z'::text
    )
    , 'a Z b'
    , 'process(template_id, ...) exists after update'
);
SELECT has_function('trunklet', 'execute_text', ARRAY['text', 'anyelement']);
SELECT has_function('trunklet', 'execute_into', ARRAY['integer', 'anyelement']);

SELECT finish();
ROLLBACK;

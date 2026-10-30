\set ECHO none
--CREATE EXTENSION IF NOT EXISTS variant;

\i test/helpers/psql.sql

BEGIN;
SET LOCAL client_min_messages = warning;
SET LOCAL search_path = public, pg_temp;
-- Discards the set-back's set_config() result row, which depends on the server's default search_path
\o /dev/null
\i sql/trunklet.sql
\o
-- A bare \i is the only place the set-back is visible; it must restore the list, not one quoted name
\t on
SELECT current_setting('search_path');
\t off
ROLLBACK;

BEGIN;
\i test/helpers/tap_setup.sql
\i test/helpers/settings_snapshot.sql
SELECT plan(5);

SELECT lives_ok(
    $$SELECT pg_temp.settings_snapshot()$$
    , 'settings_snapshot() saved the caller''s settings'
);

SELECT lives_ok(
    'CREATE EXTENSION trunklet;'
    , 'CREATE EXTENSION trunklet;'
);

SELECT lives_ok(
    $$SELECT pg_temp.settings_check('CREATE EXTENSION')$$
    , 'CREATE EXTENSION changed no setting'
);
SELECT hasnt_schema('__trunklet');

SELECT lives_ok(
    'DROP EXTENSION trunklet;'
    , 'DROP EXTENSION trunklet;'
);

SELECT finish();
ROLLBACK;

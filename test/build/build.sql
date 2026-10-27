\set ECHO none
--CREATE EXTENSION IF NOT EXISTS variant;

\i test/helpers/psql.sql

BEGIN;
-- CREATE EXTENSION raises client_min_messages to warning during the script; \i doesn't, so set it here.
SET LOCAL client_min_messages = warning;
\i sql/trunklet.sql
ROLLBACK;

BEGIN;
\i test/helpers/tap_setup.sql

SELECT plan(4);

SELECT lives_ok(
    'CREATE EXTENSION trunklet;'
    , 'CREATE EXTENSION trunklet;'
);

SELECT isnt(
    current_setting('search_path')
    , 'pg_catalog'
    , 'Verify search_path is back to something sane after extension creation.'
);
SELECT hasnt_schema('__trunklet');

SELECT lives_ok(
    'DROP EXTENSION trunklet;'
    , 'DROP EXTENSION trunklet;'
);

SELECT finish();
ROLLBACK;

\set ECHO none
--CREATE EXTENSION IF NOT EXISTS variant;

\i test/helpers/psql.sql

BEGIN;
\i sql/trunklet.sql
ROLLBACK;

BEGIN;
\i test/helpers/tap_setup.sql
\i test/helpers/settings_snapshot.sql
SELECT pg_temp.settings_snapshot() AS snapshot \gset

SELECT plan(4);

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

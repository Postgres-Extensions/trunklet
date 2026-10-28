\set ECHO none
\i test/pgxntool/setup.sql

SELECT plan(
    0

    +1 -- no setting changed
);

-- Drop test/install/load.sql's committed install; this test's rollback restores it
DROP EXTENSION trunklet;

-- Start from a value the extension script could visibly change
SET client_min_messages = notice;

\i test/helpers/settings_snapshot.sql

SHOW search_path;

CREATE EXTENSION trunklet;-- CASCADE;

CREATE TEMP TABLE changed AS SELECT * FROM pg_temp.settings_changed;

-- Forcibly reset it so we know tap will work
SET search_path=public,tap;

SELECT is_empty(
  'SELECT * FROM pg_temp.changed'
  , 'CREATE EXTENSION did not change any user-settable setting'
);

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2

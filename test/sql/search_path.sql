\set ECHO none
\i test/pgxntool/setup.sql

SELECT plan(
    0

    +1 -- verify search_path
    +1 -- verify client_min_messages
);

-- Drop test/install/load.sql's committed install; this test's rollback restores it
DROP EXTENSION trunklet;

-- Start from a value the extension script could visibly change
SET client_min_messages = notice;

CREATE TEMP TABLE before AS
  SELECT name, setting FROM pg_settings WHERE name IN ('search_path', 'client_min_messages')
;

SHOW search_path;

CREATE EXTENSION trunklet;-- CASCADE;

CREATE TEMP TABLE after AS
  SELECT name, setting FROM pg_settings WHERE name IN ('search_path', 'client_min_messages')
;

-- Forcibly reset it so we know tap will work
SET search_path=public,tap;

SELECT is(
  (SELECT setting FROM after WHERE name = n)
  , (SELECT setting FROM before WHERE name = n)
  , 'verify ' || n || ' has not changed'
)
  FROM unnest(ARRAY['search_path', 'client_min_messages']) AS n
;

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2

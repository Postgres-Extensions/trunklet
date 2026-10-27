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
  SELECT current_setting('search_path') AS search_path
    , current_setting('client_min_messages') AS client_min_messages
;

SHOW search_path;

CREATE EXTENSION trunklet;-- CASCADE;

CREATE TEMP TABLE after AS
  SELECT current_setting('search_path') AS search_path
    , current_setting('client_min_messages') AS client_min_messages
;

-- Forcibly reset it so we know tap will work
SET search_path=public,tap;

SELECT is(
  (SELECT search_path FROM after)
  , (SELECT search_path FROM before)
  , 'verify search_path has not changed'
);

SELECT is(
  (SELECT client_min_messages FROM after)
  , (SELECT client_min_messages FROM before)
  , 'verify client_min_messages has not changed'
);

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2

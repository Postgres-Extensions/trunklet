\i test/pgxntool/psql.sql

SET client_min_messages = WARNING;

DO $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='tap') THEN
  CREATE SCHEMA tap;
END IF;
END$$;

SET search_path = tap, public;
CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA tap;
SET client_min_messages = NOTICE;
\pset format unaligned
\pset tuples_only true
\pset pager

-- vi: expandtab ts=2 sw=2

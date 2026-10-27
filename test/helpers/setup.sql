BEGIN;
\i test/helpers/tap_setup.sql
--CREATE EXTENSION IF NOT EXISTS variant;

-- trunklet itself is installed by test/install/load.sql

\i test/core/functions.sql

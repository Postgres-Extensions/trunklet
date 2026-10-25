-- IF NOT EXISTS will emit NOTICEs, which is annoying
SET client_min_messages = WARNING;

-- Add any test dependency statements here
-- Note: pgTap is loaded by setup.sql
--CREATE EXTENSION IF NOT EXISTS ...;
/*
 * Now load our extension. We don't use IF NOT EXISTs here because we want an
 * error if the extension is already loaded (because we want to ensure we're
 * getting the very latest version).
 */
CREATE EXTENSION ...;

-- Re-enable notices
SET client_min_messages = NOTICE;

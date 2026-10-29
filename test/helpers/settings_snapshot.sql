/*
 * pg_temp.settings_snapshot() records every user-settable setting (pg_settings
 * context 'user' or 'superuser', the only ones SET can change in-session),
 * replacing any earlier snapshot. pg_temp.settings_check(action) raises an
 * error naming action if any snapshotted setting has since changed or no longer
 * exists. Settings that first appear later are ignored, since loading a library
 * can define new ones.
 */
CREATE TEMP TABLE settings_before(name text PRIMARY KEY, setting text);

CREATE FUNCTION pg_temp.settings_snapshot() RETURNS void LANGUAGE sql AS $body$
DELETE FROM pg_temp.settings_before;
INSERT INTO pg_temp.settings_before
  SELECT name, setting FROM pg_catalog.pg_settings WHERE context IN ('user', 'superuser')
;
$body$;

CREATE FUNCTION pg_temp.settings_check(action text) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  c_changed CONSTANT text := (
    SELECT string_agg(format('%s: %L -> %L', b.name, b.setting, s.setting), ', ' ORDER BY b.name)
      FROM pg_temp.settings_before b
        LEFT JOIN pg_catalog.pg_settings s USING (name)
      WHERE s.setting IS DISTINCT FROM b.setting
  );
BEGIN
  IF c_changed IS NOT NULL THEN
    RAISE EXCEPTION '% changed settings', action
      USING DETAIL = c_changed
    ;
  END IF;
END
$body$;

-- vi: expandtab ts=2 sw=2

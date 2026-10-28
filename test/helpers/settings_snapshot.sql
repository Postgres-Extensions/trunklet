/*
 * Snapshots every user-settable setting (pg_settings context 'user' or
 * 'superuser', the only ones SET can change in-session) into
 * pg_temp.settings_before. pg_temp.settings_changed lists each snapshotted
 * setting whose current value differs, or that no longer exists; settings that
 * first appear later are ignored, since loading a library can define new ones.
 */
CREATE TEMP TABLE settings_before AS
  SELECT name, setting FROM pg_settings WHERE context IN ('user', 'superuser')
;

CREATE TEMP VIEW settings_changed AS
  SELECT b.name, b.setting AS before, s.setting AS after
    FROM pg_temp.settings_before b
      LEFT JOIN pg_settings s USING (name)
    WHERE s.setting IS DISTINCT FROM b.setting
;

-- vi: expandtab ts=2 sw=2

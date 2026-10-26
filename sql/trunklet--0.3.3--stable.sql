-- Also added to 0.3.2--0.3.3 (retroactively); this catches installs already at 0.3.3

CREATE OR REPLACE FUNCTION _trunklet.language__get(
  language_name _trunklet.language.language_name%TYPE
) RETURNS _trunklet.language STABLE LANGUAGE plpgsql AS $body$
DECLARE
  v_return _trunklet.language;
BEGIN
  RAISE DEBUG 'language__get(%)', language_name;
  SELECT * INTO STRICT v_return
    FROM _trunklet.language l
    WHERE l.language_name = language__get.language_name
  ;
  RETURN v_return;
EXCEPTION
  WHEN no_data_found THEN
    RAISE EXCEPTION 'language "%" not found', language_name
      USING ERRCODE = 'no_data_found'
    ;
END
$body$;

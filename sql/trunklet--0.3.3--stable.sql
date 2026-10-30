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

ALTER FUNCTION trunklet.template__add(character varying, text, integer, text) SET search_path = pg_catalog, pg_temp;
ALTER FUNCTION trunklet.template__remove(integer) SET search_path = pg_catalog, pg_temp;
ALTER FUNCTION trunklet.template__remove(text, integer) SET search_path = pg_catalog, pg_temp;
ALTER FUNCTION trunklet.process_language(character varying, text, anyelement) SET search_path = pg_catalog, pg_temp;
ALTER FUNCTION trunklet.process(integer, anyelement) SET search_path = pg_catalog, pg_temp;
ALTER FUNCTION trunklet.process(text, integer, anyelement) SET search_path = pg_catalog, pg_temp;
ALTER FUNCTION trunklet.extract_parameters(character varying, anyelement, text[]) SET search_path = pg_catalog, pg_temp;

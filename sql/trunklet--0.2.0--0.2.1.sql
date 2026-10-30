/*
 * Using temp objects will result in the extension being dropped after session
 * end. Create a real schema and then explicitly drop it instead.
 */
CREATE SCHEMA __trunklet;

CREATE TABLE __trunklet.old_settings AS
  SELECT name, setting
    FROM pg_catalog.pg_settings
    WHERE name IN ('search_path')
;
SET LOCAL search_path = pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION _trunklet.template__get(
  template_id _trunklet.template.template_id%TYPE
  , loose boolean DEFAULT false
) RETURNS _trunklet.template LANGUAGE plpgsql AS $body$
DECLARE
  r _trunklet.template;
BEGIN
  SELECT * INTO STRICT r
    FROM _trunklet.template t
    WHERE t.template_id = template__get.template_id
  ;

  RETURN r;
EXCEPTION
  WHEN no_data_found THEN
    IF loose THEN
      RETURN NULL;
    ELSE
      RAISE EXCEPTION 'template not found'
        USING ERRCODE = 'no_data_found'
          , DETAIL = format( 'template id %s', template_id )
      ;
    END IF;
END
$body$;
REVOKE ALL ON FUNCTION _trunklet.template__get(
  template_id _trunklet.template.template_id%TYPE
  , loose boolean
) FROM public;

CREATE OR REPLACE FUNCTION trunklet.process_language(
  language_name _trunklet.language.language_name%TYPE
  , template text
  , parameters anyelement
) RETURNS text LANGUAGE plpgsql

-- !!!!!!!
SECURITY DEFINER SET search_path = pg_catalog
-- !!!!!!!

AS $body$
DECLARE
/*
 * !!!!! SECURITY DEFINER !!!!!
 */

  r_language _trunklet.language;
  sql text;
  v_return text;
BEGIN
  -- Can't do this during DECLARE (0A000: default value for row or record variable is not supported)
  r_language := _trunklet.language__get( language_name );

/*
 * !!!!! SECURITY DEFINER !!!!!
 */
  PERFORM _trunklet.verify_type( language_name, r_language.template_type, pg_catalog.pg_typeof(template), 'template' );
  PERFORM _trunklet.verify_type( language_name, r_language.parameter_type, pg_catalog.pg_typeof(parameters), 'parameter' );

  sql := format(
    'SELECT _trunklet_functions.%s( CAST($1 AS %s), CAST($2 AS %s) )'
    , _trunklet.function_name( r_language.language_id, 'process' )
    , r_language.template_type
    , r_language.parameter_type
  );
  RAISE DEBUG E'execute %\nUSING %, %', sql, template, parameters;
  EXECUTE sql INTO STRICT v_return USING template, parameters;
  RAISE DEBUG '% returned %', sql, v_return;

  RETURN v_return;
END
$body$;

CREATE OR REPLACE FUNCTION trunklet.process(
  template_id _trunklet.template.template_id%TYPE
  , parameters anyelement
) RETURNS text LANGUAGE SQL
-- !!!
SECURITY DEFINER SET search_path = pg_catalog
-- !!!
AS $body$
SELECT trunklet.process_language(
      -- language_id comes from template__get() below
      (_trunklet.language__get(language_id)).language_name
      , template
      , parameters
    )
  FROM _trunklet.template__get( template_id )
$body$;
CREATE OR REPLACE FUNCTION trunklet.process(
  template_name _trunklet.template.template_name%TYPE
  , template_version _trunklet.template.template_version%TYPE
  , parameters anyelement
) RETURNS text LANGUAGE SQL
-- !!!
SECURITY DEFINER SET search_path = pg_catalog
-- !!!
AS $body$
SELECT trunklet.process_language(
      -- language_id comes from template__get() below
      (_trunklet.language__get(language_id)).language_name
      , template
      , parameters
    )
  FROM _trunklet.template__get( template_name, template_version )
$body$;
CREATE OR REPLACE FUNCTION trunklet.process(
  template_name _trunklet.template.template_name%TYPE
  , parameters anyelement
) RETURNS text LANGUAGE SQL AS $body$
SELECT trunklet.process( template_name, 1, parameters )
$body$;


/*
 * trunklet.execute_into()
 */
CREATE OR REPLACE FUNCTION trunklet.execute_into__language(
  language_name _trunklet.language.language_name%TYPE
  , template text
  , parameters anyelement
) RETURNS anyelement LANGUAGE plpgsql AS $body$
DECLARE
  sql CONSTANT text := trunklet.process_language(language_name, template, parameters);

  r record;
BEGIN
  -- Define the structure of r
  EXECUTE format('SELECT NULL::%s AS out', pg_typeof(parameters)) INTO STRICT r;

  RAISE DEBUG E'execute %', sql;
  EXECUTE sql INTO STRICT r.out;
  RAISE DEBUG '% returned %', sql, r.out;

  RETURN r.out;
END
$body$;
CREATE OR REPLACE FUNCTION trunklet.execute_into(
  template_id _trunklet.template.template_id%TYPE
  , parameters anyelement
) RETURNS anyelement LANGUAGE plpgsql AS $body$
DECLARE
  sql CONSTANT text := trunklet.process(template_id, parameters);

  r record;
BEGIN
  -- Define the structure of r
  EXECUTE format('SELECT NULL::%s AS out', pg_typeof(parameters)) INTO STRICT r;

  RAISE DEBUG E'execute %', sql;
  EXECUTE sql INTO STRICT r.out;
  RAISE DEBUG '% returned %', sql, r.out;

  RETURN r.out;
END
$body$;
CREATE OR REPLACE FUNCTION trunklet.execute_into(
  template_name _trunklet.template.template_name%TYPE
  , template_version _trunklet.template.template_version%TYPE
  , parameters anyelement
) RETURNS anyelement LANGUAGE plpgsql AS $body$
DECLARE
  sql CONSTANT text := trunklet.process(template_name, template_version, parameters);

  r record;
BEGIN
  -- Define the structure of r
  EXECUTE format('SELECT NULL::%s AS out', pg_typeof(parameters)) INTO STRICT r;

  RAISE DEBUG E'execute %', sql;
  EXECUTE sql INTO STRICT r.out;
  RAISE DEBUG '% returned %', sql, r.out;

  RETURN r.out;
END
$body$;
CREATE OR REPLACE FUNCTION trunklet.execute_into(
  template_name _trunklet.template.template_name%TYPE
  , parameters anyelement
) RETURNS anyelement LANGUAGE SQL AS $body$
SELECT trunklet.execute_into( template_name, 1, parameters )
$body$;





/*
 * trunklet.execute_text()
 */
CREATE OR REPLACE FUNCTION trunklet.execute_text__language(
  language_name _trunklet.language.language_name%TYPE
  , template text
  , parameters anyelement
) RETURNS text LANGUAGE plpgsql AS $body$
DECLARE
  sql CONSTANT text := trunklet.process_language(language_name, template, parameters);

  out text;
BEGIN
  RAISE DEBUG E'execute %', sql;
  EXECUTE sql INTO STRICT out;
  RAISE DEBUG '% returned %', sql, out;

  RETURN out;
END
$body$;
CREATE OR REPLACE FUNCTION trunklet.execute_text(
  template_id _trunklet.template.template_id%TYPE
  , parameters anyelement
) RETURNS anyelement LANGUAGE plpgsql AS $body$
DECLARE
  sql CONSTANT text := trunklet.process(template_id, parameters);

  out text;
BEGIN
  RAISE DEBUG E'execute %', sql;
  EXECUTE sql INTO STRICT out;
  RAISE DEBUG '% returned %', sql, out;

  RETURN out;
END
$body$;
CREATE OR REPLACE FUNCTION trunklet.execute_text(
  template_name _trunklet.template.template_name%TYPE
  , template_version _trunklet.template.template_version%TYPE
  , parameters anyelement
) RETURNS anyelement LANGUAGE plpgsql AS $body$
DECLARE
  sql CONSTANT text := trunklet.process(template_name, template_version, parameters);

  out text;
BEGIN
  RAISE DEBUG E'execute %', sql;
  EXECUTE sql INTO STRICT out;
  RAISE DEBUG '% returned %', sql, out;

  RETURN out;
END
$body$;
CREATE OR REPLACE FUNCTION trunklet.execute_text(
  template_name _trunklet.template.template_name%TYPE
  , parameters anyelement
) RETURNS anyelement LANGUAGE SQL AS $body$
SELECT trunklet.execute_text( template_name, 1, parameters )
$body$;





-- set_config() parses a list setting; SET LOCAL %I = %L would turn it into one quoted name
SELECT pg_catalog.set_config(name, setting, true)
  FROM __trunklet.old_settings
;
DROP TABLE __trunklet.old_settings;
DROP SCHEMA __trunklet;

-- vi: expandtab sw=2 ts=2

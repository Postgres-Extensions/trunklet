/*
 * LANGUAGE FACTORY: defines, in the first schema on search_path, functions that
 * create the test languages and templates on demand.
 *
 * test/helpers/update_with_data.sql also runs this under TEST_UPDATE_FROM, so
 * stick to the API of the oldest install script in sql/ (currently 0.2.0), and
 * don't use pgTAP.
 */
CREATE FUNCTION bogus_language_name(
) RETURNS text LANGUAGE sql AS $$SELECT 'bogus template language that does not exist'::text$$;
CREATE FUNCTION get_test_language_name(
  langtype text DEFAULT 'text'
) RETURNS text LANGUAGE sql AS $$SELECT format('Our internal %s test language', langtype)$$;
CREATE FUNCTION get_test_language_id(
) RETURNS int LANGUAGE plpgsql AS $body$
BEGIN
  BEGIN
    --SET LOCAL client_min_messages = debug;
  PERFORM trunklet.template_language__add(
      get_test_language_name()
      , parameter_type := 'text[]'
      , template_type := 'text'
      , process_function_options := 'LANGUAGE plpgsql'
      , process_function_body :=
$process$
DECLARE
  -- Convert parameters into a string of ', <parameter 1>, <parameter 2>, ...'
  v_args CONSTANT text := array_to_string(
    array(
      SELECT ', ' || quote_nullable(a)
        FROM unnest(parameters) a(a)
      )
    , ''
  );
  sql CONSTANT text := format( 'SELECT format( %L%s )', template, v_args );
  v_return text;
BEGIN
  RAISE DEBUG 'EXECUTE INTO using sql %', sql;
  EXECUTE sql INTO v_return;
  RETURN v_return;
END
$process$
      , extract_parameters_options := 'LANGUAGE sql'
      , extract_parameters_body :=
$extract$
SELECT array(
    SELECT parameters[i]
      FROM generate_subscripts( parameters, 1 ) i
      WHERE i = ANY( extract_list::int[] )
  )
$extract$
    );
  EXCEPTION
    -- TODO: incorrect return value
    WHEN no_data_found OR unique_violation THEN
      NULL;
  END;
  RETURN _trunklet.language__get_id( get_test_language_name() );
END
$body$;

CREATE FUNCTION get_json_language_id(
) RETURNS int LANGUAGE plpgsql AS $body$
BEGIN
  BEGIN
    --SET LOCAL client_min_messages = debug;
  PERFORM trunklet.template_language__add(
      get_test_language_name('json')
      , parameter_type := 'jsonb'
      , template_type := 'json'
      , process_function_options := 'LANGUAGE plpgsql'
      , process_function_body := $process$
DECLARE
  k text;
  v text;

  v_replace text;
  v_return text := template::text;
BEGIN
  FOR k,v IN
    SELECT key, parameters->>key FROM jsonb_object_keys(parameters) key
  LOOP
    v_replace := format('!%s!', k);
    RAISE DEBUG 'replacing all occurences of % with %', v_replace, v;
    v_return := replace( v_return, v_replace, v );
  END LOOP;
  RETURN v_return::json;
END
$process$
      , extract_parameters_options := 'LANGUAGE sql'
      , extract_parameters_body := $extract$
SELECT jsonb_object(keys, values) FROM (
    SELECT array_agg(k) AS keys, array_agg(parameters->>k) AS values
      FROM jsonb_object_keys(parameters) k
      WHERE k = ANY( extract_list )
  ) a
$extract$
    );
  EXCEPTION
    -- TODO: incorrect return value
    WHEN no_data_found OR unique_violation THEN
      NULL;
  END;
  RETURN _trunklet.language__get_id( get_test_language_name() );
END
$body$;

CREATE FUNCTION get_test_templates(
) RETURNS int[] LANGUAGE plpgsql AS $body$
DECLARE
  ids int[];
BEGIN
  -- Do this even if the test_templates table already exists
  PERFORM get_test_language_id();

  BEGIN
    SELECT ids INTO ids FROM test_templates;
  EXCEPTION
    WHEN undefined_table THEN
      ids[1] := trunklet.template__add( get_test_language_name(), 'test template', --any_to_trunklet_template
        ('test 1'::text) );
      ids[2] := trunklet.template__add( get_test_language_name(), 'test template', 2, --any_to_trunklet_template
        ('test 2'::text) );

      -- See also test_template__remove
      CREATE TEMP TABLE test_templates AS VALUES(ids);
  END;

  RETURN ids;
END
$body$;

-- vi: expandtab ts=2 sw=2

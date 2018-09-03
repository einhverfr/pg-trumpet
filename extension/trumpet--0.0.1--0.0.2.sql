CREATE OR REPLACE FUNCTION whole_table_to_sub(in_subname text, in_table_name regclass, in_column name)
returns subscribed_table LANGUAGE PLPGSQL STRICT AS
$$
declare metadata subscribed_table;
        sub subscription;
        funcname text;
        tname text;
begin
        select * from subscription into sub where subname = in_subname;
        funcname := 'trumpetrep.sub_' || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_whole' || '()';
        tname := 'trumpetrep.sub_' || sub.id::text || '_' || in_table_name::oid::text ;
        EXECUTE $E$ CREATE TABLE IF NOT EXISTS $E$ || tname || $E$(key int primary key)$E$;
        execute $E$ CREATE FUNCTION $E$ || funcname || $E$ RETURNS TRIGGER LANGUAGE PLPGSQL AS $F$
            BEGIN
                PERFORM * FROM $E$ || tname || $E$ WHERE key = new.$E$ || quote_ident(in_column) || $E$;
                IF NOT FOUND THEN INSERT INTO $E$ || tname || $E$ (key) VALUES (new.$E$|| quote_ident(in_column) || $E$); END IF;
                PERFORM pg_mq_send_message( $E$ || quote_literal(in_subname) || '::text,row(TG_RELID, NEW.' || quote_ident(in_column) || $E$)::trumpetrep.reptuple );
                RETURN NEW;
            END; $F$ $E$;
        EXECUTE $E$ CREATE TRIGGER sub_$E$ || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_whole' || $E$
                    AFTER INSERT OR UPDATE ON $E$ || in_table_name || $E$ FOR EACH ROW EXECUTE PROCEDURE $E$ || funcname;
        INSERT INTO subscribed_table(subname, table_name, trigger_func, key_col, "values")
        VALUES (in_subname, in_table_name, funcname::regprocedure, in_column, null)
        RETURNING * INTO metadata;
        return metadata;
end;
$$ SET SEARCH_PATH FROM CURRENT;

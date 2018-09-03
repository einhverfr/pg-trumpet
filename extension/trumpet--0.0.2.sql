
create table subscription (
    id serial not null unique,
    subname name primary key
);

CREATE TABLE subscribed_table (
    id serial not null unique,
    subname name,
    table_name regclass,
    trigger_func regprocedure,
    key_col name not null,
    values text, -- not null for filter columns
    primary key (subname, table_name, trigger_func)
);

CREATE TYPE reptuple AS (
    src_table regclass,
    id int
);

CREATE FUNCTION add_queue() returns trigger language plpgsql as
$$
BEGIN
 PERFORM pg_mq_create_queue(new.subname, 'reptuple');
 return new;
END;
$$ SET SEARCH_PATH FROM CURRENT;;

create function get_sub_row(in_subname text) returns reptuple
language sql as
$$
select payload::reptuple from pg_mq_get_msg_text($1, 1)
$$ SET SEARCH_PATH FROM CURRENT;;

CREATE TRIGGER sub_add_queue after insert on subscription
FOR EACH ROW EXECUTE PROCEDURE add_queue();

CREATE OR REPLACE FUNCTION create_sub(in_subname text) returns subscription language SQL as
$$
insert into subscription (subname) values (in_subname) returning *;
$$ SET SEARCH_PATH FROM CURRENT;;

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

CREATE OR REPLACE FUNCTION filtered_table_to_sub(in_subname text, in_table_name regclass, in_column name, in_values anyarray)
returns subscribed_table LANGUAGE PLPGSQL STRICT AS
$$
declare metadata subscribed_table;
        sub subscription;
        funcname text;
        tname text;
begin
        select * from subscription into sub where subname = in_subname;
        funcname := 'trumpetrep.sub_' || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_filter' || '()';
        tname := 'trumpetrep.sub_' || sub.id::text || '_' || in_table_name::oid::text ;
        EXECUTE $E$ CREATE TABLE IF NOT EXISTS $E$ || tname || $E$(key int primary key)$E$;
    	execute $E$ CREATE FUNCTION $E$ || funcname || $E$ RETURNS TRIGGER LANGUAGE PLPGSQL AS $F$
            BEGIN
                IF new.$E$ || quote_ident(in_column) || $E$ = any($E$ || quote_literal(in_values::text) || $E$) THEN
                    PERFORM * FROM $E$ || tname || $E$ WHERE key = new.$E$ || quote_ident(in_column) || $E$;
                    IF NOT FOUND THEN INSERT INTO $E$ || tname || $E$ (key) VALUES (new.$E$|| quote_ident(in_column) || $E$); END IF;
                    PERFORM pg_mq_send_message( $E$ || quote_literal(in_subname) || '::text,row(TG_RELID, NEW.' || quote_ident(in_column) || $E$)::trumpetrep.reptuple );
                END IF;
                RETURN NEW;
            END; $F$ $E$;
        EXECUTE $E$ CREATE TRIGGER sub_$E$ || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_filter' || $E$
                    AFTER INSERT OR UPDATE ON $E$ || in_table_name || $E$ FOR EACH ROW EXECUTE PROCEDURE $E$ || funcname;
        INSERT INTO subscribed_table(subname, table_name, trigger_func, key_col, "values")
        VALUES (in_subname, in_table_name, funcname::regprocedure, in_column, in_values::text)
        RETURNING * INTO metadata;
        return metadata;
end;
$$ SET SEARCH_PATH FROM CURRENT;

CREATE OR REPLACE FUNCTION remove_filtered_table (in_subname text, in_table_name regclass, in_column name)
RETURNS VOID LANGUAGE PLPGSQL as
$$
DECLARE funcname text;
        tname text;
BEGIN
   funcname := 'trumpetrep.sub_' || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_filter';
   tname := 'trumpetrep.sub_' || sub.id::text || '_' || in_table_name::oid::text;

   EXECUTE $E$ drop function $E$ || funcname || $E$()$E$;
END;  
$$ SET SEARCH_PATH FROM CURRENT;

CREATE OR REPLACE FUNCTION fkey_table_to_sub
(in_subname text, in_table_name regclass, in_key_col text, in_column_name text, in_referent regclass)
returns subscribed_table language plpgsql as
$$
declare metadata subscribed_table;
        sub subscription;
        funcname text;
        tname text;
        utname text;
begin
        select * from subscription into sub where subname = in_subname;
        funcname := 'trumpetrep.sub_' || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_fkey()';
        tname := 'trumpetrep.sub_' || sub.id::text || '_' || in_table_name::oid::text;
        utname := 'trumpetrep.sub_' || sub.id::text || '_' || in_referent::oid::text;
        EXECUTE $E$ CREATE TABLE IF NOT EXISTS $E$ || tname || $E$(key int primary key)$E$;
    	execute $E$ CREATE FUNCTION $E$ || funcname || $E$ RETURNS TRIGGER LANGUAGE PLPGSQL AS $F$
            BEGIN
                PERFORM * FROM $E$ || utname || $E$ WHERE key = new.$E$ || quote_ident(in_column_name) || $E$;
                IF FOUND THEN
                    RAISE NOTICE 'Found item';
                    PERFORM * FROM $E$ || tname || $E$ WHERE key = new.$E$ || quote_ident(in_key_col) || $E$;
                    IF NOT FOUND THEN INSERT INTO $E$ || tname || $E$ (key) VALUES (new.$E$ || quote_ident(in_key_col) || $E$); END IF;
                    PERFORM pg_mq_send_message( $E$ || quote_literal(in_subname) || ',row(TG_RELID, NEW.' || quote_ident(in_key_col) || $E$ )::reptuple::text);
                END IF;
                RETURN NEW;
            END; $F$ $E$;
        EXECUTE $E$ CREATE TRIGGER sub_$E$ || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_fkey' || $E$
                    AFTER INSERT OR UPDATE ON $E$ || in_table_name || $E$ FOR EACH ROW EXECUTE PROCEDURE $E$ || funcname;
        INSERT INTO subscribed_table(subname, table_name, trigger_func, key_col)
        VALUES (in_subname, in_table_name, funcname::regprocedure, in_column_name)
        RETURNING * INTO metadata;
        return metadata;
end;

$$ SET SEARCH_PATH FROM CURRENT;

create or replace function remove_fkey_table
(in_subname text, in_table_name regclass, in_column_name text, in_referent regclass, in_fcolumn name)
returns subscribed_table language plpgsql as
$$
DECLARE funcname text;
BEGIN
        funcname := 'trumpetrep.sub_' || array_to_string(array[sub.id, in_table_name::oid::int], '_') || '_fkey';
        EXECUTE $E$DROP FUNCTION $E$ || funcname || $E$()$E$;
END;
$$ SET SEARCH_PATH FROM CURRENT;


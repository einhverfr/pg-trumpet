
set search_path to trumpetrep;
CREATE SCHEMA trumpetrep;
create extension pg_message_queue;
create extension trumpet;
SELECT * from create_sub('test');
CREATE TABLE public.foo(id int primary key, parent_id int, test text);

select * from get_sub_row('test');
insert into public.foo (id, parent_id, test) values (1, null, 'Test'), (2, null, 'Test2');

select * from get_sub_row('test');
SELECT filtered_table_to_sub('test', 'public.foo', 'id', array[1]);


UPDATE public.foo set id = id;

select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');

select fkey_table_to_sub('test', 'public.foo', 'id', 'parent_id', 'public.foo');

insert into public.foo(id, parent_id, test) values (3, 1, 'Got this one'), (4, 2, 'Excluded');

select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');

create table public.bar(id int primary key, foo_id int, test text); 
select fkey_table_to_sub('test', 'public.bar', 'id', 'foo_id', 'public.foo');
insert into public.bar(id, foo_id, test) values (1, 1, 'test'), (2, 2, 'test2');


select * from get_sub_row('test');
select * from get_sub_row('test');

insert into public.bar(id, foo_id, test) values
(3, 3, 'include this one'), (4, 4, 'But not this one'),
(5, 1, 'include this one too'), (6, 2, 'But not this one either');

select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');
select * from get_sub_row('test');

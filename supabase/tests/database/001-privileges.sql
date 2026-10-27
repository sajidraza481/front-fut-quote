-- Platform rules from BRIEF §6.2 and ADR-003 that apply to every table.
begin;
select plan(8);

select is(
  array(
    select tablename::text from pg_catalog.pg_tables
    where schemaname = 'public' and not rowsecurity
  ),
  '{}'::text[],
  'RLS is enabled on every public table'
);

select is(
  array(
    select t.tablename::text from pg_catalog.pg_tables t
    where t.schemaname = 'public'
      and not exists (
        select 1 from pg_catalog.pg_policies p
        where p.schemaname = 'public' and p.tablename = t.tablename
      )
  ),
  '{}'::text[],
  'every public table has at least one policy'
);

select is(
  array(
    select c.relname::text from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
      and has_table_privilege(
        'anon', c.oid,
        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
      )
  ),
  '{}'::text[],
  'anon has no privileges on any public table or view'
);

select is(
  array(
    select c.relname::text from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
      and has_table_privilege('authenticated', c.oid, 'DELETE, TRUNCATE')
  ),
  '{}'::text[],
  'authenticated cannot hard-delete or truncate any public table'
);

select is(
  array(
    select p.oid::regprocedure::text
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosecdef
      and not coalesce(p.proconfig @> array['search_path=""'], false)
  ),
  '{}'::text[],
  'every SECURITY DEFINER function sets search_path to empty'
);

select is(
  array(
    select p.oid::regprocedure::text
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  '{}'::text[],
  'anon cannot execute any public or private function'
);

set local role anon;
select is(
  tests.tables_selectable_by_current_role(),
  '{}'::text[],
  'anon cannot select from any public table'
);
reset role;

select is(
  array(
    select p.oid::regprocedure::text
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    order by 1
  ),
  array[
    'create_business(text,text,text,text,text,uuid)',
    'mark_quote_sent(uuid)'
  ],
  'authenticated can call only the intended public functions'
);

select * from finish();
rollback;

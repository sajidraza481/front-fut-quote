-- Test helpers, (re)created at the start of every `supabase test db` run.
-- Users are synthetic (@test.invalid). Never put real personal data here.
-- This file commits so later files can use the helpers.

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

create table if not exists tests.fixtures (
  label text not null,
  key text not null,
  id uuid not null,
  primary key (label, key)
);

create or replace function tests.create_user(p_email text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  insert into auth.users (id, instance_id, aud, role, email)
  values (
    gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', p_email
  )
  returning id;
$$;

-- Act as [p_user] through the API role, as PostgREST would.
create or replace function tests.authenticate_as(p_label text)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', tests.fx(p_label, 'user'), 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function tests.fx(p_label text, p_key text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from tests.fixtures where label = p_label and key = p_key;
$$;

-- A complete tenant: user, business (via create_business), price list and
-- item, customer, draft quote with one section, measurement and line.
-- Line: 70.00 m² × 450p = 31 500; tax 6 300; total 37 800.
create or replace function tests.seed_tenant(p_label text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := tests.create_user(p_label || '@test.invalid');
  v_business uuid := gen_random_uuid();
  v_list uuid := gen_random_uuid();
  v_item uuid := gen_random_uuid();
  v_customer uuid := gen_random_uuid();
  v_quote uuid := gen_random_uuid();
  v_section uuid := gen_random_uuid();
  v_measurement uuid := gen_random_uuid();
  v_line uuid := gen_random_uuid();
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );
  perform public.create_business(
    'Business ' || p_label, 'GB', 'eu-west-2', 'GBP', 'painting', v_business
  );
  insert into public.price_lists (id, business_id, trade_pack_id, name, unit_system)
  values (v_list, v_business, 'painting', 'Default', 'metric');
  insert into public.price_items (
    id, business_id, price_list_id, code, name, kind, unit, unit_price
  ) values (
    v_item, v_business, v_list, 'wall_painting', 'Wall painting', 'labour',
    'squareMetre', 450
  );
  insert into public.customers (id, business_id, name)
  values (v_customer, v_business, 'Customer ' || p_label);
  insert into public.quotes (
    id, business_id, customer_id, trade_pack_id, currency, subtotal, tax, total
  ) values (v_quote, v_business, v_customer, 'painting', 'GBP', 31500, 6300, 37800);
  insert into public.quote_sections (id, business_id, quote_id, name)
  values (v_section, v_business, v_quote, 'Room');
  insert into public.measurements (
    id, business_id, quote_id, section_id, kind, inputs, pack_schema_version
  ) values (v_measurement, v_business, v_quote, v_section, 'area', '{}', 1);
  insert into public.line_items (
    id, business_id, quote_id, section_id, price_item_id, code, description,
    kind, unit, qty_hundredths, unit_price, total
  ) values (
    v_line, v_business, v_quote, v_section, v_item, 'wall_painting',
    'Wall painting', 'labour', 'squareMetre', 7000, 450, 31500
  );
  insert into tests.fixtures (label, key, id) values
    (p_label, 'user', v_user), (p_label, 'business', v_business),
    (p_label, 'price_list', v_list), (p_label, 'price_item', v_item),
    (p_label, 'customer', v_customer), (p_label, 'quote', v_quote),
    (p_label, 'section', v_section), (p_label, 'measurement', v_measurement),
    (p_label, 'line', v_line);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Tables in public that anon can actually read, found by trying each one.
create or replace function tests.tables_selectable_by_current_role()
returns text[]
language plpgsql
as $$
declare
  v_table text;
  v_readable text[] := '{}'::text[];
begin
  for v_table in
    select tablename from pg_catalog.pg_tables where schemaname = 'public'
  loop
    begin
      execute format('select 1 from public.%I limit 1', v_table);
      v_readable := v_readable || v_table;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v_readable;
end;
$$;

-- Records a fixture id from any role.
create or replace function tests.remember(p_label text, p_key text, p_id uuid)
returns uuid
language sql
security definer
set search_path = ''
as $$
  insert into tests.fixtures (label, key, id) values (p_label, p_key, p_id)
  on conflict (label, key) do update set id = excluded.id
  returning id;
$$;

-- A draft quote for tenant [p_label], written as the current role (so RLS
-- and the draft guards apply). One section; one line unless [p_qty] is null.
create or replace function tests.draft_quote(
  p_label text,
  p_key text,
  p_qty bigint,
  p_unit_price bigint,
  p_line_total bigint,
  p_subtotal bigint,
  p_tax bigint,
  p_total bigint,
  p_revision_of uuid default null,
  p_with_customer boolean default true
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_business uuid := tests.fx(p_label, 'business');
  v_quote uuid := gen_random_uuid();
  v_section uuid := gen_random_uuid();
begin
  insert into public.quotes (
    id, business_id, customer_id, trade_pack_id, currency, subtotal, tax,
    total, revision_of
  ) values (
    v_quote, v_business,
    case when p_with_customer then tests.fx(p_label, 'customer') end,
    'painting', 'GBP', p_subtotal, p_tax, p_total, p_revision_of
  );
  insert into public.quote_sections (id, business_id, quote_id, name)
  values (v_section, v_business, v_quote, 'Room');
  if p_qty is not null then
    insert into public.line_items (
      business_id, quote_id, section_id, code, description, kind, unit,
      qty_hundredths, unit_price, total
    ) values (
      v_business, v_quote, v_section, 'wall_painting', 'Wall painting',
      'labour', 'squareMetre', p_qty, p_unit_price, p_line_total
    );
  end if;
  return tests.remember(p_label, p_key, v_quote);
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;

select plan(1);
select pass('test helpers installed');
select * from finish();

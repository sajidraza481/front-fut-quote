-- Tenant isolation for quotes, sections, measurements and line items,
-- including references that would reveal another business's rows.
begin;
select plan(15);

select tests.seed_tenant('a');
select tests.seed_tenant('b');
select tests.authenticate_as('a');

select is((select count(*) from public.quotes), 1::bigint, 'A sees only its quotes');
select is((select count(*) from public.quote_sections), 1::bigint, 'A sees only its sections');
select is((select count(*) from public.measurements), 1::bigint, 'A sees only its measurements');
select is((select count(*) from public.line_items), 1::bigint, 'A sees only its lines');

select throws_ok(
  format(
    $$ insert into public.quotes (business_id, trade_pack_id, currency) values (%L, 'painting', 'GBP') $$,
    tests.fx('b', 'business')
  ),
  '42501', null, 'cannot create a quote in B'
);
select throws_ok(
  format(
    $$ insert into public.quotes (business_id, customer_id, trade_pack_id, currency)
       values (%L, %L, 'painting', 'GBP') $$,
    tests.fx('a', 'business'), tests.fx('b', 'customer')
  ),
  '23503', null, 'cannot quote B''s customer'
);
select throws_ok(
  format(
    $$ insert into public.quote_sections (business_id, quote_id, name) values (%L, %L, 'X') $$,
    tests.fx('a', 'business'), tests.fx('b', 'quote')
  ),
  '23503', null, 'cannot add a section to B''s quote'
);
select throws_ok(
  format(
    $$ insert into public.line_items (business_id, quote_id, section_id, price_item_id, code,
         description, kind, unit, qty_hundredths, unit_price, total)
       values (%L, %L, %L, %L, 'x', 'X', 'labour', 'each', 100, 1, 1) $$,
    tests.fx('a', 'business'), tests.fx('a', 'quote'), tests.fx('a', 'section'),
    tests.fx('b', 'price_item')
  ),
  '23503', null, 'cannot price a line from B''s price item'
);
select throws_ok(
  format(
    $$ insert into public.quotes (business_id, trade_pack_id, currency, revision_of, revision)
       values (%L, 'painting', 'GBP', %L, 1) $$,
    tests.fx('a', 'business'), tests.fx('b', 'quote')
  ),
  '23503', null, 'cannot revise B''s quote'
);
select throws_ok(
  format(
    $$ update public.quote_sections set quote_id = %L where id = %L $$,
    tests.fx('b', 'quote'), tests.fx('a', 'section')
  ),
  '42501', null, 'cannot move a section to another quote'
);

update public.quotes set total = 1 where id = tests.fx('b', 'quote');
update public.quote_sections set name = 'Changed' where id = tests.fx('b', 'section');
update public.measurements set inputs = '{"x": 1}' where id = tests.fx('b', 'measurement');
update public.line_items set total = 1 where id = tests.fx('b', 'line');

reset role;
select is(
  (select total from public.quotes where id = tests.fx('b', 'quote')),
  37800::bigint, 'A cannot edit B''s quote'
);
select is(
  (select name from public.quote_sections where id = tests.fx('b', 'section')),
  'Room', 'A cannot edit B''s section'
);
select is(
  (select inputs from public.measurements where id = tests.fx('b', 'measurement')),
  '{}'::jsonb, 'A cannot edit B''s measurement'
);
select is(
  (select total from public.line_items where id = tests.fx('b', 'line')),
  31500::bigint, 'A cannot edit B''s line'
);

select tests.authenticate_as('b');
select is(
  (select count(*) from public.line_items where business_id = tests.fx('a', 'business')),
  0::bigint, 'B cannot see A''s lines'
);
reset role;

select * from finish();
rollback;

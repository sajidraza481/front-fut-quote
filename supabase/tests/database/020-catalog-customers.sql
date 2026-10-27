-- Tenant isolation for price lists, price items and customers; soft delete
-- and server-set timestamps.
begin;
select plan(16);

select tests.seed_tenant('a');
select tests.seed_tenant('b');
select tests.authenticate_as('a');

select is((select count(*) from public.price_lists), 1::bigint, 'A sees only its price lists');
select is((select count(*) from public.price_items), 1::bigint, 'A sees only its price items');
select is((select count(*) from public.customers), 1::bigint, 'A sees only its customers');

select throws_ok(
  format(
    $$ insert into public.customers (business_id, name) values (%L, 'Intruder') $$,
    tests.fx('b', 'business')
  ),
  '42501', null, 'cannot insert a customer into B'
);
select throws_ok(
  format(
    $$ insert into public.price_lists (business_id, trade_pack_id, name, unit_system)
       values (%L, 'painting', 'Intruder', 'metric') $$,
    tests.fx('b', 'business')
  ),
  '42501', null, 'cannot insert a price list into B'
);
select throws_ok(
  format(
    $$ insert into public.price_items (business_id, price_list_id, code, name, kind, unit, unit_price)
       values (%L, %L, 'x', 'X', 'labour', 'each', 1) $$,
    tests.fx('a', 'business'), tests.fx('b', 'price_list')
  ),
  '23503', null, 'cannot attach an item to B''s price list'
);

update public.customers set name = 'Changed' where id = tests.fx('b', 'customer');
update public.price_items set unit_price = 1 where id = tests.fx('b', 'price_item');
update public.price_lists set name = 'Changed' where id = tests.fx('b', 'price_list');

select throws_ok(
  format($$ delete from public.customers where id = %L $$, tests.fx('a', 'customer')),
  '42501', null, 'hard delete is refused'
);

-- Soft delete: the row stays visible so sync can propagate it.
update public.customers set deleted_at = now() where id = tests.fx('a', 'customer');
select isnt(
  (select deleted_at from public.customers where id = tests.fx('a', 'customer')),
  null, 'soft-deleted customer is still visible to its business'
);

-- Timestamps come from the server, whatever the client sends.
update public.price_items
set unit_price = 500, updated_at = '2000-01-01', created_at = '2000-01-01'
where id = tests.fx('a', 'price_item');
select ok(
  (select updated_at > '2001-01-01' and created_at > '2001-01-01'
   from public.price_items where id = tests.fx('a', 'price_item')),
  'updated_at and created_at are set by the server'
);

select throws_ok(
  format(
    $$ insert into public.price_items (business_id, price_list_id, code, name, kind, unit, unit_price, pack_size_hundredths)
       values (%L, %L, 'bad', 'Bad', 'material', 'litre', 1, 0) $$,
    tests.fx('a', 'business'), tests.fx('a', 'price_list')
  ),
  '23514', null, 'pack size must be positive'
);
select lives_ok(
  format(
    $$ insert into public.price_items (business_id, price_list_id, code, name, kind, unit, unit_price)
       values (%L, %L, 'high_access', 'High access', 'flat', 'each', null) $$,
    tests.fx('a', 'business'), tests.fx('a', 'price_list')
  ),
  'an item may have no price (entered per quote)'
);

reset role;
select is(
  (select name from public.customers where id = tests.fx('b', 'customer')),
  'Customer b', 'A cannot edit B''s customer'
);
select is(
  (select unit_price from public.price_items where id = tests.fx('b', 'price_item')),
  450::bigint, 'A cannot edit B''s price item'
);
select is(
  (select name from public.price_lists where id = tests.fx('b', 'price_list')),
  'Default', 'A cannot edit B''s price list'
);

select tests.authenticate_as('b');
select is(
  (select count(*) from public.customers where id = tests.fx('a', 'customer')),
  0::bigint, 'B cannot see A''s soft-deleted customer either'
);
select is(
  (select count(*) from public.price_items where business_id = tests.fx('a', 'business')),
  0::bigint, 'B cannot see A''s price items'
);
reset role;

select * from finish();
rollback;

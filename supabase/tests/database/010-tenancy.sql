-- create_business() and tenant isolation of businesses, memberships, trades
-- and counters.
begin;
select plan(17);

select tests.seed_tenant('a');
select tests.seed_tenant('b');

-- create_business() set everything up for A.
select is(
  (select role from public.memberships
   where business_id = tests.fx('a', 'business') and user_id = tests.fx('a', 'user')),
  'owner', 'creator is the owner'
);
select is(
  (select trade_pack_id || ':' || is_primary from public.business_trades
   where business_id = tests.fx('a', 'business')),
  'painting:true', 'primary trade recorded'
);
select is(
  (select last_quote_number from public.business_counters
   where business_id = tests.fx('a', 'business')),
  0::bigint, 'quote counter starts at 0'
);

select tests.authenticate_as('a');

select throws_ok(
  $$ select public.create_business('Second', 'GB', 'eu-west-2', 'GBP', 'painting') $$,
  '23505', null, 'one business per trader'
);
select throws_ok(
  format(
    $$ insert into public.memberships (business_id, user_id) values (%L, %L) $$,
    tests.fx('b', 'business'), tests.fx('a', 'user')
  ),
  '42501', null, 'cannot add yourself to another business'
);
select throws_ok(
  format(
    $$ insert into public.business_trades (business_id, trade_pack_id) values (%L, 'painting') $$,
    tests.fx('a', 'business')
  ),
  '42501', null, 'cannot add trades directly'
);
select throws_ok(
  format(
    $$ update public.business_counters set last_quote_number = 99 where business_id = %L $$,
    tests.fx('a', 'business')
  ),
  '42501', null, 'cannot touch the quote counter'
);
select throws_ok(
  format($$ update public.businesses set currency = 'USD' where id = %L $$,
    tests.fx('a', 'business')),
  '42501', null, 'cannot change currency'
);
select throws_ok(
  format($$ update public.businesses set deleted_at = now() where id = %L $$,
    tests.fx('a', 'business')),
  '42501', null, 'cannot delete the business'
);

select is(
  (select count(*) from public.businesses), 1::bigint,
  'A sees only its own business'
);
select is(
  (select count(*) from public.memberships), 1::bigint,
  'A sees only its own membership'
);
select is(
  (select count(*) from public.business_trades), 1::bigint,
  'A sees only its own trades'
);
select is(
  (select count(*) from public.business_counters), 1::bigint,
  'A sees only its own counter'
);

update public.businesses set name = 'Taken over' where id = tests.fx('b', 'business');
update public.businesses set markup_basis_points = 1500 where id = tests.fx('a', 'business');
select is(
  (select markup_basis_points from public.businesses where id = tests.fx('a', 'business')),
  1500, 'A can edit its own profile'
);

reset role;
select is(
  (select name from public.businesses where id = tests.fx('b', 'business')),
  'Business b', 'A cannot edit B''s business'
);

select tests.authenticate_as('b');
select is(
  (select count(*) from public.businesses where id = tests.fx('a', 'business')),
  0::bigint, 'B cannot see A''s business'
);
reset role;

select set_config('request.jwt.claims', '', true);
select throws_ok(
  $$ select public.create_business('Nobody', 'GB', 'eu-west-2', 'GBP', 'painting') $$,
  '42501', null, 'create_business needs a signed-in user'
);

select * from finish();
rollback;

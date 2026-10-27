-- mark_quote_sent(): arithmetic checks, gap-free numbering, revisions and
-- locking of sent quotes.
begin;
select plan(30);

select tests.seed_tenant('a');
select tests.seed_tenant('b');

-- Only members can send, and never anonymously.
select tests.authenticate_as('b');
select throws_ok(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'quote')),
  'P0002', null, 'B cannot send A''s quote'
);
reset role;
set local role anon;
select throws_ok(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'quote')),
  '42501', null, 'anon cannot call mark_quote_sent'
);
reset role;

select tests.authenticate_as('a');

-- The app cannot send by writing status or number itself.
select throws_ok(
  format($$ update public.quotes set status = 'sent', number = 1, sent_at = now() where id = %L $$,
    tests.fx('a', 'quote')),
  '42501', null, 'app cannot mark a quote sent directly'
);

-- Arithmetic checks, each rejected without using up a number.
select tests.draft_quote('a', 'bad_line', 7000, 450, 31501, 31501, 0, 31501);
select throws_like(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'bad_line')),
  '%does not equal qty × unit price%', 'line total must equal qty × unit price'
);
-- 31.91 m² × 450p = 14 359.5 → 14 360 (half-up); 14 359 is wrong.
select tests.draft_quote('a', 'round_down', 3191, 450, 14359, 14359, 0, 14359);
select throws_like(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'round_down')),
  '%does not equal qty × unit price%', 'line total rounded down is rejected'
);
select tests.draft_quote('a', 'bad_subtotal', 7000, 450, 31500, 31000, 0, 31000);
select throws_like(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'bad_subtotal')),
  '%does not equal the sum of lines%', 'subtotal must equal the sum of lines'
);
select tests.draft_quote('a', 'bad_total', 7000, 450, 31500, 31500, 6300, 37000);
select throws_like(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'bad_total')),
  '%does not equal subtotal + tax%', 'total must equal subtotal + tax'
);
select tests.draft_quote('a', 'no_lines', null, null, null, 0, 0, 0);
select throws_like(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'no_lines')),
  '%no lines%', 'a quote needs at least one line'
);
select tests.draft_quote('a', 'no_customer', 7000, 450, 31500, 31500, 0, 31500, null, false);
select throws_like(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'no_customer')),
  '%no customer%', 'a quote needs a customer'
);

-- Half-up accepted; soft-deleted lines are excluded from the subtotal.
select tests.draft_quote('a', 'round_up', 3191, 450, 14360, 14360, 2872, 17232);
insert into public.line_items (business_id, quote_id, section_id, code, description,
  kind, unit, qty_hundredths, unit_price, total, deleted_at)
select tests.fx('a', 'business'), tests.fx('a', 'round_up'), s.id, 'wall_paint',
  'Removed line', 'material', 'litre', 100, 999, 999, now()
from public.quote_sections s where s.quote_id = tests.fx('a', 'round_up');

-- Sending numbers quotes 1, 2, … with no gaps despite the failures above.
select is(
  (select number from public.mark_quote_sent(tests.fx('a', 'quote'))),
  1::bigint, 'first sent quote is number 1'
);
select is(
  (select number || '/' || revision || '/' || status
   from public.mark_quote_sent(tests.fx('a', 'round_up'))),
  '2/1/sent', 'second sent quote is number 2, half-up line accepted, deleted line ignored'
);
select ok(
  (select sent_at is not null from public.quotes where id = tests.fx('a', 'quote')),
  'sent_at is recorded'
);
select throws_ok(
  format($$ select public.mark_quote_sent(%L) $$, tests.fx('a', 'quote')),
  '55000', null, 'a quote is sent once'
);

-- Sent quotes and everything under them are locked.
select throws_ok(
  format($$ update public.quotes set total = 1 where id = %L $$, tests.fx('a', 'quote')),
  '42501', null, 'sent quote cannot be edited'
);
select throws_ok(
  format($$ update public.quotes set deleted_at = now() where id = %L $$, tests.fx('a', 'quote')),
  '42501', null, 'sent quote cannot be deleted'
);
select throws_ok(
  format($$ update public.line_items set total = 1 where id = %L $$, tests.fx('a', 'line')),
  '42501', null, 'lines of a sent quote cannot be edited'
);
select throws_ok(
  format($$ update public.line_items set deleted_at = now() where id = %L $$, tests.fx('a', 'line')),
  '42501', null, 'lines of a sent quote cannot be deleted'
);
select throws_ok(
  format(
    $$ insert into public.line_items (business_id, quote_id, section_id, code, description,
         kind, unit, qty_hundredths, unit_price, total)
       values (%L, %L, %L, 'x', 'X', 'labour', 'each', 100, 1, 1) $$,
    tests.fx('a', 'business'), tests.fx('a', 'quote'), tests.fx('a', 'section')
  ),
  '42501', null, 'no lines can be added to a sent quote'
);
select throws_ok(
  format($$ update public.quote_sections set name = 'X' where id = %L $$, tests.fx('a', 'section')),
  '42501', null, 'sections of a sent quote cannot be edited'
);
select throws_ok(
  format($$ update public.measurements set inputs = '{"x": 1}' where id = %L $$,
    tests.fx('a', 'measurement')),
  '42501', null, 'measurements of a sent quote cannot be edited'
);

-- Revisions keep the original's number and count up.
select throws_like(
  format($$ select tests.draft_quote('a', 'rev_of_draft', 7000, 450, 31500, 31500, 0, 31500, %L) $$,
    tests.fx('a', 'bad_line')),
  '%must point at a sent original%', 'cannot revise a draft'
);
select tests.draft_quote('a', 'rev2', 7000, 450, 31500, 31500, 0, 31500, tests.fx('a', 'quote'));
select tests.draft_quote('a', 'rev3', 7000, 450, 31500, 31500, 0, 31500, tests.fx('a', 'quote'));
select is(
  (select number || ' rev ' || revision from public.mark_quote_sent(tests.fx('a', 'rev2'))),
  '1 rev 2', 'first revision of quote 1 is 1 rev 2'
);
select is(
  (select number || ' rev ' || revision from public.mark_quote_sent(tests.fx('a', 'rev3'))),
  '1 rev 3', 'second revision is 1 rev 3'
);
select throws_like(
  format($$ select tests.draft_quote('a', 'rev_of_rev', 7000, 450, 31500, 31500, 0, 31500, %L) $$,
    tests.fx('a', 'rev2')),
  '%must point at a sent original%', 'revisions point at the original, not a revision'
);
select throws_ok(
  format($$ insert into public.quotes (business_id, trade_pack_id, currency, revision)
            values (%L, 'painting', 'GBP', 2) $$, tests.fx('a', 'business')),
  '23514', null, 'a quote that is not a revision is revision 1'
);
select throws_ok(
  format($$ update public.quotes set revision_of = %L where id = %L $$,
    tests.fx('a', 'quote'), tests.fx('a', 'bad_line')),
  '42501', null, 'revision fields cannot be changed later'
);

-- A new original continues the sequence after the revisions.
select tests.draft_quote('a', 'third', 7000, 450, 31500, 31500, 0, 31500);
select is(
  (select number from public.mark_quote_sent(tests.fx('a', 'third'))),
  3::bigint, 'next original is number 3'
);
reset role;
select is(
  (select last_quote_number from public.business_counters
   where business_id = tests.fx('a', 'business')),
  3::bigint, 'counter has no gaps after failed sends'
);
select is(
  (select last_quote_number from public.business_counters
   where business_id = tests.fx('b', 'business')),
  0::bigint, 'numbering is per business'
);
select is(
  (select count(*) from public.quotes where status = 'sent'),
  5::bigint, 'exactly the five successful sends are sent'
);

select * from finish();
rollback;

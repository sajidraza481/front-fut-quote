-- Quotes, sections, measurements and line items (BRIEF §6). Drafts are
-- edited by the app; mark_quote_sent() numbers and locks them. A revision is
-- a new quote whose revision_of points at the original (Q-0012 rev 2).

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id),
  customer_id uuid,
  trade_pack_id text not null check (trade_pack_id in ('painting')),
  number bigint check (number > 0),
  revision integer not null default 1 check (revision >= 1),
  revision_of uuid,
  status text not null default 'draft' check (status in (
    'draft', 'sent', 'viewed', 'accepted', 'declined', 'expired'
  )),
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  subtotal bigint not null default 0 check (subtotal >= 0),
  tax bigint not null default 0 check (tax >= 0),
  total bigint not null default 0 check (total >= 0),
  valid_until date,
  compliance_profile_version integer,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, id),
  foreign key (business_id, customer_id)
    references public.customers (business_id, id),
  foreign key (business_id, revision_of)
    references public.quotes (business_id, id),
  -- Drafts have no number; everything else was numbered when sent.
  check (
    (status = 'draft' and number is null and sent_at is null)
    or (status <> 'draft' and number is not null and sent_at is not null)
  ),
  check (revision_of is not null or revision = 1)
);
create unique index quotes_number_idx
  on public.quotes (business_id, number, revision) where number is not null;
create index quotes_sync_idx on public.quotes (business_id, updated_at);
create index quotes_customer_idx on public.quotes (business_id, customer_id);
create index quotes_revision_of_idx on public.quotes (business_id, revision_of);

create table public.quote_sections (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  quote_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 200),
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, id),
  unique (quote_id, id),
  foreign key (business_id, quote_id) references public.quotes (business_id, id)
);
create index quote_sections_sync_idx on public.quote_sections (business_id, updated_at);

-- Raw field values and extras as entered, with the pack schema version that
-- reads them (ADR-001).
create table public.measurements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  quote_id uuid not null,
  section_id uuid not null,
  kind text not null check (kind in ('area', 'linear', 'volume', 'count', 'flat')),
  inputs jsonb not null check (jsonb_typeof(inputs) = 'object'),
  source text not null default 'manual' check (source in ('manual', 'ar')),
  pack_schema_version integer not null check (pack_schema_version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (business_id, quote_id) references public.quotes (business_id, id),
  foreign key (quote_id, section_id) references public.quote_sections (quote_id, id)
);
create index measurements_sync_idx on public.measurements (business_id, updated_at);
create index measurements_section_idx on public.measurements (quote_id, section_id);

-- Priced lines, snapshotted from the engine; never re-priced after send.
create table public.line_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  quote_id uuid not null,
  section_id uuid not null,
  price_item_id uuid,
  code text not null check (code ~ '^[a-z0-9_]{1,64}$'),
  description text not null check (length(description) <= 300),
  kind text not null check (kind in ('material', 'labour', 'flat')),
  unit text not null check (unit in (
    'squareMetre', 'squareFoot', 'metre', 'foot', 'litre', 'usGallon', 'each'
  )),
  pack_size_hundredths integer not null default 100 check (pack_size_hundredths > 0),
  qty_hundredths bigint not null check (qty_hundredths > 0),
  unit_price bigint not null check (unit_price >= 0),
  is_price_override boolean not null default false,
  total bigint not null check (total >= 0),
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (business_id, quote_id) references public.quotes (business_id, id),
  foreign key (quote_id, section_id) references public.quote_sections (quote_id, id),
  foreign key (business_id, price_item_id)
    references public.price_items (business_id, id)
);
create index line_items_sync_idx on public.line_items (business_id, updated_at);
create index line_items_quote_idx on public.line_items (quote_id, section_id);
create index line_items_price_item_idx on public.line_items (business_id, price_item_id);

create trigger set_timestamps before insert or update on public.quotes
  for each row execute function private.set_timestamps();
create trigger set_timestamps before insert or update on public.quote_sections
  for each row execute function private.set_timestamps();
create trigger set_timestamps before insert or update on public.measurements
  for each row execute function private.set_timestamps();
create trigger set_timestamps before insert or update on public.line_items
  for each row execute function private.set_timestamps();

-- App writes (role authenticated) may only create and edit drafts. Server
-- code (security definer functions, service role) is not restricted here.
create function private.guard_quote_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_original public.quotes;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' then
    raise exception 'quote % has been sent and is locked', old.id
      using errcode = '42501';
  end if;
  if new.status <> 'draft' or new.number is not null or new.sent_at is not null then
    raise exception 'only the server can send a quote' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and (
    new.revision <> old.revision
    or new.revision_of is distinct from old.revision_of
    or new.business_id <> old.business_id
  ) then
    raise exception 'revision fields cannot be changed' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and new.revision_of is not null then
    -- Revisions always point at the original, which must have been sent.
    select * into v_original from public.quotes where id = new.revision_of;
    if v_original.revision_of is not null or v_original.status = 'draft' then
      raise exception 'a revision must point at a sent original quote'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger guard_quote_write before insert or update on public.quotes
  for each row execute function private.guard_quote_write();

-- Sections, measurements and lines can only change while their quote is a
-- draft, and cannot move to another quote.
create function private.guard_quote_child_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status text;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.quote_id <> old.quote_id then
    raise exception 'rows cannot move between quotes' using errcode = '42501';
  end if;
  select q.status into v_status from public.quotes q where q.id = new.quote_id;
  if v_status is not null and v_status <> 'draft' then
    raise exception 'quote % has been sent and is locked', new.quote_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_quote_child_write before insert or update on public.quote_sections
  for each row execute function private.guard_quote_child_write();
create trigger guard_quote_child_write before insert or update on public.measurements
  for each row execute function private.guard_quote_child_write();
create trigger guard_quote_child_write before insert or update on public.line_items
  for each row execute function private.guard_quote_child_write();

alter table public.quotes enable row level security;
alter table public.quote_sections enable row level security;
alter table public.measurements enable row level security;
alter table public.line_items enable row level security;

create policy quotes_select on public.quotes for select to authenticated
  using (private.is_member(business_id));
create policy quotes_insert on public.quotes for insert to authenticated
  with check (private.is_member(business_id));
create policy quotes_update on public.quotes for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

create policy quote_sections_select on public.quote_sections for select to authenticated
  using (private.is_member(business_id));
create policy quote_sections_insert on public.quote_sections for insert to authenticated
  with check (private.is_member(business_id));
create policy quote_sections_update on public.quote_sections for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

create policy measurements_select on public.measurements for select to authenticated
  using (private.is_member(business_id));
create policy measurements_insert on public.measurements for insert to authenticated
  with check (private.is_member(business_id));
create policy measurements_update on public.measurements for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

create policy line_items_select on public.line_items for select to authenticated
  using (private.is_member(business_id));
create policy line_items_insert on public.line_items for insert to authenticated
  with check (private.is_member(business_id));
create policy line_items_update on public.line_items for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

revoke all on public.quotes, public.quote_sections, public.measurements,
  public.line_items from anon, authenticated;
grant select, insert, update on public.quotes, public.quote_sections,
  public.measurements, public.line_items to authenticated;

-- Sends a draft: re-checks the app's arithmetic, assigns the business's next
-- gap-free number (or the original's number and next revision), and locks it.
-- Phase 1 trusts the app's engine for prices; this only checks the sums.
create function public.mark_quote_sent(p_quote_id uuid)
returns public.quotes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote public.quotes;
  v_original public.quotes;
  v_bad_line uuid;
  v_line_count bigint;
  v_subtotal bigint;
  v_number bigint;
  v_revision integer;
begin
  select * into v_quote from public.quotes
  where id = p_quote_id and deleted_at is null
  for update;
  if not found or not private.is_member(v_quote.business_id) then
    raise exception 'quote not found' using errcode = 'P0002';
  end if;
  if v_quote.status <> 'draft' then
    raise exception 'quote has already been sent' using errcode = '55000';
  end if;
  if v_quote.customer_id is null then
    raise exception 'quote has no customer' using errcode = '23514';
  end if;

  -- Each line: total = qty × unit price, qty in hundredths, rounded half-up.
  select li.id into v_bad_line
  from public.line_items li
  where li.quote_id = v_quote.id
    and li.deleted_at is null
    and li.total <> (li.qty_hundredths * li.unit_price + 50) / 100
  limit 1;
  if v_bad_line is not null then
    raise exception 'line % total does not equal qty × unit price', v_bad_line
      using errcode = '23514';
  end if;

  select count(*), coalesce(sum(li.total), 0) into v_line_count, v_subtotal
  from public.line_items li
  where li.quote_id = v_quote.id and li.deleted_at is null;
  if v_line_count = 0 then
    raise exception 'quote has no lines' using errcode = '23514';
  end if;
  if v_quote.subtotal <> v_subtotal then
    raise exception 'subtotal % does not equal the sum of lines %',
      v_quote.subtotal, v_subtotal using errcode = '23514';
  end if;
  if v_quote.total <> v_quote.subtotal + v_quote.tax then
    raise exception 'total % does not equal subtotal + tax', v_quote.total
      using errcode = '23514';
  end if;

  if v_quote.revision_of is null then
    update public.business_counters
    set last_quote_number = last_quote_number + 1
    where business_id = v_quote.business_id
    returning last_quote_number into v_number;
    v_revision := 1;
  else
    -- Locking the original serialises revisions of the same quote.
    select * into v_original from public.quotes
    where id = v_quote.revision_of
    for update;
    v_number := v_original.number;
    select max(q.revision) + 1 into v_revision
    from public.quotes q
    where q.business_id = v_quote.business_id and q.number = v_number;
  end if;

  update public.quotes
  set status = 'sent', number = v_number, revision = v_revision, sent_at = now()
  where id = v_quote.id
  returning * into v_quote;
  return v_quote;
end;
$$;
revoke all on function public.mark_quote_sent(uuid) from public, anon;
grant execute on function public.mark_quote_sent(uuid) to authenticated;

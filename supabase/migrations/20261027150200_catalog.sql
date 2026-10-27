-- Price lists and price items, seeded from a TradePack's default catalog
-- (BRIEF §6, docs/design/painting-pack-vectors.md §3–4).

create table public.price_lists (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id),
  trade_pack_id text not null check (trade_pack_id in ('painting')),
  name text not null check (length(btrim(name)) between 1 and 200),
  unit_system text not null check (unit_system in ('metric', 'imperial')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, id)
);
create index price_lists_sync_idx on public.price_lists (business_id, updated_at);

create table public.price_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  price_list_id uuid not null,
  code text not null check (code ~ '^[a-z0-9_]{1,64}$'),
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null check (kind in ('material', 'labour', 'flat')),
  unit text not null check (unit in (
    'squareMetre', 'squareFoot', 'metre', 'foot', 'litre', 'usGallon', 'each'
  )),
  -- Minor units per unit (per pack for packed items); null = entered per quote.
  unit_price bigint check (unit_price >= 0),
  coverage_hundredths integer check (coverage_hundredths > 0),
  pack_size_hundredths integer not null default 100 check (pack_size_hundredths > 0),
  waste_basis_points integer not null default 0 check (waste_basis_points >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, id),
  foreign key (business_id, price_list_id)
    references public.price_lists (business_id, id)
);
create unique index price_items_code_idx
  on public.price_items (price_list_id, code) where deleted_at is null;
create index price_items_sync_idx on public.price_items (business_id, updated_at);

create trigger set_timestamps before insert or update on public.price_lists
  for each row execute function private.set_timestamps();
create trigger set_timestamps before insert or update on public.price_items
  for each row execute function private.set_timestamps();

alter table public.price_lists enable row level security;
alter table public.price_items enable row level security;

create policy price_lists_select on public.price_lists for select to authenticated
  using (private.is_member(business_id));
create policy price_lists_insert on public.price_lists for insert to authenticated
  with check (private.is_member(business_id));
create policy price_lists_update on public.price_lists for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

create policy price_items_select on public.price_items for select to authenticated
  using (private.is_member(business_id));
create policy price_items_insert on public.price_items for insert to authenticated
  with check (private.is_member(business_id));
create policy price_items_update on public.price_items for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

revoke all on public.price_lists, public.price_items from anon, authenticated;
grant select, insert, update on public.price_lists, public.price_items
  to authenticated;

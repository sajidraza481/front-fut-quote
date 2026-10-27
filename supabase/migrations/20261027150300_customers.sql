-- Customers. The trader is the controller of this data (BRIEF §6); collect
-- only what the quote, contract and invoice need.

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id),
  name text not null check (length(btrim(name)) between 1 and 200),
  email text check (length(email) <= 320),
  phone text check (length(phone) <= 40),
  site_address jsonb check (site_address is null or jsonb_typeof(site_address) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, id)
);
create index customers_sync_idx on public.customers (business_id, updated_at);

create trigger set_timestamps before insert or update on public.customers
  for each row execute function private.set_timestamps();

alter table public.customers enable row level security;

create policy customers_select on public.customers for select to authenticated
  using (private.is_member(business_id));
create policy customers_insert on public.customers for insert to authenticated
  with check (private.is_member(business_id));
create policy customers_update on public.customers for update to authenticated
  using (private.is_member(business_id))
  with check (private.is_member(business_id));

revoke all on public.customers from anon, authenticated;
grant select, insert, update on public.customers to authenticated;

-- Businesses, memberships, trades and per-business counters (BRIEF §6).

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  legal_name text check (length(legal_name) <= 200),
  country char(2) not null check (country ~ '^[A-Z]{2}$'),
  region_code text not null check (region_code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  tax_id text check (length(tax_id) <= 50),
  licence_number text check (length(licence_number) <= 100),
  address jsonb check (address is null or jsonb_typeof(address) = 'object'),
  logo_path text check (length(logo_path) <= 500),
  compliance_profile_id text,
  markup_basis_points integer not null default 0
    check (markup_basis_points between 0 and 100000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id),
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'owner' check (role in ('owner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, user_id)
);
create index memberships_user_business_idx
  on public.memberships (user_id, business_id);

create table public.business_trades (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id),
  trade_pack_id text not null check (trade_pack_id in ('painting')),
  is_primary boolean not null default false,
  status text not null default 'active' check (status in ('active', 'read_only')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, trade_pack_id)
);
create unique index business_trades_one_primary_idx
  on public.business_trades (business_id) where is_primary;

-- Gap-free quote numbers: the counter row is locked by mark_quote_sent(), so
-- a rolled-back send never consumes a number.
create table public.business_counters (
  business_id uuid primary key references public.businesses (id),
  last_quote_number bigint not null default 0 check (last_quote_number >= 0)
);

create trigger set_timestamps before insert or update on public.businesses
  for each row execute function private.set_timestamps();
create trigger set_timestamps before insert or update on public.memberships
  for each row execute function private.set_timestamps();
create trigger set_timestamps before insert or update on public.business_trades
  for each row execute function private.set_timestamps();

-- The basis of every business-scoped policy. Invoker rights: memberships RLS
-- only shows the caller's own rows, so this cannot see anyone else's.
create function private.is_member(target_business_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.business_id = target_business_id
      and m.user_id = (select auth.uid())
      and m.deleted_at is null
  );
$$;
revoke all on function private.is_member(uuid) from public;
grant execute on function private.is_member(uuid) to authenticated, service_role;

alter table public.businesses enable row level security;
alter table public.memberships enable row level security;
alter table public.business_trades enable row level security;
alter table public.business_counters enable row level security;

create policy businesses_select on public.businesses for select to authenticated
  using (private.is_member(id));
create policy businesses_update on public.businesses for update to authenticated
  using (private.is_member(id))
  with check (private.is_member(id));

create policy memberships_select on public.memberships for select to authenticated
  using (user_id = (select auth.uid()));

create policy business_trades_select on public.business_trades for select to authenticated
  using (private.is_member(business_id));

create policy business_counters_select on public.business_counters for select to authenticated
  using (private.is_member(business_id));

-- Businesses are created only by create_business(). The app may edit its
-- profile, but not country, currency or region (they drive compliance and
-- data residency) and not deleted_at (account deletion is server-side).
revoke all on public.businesses, public.memberships, public.business_trades,
  public.business_counters from anon, authenticated;
grant select on public.businesses, public.memberships, public.business_trades,
  public.business_counters to authenticated;
grant update (name, legal_name, tax_id, licence_number, address, logo_path,
  markup_basis_points) on public.businesses to authenticated;

-- Onboarding: business + owner membership + primary trade + counter, in one
-- transaction. One business per trader in v1. [p_id] lets the app create the
-- id offline.
create function public.create_business(
  p_name text,
  p_country text,
  p_region_code text,
  p_currency text,
  p_trade_pack_id text,
  p_id uuid default gen_random_uuid()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.memberships
    where user_id = v_user and deleted_at is null
  ) then
    raise exception 'user already belongs to a business' using errcode = '23505';
  end if;

  insert into public.businesses (id, name, country, region_code, currency)
  values (p_id, p_name, p_country, p_region_code, p_currency);
  insert into public.memberships (business_id, user_id, role)
  values (p_id, v_user, 'owner');
  insert into public.business_trades (business_id, trade_pack_id, is_primary)
  values (p_id, p_trade_pack_id, true);
  insert into public.business_counters (business_id) values (p_id);
  return p_id;
end;
$$;
revoke all on function public.create_business(text, text, text, text, text, uuid)
  from public, anon;
grant execute on function public.create_business(text, text, text, text, text, uuid)
  to authenticated;

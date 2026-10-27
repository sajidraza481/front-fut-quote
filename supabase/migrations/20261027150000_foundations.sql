-- Foundations shared by every business-scoped table. See ADR-003.

-- Anonymous callers get nothing, now or on tables created later. Clients
-- never hard-delete: removal is a soft delete (deleted_at).
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges revoke execute on functions from public;
alter default privileges in schema public
  revoke delete, truncate, references, trigger on tables from authenticated;

-- Internal helpers live outside the API-exposed public schema.
create schema private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- created_at / updated_at come from the server clock, never from a device.
-- updated_at is the transaction start time; pull-sync relies on an overlap
-- window to catch late commits (ADR-003).
create function private.set_timestamps()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

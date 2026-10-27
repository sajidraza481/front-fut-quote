# Supabase

Postgres schema, RLS policies and pgTAP tests (BRIEF §6). Rules: [ADR-003](../docs/adr/ADR-003-tenancy-and-rls.md).

```bash
supabase db start      # Postgres only (light on memory)
supabase db reset      # fresh database from migrations/ + seed.sql
supabase test db       # pgTAP: privileges, tenant isolation, quote sending
supabase db lint
supabase stop          # free memory when not working on the backend
```

The CLI version is pinned in `.mise.toml`; run it through mise (`mise exec -- supabase …`) so local and CI match.

Every new table ships with RLS policies and pgTAP isolation tests in the same change. `tests/database/001-privileges.sql` fails if any table lacks RLS or policies, if `anon` can reach anything, or if a `SECURITY DEFINER` function lacks `search_path = ''`.

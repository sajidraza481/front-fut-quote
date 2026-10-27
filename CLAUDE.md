# Frontfut — Claude Code guide

Product: trade quoting app — measure → quote → e-signed contract → invoice → paid.
Full brief: docs/BRIEF.md (read the relevant section before any task).

## Layout
- apps/mobile — Flutter app (fvm flutter …)
- apps/portal — Next.js customer portal
- packages/quote_engine — pure Dart engine + TradePacks (no Flutter imports)
- packages/compliance — ComplianceProfile JSON + schema
- services/signing — Java 21 Spring Boot sealing service
- supabase — migrations, Edge Functions, pgTAP tests

## Commands
- Engine tests: cd packages/quote_engine && fvm dart test
- App: cd apps/mobile && fvm flutter analyze && fvm flutter test
- Backend: supabase start && supabase db reset && supabase test db
- Functions: deno test supabase/functions
- Portal: cd apps/portal && npm run typecheck && npm test
- Signing: cd services/signing && ./gradlew test

## Rules
- Plan first, then code. Run the relevant tests before saying a task is done.
- Every new table: RLS policies + pgTAP isolation tests in the same change.
- Money in integer minor units. UTC in storage.
- Never put secrets, service-role keys or real personal data in code, tests, logs or prompts.
- Legal text comes only from docs/compliance/ — never write or edit clause wording.
- Server decides signatures, payments, entitlements and credits; the app never does.
- Keep quote_engine pure: no I/O, no clock, no Flutter.
- Record significant decisions as ADRs in docs/adr/.

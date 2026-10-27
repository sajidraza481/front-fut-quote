# Frontfut

Trade quoting app: measure → quote → e-signed contract → invoice → paid.
Product and architecture: [docs/BRIEF.md](docs/BRIEF.md). Decisions: [docs/adr/](docs/adr/).

## Quick start (macOS, Apple Silicon)

```bash
brew tap leoafarias/fvm
brew install fvm mise gitleaks gh supabase/tap/supabase stripe/stripe-cli/stripe
./scripts/bootstrap.sh   # git hooks, pinned Node/Java/Deno/Flutter, pub get
```

## Layout

| Path | What |
|---|---|
| `apps/mobile` | Flutter app (iOS + Android) |
| `apps/portal` | Next.js customer portal (Phase 2) |
| `packages/quote_engine` | Pure Dart quote engine + TradePacks |
| `packages/compliance` | ComplianceProfile JSON + schema (Phase 2) |
| `services/signing` | Java 21 sealing service (Phase 2) |
| `supabase` | Migrations, Edge Functions, pgTAP tests (Phase 1) |

## Tests

```bash
cd packages/quote_engine && fvm dart test
cd apps/mobile && fvm flutter analyze && fvm flutter test
```

A gitleaks pre-commit hook blocks commits containing secrets. Never commit `.env` files, keys or real personal data.

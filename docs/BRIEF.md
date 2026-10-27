# Frontfut Trade Quote App — Implementation Brief

> **Audience:** Sajid (solo founder/architect) and Claude Code.
> **Status:** v1.0 of the brief, written 27 Oct 2026. Source of product decisions: *Frontfut Trade Estimation App — Handoff v2*.
> **How to use:** commit this file as `docs/BRIEF.md`. The root `CLAUDE.md` (template in §20) points Claude Code here. Work one phase at a time (§17); start each phase by asking Claude Code to read the brief and produce a plan before writing code.

---

## 1. Product in one paragraph

A mobile app (iOS + Android) that takes a tradesperson from **measure → priced quote → legally compliant e-signed contract → invoice → paid**. It is trade-agnostic: each trade is a *TradePack* (painting is pack #1, flooring #2). Each market's consumer law is a *ComplianceProfile* (cooling-off notices, disclosures, payment-timing rules). Customers (homeowners) never install the app; they view, sign and pay through a secure web link. Target markets: US, UK, EU, Australia, New Zealand. Launch in **one trade and one market** first.

**Non-goals for v1:** AR/LiDAR scanning, team accounts, multi-currency per business, accounting integrations, full remodel estimators, a marketing website beyond a landing page.

---

## 2. Repository decision: one monorepo

**Decision: a single GitHub monorepo** (`frontfut/frontfut`, private).

Why, for this project specifically:

- **Claude Code works best with the whole system in view.** One repo means one `CLAUDE.md`, one brief, and changes that span app + database + portal land in one reviewed PR.
- **Shared contracts stay in sync.** DB migrations, generated types, compliance profiles and the quote engine are used by more than one app. Separate repos would need versioned packages and cross-repo releases — overhead with no benefit for a solo developer.
- **Atomic changes.** Adding a column touches a migration, an RLS policy, the Dart model and the portal. One commit, one CI run.
- **CI stays simple** with path filters: only the affected parts build and test.

Split a service out later only if a separate team owns it or it needs a different access policy.

### 2.1 Repository layout

```
frontfut/
├── CLAUDE.md                    # Claude Code entry point (template §20)
├── README.md                    # Quick start for humans
├── .fvmrc                       # Pinned Flutter version
├── .mise.toml                   # Pinned Node, Java, Deno versions
├── .github/
│   ├── workflows/               # mobile.yml, portal.yml, supabase.yml, signing.yml, engine.yml
│   ├── pull_request_template.md
│   └── CODEOWNERS
├── docs/
│   ├── BRIEF.md                 # This file
│   ├── adr/                     # ADR-001 (engine), ADR-002 (monorepo), ADR-003 (signing) …
│   ├── compliance/              # Lawyer-reviewed source texts per market, with review dates
│   ├── security/                # Threat model, incident runbook, data map
│   └── design/                  # Design tokens, screen specs
├── apps/
│   ├── mobile/                  # Flutter app (iOS + Android)
│   └── portal/                  # Next.js customer portal: view, sign, pay (+ landing page later)
├── packages/
│   ├── quote_engine/            # Pure Dart: engine, measurement types, TradePacks
│   └── compliance/              # Versioned ComplianceProfile JSON + JSON Schema + generators
├── services/
│   └── signing/                 # Java 21 / Spring Boot: PAdES sealing + RFC 3161 timestamps
├── supabase/
│   ├── config.toml
│   ├── migrations/              # SQL migrations (schema + RLS)
│   ├── functions/               # Edge Functions (TypeScript / Deno)
│   ├── tests/                   # pgTAP tests, RLS isolation tests
│   └── seed.sql                 # Local dev seed data (no real personal data, ever)
└── scripts/                     # Type generation, local bootstrap, release helpers
```

### 2.2 Inside `apps/mobile`

```
apps/mobile/
├── lib/
│   ├── main_dev.dart / main_prod.dart   # Flavours
│   ├── app/                    # App widget, router (go_router), theme
│   ├── core/                   # SyncEntity, errors, result types, logging, env config
│   ├── data/
│   │   ├── local/              # drift database, DAOs
│   │   ├── remote/             # Supabase client wrappers
│   │   └── sync/               # Sync engine (push/pull, conflict rules)
│   ├── features/
│   │   ├── auth/  onboarding/  profile/  trades/
│   │   ├── price_lists/  customers/
│   │   ├── quotes/             # Create/edit quote, rooms/sections, line items
│   │   ├── pdf/                # On-device PDF rendering
│   │   ├── contracts/          # Send for signature, signature status
│   │   ├── invoices/  payments/
│   │   ├── billing/            # RevenueCat paywall, plans
│   │   └── ad_credits/         # Rewarded ads, credit balance
│   └── l10n/                   # ARB files (en-US, en-GB, en-AU, en-NZ first)
├── test/  integration_test/
└── ios/  android/
```

Each feature folder follows `presentation/` (widgets, controllers) · `application/` (use cases) · `domain/` (models) · `data/` (repositories). Riverpod providers live next to the code they provide.

### 2.3 Migrating the existing `quotepainter/` scaffold

1. Move `lib/engine/` and `lib/packs/painting/` into `packages/quote_engine/lib/`.
2. Move `test/painting_engine_test.dart` into `packages/quote_engine/test/`; keep the validated case (12×10×8 room, door + window, 2 coats, 8% tax → **$840.78**) and the primer/markup/clamp cases as regression tests.
3. Move `lib/core/sync_meta.dart` into `apps/mobile/lib/core/`.
4. Rebuild the app shell inside `apps/mobile` and depend on `quote_engine` via a Dart pub workspace.

---

## 3. Development machine setup (MacBook Air M4)

All tools below are native Apple Silicon (arm64). Install in this order.

### 3.1 Install list

| # | Tool | Purpose | Install |
|---|---|---|---|
| 1 | Xcode (latest stable) | iOS build, simulators, signing | Mac App Store, then `sudo xcodebuild -license accept` and `xcodebuild -runFirstLaunch` |
| 2 | Xcode Command Line Tools | git, compilers | `xcode-select --install` |
| 3 | Homebrew | Package manager | See brew.sh |
| 4 | Git + GitHub CLI | Source control, PRs from terminal | `brew install git gh` then `gh auth login` |
| 5 | Claude Code | AI development | `curl -fsSL https://claude.ai/install.sh \| bash` (or `brew install --cask claude-code`); requires a paid Claude plan |
| 6 | VS Code | Editor + Claude Code, Flutter, Dart extensions | `brew install --cask visual-studio-code` |
| 7 | fvm | Pin Flutter version per repo | `brew tap leoafarias/fvm && brew install fvm` then `fvm install` in repo |
| 8 | Android Studio | Android SDK, emulator, bundled JDK for Gradle | `brew install --cask android-studio`; install SDK + an **arm64** system image |
| 9 | CocoaPods | iOS plugin dependencies | `brew install cocoapods` |
| 10 | mise | Pin Node, Java, Deno per repo | `brew install mise`, then `mise install` in repo |
| 11 | Node.js LTS | Next.js portal, tooling | via mise |
| 12 | Java 21 (Temurin) | Signing service | via mise |
| 13 | Deno | Edge Functions local dev and tests | via mise |
| 14 | OrbStack | Docker runtime (lighter than Docker Desktop on Apple Silicon); required by Supabase local | `brew install --cask orbstack` |
| 15 | Supabase CLI | Local stack, migrations, type generation, deploy | `brew install supabase/tap/supabase` |
| 16 | Stripe CLI | Webhook forwarding and test events | `brew install stripe/stripe-cli/stripe` |
| 17 | fastlane | Store builds and uploads (Phase 4) | `brew install fastlane` |
| 18 | gitleaks | Pre-commit secret scanning | `brew install gitleaks` |
| 19 | 1Password CLI (or Bitwarden CLI) | Pull secrets into local `.env` files without committing them | `brew install --cask 1password-cli` |

Optional: Proxyman (inspect app network traffic), TablePlus (database GUI), Figma (design).

**Memory note:** a base MacBook Air has limited RAM for Xcode + Android emulator + OrbStack + Supabase at once. Prefer a physical Android phone over the emulator, and stop the Supabase stack (`supabase stop`) when not working on the backend.

### 3.2 Verify

```bash
fvm flutter doctor -v        # all green except optional items
supabase --version && stripe --version && gh --version
claude --version
java -version && node -v && deno --version
```

### 3.3 Accounts to create (not software, but needed before Phase 1)

| Account | Needed for | When |
|---|---|---|
| GitHub (org `frontfut`) | Repo, Actions CI | Phase 0 |
| Apple Developer Program | iOS builds, TestFlight, Sign in with Apple, Tap to Pay entitlement | Phase 0 (enrol as the company once it exists) |
| Google Play Console | Android release | Phase 0 |
| Supabase | Backend (dev + prod projects) | Phase 1 |
| Stripe (platform account, under the US LLC / UK Ltd) | Connect, payments | Phase 0 gate |
| RevenueCat | Subscriptions | Phase 3 |
| AdMob | Rewarded ads | Phase 3 |
| Sentry | Crash and error reporting (app, portal, functions) | Phase 1 |
| Email/SMS provider (e.g. Postmark + Twilio, or Resend) | OTP, quote links, receipts | Phase 2 |
| Cloud provider for signing service + KMS (Google Cloud Run + Cloud KMS, or AWS) | Signing service | Phase 2 |
| Vercel (or Cloudflare Pages) | Portal hosting | Phase 2 |

---

## 4. Architecture

```
┌─────────────────────────── Flutter app (local-first) ───────────────────────────┐
│ MeasurementSource ─┐                                                             │
│ TradePack ─────────┼─► QuoteEngine ─► Quote/Contract PDF (on device)             │
│ ComplianceProfile ─┘          │                                                  │
│                               ▼                                                  │
│                     drift DB (SyncEntity rows) ◄──► Sync engine                  │
└───────────────────────────────────────┬──────────────────────────────────────────┘
                                        │ HTTPS (Supabase client, JWT)
┌───────────────────────────────────────▼──────────────────────────────────────────┐
│ Supabase: Auth · Postgres (RLS) · Storage (PDFs) · Edge Functions                │
│   functions: send-for-signature, portal-api, stripe-webhooks, revenuecat-webhook,│
│              admob-ssv, invoice-reminders (cron), account-export, account-delete │
└──────┬──────────────────────┬──────────────────────┬─────────────────────────────┘
       │                      │                      │
┌──────▼───────┐   ┌──────────▼─────────┐   ┌────────▼──────────────────────────┐
│ Signing svc  │   │ Customer portal     │   │ External: Stripe Connect,         │
│ (Spring Boot)│   │ (Next.js): view,    │   │ RevenueCat, AdMob, Email/SMS,     │
│ PAdES + TSA  │   │ OTP, sign, pay      │   │ RFC 3161 timestamp authority      │
│ key in KMS   │   └─────────────────────┘   └───────────────────────────────────┘
└──────────────┘
```

**Principles**

1. **Local-first.** The device DB is the working copy; the app is fully usable offline for measuring, pricing, drafting and PDF preview. Sending, signing, invoicing and payments need connectivity.
2. **Server is the source of truth** for anything legal or financial: signatures, contract versions, invoices, payments, entitlements, ad credits. The app never decides these alone.
3. **Pure engine.** `quote_engine` has no Flutter, I/O, or clock dependencies. Same inputs → same totals, always. All money is integer minor units (cents/pence).
4. **Data-driven extension.** New trade = new TradePack (config + small formula plugin). New market = new ComplianceProfile (JSON, lawyer-reviewed) + any market-specific rule code.
5. **No card data, ever.** Stripe-hosted checkout and Stripe SDKs only.

---
## 5. Tech stack

Pin every version at project start (`.fvmrc`, `.mise.toml`, lockfiles) and upgrade deliberately. Pick versions at least two weeks old.

| Layer | Choice |
|---|---|
| Mobile | Flutter (stable, via fvm), Dart 3 pub workspaces |
| State / DI | `flutter_riverpod` (+ `riverpod_generator`) |
| Navigation | `go_router` |
| Models | `freezed` + `json_serializable` |
| Local DB | `drift` (SQLite) |
| Backend client | `supabase_flutter` |
| Auth | Supabase Auth: email (magic link + password), Google (`google_sign_in`), Apple (`sign_in_with_apple`); TOTP MFA |
| Secure storage | `flutter_secure_storage` (tokens, never secrets) |
| PDF | `pdf` + `printing` (on device) |
| Subscriptions | RevenueCat `purchases_flutter` |
| Ads | `google_mobile_ads` (rewarded, non-personalised) |
| Payments in app | Stripe Connect onboarding via hosted link; Tap to Pay later via native Stripe Terminal SDKs on platform channels |
| Crash reporting | `sentry_flutter` (PII scrubbing on) |
| i18n | `flutter_localizations` + ARB; `intl` for money/dates |
| Portal | Next.js (App Router, TypeScript, server components), `@supabase/ssr`, Stripe.js / Checkout |
| Edge Functions | Supabase Edge Functions (TypeScript / Deno) |
| Database | Postgres via Supabase, migrations in SQL, pgTAP tests |
| Signing service | Java 21, Spring Boot, Apache PDFBox, Bouncy Castle; signing key in a cloud KMS/HSM (never in a file) |
| CI | GitHub Actions with path filters |
| Release | fastlane → TestFlight / Play internal testing |

**Supabase region:** the launch market's region (UK launch → London; EU → Frankfurt). Multi-region is a later decision; keep `region` on the business record from day one so data can be routed later.

---

## 6. Domain model

All tables: `id uuid primary key default gen_random_uuid()`, `created_at`, `updated_at` (trigger-maintained), `deleted_at` (soft delete) — mirroring `SyncEntity` in the app. Money columns are `bigint` minor units + a `currency char(3)` on the parent record.

### 6.1 Tables

| Table | Key columns | Notes |
|---|---|---|
| `businesses` | name, legal_name, country, region_code, currency, tax_id, licence_number, address, logo_path, compliance_profile_id | One per trader in v1 (teams later) |
| `memberships` | business_id, user_id, role (`owner`) | Basis of every RLS policy |
| `business_trades` | business_id, trade_pack_id, is_primary, status (`active`/`read_only`) | Limited by plan |
| `price_lists` / `price_items` | business_id, trade_pack_id, name; item: code, unit, unit_price, kind (`material`/`labour`/`flat`) | Seeded from the TradePack default catalog |
| `customers` | business_id, name, email, phone, site_address | Trader is controller of this data |
| `quotes` | business_id, customer_id, trade_pack_id, number, status, currency, subtotal, tax, total, valid_until, compliance_profile_version | Status: `draft → sent → viewed → accepted/declined → expired` |
| `quote_sections` | quote_id, name (e.g. "Living room"), sort | |
| `measurements` | section_id, kind (`area`/`linear`/`volume`/`count`), inputs jsonb, source (`manual`/`ar`) | Raw inputs kept for audit |
| `line_items` | quote_id, section_id, price_item_id, description, qty, unit, unit_price, total, sort | Snapshot prices; never re-priced after send |
| `contracts` | quote_id, version, status, unsigned_pdf_path, unsigned_sha256, sealed_pdf_path, sealed_sha256, cooling_off_ends_at | Immutable once sent; edits create a new version |
| `signers` | contract_id, role (`customer`/`trader`), name, email, phone, verified_via, signed_at | |
| `signature_events` | contract_id, signer_id, type, at, ip, user_agent, details jsonb | **Append-only** (no update/delete grants); feeds the audit certificate |
| `portal_tokens` | contract_id or invoice_id, token_hash, expires_at, revoked_at | Only the hash is stored |
| `invoices` | business_id, contract_id, number, kind (`deposit`/`progress`/`final`/`standalone`), status, due_at, totals, stripe_payment_link_id | Numbering per business, gap-free |
| `payments` | invoice_id, method (`stripe`/`cash`/`bank_transfer`), amount, stripe_payment_intent_id, status, received_at, platform_fee | Written by webhook for Stripe payments |
| `stripe_accounts` | business_id, stripe_account_id, charges_enabled, payouts_enabled | Connect Express |
| `entitlements` | business_id, plan (`free`/`pro`/`business`), source (`revenuecat`), expires_at, max_trades | Written only by the RevenueCat webhook |
| `quote_credits` | business_id, delta, reason (`signup`/`rewarded_ad`/`spent`), ad_transaction_id unique, at | Ledger; balance = sum |
| `audit_log` | actor, action, target, at, ip | Security-relevant events; append-only |

### 6.2 Row-level security pattern

- RLS **enabled on every table**, no exceptions; CI fails if a table lacks policies.
- Business-scoped rows: `using (business_id in (select business_id from memberships where user_id = auth.uid()))`.
- Tables written only by the server (`entitlements`, `payments`, `quote_credits`, `signature_events`, `contracts.sealed_*`) have **no** client insert/update policies; Edge Functions use the service role.
- Portal access never uses the service role directly from the browser; the portal calls `portal-api`, which validates the token hash, then reads only that contract/invoice.
- pgTAP tests prove: user A cannot read, write or infer user B's rows for every table.

---

## 7. Quote engine (`packages/quote_engine`)

Pure Dart. 100% unit-test coverage target on pricing code.

```dart
enum MeasurementKind { area, linear, volume, count, flat }

abstract interface class MeasurementSource {
  Stream<MeasurementInput> capture(MeasurementRequest request); // ManualEntry now, AR later
}

abstract interface class TradePack {
  String get id;                       // 'painting', 'flooring'
  int get schemaVersion;
  List<MeasurementKind> get kinds;
  List<CatalogItem> get defaultCatalog;
  List<FieldSpec> sectionFields();     // drives the input UI (e.g. wall height, coats)
  QuantitySet quantities(SectionInput input);           // geometry → quantities
  List<LineItem> price(QuantitySet q, PriceList prices); // quantities → priced lines
  PdfTemplateSpec get template;
}

abstract interface class ComplianceProfile {
  String get id;                       // 'uk', 'us-md', 'au-wa', 'nz'
  int get version;
  List<RequiredClause> clauses(ContractContext ctx);   // notices, cancellation form
  CoolingOff? coolingOff(ContractContext ctx);         // window + business-day calendar
  PaymentRule paymentRule(ContractContext ctx);        // e.g. block deposits during cooling-off
  List<DisclosureDoc> disclosures(ContractContext ctx);// e.g. NZ checklist ≥ NZ$30k
  List<TraderFieldRequirement> traderFields();         // licence no., address…
}

class QuoteEngine {
  QuoteTotals compute(Quote quote, TradePack pack, PriceList prices, TaxRule tax);
}
```

**Rules**

- Rounding: half-up at line level in minor units; document it and test it.
- Waste %, coats, openings, box-quantity rounding (flooring) live in the pack, not the engine.
- Flooring pack (Phase 5) is the proof that the abstraction holds; if it forces engine changes, record them in an ADR.
- ComplianceProfile *content* (clause texts, form templates) lives in `packages/compliance/profiles/<id>/<version>.json`, validated by JSON Schema. *Rules* that need code (business-day calculation, thresholds) live in Dart with a TypeScript mirror generated or hand-kept in `portal` and Edge Functions — covered by shared JSON test vectors so both implementations agree.

---

## 8. Backend: Edge Functions

| Function | Trigger | Does |
|---|---|---|
| `send-for-signature` | App call | Validates the contract snapshot, uploads the unsigned PDF, computes SHA-256, creates signers and a portal token, sends the link by email/SMS |
| `portal-api` | Portal calls | Token check → contract view, OTP send/verify, e-consent capture, signature submit, triggers sealing |
| `seal-contract` | Internal | Calls the signing service with PDF + audit data; stores sealed PDF + hash; notifies both parties |
| `create-invoice` | App call | Gap-free numbering, Stripe payment link on the trader's connected account with application fee |
| `stripe-webhooks` | Stripe | Verifies signature; idempotently records payments, account status changes, disputes |
| `stripe-onboarding` | App call | Creates Express account + onboarding link |
| `revenuecat-webhook` | RevenueCat | Updates `entitlements`; on downgrade marks extra trades `read_only` |
| `admob-ssv` | AdMob | Verifies the server-side verification signature; inserts one `quote_credits` row (unique on transaction id) |
| `spend-credit` | App call | Atomic: checks plan or credit balance, records spend, returns authorisation to finalise the quote |
| `invoice-reminders` | Cron (daily) | Sends overdue reminders per invoice settings |
| `account-export` / `account-delete` | App call | GDPR-style export (zip of JSON + PDFs) and deletion respecting legal holds |

Conventions: every function validates input with a schema (e.g. Zod), is idempotent where it receives webhooks, logs without personal data, and has Deno tests.

---

## 9. Signing flow and service

### 9.1 Sequence

1. Trader taps **Send for signature**. The app freezes the quote into a contract version (prices, clauses, ComplianceProfile version) and renders the contract PDF.
2. `send-for-signature` stores it and its SHA-256; the customer receives a link `https://<portal>/s/<token>`.
3. Customer opens the link → enters a 6-digit OTP sent to their email/phone (rate-limited, 10-minute expiry).
4. Customer sees the e-consent disclosure (required for US consumers) and accepts.
5. Customer reviews the full contract including the cancellation notice and form, ticks **"I agree to be bound by this contract"**, types their name and optionally draws a signature.
6. Trader counter-signs in the app (or signs before sending — configurable; default: trader signs first).
7. `seal-contract` sends the PDF + audit record to the signing service, which:
   - appends an **audit certificate page** (signers, verification method, timestamps, IP, user agent, document hash);
   - applies a **PAdES** signature with the platform's document-signing key held in KMS;
   - embeds an **RFC 3161 timestamp** from a trusted timestamp authority.
8. Sealed PDF is stored; both parties are emailed a copy; `contracts.status = signed`; cooling-off end date is computed from the ComplianceProfile.

### 9.2 Signing service (`services/signing`)

- Spring Boot, single endpoint `POST /v1/seal` (mTLS or signed service token; reachable only from Edge Functions).
- PDFBox external-signing API + Bouncy Castle CMS; private key never leaves KMS (sign-the-digest call).
- Deterministic output tests: verify seals with an independent validator in CI.
- Certificate: start with an organisation document-signing certificate; evaluate an Adobe-trusted (AATL) certificate before launch so PDF readers show a valid seal.

---

## 10. Payments and invoicing

- **Onboarding:** trader → `stripe-onboarding` → Stripe-hosted Express onboarding → `stripe_accounts` updated via webhook.
- **Invoice from contract:** one tap creates a deposit/progress/final invoice; line items copy from the signed contract; the invoice references the contract.
- **Collection:** Stripe Checkout / Payment Link on the connected account with `application_fee_amount` by plan (Free ~1.5%, Pro ~1%, Business ~0.5% — configurable server-side, never hard-coded in the app). Apple Pay and Google Pay appear automatically.
- **Manual payments:** cash/bank transfer marked paid by the trader (logged in `audit_log`).
- **Compliance hook:** `create-invoice` asks the ComplianceProfile's `paymentRule`; during a cooling-off window it blocks (AU unsolicited agreements) or warns and requires the customer's express request (UK/EU).
- **Tap to Pay:** Phase 5, native Stripe Terminal SDKs behind a platform channel; needs Apple's Tap to Pay entitlement.
- **App Store rules:** payments are for physical services → not subject to in-app purchase. Subscriptions are digital → RevenueCat / IAP only.

---

## 11. Subscriptions, trades and ad credits

| | Free | Pro | Business |
|---|---|---|---|
| Trades | 1 | 2 | All |
| Quotes | 3 starter, then 2 per rewarded ad, cap ~10/month | Unlimited | Unlimited |
| E-sign | Yes | Yes | Yes |
| Invoices | From own quotes | Unlimited + reminders | + staged billing |
| Branding | "Made with" footer | Full | Full |
| Payment fee | ~1.5% | ~1% | ~0.5% |

- **RevenueCat** is the source of truth for plans; the server mirrors it into `entitlements` via webhook. The app reads entitlements from the server, not just from the SDK, for gated server actions.
- **Trade limits:** `business_trades` count checked server-side on add; downgrade → extra trades `read_only`, data kept.
- **Ad credits:** credits are banked before quote time; the rewarded-ad screen is reachable from the credits screen only, never blocking the send flow. `google_mobile_ads` with non-personalised requests only; no ATT prompt; credits only via `admob-ssv`. Monthly cap enforced in `spend-credit`. Plan limits and caps live in a server config table so they can change without an app release.
- **Never lock out data:** quotes, contracts and invoices remain viewable and exportable on every plan.

---

## 12. Security and privacy requirements

These are acceptance criteria, not suggestions. Each item has a test, a CI check or a documented review.

**Data protection**
- [ ] RLS on every table; pgTAP cross-tenant tests in CI.
- [ ] TLS only; HSTS on the portal; certificate pinning not required in v1.
- [ ] Encryption at rest (Supabase default) + Storage buckets private; PDFs served only through short-lived signed URLs.
- [ ] Portal tokens: 32+ random bytes, only SHA-256 stored, expiry, revocation, single contract scope.
- [ ] OTP: hashed, 10-minute expiry, 5 attempts, rate-limited per token and per IP.
- [ ] No personal data in logs, analytics events, crash reports or URLs. Sentry `beforeSend` scrubber + tests.
- [ ] Data minimisation: collect only what the contract, invoice or law needs.

**Identity and access**
- [ ] MFA available to traders; mandatory for any admin/support access to production.
- [ ] Service-role key only in Edge Functions and the signing service environment — never in the app or portal bundle (CI greps built artefacts).
- [ ] Production DB access via named accounts with audit logging; no shared credentials.

**Supply chain and code**
- [ ] `gitleaks` pre-commit hook + CI secret scan; GitHub secret scanning + push protection on.
- [ ] Dependabot (or Renovate) with a 14-day minimum release age; lockfiles committed.
- [ ] Mobile app reviewed against OWASP MASVS (L1); no secrets in the binary; release builds obfuscated.
- [ ] Third-party penetration test before launch (Phase 4 gate).

**Legal and process**
- [ ] Privacy policy, terms of service with a data processing agreement (trader = controller, Frontfut = processor), sub-processor list.
- [ ] EU and UK representatives appointed before serving those markets; Standard Contractual Clauses for any access from outside the hosting region.
- [ ] Retention jobs: drafts purged after inactivity; signed contracts/invoices kept for the market's period (lawyer to confirm); closed accounts exported then deleted except legal holds.
- [ ] Incident runbook in `docs/security/`, including the 72-hour GDPR notification path and AU/NZ/UK/US timelines; one tabletop exercise before launch.
- [ ] App Store privacy labels and Play data-safety form match reality (including the ad SDK).

---

## 13. UI and design system

- **Typography:** iOS uses the system font (SF Pro); Android uses **Inter** (bundled, OFL). Define one `TextTheme` scale; tabular figures (`FontFeature.tabularFigures()`) for every number and price.
- **Look:** one restrained accent colour, neutral surfaces, hierarchy through type weight and spacing (4/8-pt scale), not boxes. No gradients, no emoji icons, no glassmorphism, no card-inside-card.
- **Icons:** SF Symbols style on iOS (Cupertino icons), Material Symbols (outlined, one weight) on Android — never mixed on one platform.
- **Platform-adaptive:** Cupertino navigation and sheets on iOS, Material 3 on Android; shared layout and tokens.
- **Field-ready:** 48-pt minimum targets, one-handed reach for primary actions, works in bright sunlight (contrast AA+), dark mode supported.
- **Key journey:** Home → New quote → pick customer → add sections + measurements → review totals → present on screen → send for signature. Target: a simple one-room quote in under 60 seconds for a returning user.
- Design tokens live in `docs/design/tokens.json` and generate the Flutter theme and portal CSS variables.

---

## 14. Testing and CI

| Area | Tests | CI job (path-filtered) |
|---|---|---|
| `packages/quote_engine` | Unit tests, golden numeric vectors (incl. $840.78), property tests for rounding | `engine.yml` |
| `packages/compliance` | JSON Schema validation; shared Dart/TS rule vectors (business days, thresholds) | `engine.yml` |
| `apps/mobile` | Unit, widget, golden screenshots of key screens and PDFs; integration tests on the quote → send flow | `mobile.yml` (analyze, test, build iOS + Android) |
| `supabase` | Migrations apply cleanly on a fresh DB; pgTAP RLS tests; Edge Function Deno tests | `supabase.yml` (runs `supabase start` in CI) |
| `apps/portal` | Typecheck, unit tests, Playwright e2e: open link → OTP → sign → pay (Stripe test mode) | `portal.yml` |
| `services/signing` | JUnit; seal validation with an independent validator; tampered-PDF test must fail | `signing.yml` |

Branching: `main` is always releasable; short-lived feature branches; PR required with CI green; squash merge; Conventional Commits (`feat(quotes): …`).

---

## 15. Environments and secrets

| Env | Supabase | Stripe | RevenueCat / AdMob | App flavour |
|---|---|---|---|---|
| local | `supabase start` (Docker) | test mode + `stripe listen` | sandbox / test ads | `dev` |
| staging | `frontfut-staging` project | test mode | sandbox / test ads | `dev` (TestFlight internal) |
| production | `frontfut-prod` project | live mode | production | `prod` |

- Secrets live in a password manager and in GitHub Actions / Supabase / hosting secret stores. Local `.env` files are generated by `scripts/env-pull.sh` and git-ignored.
- The app only ever holds public keys (Supabase anon key, Stripe publishable key, RevenueCat public key, AdMob IDs).
- Use **test ad unit IDs** everywhere except production builds (clicking live ads in development can get the AdMob account banned).

---

## 16. Working with Claude Code on this repo

1. Keep `CLAUDE.md` short and current; put depth in `docs/`.
2. Start every task with: *"Read CLAUDE.md and docs/BRIEF.md §<section>. Propose a plan with files to change and tests to add. Don't write code yet."* Review the plan, then let it implement.
3. One phase task per branch/PR. Ask Claude Code to run the relevant tests and `flutter analyze` / `supabase db lint` / `tsc` before declaring done.
4. For migrations, always request the RLS policies and pgTAP tests in the same change.
5. For anything legal (clause text, cancellation forms), Claude Code wires up the structure; the **text** comes only from `docs/compliance/` after lawyer review — never generated.
6. Record each significant decision as an ADR in `docs/adr/`.
7. Never paste production secrets or real customer data into a Claude Code session.

---

## 17. Build phases and acceptance criteria

Gates are hard stops: nothing customer-facing ships until the gate before it is passed.

### Phase 0 — Foundations (non-code + repo)
- [ ] Company entity (US LLC or UK Ltd) formed; business bank account; Stripe platform account approved.
- [ ] Trademark search for Frontfut and the app name; app name chosen; store names reserved.
- [ ] Launch trade and launch market chosen; lawyer engaged for that market.
- [ ] Monorepo created with the layout in §2, `CLAUDE.md`, CI skeleton, branch protection, gitleaks.
- [ ] `quotepainter` engine migrated into `packages/quote_engine` with all tests passing (§2.3).

**Gate 1:** entity and Stripe platform approved.

### Phase 1 — Core app
- [ ] Supabase schema for businesses, memberships, trades, price lists, customers, quotes, sections, measurements, line items — with RLS + pgTAP tests.
- [ ] Auth: email (magic link + password), Google, Sign in with Apple; onboarding picks primary trade, country and currency.
- [ ] drift schema mirroring the server; sync engine (push/pull by `updated_at`, last-writer-wins per row, soft deletes) with tests for offline edits on two devices.
- [ ] TradePack schema generalised; painting pack complete; price-list editor.
- [ ] Quote creation UI (sections, measurements, line items, totals) meeting the 60-second journey target.
- [ ] Branded quote PDF on device (logo, business details, totals); share sheet.
- **Done when:** a trader can sign up on iOS and Android, build a painting quote offline, sync it to a second device and export a branded PDF.

### Phase 2 — Contracts
- [ ] `packages/compliance` with JSON Schema and the launch market's profile (lawyer-reviewed text from `docs/compliance/`).
- [ ] Contract versioning, `send-for-signature`, portal (Next.js) with OTP, e-consent, review, agree-and-sign.
- [ ] Signing service deployed with KMS key; sealed PDF with audit certificate and RFC 3161 timestamp; tamper test fails as expected.
- [ ] Cooling-off end date computed and shown to both parties; cancellation flow recorded.
- **Done when:** a contract can be sent, signed by both parties, sealed, emailed, and the sealed PDF validates in Adobe Acrobat and an independent validator.

**Gate 2:** contract templates and flows signed off by a local lawyer.

### Phase 3 — Monetisation
- [ ] Stripe Connect Express onboarding; quote → invoice conversion; staged billing; payment links with application fees; webhook-driven paid status; manual payment marking; overdue reminders.
- [ ] ComplianceProfile payment rule enforced during cooling-off.
- [ ] RevenueCat plans (Free/Pro/Business), paywall, entitlements webhook, trade limits and downgrade behaviour.
- [ ] Rewarded-ad credits with AdMob SSV, banked balance, monthly cap, server-side spend.
- **Done when:** in test mode, a customer pays a deposit invoice by Apple Pay and Google Pay, the trader sees it paid within seconds, and the platform fee lands in the platform account.

### Phase 4 — Harden and launch
- [ ] Every item in §12 checked; penetration test done and findings fixed.
- [ ] Privacy policy, terms + DPA, representatives, privacy labels, data-safety form.
- [ ] Sentry alerts, uptime checks on portal and signing service, DB backups + one restore test.
- [ ] Store listings (ASO), screenshots, fastlane lanes; TestFlight + Play internal beta with 10–20 real traders.

**Gate 3:** pen test passed and store approval.

### Phase 5 — Expand
- [ ] Flooring pack (box rounding, waste by layout) — proves the TradePack abstraction.
- [ ] Second market ComplianceProfile.
- [ ] Tap to Pay (iOS + Android) via Stripe Terminal.
- [ ] AR measurement on LiDAR iOS devices (RoomPlan) behind `MeasurementSource`.
- [ ] Business tier team members.

---

## 18. Conventions

- **Dart:** `very_good_analysis` (or `flutter_lints` + strict mode); no `dynamic` in domain code; `Result` types instead of throwing across layers.
- **TypeScript:** `strict: true`; Zod at every boundary; ESLint + Prettier.
- **Java:** Spring Boot conventions; Checkstyle or Spotless; no Lombok in security-sensitive code paths.
- **SQL:** snake_case; one migration per change; never edit a merged migration.
- **Money:** integer minor units end to end; format only at the UI edge.
- **Time:** store UTC; display in the business's time zone; business-day calculations always use the ComplianceProfile calendar.
- **IDs:** UUID v4 generated client-side for offline creation.
- **Naming:** feature folders and providers named after the domain (`quoteListProvider`), not the widget.

---

## 19. Open decisions (resolve before the phase that needs them)

| Decision | Needed by | Default if undecided |
|---|---|---|
| US LLC vs UK Ltd | Phase 0 | — (blocks Stripe) |
| Launch trade and market | Phase 0 | Painting, UK |
| App name | Phase 0 | — |
| Cloud for signing service + KMS | Phase 2 | Google Cloud Run + Cloud KMS |
| Email/SMS provider | Phase 2 | Postmark (email) + Twilio (SMS) |
| Trader signs before or after customer | Phase 2 | Trader first |
| Retention periods per market | Phase 4 | Lawyer advice |
| Exact prices and fee percentages | Phase 3 | §11 values, server-configurable |

---

## 20. `CLAUDE.md` template (repo root)

```markdown
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
```

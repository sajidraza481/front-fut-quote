# ADR-002: Single monorepo with a Dart pub workspace

- **Status:** Accepted
- **Date:** 2026-10-27
- **Context:** BRIEF §2

## Decision

All apps, packages, services and the Supabase project live in one repository. Dart code (`packages/quote_engine`, `apps/mobile`) shares one pub workspace and one `pubspec.lock` at the root. CI uses one workflow per area with path filters.

Toolchain versions are pinned in `.fvmrc` (Flutter) and `.mise.toml` (Node, Java, Deno); new versions must be at least two weeks old.

Branch protection is deferred while the repo is private on the GitHub free plan; required CI checks are added once the repo moves to the `frontfut` organisation.

## Consequences

- One PR can change a migration, its RLS policies, the Dart model and the portal together.
- `flutter pub get` at the root resolves the whole workspace, so engine CI also installs Flutter.
- A service is split out only if another team owns it or it needs a different access policy.

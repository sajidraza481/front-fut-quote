#!/usr/bin/env bash
# One-time local setup after cloning. Safe to re-run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks
echo "Git hooks: .githooks (gitleaks pre-commit)"

mise trust --quiet .
mise install
fvm install
fvm dart pub get

echo "Done. Run: cd packages/quote_engine && fvm dart test"

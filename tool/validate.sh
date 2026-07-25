#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

test -z "$(git ls-files -- pubspec_overrides.yaml)"
git check-ignore -q pubspec_overrides.yaml
test -f pubspec_overrides.yaml

for dependency in beads_dart federated_grid_assets; do
  rg -q "^  ${dependency}: any$" packages/butane_grid_assets/pubspec.yaml
done

if rg -n '^  (grid_controller|grid_federation|grid_reconciler):' \
  packages/butane_grid_assets/pubspec.yaml pubspec_overrides.yaml; then
  echo 'obsolete grid dependency name remains' >&2
  exit 1
fi

for dependency in \
  leonard_agent \
  leonard_contract \
  leonard_flutter \
  beads_dart \
  federated_grid_assets \
  grid_diagnostics_contract; do
  rg -q "^  ${dependency}:" pubspec_overrides.yaml
done

dart pub get

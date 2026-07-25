#!/usr/bin/env bash
set -euo pipefail

for required_command in git grep dart; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "required tool not found: $required_command" >&2
    exit 127
  fi
done

repo_root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
cd "$repo_root"

test -z "$(git ls-files -- pubspec_overrides.yaml)"
git check-ignore -q pubspec_overrides.yaml
test -f pubspec_overrides.yaml

for dependency in \
  grid_assets \
  grid_cli \
  beads_dart \
  grid_engine \
  federated_grid_assets \
  grid_runtime \
  grid_exploration; do
  grep -Eq "^  ${dependency}: any$" packages/butane_grid_assets/pubspec.yaml
done

grep -Eq '^  sdk: \^3\.9\.0$' pubspec.yaml
grep -Eq '^  genesis_perception: \^0\.1\.3$' \
  packages/butane_harness/pubspec.yaml
grep -Eq '^  leonard_flutter: \^0\.1\.7$' \
  packages/butane_harness/pubspec.yaml

if grep -En '^  (grid_controller|grid_federation|grid_reconciler):' \
  packages/butane_grid_assets/pubspec.yaml pubspec_overrides.yaml; then
  echo 'obsolete grid dependency name remains' >&2
  exit 1
fi

for dependency in \
  grid_assets \
  dart_grid_assets \
  federated_grid_assets \
  beads_dart \
  grid_engine \
  grid_runtime \
  grid_sdk \
  leonard_flutter; do
  grep -Eq "^  ${dependency}:" pubspec_overrides.yaml
done

if grep -En '\.\./(lenny|the_grid|power_station|genesis)(/|$)' \
  pubspec_overrides.yaml; then
  echo 'stale sibling-checkout dependency path remains' >&2
  exit 1
fi

dart pub get

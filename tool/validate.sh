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

for dependency in beads_dart federated_grid_assets; do
  grep -Eq "^  ${dependency}: any$" packages/butane_grid_assets/pubspec.yaml
done

if grep -En '^  (grid_controller|grid_federation|grid_reconciler):' \
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
  grep -Eq "^  ${dependency}:" pubspec_overrides.yaml
done

dart pub get

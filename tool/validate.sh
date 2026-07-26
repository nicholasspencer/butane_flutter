#!/usr/bin/env bash
set -euo pipefail

trap 'status=$?; echo "validate.sh: failed at line $LINENO" >&2; exit "$status"' ERR

for required_command in git grep; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "validate.sh: required tool not found: $required_command" >&2
    exit 127
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

validate_repo() {
  if [[ -n "$(git ls-files -- pubspec_overrides.yaml)" ]]; then
    echo 'validate.sh: pubspec_overrides.yaml must remain untracked' >&2
    return 1
  fi
  if ! git check-ignore -q pubspec_overrides.yaml; then
    echo 'validate.sh: pubspec_overrides.yaml must remain ignored' >&2
    return 1
  fi

  # grid_cli left this list when butane_flutter-t9y deleted the ServeCommand
  # composition (the burn drives through the resident station; no CLI SDK dep).
  for dependency in \
    grid_assets \
    beads_dart \
    grid_engine \
    federated_grid_assets \
    grid_runtime \
    grid_exploration; do
    if ! grep -Eq "^  ${dependency}: any$" packages/butane_grid_assets/pubspec.yaml; then
      echo "validate.sh: expected tracked dependency declaration: ${dependency}: any" >&2
      return 1
    fi
  done

  if ! grep -Eq '^  sdk: \^3\.9\.0$' pubspec.yaml; then
    echo 'validate.sh: expected tracked SDK declaration: sdk: ^3.9.0' >&2
    return 1
  fi
  if ! grep -Eq '^  genesis_perception: \^0\.1\.3$' packages/butane_harness/pubspec.yaml; then
    echo 'validate.sh: expected tracked dependency declaration: genesis_perception: ^0.1.3' >&2
    return 1
  fi
  if ! grep -Eq '^  leonard_flutter: \^0\.1\.7$' packages/butane_harness/pubspec.yaml; then
    echo 'validate.sh: expected tracked dependency declaration: leonard_flutter: ^0.1.7' >&2
    return 1
  fi
}

validate_local() {
  if [[ ! -f pubspec_overrides.yaml ]]; then
    echo 'validate.sh: pubspec_overrides.yaml absent; skipping local dependency resolution'
    return 0
  fi

  local obsolete_key
  for obsolete_key in grid_controller grid_federation grid_reconciler; do
    if grep -Eq "^  ${obsolete_key}:" pubspec_overrides.yaml; then
      echo "validate.sh: obsolete override key: $obsolete_key" >&2
      return 1
    fi
  done

  if ! command -v dart >/dev/null 2>&1; then
    echo 'validate.sh: required tool not found: dart' >&2
    return 127
  fi
  dart pub get
}

case "${1:---repo}" in
  --repo)
    validate_repo
    ;;
  --local)
    validate_local
    ;;
  *)
    echo 'usage: validate.sh [--repo|--local]' >&2
    exit 64
    ;;
esac

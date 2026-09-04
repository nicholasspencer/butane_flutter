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

  # The burn pack must name the published wave explicitly. `any` cannot select
  # prereleases and previously let this workspace validate an obsolete engine
  # while Lunar supplied the incompatible current closure.
  while IFS='|' read -r file dependency constraint; do
    if ! grep -Fqx "  ${dependency}: ${constraint}" "$file"; then
      echo "validate.sh: expected tracked dependency declaration: ${dependency}: ${constraint}" >&2
      return 1
    fi
  done <<'DEPENDENCIES'
packages/butane_grid_assets/pubspec.yaml|genesis_tree|^0.3.0
packages/butane_grid_assets/pubspec.yaml|grid_assets|^0.6.0-rc.10
packages/butane_grid_assets/pubspec.yaml|beads_dart|^0.2.0-rc.7
packages/butane_grid_assets/pubspec.yaml|grid_engine|^0.3.0-rc.12
packages/butane_grid_assets/pubspec.yaml|federated_grid_assets|^0.3.0-rc.3
packages/butane_grid_assets/pubspec.yaml|grid_runtime|^0.2.0-rc.10
packages/butane_grid_assets/pubspec.yaml|grid_exploration|^0.3.0-rc.4
packages/butane_harness/pubspec.yaml|genesis_perception|^0.3.0
packages/butane_harness/pubspec.yaml|leonard_contract|^0.2.2
packages/butane_harness/pubspec.yaml|leonard_flutter|^0.3.1
DEPENDENCIES

  if ! grep -Eq '^  sdk: \^3\.9\.0$' pubspec.yaml; then
    echo 'validate.sh: expected tracked SDK declaration: sdk: ^3.9.0' >&2
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

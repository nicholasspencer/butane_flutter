#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/butane-validate.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/repo/tool" \
  "$fixture_root/repo/packages/butane_grid_assets" \
  "$fixture_root/repo/packages/butane_harness"
cp -f "$script_root/tool/validate.sh" "$fixture_root/repo/tool/validate.sh"
printf '%s\n' '**/pubspec_overrides.yaml' > "$fixture_root/repo/.gitignore"
printf '%s\n' 'environment:' '  sdk: ^3.9.0' > "$fixture_root/repo/pubspec.yaml"
printf '%s\n' \
  'dependencies:' \
  '  grid_assets: any' \
  '  grid_cli: any' \
  '  beads_dart: any' \
  '  grid_engine: any' \
  '  federated_grid_assets: any' \
  '  grid_runtime: any' \
  'dev_dependencies:' \
  '  grid_exploration: any' \
  > "$fixture_root/repo/packages/butane_grid_assets/pubspec.yaml"
printf '%s\n' \
  'dependencies:' \
  '  genesis_perception: ^0.1.3' \
  '  leonard_flutter: ^0.1.8' \
  > "$fixture_root/repo/packages/butane_harness/pubspec.yaml"

git -C "$fixture_root/repo" init -q
git -C "$fixture_root/repo" add .gitignore pubspec.yaml packages tool/validate.sh
git -C "$fixture_root/repo" \
  -c user.name='Validate Test' \
  -c user.email='validate@example.invalid' \
  commit -qm 'test fixture'

(
  cd "$fixture_root/repo"
  bash tool/validate.sh --repo
)

skip_output="$(
  cd "$fixture_root/repo"
  bash tool/validate.sh --local
)"
if [[ "$skip_output" != 'validate.sh: pubspec_overrides.yaml absent; skipping local dependency resolution' ]]; then
  echo "validate_test.sh: unexpected skip output: $skip_output" >&2
  exit 1
fi

for obsolete_key in grid_controller grid_federation grid_reconciler; do
  printf 'dependency_overrides:\n  %s: any\n' "$obsolete_key" \
    > "$fixture_root/repo/pubspec_overrides.yaml"
  if local_output="$(
    cd "$fixture_root/repo"
    bash tool/validate.sh --local 2>&1
  )"; then
    echo "validate_test.sh: obsolete key passed: $obsolete_key" >&2
    exit 1
  fi
  if [[ "$local_output" != *"validate.sh: obsolete override key: $obsolete_key"* ]]; then
    echo "validate_test.sh: missing diagnostic for: $obsolete_key" >&2
    exit 1
  fi
done
rm -f "$fixture_root/repo/pubspec_overrides.yaml"

(
  cd "$fixture_root/repo/tool"
  bash validate.sh --repo
)

echo 'validate_test.sh: all tests passed'

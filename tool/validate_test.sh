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
  '  genesis_tree: ^0.3.0' \
  '  grid_assets: ^0.6.0-rc.10' \
  '  beads_dart: ^0.2.0-rc.7' \
  '  grid_engine: ^0.3.0-rc.12' \
  '  federated_grid_assets: ^0.3.0-rc.3' \
  '  grid_runtime: ^0.2.0-rc.10' \
  'dev_dependencies:' \
  '  grid_exploration: ^0.3.0-rc.4' \
  > "$fixture_root/repo/packages/butane_grid_assets/pubspec.yaml"
printf '%s\n' \
  'dependencies:' \
  '  genesis_perception: ^0.3.0' \
  '  leonard_contract: ^0.2.2' \
  '  leonard_flutter: ^0.4.0' \
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

sed -i.bak 's/grid_assets: \^0.6.0-rc.10/grid_assets: any/' \
  "$fixture_root/repo/packages/butane_grid_assets/pubspec.yaml"
if repo_output="$(
  cd "$fixture_root/repo"
  bash tool/validate.sh --repo 2>&1
)"; then
  echo 'validate_test.sh: obsolete grid_assets constraint passed' >&2
  exit 1
fi
if [[ "$repo_output" != *'expected tracked dependency declaration: grid_assets: ^0.6.0-rc.10'* ]]; then
  echo 'validate_test.sh: missing current grid_assets floor diagnostic' >&2
  exit 1
fi
mv -f "$fixture_root/repo/packages/butane_grid_assets/pubspec.yaml.bak" \
  "$fixture_root/repo/packages/butane_grid_assets/pubspec.yaml"

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

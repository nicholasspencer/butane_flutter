#!/usr/bin/env bash
# Package analyze and test gates, shared by CI and local runs.
#
#   tool/ci.sh analyze   # dart/flutter analyze every package
#   tool/ci.sh test      # unit suites; live burns tagged `integration` excluded
#
# Run `flutter pub get` at the workspace root first.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pure-Dart packages use the Dart runner; `flutter test` cannot load them.
dart_packages=(
  butane_dart
  butane_dart_bluez
  butane_grid_assets
)

flutter_packages=(
  butane
  butane_android
  butane_bluez
  butane_core_bluetooth
  butane_harness
  butane_platform_interface
  butane_windows
)

failures=()

run() {
  local package="$1"
  shift
  echo "::group::${package}: $*"
  if ! (cd "$repo_root/packages/$package" && "$@"); then
    failures+=("${package}: $*")
  fi
  echo "::endgroup::"
}

case "${1:-}" in
  analyze)
    for package in "${dart_packages[@]}"; do
      run "$package" dart analyze --fatal-infos
    done
    for package in "${flutter_packages[@]}"; do
      run "$package" flutter analyze
    done
    ;;
  test)
    for package in "${dart_packages[@]}"; do
      run "$package" dart test -x integration
    done
    for package in "${flutter_packages[@]}"; do
      if [[ -d "$repo_root/packages/$package/test" ]]; then
        run "$package" flutter test
      fi
    done
    ;;
  *)
    echo "usage: tool/ci.sh analyze|test" >&2
    exit 64
    ;;
esac

if ((${#failures[@]})); then
  printf 'ci.sh: failed: %s\n' "${failures[@]}" >&2
  exit 1
fi

#!/usr/bin/env bash
# deploy.sh — build, install, launch harness on two selector-addressed devices
# and run `coordinator --discover` (mDNS). No IP addresses required.
#
# Vertical slice: central=local (macOS) + peripheral=udid:<iOS-UDID>.
set -euo pipefail

central="" peripheral="" scenario="ble_flow"
for arg in "$@"; do
  case "$arg" in
    --central=*)    central="${arg#--central=}" ;;
    --peripheral=*) peripheral="${arg#--peripheral=}" ;;
    --scenario=*)   scenario="${arg#--scenario=}" ;;
    *) echo "deploy: unknown arg '$arg'" >&2; exit 64 ;;
  esac
done
[[ -n "$central" && -n "$peripheral" ]] || { echo "deploy: --central and --peripheral required" >&2; exit 64; }

repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$repo/.burns"
log="$repo/.burns/${ts}-${scenario}.log"
harness="$repo/packages/butane_harness"

preflight_ssh() {
  local host="$1"
  # Local working tree must be clean.
  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    echo "deploy: working tree dirty — commit or stash before burning" >&2
    exit 2
  fi
  # 'linux' remote must exist.
  local remote_url
  remote_url="$(git -C "$repo" remote get-url linux 2>/dev/null || true)"
  [[ -n "$remote_url" ]] || {
    echo "deploy: no git remote 'linux' found — see docs/linux-dev-environment.md" >&2
    exit 2
  }
  # Remote URL host must match selector host (strip user@, trailing :path).
  local remote_host="${remote_url#*@}"
  remote_host="${remote_host%%:*}"
  local sel_host="${host#*@}"
  if [[ "$remote_host" != "$sel_host" ]]; then
    echo "deploy: linux remote host $remote_host does not match selector host $sel_host" >&2
    exit 2
  fi
  # Remote working tree must be clean.
  local dirty
  dirty="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" 'cd ~/butane_flutter && git status --porcelain' 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    echo "deploy: remote working tree at $host:~/butane_flutter is dirty" >&2
    exit 2
  fi
}

# Only the mac+ipad pair is supported in this slice.
if ! [[ "$central" == "local" && "$peripheral" == udid:* ]]; then
  echo "deploy: pair central=$central peripheral=$peripheral not supported in vertical slice" >&2
  exit 64
fi
udid="${peripheral#udid:}"

CENTRAL_PORT="${CENTRAL_PORT:-19100}"
PERIPHERAL_PORT="${PERIPHERAL_PORT:-19101}"

{
  echo "=== burn deploy: central=local peripheral=udid:$udid scenario=$scenario ==="

  # --- Kill any prior mac harness instances ---
  killall butane_harness 2>/dev/null || true
  sleep 1

  # --- Build macOS (central) ---
  echo "Building macOS harness (release)..."
  ( cd "$harness" && flutter build macos --release )
  mac_bundle="$harness/build/macos/Build/Products/Release/butane_harness.app"
  [[ -d "$mac_bundle" ]] || { echo "deploy: missing macOS app bundle $mac_bundle" >&2; exit 2; }

  # --- Build iOS (peripheral) with dart-defines baked in ---
  echo "Building iOS harness (release, ROLE=peripheral, WS_PORT=$PERIPHERAL_PORT)..."
  ( cd "$harness" && flutter build ios --release \
      --dart-define=ROLE=peripheral \
      --dart-define=WS_PORT="$PERIPHERAL_PORT" )
  ios_bundle="$harness/build/ios/iphoneos/Runner.app"
  [[ -d "$ios_bundle" ]] || { echo "deploy: missing iOS app bundle $ios_bundle" >&2; exit 2; }

  # --- Install on iPad via ios-deploy ---
  echo "Installing on iPad $udid..."
  ios-deploy --bundle "$ios_bundle" --id "$udid" --uninstall --no-wifi | tail -3

  # --- Resolve CoreDevice UUID (devicectl identifier) from iOS UDID via JSON ---
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  xcrun devicectl list devices --json-output "$tmp/devices.json" >/dev/null 2>&1 || true
  core_uuid="$(jq -r --arg udid "$udid" '.result.devices[] | select(.hardwareProperties.udid == $udid) | .identifier' "$tmp/devices.json" 2>/dev/null || true)"
  [[ -n "$core_uuid" ]] || { echo "deploy: could not map UDID $udid → CoreDevice UUID via devicectl" >&2; exit 2; }
  echo "CoreDevice UUID: $core_uuid"

  # --- Launch peripheral on iPad ---
  echo "Launching peripheral on iPad..."
  xcrun devicectl device process launch \
    --device "$core_uuid" \
    --terminate-existing \
    com.nicospencer.butaneHarness

  # --- Launch central on macOS ---
  echo "Launching central on macOS..."
  open -n "$mac_bundle" --env ROLE=central --env WS_PORT="$CENTRAL_PORT"

  # --- Let CoreBluetooth settle and mDNS advertise ---
  sleep 4

  # --- Run coordinator in mDNS discovery mode (no host args) ---
  echo ""
  echo "Running coordinator (--discover)..."
  cd "$repo"
  dart run packages/butane_coordinator/bin/coordinator.dart --discover --timeout 30
  rc=$?
  echo ""
  echo "Coordinator exited with code $rc"
  exit "$rc"
} 2>&1 | tee "$log"

echo "$log"
exit "${PIPESTATUS[0]}"

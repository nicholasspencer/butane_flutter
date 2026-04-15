#!/usr/bin/env bash
# deploy.sh — build, install, launch harness on two selector-addressed devices
# and run `coordinator --discover` (mDNS). No IP addresses required.
#
# Supported role selectors (either side):
#   central:    local | ssh:<user@host>
#   peripheral: local | ssh:<user@host> | udid:<iOS-UDID>
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

CENTRAL_PORT="${CENTRAL_PORT:-19100}"
PERIPHERAL_PORT="${PERIPHERAL_PORT:-19101}"

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

# --- Resolve each role to {kind, detail} ---
resolve_role() {
  local sel="$1"
  case "$sel" in
    local)  echo "local:" ;;
    ssh:*)  echo "ssh:${sel#ssh:}" ;;
    udid:*) echo "ipad:${sel#udid:}" ;;
    *) echo "deploy: selector '$sel' not supported" >&2; exit 64 ;;
  esac
}
central_resolved="$(resolve_role "$central")"
peripheral_resolved="$(resolve_role "$peripheral")"
central_kind="${central_resolved%%:*}"; central_detail="${central_resolved#*:}"
peripheral_kind="${peripheral_resolved%%:*}"; peripheral_detail="${peripheral_resolved#*:}"

# iPad is peripheral-only in this slice.
[[ "$central_kind" == "ipad" ]] && { echo "deploy: udid: not supported for central role" >&2; exit 64; }

# Preflight each ssh role up-front (fail fast before any build).
[[ "$central_kind"    == "ssh" ]] && preflight_ssh "$central_detail"
[[ "$peripheral_kind" == "ssh" ]] && preflight_ssh "$peripheral_detail"

# --- Teardown: remember every ssh host we touch and kill harness on exit ---
TEARDOWN_HOSTS=()
teardown() {
  local h
  for h in "${TEARDOWN_HOSTS[@]:-}"; do
    # Kill the harness and any avahi-publish-service children it spawned.
    # The advertiser subprocess is detached (ProcessStartMode.detachedWithStdio
    # in mdns_advertiser.dart), so it doesn't die when the harness is SIGTERM'd
    # — orphaned advertisements would pollute mDNS for future burns and cause
    # the coordinator to pick up stale endpoints.
    #
    # Kill-pattern gotchas:
    #   * `pkill -f avahi-publish-service` self-matches: the bash -c wrapper
    #     running this very command has that literal string in its cmdline,
    #     so pkill kills the ssh session before the true cleanup happens.
    #     Anchoring with `^avahi-publish-service ` avoids the self-match
    #     because the wrapper's cmdline starts with `bash`, not with the
    #     avahi binary.
    #   * `pkill avahi-publish-service` (no -f) refuses because /proc comm
    #     is truncated to 15 chars on Linux and pkill rejects longer names
    #     outright (verified: 'pattern that searches for process name
    #     longer than 15 characters will result in zero matches').
    ssh -o BatchMode=yes "$h" '
      pkill -x butane_harness 2>/dev/null
      pkill -f "^avahi-publish-service " 2>/dev/null
      true
    ' >/dev/null 2>&1 || true
  done
}
trap teardown EXIT

# --- Role launchers ---
launch_local() {
  local role="$1" port="$2"
  open -n "$mac_bundle" --env "ROLE=$role" --env "WS_PORT=$port"
}

launch_ssh() {
  local host="$1" role="$2" port="$3"
  TEARDOWN_HOSTS+=("$host")

  echo "Pushing HEAD to linux remote (refs/heads/burn)..."
  git -C "$repo" push --force linux HEAD:refs/heads/burn

  echo "Building harness on $host..."
  ssh -o BatchMode=yes "$host" '
    set -e
    cd ~/butane_flutter
    git fetch origin
    git checkout -B burn origin/burn
    export PATH=$HOME/flutter/bin:$PATH
    flutter pub get
    cd packages/butane_harness
    flutter build linux --release
  '

  echo "Launching $role on $host..."
  ssh -o BatchMode=yes "$host" "
    cd ~/butane_flutter/packages/butane_harness
    nohup env ROLE=$role WS_PORT=$port \
      ./build/linux/x64/release/bundle/butane_harness \
      > ~/.burn-harness.log 2>&1 &
    disown || true
  "
}

launch_ipad() {
  local udid="$1" port="$2"
  echo "Building iOS harness (release, ROLE=peripheral, WS_PORT=$port)..."
  ( cd "$harness" && flutter build ios --release \
      --dart-define=ROLE=peripheral \
      --dart-define=WS_PORT="$port" )
  local ios_bundle="$harness/build/ios/iphoneos/Runner.app"
  [[ -d "$ios_bundle" ]] || { echo "deploy: missing iOS app bundle $ios_bundle" >&2; exit 2; }

  echo "Installing on iPad $udid..."
  ios-deploy --bundle "$ios_bundle" --id "$udid" --uninstall --no-wifi | tail -3

  local tmp core_uuid
  tmp="$(mktemp -d)"
  xcrun devicectl list devices --json-output "$tmp/devices.json" >/dev/null 2>&1 || true
  core_uuid="$(jq -r --arg udid "$udid" '.result.devices[] | select(.hardwareProperties.udid == $udid) | .identifier' "$tmp/devices.json" 2>/dev/null || true)"
  rm -rf "$tmp"
  [[ -n "$core_uuid" ]] || { echo "deploy: could not map UDID $udid → CoreDevice UUID via devicectl" >&2; exit 2; }
  echo "CoreDevice UUID: $core_uuid"

  echo "Launching peripheral on iPad..."
  xcrun devicectl device process launch \
    --device "$core_uuid" \
    --terminate-existing \
    com.nicospencer.butaneHarness
}

{
  echo "=== burn deploy: central=$central peripheral=$peripheral scenario=$scenario ==="

  # --- Kill any prior local harness instances ---
  killall butane_harness 2>/dev/null || true
  sleep 1

  # --- Build macOS app once if either role is local ---
  if [[ "$central_kind" == "local" || "$peripheral_kind" == "local" ]]; then
    echo "Building macOS harness (release)..."
    ( cd "$harness" && flutter build macos --release )
    mac_bundle="$harness/build/macos/Build/Products/Release/butane_harness.app"
    [[ -d "$mac_bundle" ]] || { echo "deploy: missing macOS app bundle $mac_bundle" >&2; exit 2; }
  fi

  # --- Launch peripheral first (advertiser must be up before central scans) ---
  case "$peripheral_kind" in
    local) launch_local peripheral "$PERIPHERAL_PORT" ;;
    ssh)   launch_ssh   "$peripheral_detail" peripheral "$PERIPHERAL_PORT" ;;
    ipad)  launch_ipad  "$peripheral_detail" "$PERIPHERAL_PORT" ;;
  esac

  # --- Launch central ---
  case "$central_kind" in
    local) launch_local central "$CENTRAL_PORT" ;;
    ssh)   launch_ssh   "$central_detail" central "$CENTRAL_PORT" ;;
  esac

  # --- Let CoreBluetooth / BlueZ settle and mDNS advertise ---
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

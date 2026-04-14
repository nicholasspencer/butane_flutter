#!/usr/bin/env bash
set -euo pipefail

# run_harness.sh — Build and launch BLE test harness, run coordinator.
#
# Supports two modes:
#   1. macOS-only: both central and peripheral run as macOS apps (same machine)
#   2. Cross-device: central on macOS, peripheral on a connected iOS device
#
# Environment variables:
#   CENTRAL_PORT      — WebSocket port for central harness (default: 19100)
#   PERIPHERAL_PORT   — WebSocket port for peripheral harness (default: 19101)
#   HOST              — Coordinator host address (default: localhost)
#   TIMEOUT           — Command timeout in seconds (default: 30)
#   SKIP_BUILD        — Set to 1 to skip the build step
#   IOS_DEVICE        — iOS device UDID for peripheral role (enables cross-device mode)
#   IOS_DEVICE_UUID   — CoreDevice UUID for devicectl (auto-detected if not set)
#   PERIPHERAL_HOST   — IP/hostname of the iOS device for coordinator to reach it
#                       (required when IOS_DEVICE is set)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CENTRAL_PORT="${CENTRAL_PORT:-19100}"
PERIPHERAL_PORT="${PERIPHERAL_PORT:-19101}"
HOST="${HOST:-localhost}"
TIMEOUT="${TIMEOUT:-30}"
SKIP_BUILD="${SKIP_BUILD:-0}"
IOS_DEVICE="${IOS_DEVICE:-}"
IOS_DEVICE_UUID="${IOS_DEVICE_UUID:-}"
PERIPHERAL_HOST="${PERIPHERAL_HOST:-}"

# If IOS_DEVICE is set, we're in cross-device mode.
CROSS_DEVICE=0
if [[ -n "$IOS_DEVICE" ]]; then
  CROSS_DEVICE=1
  if [[ -z "$PERIPHERAL_HOST" ]]; then
    echo "ERROR: PERIPHERAL_HOST is required when IOS_DEVICE is set."
    echo "  Set PERIPHERAL_HOST to the IP address of the iOS device on the local network."
    exit 1
  fi
fi

# Auto-detect CoreDevice UUID if not provided.
if [[ "$CROSS_DEVICE" == "1" && -z "$IOS_DEVICE_UUID" ]]; then
  IOS_DEVICE_UUID=$(xcrun devicectl list devices 2>/dev/null | grep -i "iPad\|iPhone" | grep "connected" | awk '{print $NF}' | head -1 || true)
  if [[ -z "$IOS_DEVICE_UUID" ]]; then
    # Try to find from the devices list by matching device name/state
    IOS_DEVICE_UUID=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/{for(i=1;i<=NF;i++) if($i ~ /^[A-F0-9-]{36}$/) print $i}' | head -1 || true)
  fi
  if [[ -z "$IOS_DEVICE_UUID" ]]; then
    echo "WARNING: Could not auto-detect CoreDevice UUID for devicectl."
    echo "  Set IOS_DEVICE_UUID environment variable manually."
  fi
fi

cleanup() {
  echo ""
  echo "Cleaning up..."
  killall butane_harness 2>/dev/null || true
  sleep 1
  echo "Done."
}

trap cleanup EXIT INT TERM

wait_for_port() {
  local host="$1"
  local port="$2"
  local label="$3"
  local max_attempts=60
  local attempt=0

  echo "Waiting for $label on $host:$port..."
  while ! nc -z "$host" "$port" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      echo "ERROR: $label on $host:$port did not start within ${max_attempts}s"
      exit 1
    fi
    sleep 1
  done
  echo "  $label is ready on $host:$port"
}

echo "=== Butane BLE Test Harness ==="
echo ""
if [[ "$CROSS_DEVICE" == "1" ]]; then
  echo "Mode:            Cross-device (macOS central + iOS peripheral)"
  echo "iOS device:      $IOS_DEVICE"
  echo "CoreDevice UUID: ${IOS_DEVICE_UUID:-<not detected>}"
  echo "Peripheral host: $PERIPHERAL_HOST"
else
  echo "Mode:            macOS-only (both roles on this machine)"
fi
echo "Central port:    $CENTRAL_PORT"
echo "Peripheral port: $PERIPHERAL_PORT"
echo "Host:            $HOST"
echo "Timeout:         ${TIMEOUT}s"
echo ""

# --- Resolve dependencies ---
echo "Resolving dependencies..."
cd "$PROJECT_DIR"
dart pub get 2>&1
echo ""

# --- Build ---
if [[ "$SKIP_BUILD" != "1" ]]; then
  cd "$PROJECT_DIR/packages/butane_harness"

  # Always build macOS for the central role (no dart-defines — uses runtime env vars).
  echo "Building harness app (macOS release)..."
  flutter build macos --release 2>&1
  echo "  macOS build complete."
  echo ""

  if [[ "$CROSS_DEVICE" == "1" ]]; then
    # iOS build with dart-defines baked in (iOS can't use runtime env vars via open).
    echo "Building harness app (iOS release) for device $IOS_DEVICE..."
    flutter build ios --release \
      --dart-define=ROLE=peripheral \
      --dart-define=WS_PORT="$PERIPHERAL_PORT" \
      2>&1
    echo "  iOS build complete."
    echo ""

    # Install via ios-deploy (preserves the dart-defines from the build).
    echo "Installing iOS app via ios-deploy..."
    ios-deploy --bundle build/ios/iphoneos/Runner.app \
      --id "$IOS_DEVICE" --uninstall --no-wifi 2>&1 | tail -3
    echo "  iOS install complete."
    echo ""
  fi
fi

APP_BUNDLE="$PROJECT_DIR/packages/butane_harness/build/macos/Build/Products/Release/butane_harness.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: Could not find built macOS harness app at:"
  echo "  $APP_BUNDLE"
  exit 1
fi

echo "Using macOS app: $APP_BUNDLE"
echo ""

# --- Kill any existing instances ---
killall butane_harness 2>/dev/null || true
sleep 1

# --- Launch ---
echo "Launching harness instances..."

if [[ "$CROSS_DEVICE" == "1" ]]; then
  # Cross-device: peripheral on iOS, central on macOS.

  if [[ -n "$IOS_DEVICE_UUID" ]]; then
    echo "  Launching peripheral on iOS device via devicectl..."
    xcrun devicectl device process launch \
      --device "$IOS_DEVICE_UUID" \
      --terminate-existing \
      com.nicospencer.butaneHarness 2>&1
  else
    echo "  WARNING: No CoreDevice UUID. Attempting manual launch..."
    echo "  Please tap the butane_harness app icon on the iPad."
  fi
  echo "  Peripheral launching on iOS"

  # Launch central on macOS.
  open -n "$APP_BUNDLE" --env ROLE=central --env WS_PORT="$CENTRAL_PORT"
  echo "  Central harness launched (macOS)"
else
  # macOS-only: both roles on this machine.
  open -n "$APP_BUNDLE" --env ROLE=peripheral --env WS_PORT="$PERIPHERAL_PORT"
  echo "  Peripheral harness launched"

  open -n "$APP_BUNDLE" --env ROLE=central --env WS_PORT="$CENTRAL_PORT"
  echo "  Central harness launched"
fi

echo ""

# --- Wait for servers ---
if [[ "$CROSS_DEVICE" == "1" ]]; then
  wait_for_port "$PERIPHERAL_HOST" "$PERIPHERAL_PORT" "peripheral harness (iOS)"
else
  wait_for_port "localhost" "$PERIPHERAL_PORT" "peripheral harness"
fi
wait_for_port "localhost" "$CENTRAL_PORT" "central harness"

# Extra settle time for CoreBluetooth to transition to poweredOn.
echo "Waiting for BLE initialization..."
sleep 3

echo ""

# --- Determine coordinator args ---
if [[ "$CROSS_DEVICE" == "1" ]]; then
  COORD_PERIPHERAL_HOST="$PERIPHERAL_HOST"
else
  COORD_PERIPHERAL_HOST="$HOST"
fi

# --- Run coordinator ---
echo "Running coordinator..."
cd "$PROJECT_DIR"
dart run packages/butane_coordinator/bin/coordinator.dart \
  --central-port "$CENTRAL_PORT" \
  --peripheral-port "$PERIPHERAL_PORT" \
  --host "$HOST" \
  --peripheral-host "$COORD_PERIPHERAL_HOST" \
  --timeout "$TIMEOUT"

COORDINATOR_EXIT=$?
echo ""
echo "Coordinator exited with code $COORDINATOR_EXIT"
exit $COORDINATOR_EXIT

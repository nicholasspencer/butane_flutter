#!/usr/bin/env bash
set -euo pipefail

# run_harness.sh — Build and launch BLE test harness, run coordinator.
#
# By default, the coordinator discovers harness instances via mDNS.
# Set HOST to disable mDNS and use manual host/port addressing.
#
# Supports two modes:
#   1. macOS-only: both central and peripheral run as macOS apps (same machine)
#   2. Cross-device: central on macOS, peripheral on a connected iOS device
#
# Environment variables:
#   CENTRAL_PORT      — WebSocket port for central harness (default: 19100)
#   PERIPHERAL_PORT   — WebSocket port for peripheral harness (default: 19101)
#   TIMEOUT           — Command timeout in seconds (default: 30)
#   SKIP_BUILD        — Set to 1 to skip the build step
#   IOS_DEVICE        — iOS device UDID for peripheral role (enables cross-device mode)
#   IOS_DEVICE_UUID   — CoreDevice UUID for devicectl (auto-detected if not set)
#   HOST              — Set to disable mDNS and use this host (triggers --no-discover)
#   PERIPHERAL_HOST   — Host for peripheral harness (used with HOST; defaults to HOST)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CENTRAL_PORT="${CENTRAL_PORT:-19100}"
PERIPHERAL_PORT="${PERIPHERAL_PORT:-19101}"
TIMEOUT="${TIMEOUT:-30}"
SKIP_BUILD="${SKIP_BUILD:-0}"
IOS_DEVICE="${IOS_DEVICE:-}"
IOS_DEVICE_UUID="${IOS_DEVICE_UUID:-}"

# If IOS_DEVICE is set, we're in cross-device mode.
CROSS_DEVICE=0
if [[ -n "$IOS_DEVICE" ]]; then
  CROSS_DEVICE=1
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

echo "=== Butane BLE Test Harness ==="
echo ""
if [[ "$CROSS_DEVICE" == "1" ]]; then
  echo "Mode:            Cross-device (macOS central + iOS peripheral)"
  echo "iOS device:      $IOS_DEVICE"
  echo "CoreDevice UUID: ${IOS_DEVICE_UUID:-<not detected>}"
else
  echo "Mode:            macOS-only (both roles on this machine)"
fi
if [[ -n "${HOST:-}" ]]; then
  echo "Discovery:       disabled (HOST=$HOST)"
else
  echo "Discovery:       mDNS (default)"
fi
echo "Central port:    $CENTRAL_PORT"
echo "Peripheral port: $PERIPHERAL_PORT"
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

# --- Run coordinator ---
# mDNS discovery is the default — the coordinator will wait for harness instances
# to advertise before connecting. No need for wait_for_port or BLE sleep.
echo "Running coordinator..."
cd "$PROJECT_DIR"

COORD_ARGS=(--timeout "$TIMEOUT")

if [[ -n "${HOST:-}" ]]; then
  # Manual mode — disable mDNS, pass all connection details.
  COORD_ARGS+=(--no-discover)
  COORD_ARGS+=(--host "$HOST")
  COORD_ARGS+=(--central-port "$CENTRAL_PORT")
  COORD_ARGS+=(--peripheral-port "$PERIPHERAL_PORT")
  COORD_ARGS+=(--peripheral-host "${PERIPHERAL_HOST:-$HOST}")
fi

dart run packages/butane_coordinator/bin/coordinator.dart "${COORD_ARGS[@]}"

COORDINATOR_EXIT=$?
echo ""
echo "Coordinator exited with code $COORDINATOR_EXIT"
exit $COORDINATOR_EXIT

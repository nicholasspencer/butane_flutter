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
#   IOS_DEVICE        — iOS device ID for peripheral role (enables cross-device mode)
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

cleanup() {
  echo ""
  echo "Cleaning up..."
  killall butane_harness 2>/dev/null || true
  # Uninstall from iOS device is not automatic — app stays installed.
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

  # Always build macOS for the central role.
  echo "Building harness app (macOS release)..."
  flutter build macos --release 2>&1
  echo "  macOS build complete."
  echo ""

  if [[ "$CROSS_DEVICE" == "1" ]]; then
    echo "Building harness app (iOS debug) for device $IOS_DEVICE..."
    flutter build ios --debug 2>&1
    echo "  iOS build complete."
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
  echo "  Installing and launching peripheral on iOS device..."
  cd "$PROJECT_DIR/packages/butane_harness"
  flutter run -d "$IOS_DEVICE" \
    --dart-define=ROLE=peripheral \
    --dart-define=WS_PORT="$PERIPHERAL_PORT" \
    --no-hot-reload \
    --debug &
  IOS_PID=$!
  echo "  Peripheral launching on iOS (pid $IOS_PID)"

  # Launch central on macOS.
  open -n -a "$APP_BUNDLE" --env ROLE=central --env WS_PORT="$CENTRAL_PORT"
  echo "  Central harness launched (macOS)"
else
  # macOS-only: both roles on this machine.
  open -n -a "$APP_BUNDLE" --env ROLE=peripheral --env WS_PORT="$PERIPHERAL_PORT"
  echo "  Peripheral harness launched"

  open -n -a "$APP_BUNDLE" --env ROLE=central --env WS_PORT="$CENTRAL_PORT"
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
  # Coordinator connects to peripheral on the iOS device's IP.
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

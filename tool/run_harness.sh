#!/usr/bin/env bash
set -euo pipefail

# run_harness.sh — Build harness app, launch two instances (central + peripheral),
# run coordinator, clean up.
#
# Environment variables:
#   CENTRAL_PORT      — WebSocket port for central harness (default: 9100)
#   PERIPHERAL_PORT   — WebSocket port for peripheral harness (default: 9101)
#   HOST              — Host address (default: localhost)
#   TIMEOUT           — Command timeout in seconds (default: 30)
#   SKIP_BUILD        — Set to 1 to skip the build step

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CENTRAL_PORT="${CENTRAL_PORT:-19100}"
PERIPHERAL_PORT="${PERIPHERAL_PORT:-19101}"
HOST="${HOST:-localhost}"
TIMEOUT="${TIMEOUT:-30}"
SKIP_BUILD="${SKIP_BUILD:-0}"

cleanup() {
  echo ""
  echo "Cleaning up..."
  killall butane_harness 2>/dev/null || true
  sleep 1
  echo "Done."
}

trap cleanup EXIT INT TERM

wait_for_port() {
  local port="$1"
  local label="$2"
  local max_attempts=60
  local attempt=0

  echo "Waiting for $label on port $port..."
  while ! nc -z "$HOST" "$port" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      echo "ERROR: $label on port $port did not start within ${max_attempts}s"
      exit 1
    fi
    sleep 1
  done
  echo "  $label is ready on port $port"
}

echo "=== Butane BLE Test Harness ==="
echo ""
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
APP_BUNDLE="$PROJECT_DIR/packages/butane_harness/build/macos/Build/Products/Release/butane_harness.app"

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "Building harness app (macOS release)..."
  cd "$PROJECT_DIR/packages/butane_harness"
  flutter build macos --release 2>&1
  echo "  Build complete."
  echo ""
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: Could not find built harness app bundle at:"
  echo "  $APP_BUNDLE"
  exit 1
fi

echo "Using app: $APP_BUNDLE"
echo ""

# --- Kill any existing instances ---
killall butane_harness 2>/dev/null || true
sleep 1

# --- Launch ---
# Use 'open -n' to launch as proper macOS app processes.
# This is required for CoreBluetooth to receive delegate callbacks
# and transition past the 'unknown' state.
echo "Launching harness instances..."

open -n -a "$APP_BUNDLE" --env ROLE=peripheral --env WS_PORT="$PERIPHERAL_PORT"
echo "  Peripheral harness launched"

open -n -a "$APP_BUNDLE" --env ROLE=central --env WS_PORT="$CENTRAL_PORT"
echo "  Central harness launched"

echo ""

# --- Wait for servers ---
wait_for_port "$PERIPHERAL_PORT" "peripheral harness"
wait_for_port "$CENTRAL_PORT" "central harness"

# Extra settle time for CoreBluetooth to transition to poweredOn.
echo "Waiting for BLE initialization..."
sleep 3

echo ""

# --- Run coordinator ---
echo "Running coordinator..."
cd "$PROJECT_DIR"
dart run packages/butane_coordinator/bin/coordinator.dart \
  --central-port "$CENTRAL_PORT" \
  --peripheral-port "$PERIPHERAL_PORT" \
  --host "$HOST" \
  --timeout "$TIMEOUT"

COORDINATOR_EXIT=$?
echo ""
echo "Coordinator exited with code $COORDINATOR_EXIT"
exit $COORDINATOR_EXIT

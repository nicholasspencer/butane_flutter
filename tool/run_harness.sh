#!/usr/bin/env bash
set -euo pipefail

# run_harness.sh — Build both harness apps, launch them, run coordinator, clean up.
#
# Environment variables:
#   CENTRAL_PORT      — WebSocket port for central harness (default: 8080)
#   PERIPHERAL_PORT   — WebSocket port for peripheral harness (default: 8081)
#   HOST              — Host address (default: localhost)
#   TIMEOUT           — Command timeout in seconds (default: 15)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CENTRAL_PORT="${CENTRAL_PORT:-8080}"
PERIPHERAL_PORT="${PERIPHERAL_PORT:-8081}"
HOST="${HOST:-localhost}"
TIMEOUT="${TIMEOUT:-15}"

CENTRAL_PID=""
PERIPHERAL_PID=""

cleanup() {
  echo ""
  echo "Cleaning up..."
  if [[ -n "$CENTRAL_PID" ]]; then
    kill "$CENTRAL_PID" 2>/dev/null || true
    wait "$CENTRAL_PID" 2>/dev/null || true
    echo "  Stopped central harness (PID $CENTRAL_PID)"
  fi
  if [[ -n "$PERIPHERAL_PID" ]]; then
    kill "$PERIPHERAL_PID" 2>/dev/null || true
    wait "$PERIPHERAL_PID" 2>/dev/null || true
    echo "  Stopped peripheral harness (PID $PERIPHERAL_PID)"
  fi
  echo "Done."
}

trap cleanup EXIT INT TERM

wait_for_port() {
  local port="$1"
  local label="$2"
  local max_attempts=30
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

# --- Build ---
echo "Building harness apps..."
cd "$PROJECT_DIR"

# Build the central harness (macOS)
if [[ -d "packages/butane/example" ]]; then
  echo "  Building central harness..."
  cd "$PROJECT_DIR/packages/butane/example"
  flutter build macos 2>/dev/null || echo "  (central build skipped — not yet available)"
  cd "$PROJECT_DIR"
fi

# Build the peripheral harness (macOS)
if [[ -d "packages/butane_core_bluetooth/example" ]]; then
  echo "  Building peripheral harness..."
  cd "$PROJECT_DIR/packages/butane_core_bluetooth/example"
  flutter build macos 2>/dev/null || echo "  (peripheral build skipped — not yet available)"
  cd "$PROJECT_DIR"
fi

echo ""

# --- Launch ---
echo "Launching harness instances..."

# Launch central harness
# The harness apps are expected to accept --port and --role arguments.
# Adjust the path/args once harness beads are implemented.
CENTRAL_APP="packages/butane/example/build/macos/Build/Products/Release/example.app/Contents/MacOS/example"
if [[ -x "$PROJECT_DIR/$CENTRAL_APP" ]]; then
  "$PROJECT_DIR/$CENTRAL_APP" --port "$CENTRAL_PORT" --role central &
  CENTRAL_PID=$!
  echo "  Central harness started (PID $CENTRAL_PID)"
else
  echo "  WARNING: Central harness binary not found at $CENTRAL_APP"
  echo "  Attempting to launch via flutter run..."
  cd "$PROJECT_DIR/packages/butane/example"
  flutter run -d macos --dart-define=PORT="$CENTRAL_PORT" --dart-define=ROLE=central &
  CENTRAL_PID=$!
  cd "$PROJECT_DIR"
  echo "  Central harness started via flutter run (PID $CENTRAL_PID)"
fi

PERIPHERAL_APP="packages/butane_core_bluetooth/example/build/macos/Build/Products/Release/example.app/Contents/MacOS/example"
if [[ -x "$PROJECT_DIR/$PERIPHERAL_APP" ]]; then
  "$PROJECT_DIR/$PERIPHERAL_APP" --port "$PERIPHERAL_PORT" --role peripheral &
  PERIPHERAL_PID=$!
  echo "  Peripheral harness started (PID $PERIPHERAL_PID)"
else
  echo "  WARNING: Peripheral harness binary not found at $PERIPHERAL_APP"
  echo "  Attempting to launch via flutter run..."
  cd "$PROJECT_DIR/packages/butane_core_bluetooth/example"
  flutter run -d macos --dart-define=PORT="$PERIPHERAL_PORT" --dart-define=ROLE=peripheral &
  PERIPHERAL_PID=$!
  cd "$PROJECT_DIR"
  echo "  Peripheral harness started via flutter run (PID $PERIPHERAL_PID)"
fi

echo ""

# --- Wait for servers ---
wait_for_port "$CENTRAL_PORT" "central harness"
wait_for_port "$PERIPHERAL_PORT" "peripheral harness"

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

#!/bin/bash
# run_ble_verification.sh — Launch both harness apps and run BLE coordinator N times.
# Usage: ./run_ble_verification.sh [RUNS]
#
# Each run launches fresh harness apps, runs the coordinator, and cleans up.
# Exits 0 only if ALL runs pass.

set -euo pipefail

RUNS="${1:-3}"
WORKTREE="/Users/nico/development/com.nicospencer/butane_flutter/.worktrees/butane_flutter-41i"
HARNESS_DIR="$WORKTREE/packages/butane_harness"
IPAD_ID="00008110-001651523CE3801E"
IPAD_IP="192.168.4.36"
CENTRAL_PORT=19100
PERIPHERAL_PORT=19101
TIMEOUT=30

cleanup() {
  echo "Cleaning up..."
  pkill -f "butane_harness" 2>/dev/null || true
  # Kill flutter run processes for this project
  pkill -f "flutter.*run.*butane_harness" 2>/dev/null || true
  sleep 2
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local label="$3"
  local max_wait=30
  local i=0
  while ! nc -z "$host" "$port" 2>/dev/null; do
    sleep 1
    ((i++))
    if [ $i -ge $max_wait ]; then
      echo "FATAL: $label not reachable at $host:$port after ${max_wait}s"
      return 1
    fi
  done
  echo "  $label ready at $host:$port"
}

trap cleanup EXIT

passed=0

for run in $(seq 1 "$RUNS"); do
  echo ""
  echo "========================================"
  echo "=== Verification Run $run/$RUNS ==="
  echo "========================================"
  echo ""

  cleanup

  # Step 1: Launch macOS central via flutter run
  echo "Launching macOS central..."
  cd "$HARNESS_DIR"
  flutter run -d macos \
    --dart-define=ROLE=central \
    --dart-define=WS_PORT=$CENTRAL_PORT \
    </dev/null >/tmp/butane_macos.log 2>&1 &
  MACOS_PID=$!

  # Wait for macOS WS to be ready
  wait_for_port localhost $CENTRAL_PORT "macOS central" || { echo "Run $run FAILED (macOS launch)"; continue; }

  # Step 2: Launch iPad peripheral via flutter run
  echo "Launching iPad peripheral..."
  flutter run -d "$IPAD_ID" \
    --dart-define=ROLE=peripheral \
    --dart-define=WS_PORT=$PERIPHERAL_PORT \
    </dev/null >/tmp/butane_ipad.log 2>&1 &
  IPAD_PID=$!

  # Wait for iPad WS to be ready
  wait_for_port "$IPAD_IP" $PERIPHERAL_PORT "iPad peripheral" || { echo "Run $run FAILED (iPad launch)"; continue; }

  echo ""
  echo "Both harness apps ready. Running coordinator..."
  echo ""

  # Step 3: Run coordinator
  cd "$WORKTREE"
  if dart run packages/butane_coordinator/bin/coordinator.dart \
    --central-port $CENTRAL_PORT \
    --peripheral-port $PERIPHERAL_PORT \
    --host localhost \
    --peripheral-host "$IPAD_IP" \
    --timeout $TIMEOUT; then
    echo ""
    echo "Run $run: PASSED ✓"
    ((passed++))
  else
    echo ""
    echo "Run $run: FAILED ✗"
    echo ""
    echo "Aborting remaining runs."
    break
  fi
done

echo ""
echo "========================================"
echo "Results: $passed/$RUNS passed"
echo "========================================"

if [ "$passed" -eq "$RUNS" ]; then
  echo "ALL $RUNS RUNS PASSED ✓"
  exit 0
else
  echo "FAILED — only $passed/$RUNS passed ✗"
  exit 1
fi

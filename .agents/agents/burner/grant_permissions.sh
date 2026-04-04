#!/usr/bin/env bash
set -euo pipefail

# grant_permissions.sh — Pre-grant Bluetooth permissions for harness apps.
#
# macOS TCC resets permissions when code signatures change (every Flutter
# debug rebuild with ad-hoc signing). This script inserts grants directly
# into the user-level TCC database so harness apps can access Bluetooth
# without manual interaction.
#
# Usage:
#   ./grant_permissions.sh [BUNDLE_ID...]
#
# If no bundle IDs are provided, uses the default harness bundle IDs.
#
# Requirements:
#   - Terminal must have Full Disk Access (System Settings → Privacy)
#   - sqlite3 must be available
#   - SIP must not block user TCC.db writes (it shouldn't for user-level)

TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

# Harness bundle IDs — both examples currently share the same ID.
# TODO: The central example (butane/example) should have its own bundle ID
#       (e.g. com.nicospencer.butaneCentralExample) to avoid TCC/macOS
#       conflicts when running both simultaneously.
DEFAULT_BUNDLE_IDS=(
  "com.nicospencer.butaneCoreBluetoothExample"
)

BUNDLE_IDS=("${@:-${DEFAULT_BUNDLE_IDS[@]}}")

if [[ ! -f "$TCC_DB" ]]; then
  echo "ERROR: TCC database not found at: $TCC_DB"
  echo "This script only works on macOS."
  exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
  echo "ERROR: sqlite3 not found"
  exit 1
fi

echo "=== Bluetooth Permission Pre-Grant ==="
echo ""

for BUNDLE_ID in "${BUNDLE_IDS[@]}"; do
  # Check current state
  CURRENT=$(sqlite3 "$TCC_DB" \
    "SELECT auth_value FROM access WHERE service='kTCCServiceBluetoothAlways' AND client='$BUNDLE_ID';" 2>/dev/null || echo "")

  if [[ "$CURRENT" == "2" ]]; then
    echo "✅ $BUNDLE_ID — already granted"
    continue
  fi

  echo "🔧 $BUNDLE_ID — granting Bluetooth access..."

  sqlite3 "$TCC_DB" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) \
     VALUES ('kTCCServiceBluetoothAlways', '$BUNDLE_ID', 0, 2, 3, 1, 0, 'UNUSED', 0, CAST(strftime('%s','now') AS INTEGER));" 2>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "   ✅ Granted"
  else
    echo "   ❌ Failed — does Terminal have Full Disk Access?"
  fi
done

echo ""
echo "Done. Permissions should persist until bundle IDs change."

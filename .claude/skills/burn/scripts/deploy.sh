#!/usr/bin/env bash
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

if [[ "$central" == "local" && "$peripheral" == udid:* ]]; then
  udid="${peripheral#udid:}"
  [[ -n "${PERIPHERAL_HOST:-}" ]] || { echo "deploy: export PERIPHERAL_HOST=<iPad LAN IP>" >&2; exit 2; }
  IOS_DEVICE="$udid" "$repo/tool/run_harness.sh" 2>&1 | tee "$log"
  echo "$log"
  exit "${PIPESTATUS[0]}"
fi
echo "deploy: pair central=$central peripheral=$peripheral not supported in vertical slice" >&2
exit 64

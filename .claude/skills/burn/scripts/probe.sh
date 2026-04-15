#!/usr/bin/env bash
set -euo pipefail
sel="${1:?usage: probe.sh <selector>}"
case "$sel" in
  local) echo "probe: local ok" ;;
  udid:*)
    udid="${sel#udid:}"
    command -v ios-deploy >/dev/null || { echo "probe: $sel ios-deploy not available" >&2; exit 2; }
    out=$(ios-deploy -c --timeout 5 2>/dev/null || true)
    if printf '%s\n' "$out" | grep -qi "$udid"; then echo "probe: $sel ok"
    else echo "probe: $sel not found via ios-deploy" >&2; exit 3; fi ;;
  ssh:*)
    target="${sel#ssh:}"
    command -v ssh >/dev/null || { echo "probe: $sel ssh not available" >&2; exit 2; }
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" true 2>/dev/null; then
      echo "probe: $sel ok"
    else
      echo "probe: $sel ssh to $target failed (auth, timeout, or host unreachable)" >&2
      exit 3
    fi ;;
  adb:*|mdns:*) echo "probe: ${sel%%:*}: not implemented in vertical slice" >&2; exit 64 ;;
  *) echo "probe: unrecognized selector '$sel'" >&2; exit 65 ;;
esac

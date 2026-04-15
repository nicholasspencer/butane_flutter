#!/usr/bin/env bash
set -euo pipefail
sel="${1:?usage: probe.sh <selector>}"
case "$sel" in
  local) echo "probe: local ok" ;;
  udid:*)
    udid="${sel#udid:}"
    command -v xcrun >/dev/null || { echo "probe: $sel xcrun not available" >&2; exit 2; }
    out=$(perl -e 'alarm shift; exec @ARGV' 5 xcrun devicectl list devices 2>/dev/null || true)
    if printf '%s\n' "$out" | grep -qi "$udid"; then echo "probe: $sel ok"
    else echo "probe: $sel not found via devicectl" >&2; exit 3; fi ;;
  adb:*|ssh:*|mdns:*) echo "probe: ${sel%%:*}: not implemented in vertical slice" >&2; exit 64 ;;
  *) echo "probe: unrecognized selector '$sel'" >&2; exit 65 ;;
esac

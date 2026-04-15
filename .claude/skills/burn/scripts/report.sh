#!/usr/bin/env bash
set -euo pipefail
log="" scenario="" bead=""
for arg in "$@"; do
  case "$arg" in
    --log=*)      log="${arg#--log=}" ;;
    --scenario=*) scenario="${arg#--scenario=}" ;;
    --bead=*)     bead="${arg#--bead=}" ;;
    *) echo "report: unknown arg '$arg'" >&2; exit 64 ;;
  esac
done
[[ -f "$log" && -n "$scenario" ]] || { echo "report: --log=<file> and --scenario=<name> required" >&2; exit 64; }

line="$(grep -E '^Coordinator exited with code [0-9]+' "$log" | tail -1 || true)"
code="$(printf '%s' "$line" | awk '{print $NF}')"; [[ -n "$code" ]] || code=1
result=$([[ "$code" == 0 ]] && echo pass || echo fail)
base="${log%.log}"; json="${base}.json"; md="${base}.md"
fin="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"scenario":"%s","result":"%s","exit_code":%s,"log":"%s","finished_at":"%s"}\n' \
  "$scenario" "$result" "$code" "$log" "$fin" >"$json"
{ echo "# burn: $scenario — $result"; echo; echo "- Exit: \`$code\`"; echo "- Log: \`$log\`"; echo "- Finished: $fin"; } >"$md"
if [[ -n "$bead" ]]; then
  bd comments add "$bead" "burn: $scenario — $result (exit $code)
JSON: $json
MD:   $md" >/dev/null
fi
[[ "$code" == 0 ]] || exit "$code"

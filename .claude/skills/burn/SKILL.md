---
name: burn
description: >
  Launch the butane harness on two selector-addressed devices, run a coordinator
  scenario between them, and write a report to .burns/. Platform playbooks are
  loaded on demand based on selector kind.
---

# Burn

## Inputs
- `central=<selector>` (required), `peripheral=<selector>` (required)
- `scenario=<name>` (default `ble_flow`), `bead=<id>` (optional)

## Selector grammar
| Selector              | Platform | Probe channel                      |
|-----------------------|----------|------------------------------------|
| `local`               | macos    | this host                          |
| `udid:<UDID>`         | ios      | `ios-deploy -c --timeout 5`        |
| `adb:<serial>`        | android  | `adb devices`                      |
| `ssh:<user@host>`     | linux    | `ssh -o ConnectTimeout=3 … true`   |
| `mdns:<service-name>` | any      | `dns-sd -B _butane-harness._tcp`   |

## Flow
1. For each selector: resolve → platform; run `scripts/probe.sh <selector>`. Abort on first failure.
2. Load **only** the matching `references/platforms/<platform>.md` per resolved selector (progressive disclosure — never preload all).
3. Load `references/coordinator.md` (always).
4. `scripts/deploy.sh --central=<sel> --peripheral=<sel> [--scenario=<name>]` — writes combined output to `.burns/<UTC-iso>-<scenario>.log`.
5. `scripts/report.sh --log=<log> --scenario=<name> [--bead=<id>]` — emits sibling `.json` + `.md` and (if bead set) posts a bead comment.
6. Exit with coordinator's exit code. On failure, load `references/troubleshooting.md`.

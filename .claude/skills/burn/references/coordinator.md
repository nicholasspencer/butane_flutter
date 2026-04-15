# Coordinator invocation
Prefer: `dart run packages/butane_coordinator/bin/coordinator.dart --discover --timeout <s>` — resolves both endpoints via mDNS (`_butane-harness._tcp`). No host/port flags needed.

Fallback (explicit): `--central-port <p> --peripheral-port <p> --host <h> --peripheral-host <h>`.

Common: `--runs <n> --discover-timeout <s>`.

Pass/fail marker: last line matching `^Coordinator exited with code (\d+)$` — 0 is pass. `scripts/report.sh` depends on this marker.

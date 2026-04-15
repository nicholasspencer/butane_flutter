# Coordinator invocation
`dart run packages/butane_coordinator/bin/coordinator.dart --central-port <p> --peripheral-port <p> --host <h> --peripheral-host <h> --timeout <s> --runs <n>`

Pass/fail marker: last line matching `^Coordinator exited with code (\d+)$` — 0 is pass. `scripts/report.sh` depends on this marker.

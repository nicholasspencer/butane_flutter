# butane_harness

A dual-role Flutter integration app for exercising Butane over real BLE radios. `ROLE=central` exposes the central command registry; `ROLE=peripheral` exposes the peripheral registry. `ButaneLeonardExtension` publishes that registry as `ext.exploration.butane.*` tools and publishes role state through perception on the Dart VM service.

This package is integration scaffolding, not a product. It directly depends on the platform packages needed by Flutter plugin registration.

## Configuration

`HarnessConfig.fromEnvironment()` reads one required value:

| Value | Meaning |
|---|---|
| `ROLE=central` | Scan, connect, discover, read, write, subscribe, and disconnect. |
| `ROLE=peripheral` | Configure services, advertise, answer ATT requests, and publish notifications. |

Use `--dart-define=ROLE=<role>` on iOS. Desktop launchers may set `ROLE` in the process environment. Use debug or profile mode so the app exposes the Dart VM service.

## Burn integration

`butane_grid_assets` launches the harness, scrapes its `GRID_VM_URI=` readiness sentinel, and drives its Leonard extension. See `docs/burn-workflow.md` for the current host/follower workflow.

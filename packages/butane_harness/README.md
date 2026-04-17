# butane_harness

Flutter app that hosts a Butane BLE role (central **or** peripheral)
behind a WebSocket control plane, so that
[`butane_coordinator`](../butane_coordinator) can drive it through
scripted integration scenarios. This is **integration-test
scaffolding**, not a product.

The harness imports `butane` directly but also pins direct deps on
`butane_core_bluetooth` and `butane_platform_interface` — Flutter's
Dart plugin registrant only walks direct dependencies when wiring up
`dartPluginClass`, so the indirect path through `butane`'s
`default_package` isn't enough.

## Two transport modes

- **Server mode** — harness listens on a local port; the coordinator
  connects in. Uses `nsd` for mDNS advertisement on the LAN.
- **Client-bridge mode** — harness dials out to a relay (see
  [`tool/ws_relay.dart`](../../tool/ws_relay.dart)), useful when
  harness and coordinator can't reach each other directly.

## Configuration

`HarnessConfig.fromEnvironment()` reads three flags (dart-defines first,
runtime env as fallback):

| Flag           | Required | Meaning |
|----------------|----------|---------|
| `ROLE`         | yes      | `central` or `peripheral` |
| `WS_PORT`      | yes      | Port the harness listens on (server mode) |
| `WS_RELAY_URL` | no       | If set, dial this relay instead of listening (used with [`tool/ws_relay.dart`](../../tool/ws_relay.dart) when the device can't accept inbound connections) |

iOS must pass these as `--dart-define` at build time (no runtime env).
macOS accepts them via `open -n ... --env`. Linux accepts them via
`env FLAG=VALUE ./butane_harness`.

## Running a burn

Harnesses are usually launched by the `/burn` skill, which handles
selector-addressed device launching, coordinator dispatch, and report
collection in `.burns/`. See
[`docs/burn-workflow.md`](../../docs/burn-workflow.md) for the full
operational walkthrough — git remote setup, SSH orchestration,
per-platform launch commands, and report artifacts.

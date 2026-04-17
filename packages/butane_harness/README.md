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

## Running a burn

Harnesses are usually launched by the `burn` skill, which handles
selector-addressed device launching, coordinator dispatch, and report
collection in `.burns/`. See
[`docs/harness-verification.md`](../../docs/harness-verification.md)
for the manual flow.

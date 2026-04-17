# butane_coordinator

CLI tool (Dart, not Flutter) that drives
[`butane_harness`](../butane_harness) instances over WebSocket to run
scripted BLE integration scenarios.

Typical setup: one harness acting as **central** on one device, another
acting as **peripheral** on a second device, both connected to the
coordinator. The coordinator sequences the scenario — advertise,
scan, connect, discover, read/write, notify — and emits a pass/fail
report per step with timings, written to the repo's `.burns/`
directory.

## Discovery

Harnesses can be reached two ways:

- **Direct WebSocket** to a harness listening on a known host:port.
- **mDNS (`multicast_dns`)** for LAN autodiscovery.

## Running

```bash
dart run packages/butane_coordinator/bin/coordinator.dart --help
```

Higher-level workflow (launch harnesses + run a scenario + capture
report) is orchestrated by the `burn` skill; see
[`docs/harness-verification.md`](../../docs/harness-verification.md)
for the end-to-end guide.

## When to touch this package

Adding a new integration scenario, changing the pass/fail format, or
adjusting timing thresholds. The wire protocol between coordinator and
harness lives here and in the harness app; keep both sides in sync.

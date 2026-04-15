# Linux (ssh:<user@host>)

## Assumptions
- Target set up per `docs/linux-dev-environment.md` (Ubuntu + Flutter + BlueZ + SSH key auth).
- Remote has a working copy at `~/butane_flutter` tracking a bare repo at `~/butane_flutter.git`.
- The host in the selector matches the `linux` git remote URL host (deploy checks this).
- User on the target is in the `bluetooth` group and has verified scanning works. No runtime TCC equivalent on Linux.

## Build + launch
- Push local HEAD to a skill-owned branch:
  `git push --force linux HEAD:refs/heads/burn`
- Build on target:
  `ssh <host> 'cd ~/butane_flutter && git fetch && git checkout burn && export PATH=$HOME/flutter/bin:$PATH && flutter pub get && cd packages/butane_harness && flutter build linux --release'`
- Artifact: `~/butane_flutter/packages/butane_harness/build/linux/x64/release/bundle/butane_harness`
- Launch (backgrounded, env vars for runtime config):
  `ssh <host> 'cd ~/butane_flutter/packages/butane_harness && nohup env ROLE=peripheral WS_PORT=19101 ./build/linux/x64/release/bundle/butane_harness > ~/.burn-harness.log 2>&1 &'`
- mDNS advertisement from the harness lets the local coordinator find it with `--discover`; no IPs needed.

## Teardown
- `ssh <host> 'pkill -f butane_harness || true'` on EXIT trap. Ignore non-zero.

## Troubleshooting
- SSH fails: see probe error — usually missing key or mDNS/avahi dropout.
- BLE fails: `groups` on target must include `bluetooth`. `bluetoothctl show` should report `Powered: yes`. Full setup in `docs/linux-dev-environment.md`.
- Remote harness log: `ssh <host> 'cat ~/.burn-harness.log'`.

## Known blockers
The deployment pipeline (probe → preflight → push → build → launch → teardown) works end-to-end.
The coordinator `--discover` stage currently cannot find a Linux harness because:
- **butane_flutter-zod**: `nsd` Flutter package has no Linux backend, so `HarnessServer.register()` silently no-ops on Linux.
- **butane_flutter-8h5.6 / 8h5.7**: BlueZ peripheral role (advertising + GATT services) is not yet implemented, so even if mDNS worked, the peripheral wouldn't respond to the coordinator's BLE flow.

Both are harness-side gaps orthogonal to the burn skill. When either lands, the corresponding burn direction (Linux as central vs. Linux as peripheral) goes green with no burn-skill changes.

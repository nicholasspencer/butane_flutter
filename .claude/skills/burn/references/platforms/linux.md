# Linux (ssh:<user@host>)

## Assumptions
- Target set up per `docs/linux-dev-environment.md` (Ubuntu + Flutter + BlueZ + SSH key auth).
- Remote has a working copy at `~/butane_flutter` tracking a bare repo at `~/butane_flutter.git`.
- The host in the selector matches the `linux` git remote URL host (deploy checks this).
- User on the target is in the `bluetooth` group and has verified scanning works. No runtime TCC equivalent on Linux.
- `avahi-utils` installed on the target (for `avahi-publish-service`, used by the harness to advertise its mDNS service). Ubuntu desktop ships it by default; on a minimal install: `sudo apt install avahi-utils`.

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
No known blockers for the mac-central ↔ linux-peripheral burn direction. Full `ble_flow` (15 steps) passes green as of 2026-04-16 (8h5.6 advertising + 8h5.7 GATT server implemented).

Linux-as-central direction is blocked by **butane_flutter-8h5.5** (Central — Read/Write/Notify) — the central can scan, connect, and discover services, but read/write/notify characteristic operations are not yet implemented.

Teardown note: orphan harness processes from crashed or interrupted burns can pollute mDNS and misdirect the coordinator. `pkill -x butane_harness; pkill -f "^avahi-publish-service "` on the Linux host clears them.

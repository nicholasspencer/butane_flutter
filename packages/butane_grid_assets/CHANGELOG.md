# Changelog

## 0.2.0-rc.4

- Fixed: raised the `genesis_tree` floor to `^0.4.0`, `grid_sdk` to `^0.4.0-dev.3`,
  `beads_dart` to `^0.3.0-dev.2`, `grid_engine` to `^0.4.0-dev.3`, and `grid_runtime` to
  `^0.2.1-dev.2` so the package admits the the_grid dev.3 wave and lunar's xvk closure
  resolves override-free (butane_flutter-typ2); `grid_assets` moves to `^0.7.0-dev.2` in
  step. `federated_grid_assets` and `grid_exploration` resolve within their existing
  floors — no constraint change needed there.
  Migration (internal only, no public API change): `grid_engine`'s
  `Capability.createAllocation` now takes `AllocationInputs` (the `treeContext` field
  moved off it) and `Allocation.startOrAdopt` takes the `TreeContext` directly as its
  argument — `_PublishedFollowerAllocation` (the resident burn follower's daemon
  allocation) and the test doubles that construct an allocation by hand migrate to the
  new shape; behavior is unchanged.

## 0.2.0-rc.3

- Fixed: raised the `grid_assets` floor to `^0.7.0-dev.1` (from `^0.6.0-rc.10`) so the
  package admits the current wave and lunar's closure resolves override-free
  (butane_flutter-vo0j). No other constraint changed; the resolved `grid_sdk`,
  `grid_engine`, and `grid_runtime` versions still satisfy their existing floors.

## 0.2.0-rc.2

- Added: the top-level `grid:` block declaring the `burn` skill pair, with the generated
  `GridAssetsPack` declaration and the `extension/mcp/config.yaml` mirror rendered by the
  vended generator (`tool/generate_grid_assets.dart`), so the pack joins a station's generated
  registrant and the burn skill installs and materializes again (butane_flutter-eb0r, #109).
- Changed: `dart_style` is pinned `>=3.1.7 <3.1.8` as a dev dependency so the generator's
  formatter matches the SDK's until pow-5ifa's fix ships in grid_assets.

## 0.2.0-rc.1

- Breaking: moved the burn asset pack onto the current Genesis/Grid release
  train, including `grid_runtime ^0.2.0-rc.10` and
  `grid_engine ^0.3.0-rc.12`; consumers on the earlier Genesis/Grid closure
  must opt into this release candidate explicitly.
  Migration: change the consumer constraint from `^0.1.0` to
  `^0.2.0-rc.1` and resolve the current Grid release train with it.
- Fixed: resident burn followers treat `RuntimeEvent.sessionOrphaned` as a
  recorded, non-terminal observation, remaining supervised until the runtime
  emits its eventual terminal or the follower publishes its endpoint.
- Fixed: the test process/runtime fakes now implement the interfaces added by
  the current runtime wave.

## 0.1.0

First tagged release — the butane burn asset pack (resident burn circuit +
burn station registry) consumed by lunar_station as a git-tag dependency
(`butane_grid_assets-v{{version}}`).

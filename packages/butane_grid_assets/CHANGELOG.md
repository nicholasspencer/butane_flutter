# Changelog

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

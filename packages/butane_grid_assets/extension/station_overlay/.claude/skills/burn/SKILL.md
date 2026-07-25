---
name: burn
description: >
  File or refine a cross-device butane burn as resident-station work, then read
  its circuit receipts. Use for BLE scenarios spanning a host and follower.
---

# Burn

A burn is a bead driven by the already-running resident station. This skill
never starts a station and never invokes a second grid.

## Inputs

Collect `peer=<host:port>`, `scenario=<name>` (default `smoke`),
`harness-dir=<path>`, `follower-target=<target>` (default `linux`), and whether
the local central harness is enabled. Reject a missing peer or harness path
before mutating the store.

## File or refine the work

Search the local butane store for an open burn bead matching the scenario. If
none exists, create a staged driveable bead:

```bash
bd create --title "Burn: <scenario> via <peer>" --type task --ephemeral \
  --defer "$(date -v+7d +%Y-%m-%d)" --actor operator \
  --description "Resident burn request: peer=<peer>; scenario=<scenario>; harness-dir=<path>; follower-target=<target>; local=<true|false>. The burn circuit leases the follower over the federation bus and drives both harnesses directly through Leonard." \
  --acceptance "- [ ] The resident burn circuit records a TestReport receipt for <scenario>\n- [ ] The follower lease and both direct drive channels are released"
```

For an existing bead, use its explicit id with `bd update <id> --actor operator`
to replace the request description and acceptance criteria. Never call
`bd update` with an empty id. After the request is complete, promote it with
`bd update <id> --persistent --actor operator`. Show the final bead and ask the
operator to bless it by removing the defer date; do not bless without that
explicit confirmation.

## Read receipts

Use `bd show <id>` and report the burn circuit's follower rendezvous, host
`TestReport`, critique/telemetry/artifact links, failure reason, and teardown
result present on the bead/session records. If the work is still deferred,
ready, or active, report that state instead of inventing a result. Richer
per-device audit is tracked separately and is not synthesized here.

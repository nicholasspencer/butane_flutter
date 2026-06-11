#!/usr/bin/env bash
# Install factoryskills' OWN rig committee skills — the dogfood (ADR 0011/0012/0013).
#
# factoryskills runs the GENERIC, stack-neutral pack on itself, then injects its
# Go opinions (go test/build/gofmt) through its rig overlay (.gascity-pack). This
# composes the two into the rig's committee skills so the committee — which
# resolves the rig's OWN skills, rig-local-first (ADR 0013) — grades
# factoryskills' Go code with the Go rubrics. Confirm with `fs config committee`.
#
# Idempotent. Run it once per dev city / checkout, and again after editing
# skills/ (it composes COPIES, not the devmode symlinks `fs init --dev` makes, so
# source edits are not live in the committee until re-composed). Local-only:
# .agents/skills and .claude/skills are gitignored.
#
# Requires a current `fs` on PATH (one with `fs init --overlay` + rig-local
# committee resolution). In the container dev venue: container/e2e-setup.sh
# rebuilds fs from /workspace first; on a host, `go install ./cmd/fs`.
set -euo pipefail

cd "$(dirname "$0")/.."
OVERLAY=".gascity-pack/overlay/.claude/skills"
[ -d "$OVERLAY" ] || { echo "missing $OVERLAY — run from a factoryskills checkout" >&2; exit 1; }

# The rig repo is already bd-initialized (the city manages it); fs init's
# bd-config steps are idempotent no-ops here. The load-bearing effect is the
# skills install + Go overlay, which run BEFORE fs init's formula step — and that
# step can fail in a dolt-migrated repo whose .beads/formulas/*.json fixtures
# were dropped (factoryskills-<bug>). That failure is benign for the committee;
# verify the real outcome with `fs config committee` below.
if ! fs init --claude --overlay "$OVERLAY"; then
	echo "note: fs init returned non-zero (likely the formula-install step in a" >&2
	echo "      dolt-migrated repo). Skills + overlay run first; verifying below." >&2
fi

echo
echo "Committee now grades with (rig-local, ADR 0013):"
fs config committee

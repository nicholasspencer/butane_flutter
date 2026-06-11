---
name: regression-risk
version: 1
phase: code
on_grade:
  D: { verdict: revise, hint: rebuild }
  F: { verdict: block }
---

## Summary

Regression-risk measures whether landing this diff is safe for everything
the diff was *not* about. The full test suite passes, the analyzer is clean,
formatting is clean, and no existing public surface changes behavior. A diff
that adds a feature but breaks an unrelated package — or leaves the suite red —
is high risk regardless of how good the new code is.

Conversely, a diff that modifies **no existing production file** — it only
adds new files, or its only edits are to `*_test.dart` and test fixtures — has
~zero regression blast radius: there is no existing behavior for it to
break. Grade such a diff on the suite/analyze state alone, not on its content.
A golden-file or fixture test that will fail when intended output later
changes is exhibiting its **designed** behavior; that brittleness is not a
regression hazard and must not pull the grade down.

**What to read.** The diff: `git diff $(git merge-base main <branch>)..<branch>`.
Run `dart test` / `flutter test`, `dart analyze`, and `dart format
--output=none --set-exit-if-changed .` against the branch (and any project lint
the Validation Plan names). The spec: the bead's `## Validation Plan` for the
canonical check commands.

## Grades

### A
`dart test` / `flutter test` passes, `dart analyze` reports no errors, `dart
format` reports nothing to change. No behavioral change to any existing
exported (public, non-`_`) symbol. The diff is purely additive or strictly
local; nothing downstream can break. A diff that adds only new files and/or
changes confined to test and fixture files (`*_test.dart`, fixtures) — zero
edits to existing production code — is grade A by construction; golden-file
brittleness is not regression risk.

### B
Suite and analyzer are green, but the diff changes an existing internal
helper in a way that *could* affect a caller — and the callers are
updated and tested, so the risk is contained but non-zero.

### C
Suite and analyzer are green, but the diff changes an existing exported
symbol's behavior in a small way that callers across packages must adapt to,
and not every caller is obviously covered. A latent break is plausible.

### D
`dart format` lists files (formatting dirty), or `dart analyze` reports
new warnings, or a flaky/skipped test masks a real change, or an exported
contract changed without a migration note. The branch needs work before it's
safe.

### F
`dart test` / `flutter test` fails, or the diff breaks an unrelated package, or it
changes a published contract that other beads/packages depend on with no
migration. Landing this breaks main — a human is needed.

## Calibration
- **Floor additive / test-only diffs at A–B.** Check `git diff --stat`
  first: if no existing *production* file is modified — only new files
  added, and/or edits confined to `*_test.dart` and test fixtures — there is
  nothing downstream to regress. Grade A, or B only if the suite is
  actually red or the analyzer/format is dirty. Do **not** grade such a diff
  C/D/F for golden-file or fixture brittleness: a golden test failing when
  intended output changes is its designed behavior, caught by the gate and the
  `test-coverage` rubric, not a regression this rubric should penalize.
- If between A and B, err toward B when the diff modifies any existing
  function/method body (not just adds new ones) — A is for additive/local diffs.
- If between B and C, err toward C when an exported symbol's behavior
  changes and a caller in another package is not visibly updated.
- If between C and D, err toward D when `dart format` is non-empty or
  `dart analyze` reports a new warning — a dirty tree is never better than C.
- If between D and F, err toward F when `dart test` / `flutter test` fails on the
  branch, or a contract other packages depend on changed without a
  migration — those are land-breaks-main, the `blocked` tier.
- Out of scope: coverage of the *new* behavior (`test-coverage`) and
  whether the diff matches the plan (`spec-adherence`). Grade only the
  blast radius on everything else.

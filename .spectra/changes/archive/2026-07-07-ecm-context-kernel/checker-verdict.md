# Checker verdict — kupo (maker≠checker) — 2026-07-07

**Recommendation: verified-transition GO, conditional on AC-4/AC-9** (live
canary — blocked upstream per `verify-fail-upstream.md`, crystalium 1.8.0).

| Gate | Result |
|---|---|
| Drift fence | PASS — diff vs merge-base `0836b02` = exactly the 18 `files_allowed`; zero `files_forbidden` touches |
| Frozen criteria | PASS — sha256 `6e0b9b102c3164281052b937c5fa58c09886f138162e4dd65fa7bf035c306015` exact |
| context.bats | PASS — independent re-run 17/17; all 15 bats-backed ACs map to real `@test` names |
| Pre-existing-failure claim | PARTIAL-CONFIRMED — 14 failures on untouched main, all shasum-absence-driven (`verify_envelope.bats` 10, `doctor_deep.bats` 1, `trace_reader.bats` 3 — maker wrote `trace.bats`; filename corrected, substance intact; 1449+17−14=1452/1466 reconciles) |
| shellcheck -x -S error | PASS — 10 scripts, zero findings |
| AC-5 idempotency intent | PASS — asserts jq -cS settings byte-equality + raw lock equality + shim sha256, not exit-0 |
| bash 3.2 scan | PASS — bash-4-isms appear only in comments documenting the constraint |

**Per-AC:** AC-1..3,5..8,10..17 PASS (15) · AC-4, AC-9 UPSTREAM-BLOCKED
(crystalium one-shot `ingest` absent in 1.7.0; see `verify-fail-upstream.md`).

**Maker artifact:** worktree branch `worktree-agent-ad5977bfcabb26885`,
commit `4cf80cf` (18 files). Verified-transition scribe deferred until the
crystalium 1.8.0 canary legs pass.

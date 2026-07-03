# Eidolons v2.0 — Repo-by-Repo Change Plan (2026-07-02)

> Companion to ARCHITECTURE-BRIEF.md. Waves are dependency-ordered; each wave is
> releasable on its own (additive, reversible). Model-tier discipline for execution:
> frontier model authors specs and reviews; standard-tier workers implement from specs;
> every change lands with tests + docs + changelog in the same PR.

## Wave 0 — nexus, no cross-repo deps (IN PROGRESS on `feat/v2-wave0-mechanization`)

| Change | Files | Status |
|---|---|---|
| Campaign artifacts committed | `.spectra/plans/eidolons-v2/` | ✅ a6ae4aa |
| model_tier(_per_step) injected into UPS hook context | `cli/src/harness_hook.sh` + harness/run bats | ⏳ delegated |
| `harness status` reality probes (never-written lock keys defect) | `cli/src/harness_status.sh` + bats | ⏳ delegated |
| Remove dead `cli/src/harness.sh` | — | ⏳ delegated |
| `memory preflight --explain` diagnostic mode | `cli/src/memory.sh` + bats | ⏳ delegated |
| doctor D13 memory-recallability probe (--deep) | `cli/src/doctor.sh` (+`lib_memory_probe.sh`) + bats | ⏳ delegated |
| `canary --memory` round-trip/liveness | `cli/src/canary.sh` + bats | ⏳ delegated |
| CHANGELOG + docs touchpoints | CHANGELOG.md, docs/cli-reference.md, docs/model.md | orchestrator, after review |

Release: nexus v1.47.0 (minor — additive verbs/probes + defect fixes).

## Wave 1 — spec repos (contracts first, so implementations have a target)

**eidolons-ecl → ECL 2.1**
- Promote S-3 (ise-required-at-high) and I-5 (hmac-at-high) SHOULD→MUST per the spec's
  own `[PROMOTION-CANDIDATE]` clause (precondition "≥3/6 Eidolons adopt ISE" is
  satisfied by Wave 3 below — cut 2.1 only after Wave 3 merges in ≥3 repos).
- Fix §6.5.3 ghost performatives (COMMIT/REJECT not in the closed 10-set): correct the
  reference (no new performatives in 2.1; a major bump is NOT warranted for this).
- Add `ise.verification` sub-block: `{fresh_context: bool, checker: <slug>,
  transcript_access: none|artifact-only}` — the attestation a verify envelope carries;
  conformance: shape-check MUST when present; required-at-verify is ESL's C8 (below),
  not ECL's.
- Conformance lib + fixtures + CHANGELOG. bash 3.2.

**eidolons-esl → ESL 1.1**
- Stamp catches up with shipped v1.1-additive content (EARS §2.5, C7 lint).
- New C8 (advisory in 1.1, MUST at 2.0): verify envelope carries
  `ise.verification.fresh_context=true` with `transcript_access: artifact-only`
  and checker ≠ maker (extends C4 from identity-inequality to context-separation).
- New preflight gate at proposed-entry: change dirs MUST record
  `memory_preflight: {ran: bool, records: n}` (graceful-skip when crystalium absent —
  ran:false is conformant in 1.1).
- ACE delta rule into the drift contract: spec revisions are structured amendments;
  wholesale regeneration flagged by drift_check.

**eidolons-eiis → EIIS 1.5**
- New manifest role `hook` (values: session-start-preflight, prompt-submit, stop) so
  hook wiring is inventory-tracked, swept on uninstall, doctor-verifiable.
- Whitelist additions for `.claude/settings.json`-adjacent shim paths as declared
  surfaces (they are host files, tracked via `hosts_wired`, not `<target>/`).
- Promotion window per 1.4 precedent.

## Wave 2 — nexus roster/kernel (after Wave 1 shapes exist)

- `roster/routing.yaml` routing_version 1.1: per-Eidolon `degraded_mode`
  (`fanout|sample-select|fallback:<peer>`), `escalation` (`verifier: <named>`,
  `on_fail: escalate-tier|reroute:<peer>`, `max_escalations`), executor cascade fields.
- `run.sh`: read degraded_mode/host_tier (extend the existing :211-219 fallthrough);
  artifact gains `escalation` block; TRANCE lead/workers tiers as computed fields.
- Decomposition dial: new cortex deep table `methodology/cortex/tier-execution.md`
  (light ⇒ fixed pipeline/one-location-per-call/whole-file-or-search-replace edits/
  per-step validation; standard ⇒ bounded loop + fanout; deep ⇒ thin loop) +
  ≤2-line pointer from EIDOLONS.md (respect I-C4 900-token budget).
- `sandbox loop --cascade light,standard[,deep]`: run at tier N; on verifier fail after
  attempts, re-run at tier N+1 (bounded; verifier stays outside executor write scope;
  test-file hash/count monotonicity ratchet).
- Single-writer invariant added to EIDOLONS.md Invariants (I-C11) — one writer per
  chain step; scouts/checkers never write; strict-tier PreToolUse recipes encode it.
- Skill surfacing: routing artifact lists procedural skills matching the selected
  capability class (from crystalium recall, layers=[procedural], fail-open).
- doctor D14: routing.yaml 1.1 shape gate; schema update `schemas/routing.schema.json`.

Release: nexus v1.48.0. Consumer contract unchanged (all new fields optional).

## Wave 3 — the eight Eidolon repos (template-driven, one PR/minor release each)

Common sweep (all 8, mirrors the June consistency-campaign mechanics):
1. Vendor `envelope.v2.json`; emit ISE block (`assertion_grade` per role:
   coders/checkers emit `validated` only when an external verifier passed; scouts/
   planners/scribes emit `self-attested`); kill 1.0/2.0 drift everywhere
   (schema == prose == install.sh == ECL_VERSION). APIVR-Δ: fix hardcoded
   `ECL_VERSION_VAL="1.0"`.
2. One canonical blocking verify-incoming (IDG retires its warn-only v1.0 intake).
3. Always-loaded budget: agent.md + ≤1-screen core; SPEC splits with load/unload
   triggers (VIGIL 3479w, SPECTRA 3481w, ATLAS 2952w, Kupo 2094w).
4. Add conformance test: ECL version coherence check.

Per-repo specifics:
- **ATLAS**: ESL discover-hop; anchor re-verification pass (external `rg` re-check of
  cited path:line before report emission — catches fabricated citations).
- **SPECTRA**: EARS acceptance-criteria emission (closed template) + acceptance-file
  SHA-256 into the spec envelope; runnable `calibrate` preflight (ship anchor plans).
- **Vivi**: FANOUT default on weak/undeclared hosts; declared `fallback: apivr` in
  roster data; no-substrate degraded mode (single external-verifier run + Kupo handoff).
- **APIVR-Δ**: ESL maker≠checker hop (success path routes through Kupo/named verifier)
  — priority one; it is the weak-host fallback and must not be a verification downgrade.
- **IDG**: fresh-context dual-read gate vs source citations (cheap second pass).
- **FORGE**: weak-host N-sample deliberation + rubric-agreement selection; checker
  handoff for verdicts feeding irreversible actions.
- **VIGIL**: scripted repro/counterfactual harness steps (substrate-enforced ≥2-run
  gate); SPEC split.
- **Kupo**: "named external verifier or REFUSE" extracted as a shared cortex primitive
  (nexus hosts the canonical text; Kupo references it); commit verified edit-patterns
  to crystalium (fix library); modest KEEP-taxonomy widening (eval-gated).

Rollout order within wave: APIVR-Δ → Vivi → SPECTRA → ATLAS → FORGE → VIGIL → IDG →
Kupo (verification-critical first). After ≥3 merge: cut ECL 2.1 (Wave 1 gate).

## Wave 4 — MCPs

**crystalium 1.6**
- Canonical scope-key derivation (single function; project key from data-dir label);
  reject/normalize free-typed drift (the live store has 3 project keys for 1 project).
- Summary quality gate at commit (mechanical: min length, content-word requirement) —
  summaries are the only indexed text.
- `recall --explain` (candidates / filtered-by-status / filtered-by-scope / arms
  active); doctor reports embedded-vs-total + dense-arm status.
- Never-deprecate-last-checkpoint guard (the live store's v2 plan checkpoint was
  deprecated into invisibility).
- `consolidate` batch verb: episode→skill promotion (k-occurrence trigger + held-out
  validation gate — mandatory per negative-transfer evidence) + ACE delta updates.
- Housekeeping: version triplet (SPEC 0.1.0 / pyproject 1.5.1 / __init__ 1.0.0),
  "7 tools" docs → 9, FTS5 injection G1.2, tool_calls audit G1.3.

**Junction 0.4**
- Build `harness.inject` (ISE + receiver_authorization enforcement — the entitlement
  gate for weaker models).
- Reconcile trace root with ECL §5 (`.eidolons/.trace/`), or spec-side amendment if
  `.junction/threads/` is deliberate — decide once, document.
- Stale "v0.1" tool descriptions; memory-preflight dispatch step before assemble.

**tonberry 0.5**
- Close archive→crystalium loop (call ingest on promotion-intent instead of emitting
  and forgetting — behind a flag while crystalium 1.6 lands).
- C8 support (fresh-context attestation check) once ESL 1.1 cuts.

## Wave 5 — proof (nexus)

- `eval swe|kupo --matrix`: (fix-hook tier × {system-on, bare-control}) × k; scorecard
  JSON schema; `evals/results/` committed store; `eval baseline` diff verb.
- Weekly scheduled live-eval workflow (secret-gated, billed consciously).
- Per-host effective-tier canary (`canary --host <h>` vs lockfile expectation).
- Compliance A/B rerun with a UserPromptSubmit-capable driver (retire the floor-driver
  66.7% number).
- **H-WIN gate**: light-tier + system ≥ standard-tier bare on the KEEP cohort. If it
  fails: ship the measurement and the honest number, not the claim.

## Cut criteria for "v2.0"

All of: Wave 0-3 merged; doctor --deep green on 5 hosts; memory round-trip canary
green; H-WIN measured (either way); MIGRATION.md for the two contract bumps.
v2.1 candidates: Copilot GAP-1 resolution, Codex A1/A2 vendor verification, Go-core
strangler-fig revival (separate ESL change, committed artifacts this time).

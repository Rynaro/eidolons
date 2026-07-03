# Eidolons v2.0 Campaign — Operator Handoff (2026-07-02)

> Session 1 of the campaign. Everything below is grounded in committed artifacts in this
> directory and the working tree on `feat/v2-wave0-mechanization`.

## What happened

**Audit (complete).** Four fan-out audits + live-store forensics. The mechanical spine is
70-90% built; its binding surfaces are opt-in, memory is write-only in practice, and the
evals cannot measure the "weaker models win" thesis. Every campaign hypothesis graded in
GAP-MAP.md. Two genuinely new discoveries: (a) the live crystalium store silently returns
0 records while holding 9 crystals (deprecation filtering + scope fragmentation + null
embeddings + terse summaries); (b) the June v2.0 Go-migration plan artifacts were never
committed and are lost — recovered only as a crystalium blob digest.

**Research (complete).** Three briefs (verification+memory, orchestration+distillation+
tier-routing, OSS landscape). Central finding: the weak-inside-beats-strong-outside
thesis is conditionally true — the condition is a deterministic verifier. The moat is
verification + maker≠checker + inspectable routing, not orchestration. Nobody else ships
the full bundle; watch Microsoft Conductor (deterministic-routing twin) and
wshobson/agents (host breadth).

**Architecture + plan (complete).** ARCHITECTURE-BRIEF.md (5 workstreams: binding
contracts, closed-loop memory, weak-worker execution, proof, correctness debt) and
REPO-PLAN.md (Waves 0-5, dependency-ordered, per-repo specifics for all 8 Eidolons +
3 spec repos + 3 MCPs).

**Implementation (Wave 0 landed in the working tree).** Six changes on
`feat/v2-wave0-mechanization`, implemented by Sonnet workers from frontier-authored
specs, reviewed line-by-line:

1. Model tiers now injected into every UserPromptSubmit routing context
   (`harness_hook.sh`) — plus a real kernel bug found & fixed: chain artifacts'
   `model_tier_per_step` was ALWAYS null (`run.sh` read a field that only exists on
   derived structures).
2. `memory preflight --explain` — diagnoses the exact silent-empty-recall incident.
3. doctor D13 memory-recallability gate (WARN "memory is effectively write-only").
4. `canary --memory` liveness probe (honest scope: not a round-trip yet).
5. `harness status` reality probes (the two "patched" fields were reading lock keys the
   installer never writes — false forever).
6. Shared `lib_memory_probe.sh` (gate + docker transform, one copy).

CHANGELOG [Unreleased] + docs/cli-reference.md updated together with the code.

## What remains (dependency-ordered — see REPO-PLAN.md)

- **Wave 1**: ECL 2.1 (ISE SHOULD→MUST + fresh-context attestation field + §6.5.3
  ghost-performative fix), ESL 1.1 (stamp, C8, preflight gate), EIIS 1.5 (hook role).
- **Wave 2**: roster/kernel — degraded_mode + escalation fields, cascade loop mode,
  tier-execution cortex table, single-writer invariant, skill surfacing.
- **Wave 3**: 8 Eidolon repos — ECL v2 envelopes + ISE, one canonical verify-incoming,
  maker≠checker hops for ATLAS/APIVR-Δ/FORGE (APIVR-Δ first — it is the weak-host
  fallback and currently a verification downgrade), SPEC splits, per-repo items.
- **Wave 4**: crystalium 1.6 (scope keys, summary gate, recall --explain, consolidate/
  skill promotion with validation gate, never-deprecate-last-checkpoint), Junction 0.4
  (build inject, trace-root), tonberry 0.5 (archive→commit).
- **Wave 5**: eval matrix (tier × system-on/off), committed scorecards, per-host tier
  canary, compliance A/B rerun with a UPS-capable driver, H-WIN measurement.

`gh` is authenticated (Rynaro, repo+workflow) — cross-repo waves are executable from
this environment.

## Risky / watch

- **H-WIN is unproven.** The measured compliance number (66.7%, floor driver) FAILED its
  gate; nothing yet demonstrates light-tier+system ≥ standard-tier bare. Wave 5 exists
  to measure it; do not market the claim before the number exists.
- **Codex surfaces are [ASSUMPTION A1/A2]** — unverified against the real vendor; its
  "T3" is aspirational (effective T1-T2). Verify or downgrade honestly.
- **harness.sh not deleted**: referenced by dead `_mcp_source_harness()`
  (lib_mcp.sh:1549-1556) + docs/architecture.md:216 — needs a coordinated 3-point
  removal (follow-up).
- **Pre-existing test failure**: doctor_deep.bats DD-7 (shasum/sha256sum environment
  issue) fails identically on clean HEAD — not introduced by this branch.
- **ECL 2.1 cut gate**: promote S-3/I-5 only after ≥3 Eidolon repos ship ISE (the
  spec's own precondition).

## Ship what / when

- **Now (this branch → PR)**: Wave 0 = nexus v1.47.0 (minor).
- **v2.0 cut**: after Waves 0-3 + doctor green on 5 hosts + memory round-trip canary +
  H-WIN measured (ship the number either way).
- **v2.1**: Copilot GAP-1, Codex A1/A2 resolution, Go-core revival (separate ESL change,
  committed artifacts this time).

## Session validation record

- Lint: `make lint` clean (portable shellcheck v0.10.0).
- Scoped tests (worker-run, orchestrator-spot-checked): harness.bats 92/92 (7 new),
  run.bats 28/28 (1 new), memory.bats 20/20 (4 new), doctor_deep.bats 26/27 (3 new;
  1 pre-existing DD-7), canary.bats 19/19 (5 new).
- Full sequential suite: see PR description (run at commit time).
- Live smokes: tier lines verified on real prompts; `--explain` reproduced the
  9-crystals/0-records incident; D13 WARNs write-only; canary --memory INCONCLUSIVE.

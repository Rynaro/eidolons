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
  *Update 2026-07-04: measured — see the addendum at the end of this document.*
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

## Measured results (addendum, 2026-07-04 — session 2)

All five waves shipped and released: nexus v1.47.0 / v1.48.0 / v1.49.0; ECL 2.1
Published (adoption gate satisfied 8/8) + ESL 1.1 + EIIS 1.5; 8 member minors with
ISE + maker≠checker, rostered; crystalium 1.6.0 / Junction 0.4.0 / tonberry 0.5.0;
PR-CI in all 8 member repos; UPS-capable compliance driver (#422).

**H-WIN (n=12 tasks, k=3, kupo-keep suite + 2-task jq top-up):**

- haiku + system (`keep-system.sh`): 12/12 resolved, pass³ = 1.00
- sonnet + bare (`keep-bare.sh`):    12/12 resolved, pass³ = 1.00
- **Exact tie at ceiling.** Non-inferiority of light-tier-inside-the-system at
  roughly ⅓ the per-token price is demonstrated; superiority is NOT demonstrable
  on this cohort (ceiling effect — a harder task cohort is the follow-up).
- Methodology disclosures: two sandbox images (alpine:3.20 for 10 tasks;
  eidolons-eval:alpine-jq for the 2 jq-verifier tasks); four instrument artifacts
  were caught adversarially BEFORE any number was accepted (fake-green `--via`
  re-parsing, missing `--permission-mode acceptEdits`, relative fix-hook path
  exit-127, argv-poisoned prompts starting with `---`). Scorecards committed under
  `evals/results/2026-07-03-*.json`.

**Compliance A/B rerun (claude-headless-ups driver, sonnet, k=2, 56 sessions):**

- ARM A (harness) correct_target_rate 41.7% vs ARM B (bare) 0.0% → Δ = +41.7pp.
  The harness effect is unambiguous: bare sonnet NEVER delegated under the
  read-only tool surface, across all 24 routed sessions.
- Gate vs 80%: **FAIL** → per FORGE dossier:106 the reversal recommendation
  stands: escalate the advisory hook toward a blocking default (v2.1 decision).
- `ups_fired=false` in the scorecard is **instrument artifact #5**, not a
  mechanism failure: timed-out sessions (5×120s) had their partial streams
  discarded while the certification demands all-sessions evidence. A $0 dead-URL
  probe in the byte-identical fixture shows UserPromptSubmit fired and the kernel
  injected `Route: …` on claude 2.1.201. Fixed (partial streams are now scored)
  + regression-tested in `feat/h-win-measurement`; the fix would only RAISE a
  rerun's measured rates (killed-after-dispatch sessions currently score 0).
- Not directly comparable to June's 66.7% (different driver, k, timeout scoring).
  Treat 41.7% as a floor under 120s timeouts and max-turns 3.

**Gate closures (2026-07-04, session 2):**

- **doctor --deep green on 5 hosts: CLOSED.** Fresh minimal-preset project wired for
  all five hosts (`harness install --hosts claude-code,codex,copilot,cursor,opencode`);
  `doctor --deep` exit 0, zero ✗. D12 effective-tier report: claude-code **T3**,
  codex **T3**, copilot **T2**, cursor **T2**, opencode **T1** — all `[inject-only]`,
  lock⇄files consistent; D14 routing shape green; D13 correctly SKIPs (no crystalium).
- **MIGRATION.md: CLOSED.** Committed at the repo root — ECL 2.0→2.1 and EIIS 1.4→1.5,
  sourced from the spec repos' shipped changelogs; consumers act on nothing, shipped
  members already migrated (Wave 3), steps are for new/third-party Eidolons.

- **Memory round-trip canary: CLOSED (2026-07-04).** crystalium v1.7.0 shipped the
  one-shot `commit` CLI verb (crystalium#30; `consolidate` deferred to 1.8 explicitly);
  nexus #428 upgraded `canary --memory` to commit → recall → forget behind a
  `commit --help` capability probe; #429 published 1.7.0 to roster + catalogue
  atomically. Live run against the released image (by GHCR digest, through the real
  docker transform): **`PASS — memory round-trip verified (commit → recall → found)`,
  exit 0, cleanup clean.** The FAIL path was also validated live by accident — a
  non-root-writable store under `--cap-drop ALL` produced the correct
  `FAIL … refused the canary write` with exit 1 before the environment was fixed.

**ALL v2.0 CUT CRITERIA ARE GREEN** (REPO-PLAN.md §Cut criteria): Waves 0–3 merged;
doctor --deep green on 5 hosts; memory round-trip canary green; H-WIN measured
(tie at ceiling — ship the number, not the claim); MIGRATION.md shipped. The v2.0
version cut is an operator decision from here.

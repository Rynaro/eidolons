# Eidolons v2.0 — Architecture Brief

**Date:** 2026-07-02 · **Status:** DRAFT v0.9 (pending R1 orchestration + R3 OSS-comparison integration)
**Basis:** four fan-out audits + verification/memory research brief (this directory) + live-store forensics.
**Prime objective:** raise the floor — a weaker model inside Eidolons should beat a stronger model outside it — while raising the ceiling and preserving the identity (named specialists, refusal boundaries, portability, traceability).

---

## 1. Design thesis

The v1.x line built the mechanical spine: a deterministic non-LLM routing kernel, hook
adapters on five hosts, a typed envelope wire format (ECL), a lifecycle grammar (ESL),
a tier-gated memory system with verifier-gated skills (crystalium), and external-verifier
execution loops (sandbox loop, Kupo). The audits show this spine is 70–90% built and
largely tested.

What v1.x did NOT do is make any of it **binding**, **recallable**, or **provable**:

- Binding: every contract is opt-in; ISE trust gates are SHOULD; 4/8 Eidolons self-review;
  3/8 lack maker≠checker; all 8 vendor the v1 envelope schema.
- Recallable: memory is write-mostly. The live store lost the project's own v2 plan to
  deprecation-filtering + scope fragmentation + null embeddings + terse summaries.
- Provable: no eval can measure "weak model + system ≥ strong model bare." Results are
  ephemeral; CI runs smoke only; the one A/B failed its gate from a floor driver.

v2.0 is therefore **not a rewrite**. It is the release that flips the built system from
*advisory* to *default-on*, from *write-only memory* to *closed-loop memory*, from
*asserted* to *measured* — with every change biased toward weak-worker benefit.

External evidence base (research briefs): fresh-context checking measurably beats
self-review and re-review (CCR 2026; self-correction literature); post-hoc failure
attribution tops out at 14.2% step accuracy, so gates must sit *between* steps;
retrieval quality dominates memory-write sophistication (r=0.98); executable acceptance
criteria written before work (Spec Kit/EARS lineage) are what make success legible to
weak verifiers; weak-to-strong supervision works exactly where checks are objective.
The orchestration brief adds the campaign's central conditional: **the weak-inside-
beats-strong-outside thesis holds exactly where a deterministic verifier exists** —
replicated from AlphaCode through Devin Fusion (frontier parity at −35-41% cost with a
cheap executor) — and fails where verification is judgment-based. Structure is worth
~12-22 SWE-bench points BELOW the frontier (Kimi-Dev fixed-workflow ablation; o3-mini
scaffold gap) and ~nothing at it, so scaffold depth must be a per-tier dial. The durable
moat is verification + maker≠checker + inspectable routing, not orchestration cleverness.

## 2. Goals / non-goals

**Goals**
1. Weak-model win-rate: a light-tier worker inside the system completes the KEEP/SWE
   cohorts at ≥ the bare standard-tier rate (measured, not asserted).
2. Default-on integrity: new installs get blocking verify-incoming, maker≠checker
   handoffs, and memory preflight without opt-in flags (with honest degradation).
3. Closed memory loop: what one session writes, a later session can find — with
   diagnosable failure when it can't.
4. Measurement: a (model-tier × system-on/off) matrix with persisted scorecards, run
   on release candidates.
5. All of the above portable: no host-specific hack in core; adapters stay shims.

**Non-goals**
- No new Eidolons (roster is complete for v2.0; capability gaps close via skills/gates).
- No Go migration in v2.0 (orthogonal infra; candidate v2.x track — see GAP-MAP).
- No LLM-discretionary routing, no vendor lock-in, no infra dependencies (servers,
  DBs beyond crystalium's embedded stores).
- No prose-methodology rewrites in Eidolon repos beyond what the gates require
  (format migrations stay format migrations).

## 3. The five workstreams

### WS1 — Binding contracts (G-A)
Flip the already-mechanical from SHOULD to MUST along the specs' own promotion paths.

- **ECL 2.1:** promote S-3 (ise-required-at-high) and I-5 (hmac-at-high) per the
  documented promotion-candidate clause (adoption precondition: ≥3/6 → satisfied by
  this campaign shipping ISE in all 8). Fix §6.5.3 COMMIT/REJECT ghost references.
  Add `verification.fresh_context: true|false` + checker identity to the ISE block so
  assertion_grade=validated mechanically implies a fresh-context checker.
- **All 8 Eidolon repos:** vendor envelope.v2 schema, emit ISE, kill 1.0/2.0 drift
  (schema == prose == install.sh == ECL_VERSION), one canonical blocking
  verify-incoming (retire IDG's warn-only fork).
- **ESL 1.1:** stamp catches up with shipped content (EARS §2.5, C7); new C8 (advisory
  → MUST at 2.0): verify envelope carries fresh-context attestation. Memory-preflight
  gate at proposed-entry (recall before authoring; graceful-skip).
- **maker≠checker everywhere:** ESL hops for ATLAS (discover), APIVR-Δ (verify via
  Kupo/named verifier), FORGE (checker handoff for irreversible verdicts).
  Kupo's "named external verifier or REFUSE" promoted to a shared cortex primitive.

### WS2 — Closed-loop memory (G-B)
Retrieval-first investment per the research; fix the four live-store defects.

- **crystalium 1.6:** canonical scope-key derivation (one function: project key from
  data-dir label/config, never free-typed); summary quality gate at commit (min length,
  must contain layer-appropriate content words — mechanical, not LLM); recall
  `--explain` (candidates found / filtered-by-status / filtered-by-scope / arms active);
  doctor probe reporting embedded-vs-total and dense-arm status; never-deprecate-last-
  checkpoint guard; `consolidate` batch verb (sleep-time-as-command) hosting the
  episode→skill promotion pipeline (k-occurrence trigger + held-out validation gate —
  the 2026 skill-consumption study shows unguarded extraction causes negative transfer,
  so the validation gate is mandatory, not optional). Skill/spec updates follow the
  ACE delta rule: structured incremental amendments, never wholesale regeneration.
- **Nexus:** `memory preflight --explain` surfacing crystalium's explain; doctor D13
  memory-recallability probe (store reachable, N crystals, M active, dense arm status);
  post-flight commit prompt in the SessionStart/Stop injection (mechanize the cortex's
  "mandatory post-flight" that is prose today).
- **EIIS 1.5:** `hooks`/`preflight` manifest role so preflight wiring is
  contract-tracked, swept, and doctor-verifiable.
- **Two-tier recall:** injected digest stays ≤ the existing cap; everything else behind
  recall tools (already the shape; make the injected index content-adaptive: last-N
  active crystals for the project scope).

### WS3 — Weak-worker execution (G-C)
Push reasoning up, state out, verification to the boundary.

- **Cascade escalation (the routing algorithm for tiers):** post-generation cascade —
  dispatch at the roster-suggested tier's LOWER bound where an external verifier exists;
  on verifier failure, escalate one tier and retry (bounded). Never pre-predict
  difficulty (every pre-generation router is ML-shaped); never let the worker's
  self-assessment trigger acceptance or escalation — the verifier verdict does.
  Kupo's economic gate + sandbox-loop pass^k are the existing seams; generalize as
  `escalation` fields in routing.yaml + a sandbox-loop `--cascade` mode.
- **Kernel/hook:** inject `model_tier_per_step` (and per-step verifier expectations)
  through `harness_hook.sh` on every T3 host; TRANCE lead=deep/workers=light becomes a
  computed artifact field, not prose. Plan-boundary tiering (opusplan pattern): the
  SPECTRA→coder edge is the mechanical tier-switch point.
- **Tier-indexed decomposition dial (cortex table):** light-tier worker ⇒ fixed
  pipeline, mechanical localization, one location per call, whole-file or
  search/replace edit format, per-step validation; standard ⇒ bounded loop + best-of-N
  fanout; deep ⇒ thin two-tool loop. Structure that adds 12-22 points below the
  frontier adds ~nothing at it — the dial, not a global scaffold choice.
- **Host-tier contract:** roster gains per-Eidolon `degraded_mode` descriptors
  (FANOUT default on weak/undeclared hosts; N-sample + rubric-selection for FORGE;
  automatic APIVR-Δ fallback as data, not prose). run.sh already has the host-tier
  fallthrough seam (run.sh:211-219) — extend it to read these.
- **Single-writer invariant, formalized:** most Eidolons are already read-only or
  PROPOSE-only; state it as a cortex invariant (one writer per chain step; scouts and
  checkers never write) and encode it in strict-tier PreToolUse recipes.
- **EARS acceptance grammar:** SPECTRA emits acceptance criteria in the closed EARS
  template; ESL C7 lints it (already shipped as advisory); acceptance file SHA-256
  frozen in the ECL envelope at spec time; verifiers re-hash before running (anti-tamper
  ratchet: test-file hash/count monotonicity check in sandbox loop; test files
  read-only to the executor — verifier runs outside the executor's write scope).
- **Always-loaded budget:** enforce agent.md + ≤1-screen core (the 3.5k-word SPECs in
  VIGIL/SPECTRA/ATLAS split into chapters with load/unload triggers).
- **Skill surfacing:** verifier-gated procedural skills become visible to routing —
  the routing artifact lists matching skills (by capability class) so a weak worker
  starts from a verified procedure instead of reasoning from scratch.

### WS4 — Proof (G-D)
- **eval matrix:** `eidolons eval swe|kupo --matrix` sweeping (fix-hook model tier ×
  {system-on, bare-control}) with k runs; emits scorecard JSON.
- **Scorecard store:** `evals/results/` (committed) with schema'd scorecards +
  `eval baseline` diffing; CI gains a weekly scheduled live-eval workflow (billed,
  gated on a repo secret/flag) writing scorecards as PR artifacts.
- **Per-host tier canary:** `canary --host <h>` probing the effective tier
  (doctor D12 data) against the lockfile expectation.
- **Compliance A/B rerun:** UserPromptSubmit-capable driver so the number stops being
  a floor (the 66.7% figure decided inject-vs-block; it deserves a real measurement).

### WS5 — Correctness debt (G-E)
harness status lock keys; dead harness.sh removal; junction "v0.1" strings + trace-root
reconciliation with ECL §5; crystalium version triplet + "9 tools" docs; ESL stamp;
Codex [A1]/[A2] verification against the real vendor (or downgrade the claimed tier
honestly in harness_status).

## 4. Expected effects

**On weaker models** — every workstream converts a judgment a weak model must make
into a field it reads or a gate that catches it: ISE assertion_grade replaces "do I
trust this input?"; EARS + frozen checks replace "am I done?"; named-verifier-or-REFUSE
replaces self-review; FANOUT + selection replaces self-correction; surfaced skills
replace derive-from-scratch; injected tier map replaces "which model should do this?".
**On portability** — all changes land in specs, roster data, or the kernel; adapters
stay shims; every gate degrades to warn on hosts that can't enforce.
**On reliability** — gates move between steps (the only place failure attribution
works); memory becomes diagnosable; evals catch regressions with persisted baselines.

## 5. Rollout order (dependency-driven)

1. **WS5 + WS2-nexus** (no cross-repo deps; immediate)
2. **WS1 spec bumps** (ECL 2.1, ESL 1.1, EIIS 1.5) — contracts first, so repos have a
   target
3. **WS3 kernel/roster changes** (nexus-local; unblocks host injection)
4. **WS1/WS3 Eidolon-repo wave** (8 repos, one release each, template-driven like the
   June consistency campaign)
5. **WS2 crystalium 1.6 + junction/tonberry closes** (inject build, archive→commit)
6. **WS4 eval matrix + baselines** (measures the assembled system; some parts land
   earlier as harness code)
7. v2.0 cut: nexus major with roster requiring the new member releases; consumer
   contract unchanged (v1 projects keep working — degradation rules).

## 6. Ship gate for calling it "v2.0"

- Matrix eval shows light-tier + system ≥ standard-tier bare on the KEEP cohort
  (hypothesis H-WIN; if it fails, v2.0 does not ship the claim — it ships the
  measurement and the honest number).
- doctor --deep green on all five hosts' effective-tier reports.
- All 8 members released with ECL v2 envelopes + maker≠checker hops.
- Memory round-trip canary: commit in session A, recall in session B, assert found.

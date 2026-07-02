# Eidolons v2.0 — Consolidated Gap Map (2026-07-02)

> Synthesis of four fan-out audits (nexus mechanization, evals/model-mgmt, eight Eidolon
> repos, specs/MCPs/infra) + orchestrator-verified live-store findings. Each campaign
> hypothesis is graded against evidence. Companion files in this directory hold the
> full audits with file:line evidence.

## Hypothesis verdicts

| # | Campaign hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | Routing stronger in theory than enforcement | **PARTLY WRONG — better than assumed on claude-code, worse elsewhere.** Genuine T3 (inject+block, tested) on claude-code. Codex "T3" is aspirational ([ASSUMPTION A1/A2] surfaces, unverified). Copilot/cursor static-only, opencode T1. Live compliance A/B failed its 80% gate at 66.7% — but from a SessionStart-only floor driver. | audit-nexus-mechanization.md |
| H2 | Memory preflight not fully mechanical | **CONFIRMED, and worse: memory is write-mostly.** Preflight mechanized on claude-code only; EIIS has no hook role (wiring is out-of-contract). Post-flight commit is prose. Live store: recall returns zero for everything — deprecated-checkpoint invisibility, scope-key fragmentation, null embeddings, terse summaries. The system lost its own v2 Go plan. | audit-memory-runtime-defects.md |
| H3 | Lifecycle/handoff integrity not default enough | **CONFIRMED.** ECL/ESL/EIIS/tonberry/junction all opt-in, advisory-by-default. ISE gates SHOULD not MUST. All 8 Eidolons vendor ECL **v1** schema (no ISE) while declaring 2.0; APIVR-Δ hardcodes 1.0. Junction inject is a stub. tonberry never calls crystalium. | audit-specs-mcps-infra.md, audit-eidolon-repos.md |
| H4 | Harness support uneven | **CONFIRMED with precise tier map.** claude-code T3 / codex T1-T2 / copilot T2-floor / cursor T2-static / opencode T1. Vendor bugs honestly refused in code. | audit-nexus-mechanization.md |
| H5 | Evals can't prove system-level gains | **CONFIRMED strongly.** No (model × system-on/off) matrix; no persisted baselines; no bare-model control arm; CI runs only smoke; the cited "weak-host adversarial suite" behind Vivi's default-coder seat is not in the repo. | audit-evals-model-mgmt.md |
| H6 | Weaker-model optimization implicit | **CONFIRMED.** Tier ladder + resolver + per-Eidolon tiers exist but are advisory; model_tier_per_step computed and never injected; TRANCE lead=deep/workers=light has no code path; crystalium's verifier-gated skills (the strongest weak-model lever) are invisible to routing/handoffs. 4/8 Eidolons rely on self-review — the pattern the project's own citations say degrades on weak models. | all |
| H7 | Seams too optional/prose-driven | **CONFIRMED** = H3 + version drift (ECL 2.0/1.0 x8, crystalium 3 version strings, ESL 1.0 stamp with 1.1 content). | audits 3,4 |

## The one-sentence diagnosis

The mechanical spine (kernel, gates, envelopes, tiers, skills, verifiers) is ~70-90%
BUILT — but its binding surfaces are opt-in, its weak-model levers are advisory, its
memory is write-only in practice, and its evals cannot detect any of this.

## Gap classes (what v2.0 must change)

**G-A. Enforcement defaults (make the built things binding)**
- ECL ISE S-3/I-5 SHOULD→MUST path; assertion_grade as the mechanical trust gate
- ESL fresh-context verify attestation (C4 + "checker had no maker transcript")
- verify-incoming: one canonical blocking gate in all 8 (retire IDG v1.0 fork)
- ECL v2 envelope + ISE vendored in all 8 repos (schema, prose, install.sh)

**G-B. Memory that recalls (close the write→recall loop)**
- Canonical scope-key derivation (one function, all writers)
- Summary quality gates at write; embeddings-or-visibly-degraded (doctor probe)
- recall --explain (candidates vs filtered-by-status/scope counts)
- never-deprecate-last-checkpoint guard; commit-on-success standard obligation
- EIIS hook/preflight role (contract home for SessionStart wiring)
- Two-tier recall: tiny injected index + on-demand tools (already half-built)

**G-C. Weak-worker execution (push difficulty up into architecture)**
- Inject model_tier_per_step via harness_hook
- Host-tier capability contract + declared degraded modes (FANOUT default on weak
  hosts; sampling+selection replaces self-correction; auto APIVR-Δ fallback)
- Kupo's named-verifier-or-REFUSE as shared primitive for self-review agents
- ESL maker≠checker hop in all 8 (ATLAS, APIVR-Δ, FORGE missing)
- EARS-templated acceptance criteria frozen (hashed) before work
- Always-loaded budget enforcement; split 3.5k-word SPECs

**G-D. Proof (evals that can detect the thesis)**
- (model × system-on/off) task-solving matrix on the KEEP/SWE suites
- Persisted scorecard/baseline store (results are currently ephemeral)
- Per-host effective-tier canary
- Re-run compliance A/B with a UserPromptSubmit-capable driver (current number is a floor)

**G-E. Correctness debt (small, land regardless)**
- harness status reads lock keys installer never writes (always false)
- dead cli/src/harness.sh; junction tool descriptions say v0.1
- ECL §6.5.3 references COMMIT/REJECT not in the closed set
- crystalium version-string triplet; "7 tools" docs (actual: 9)
- Junction trace root ≠ ECL §5 path
- ESL stamp 1.0 vs 1.1 content

## Reconciliation: the June Go-migration plan

The 2026-06-24 "eidolons-core Go binary" strangler-fig plan (recovered from crystalium
blobs; artifacts lost) is **orthogonal infrastructure** — it changes the data engine's
implementation language, not the system's behavior toward weaker models. None of G-A…G-D
depends on it; bash 3.2 portability remains an identity constraint for consumer-facing
surfaces either way. Recommendation: v2.0 = this campaign (system-strength);
Go core = candidate v2.x infra track, re-planned through ESL with committed artifacts.

# ADR 0001 — Eidolons Routing Cortex (`EIDOLONS.md`)

- **Status:** Accepted
- **Date:** 2026-05-04
- **Deciders:** APIVR-Δ (implementation), IDG (chronicling), nexus maintainer

## Context

`cli/eidolons` is a deterministic string dispatcher: it pattern-matches `argv[1]`
against built-in verbs, then against `roster_list_names`, and shells out to
`./.eidolons/<name>/commands/<sub>.sh` (`cli/eidolons:84-133`,
`cli/src/dispatch_eidolon.sh`). That path requires the user to already know
which Eidolon and which subcommand to call. **Free-form natural-language
prompts arriving through Claude Code, Cursor, OpenCode, or Codex have no
semantic dispatch path** (foundation `.spectra/research/eidolons-cortex-foundation.md` §5,
§6 mis-routing examples). Common failure modes today: prompts that span ≥2
capability classes ("scout *and* spec the auth refactor") land on whichever
skill the host happens to load; "fix the bug" with a stack trace runs through
APIVR-Δ's three-attempt budget before reaching VIGIL; "document this" silently
needs IDG named explicitly because IDG refuses retrieval.

The cortex must close that gap **without** replacing the deterministic path,
**without** re-implementing roster membership (`roster/index.yaml` is the
source of truth, foundation §9 invariant 14), and **without** becoming the
monolithic system prompt the manifesto refuses to ship (`MANIFESTO.md:39`,
`methodology/prime-directives.md:27` D1 ≤3500-token specialist working set).

Architectures considered and rejected (`.spectra/plans/eidolons-cortex-spec.md` §4.4):

- **Single-router (one-shot classifier).** Insufficient: "no correction once
  dispatched" (dossier §4). The roster needs relay capability — refusal-driven
  re-routing and multi-step chains.
- **Cascade by strength.** Wrong shape: Eidolons differ in *role*, not
  *strength* (dossier §4). A "weaker" ATLAS is not a smaller-budget APIVR-Δ.
- **Mixture-of-Agents aggregation as default.** ~N× cost on every prompt;
  reserved for TRANCE on hard FORGE queries only (dossier §3.4, §3.6).
- **Multi-agent debate as default.** Underperforms self-consistency at equal
  cost without heterogeneity (dossier §2 #6, X-MAS / Stop-Overvaluing-MAD).
  Available only as an opt-in FORGE-TRANCE mode.

## Decision

Adopt a **hierarchical-supervisor cortex with two-stage hybrid dispatch**:
descriptor soft-match → confidence gate + TRANCE escalation
(`.spectra/plans/eidolons-cortex-spec.md` §4.4).

- **Artifact:** `EIDOLONS.md` at the nexus repo root, marker-bounded
  `<!-- eidolon:cortex start --> … <!-- eidolon:cortex end -->`. Always-loaded
  section ≤900 tokens (cortex invariant I-C4, spec §9). Mirrored by
  `eidolons sync` into the consumer's `./.eidolons/cortex/EIDOLONS.md`
  (spec §11.1; nexus-only write authority per `docs/architecture.md` Security
  model).
- **Always-loaded content:** six-row roster descriptor table, 5-step dispatch
  protocol (Classify → Gate → Refusal-check → Tier → Emit), 8 chain templates,
  6 TRANCE activation gates G1–G6, confidence-signal table, 10 cortex
  invariants I-C1–I-C10.
- **Progressive disclosure** for deep tables: `methodology/cortex/handoff-graph.md`,
  `trance-matrix.md`, `validation-gates.md` load on demand
  (dossier §3.1 Anthropic Skills; spec P3). The cortex + one deep table
  fits inside the 3500-token specialist budget.
- **Capability classes only.** `model_tier ∈ {speed-class, reasoning-class}`;
  vendor model names never appear in the cortex
  (`methodology/prime-directives.md:152-162` D9; spec invariant I-C3).
- **TRANCE definition.** Parallel fan-out (max 5 branches), worktree isolation
  per branch, verifier-cascade wrapping, evaluator-optimizer loop capped at 3
  iterations, capability-class upgrade per role. **Not** longer single-thread
  thinking — Anthropic multi-agent research-system blog (90.2% lift via
  parallelism, dossier §3.4) and ACL 2025 "Revisiting o1 test-time scaling"
  (longer CoT often degrades, dossier §2 #18). Auto-trigger requires **both**
  a complexity flag AND a stakes flag (spec §6.4 C6); refused capabilities
  are never granted at TRANCE (spec §6.3 R1).
- **Hand-off graph dispute resolved.** Foundation §4 flagged a disagreement
  between `roster/index.yaml` declared edges and `methodology/composition.md`
  prose edges. The cortex adopts the **union as the routable set**, with
  every emitted chain step recording `edge_origin: "roster" | "composition" | "implicit"`
  (spec §7.1). A roster reconciliation work-item is filed (spec OQ-3).
- **Refusals are routing signals, not stops.** ATLAS-won't-write,
  SPECTRA-won't-implement, IDG-won't-retrieve, FORGE-won't-tool-call,
  VIGIL-won't-auto-apply: cortex re-routes to a capable peer and emits
  `[DECISION]` (spec P6, R1; foundation §9 invariant 5).

## Consequences

**Positive.**

- Free-form natural-language prompts now route deterministically through a
  single always-loaded artifact; the headline gap from foundation §5 is
  closed (spec V10).
- TRANCE escalation is bounded by gates G1–G6 and cost ceilings C1–C6, with a
  5× standard-tier budget warning (spec §6.4 C4) — the manifesto's "no
  always-on parallel fan-out" stance is preserved.
- The cortex publishes a spec-grade rubric (14 GIVEN/WHEN/THEN gates V1–V14
  in `methodology/cortex/validation-gates.md`) which doubles as the cortex's
  self-test surface and as APIVR-Δ's Verify rubric for any future cortex
  change.
- The hand-off graph dispute is resolved without rewriting either source;
  edge provenance travels with every chain step.
- `eidolons sync` mirroring keeps the consumer-side cortex in step with the
  roster. Per-Eidolon installers continue to write only to cwd
  (`docs/architecture.md` Security model preserved).

**Negative / accepted trade-offs.**

- **No trained classifier in v1.** Soft-matching against descriptors is the
  v1 mechanism; calibrated routing (RouteLLM ICLR 2025, dossier §2 #1) is
  carried as spec OQ-1. Mitigation: descriptors stay authoritative; a future
  classifier consumes them rather than replacing them.
- **Stateless cortex.** No cross-session routing memory in v1 (spec OQ-9).
  Reproducibility wins over learned routing for now; Reflexion-style memory
  (dossier §3.8) is opt-in v2.
- **New file at the repo root.** `EIDOLONS.md` joins `MANIFESTO.md` and
  `CLAUDE.md` at the top level; the surface count grew by one. Justified by
  the parallel role and host-discovery convention.
- **CLI sync responsibility expanded.** `cli/src/sync.sh` now mirrors the
  cortex into the consumer project. Idempotency, dry-run, and bash 3.2
  compatibility were preserved by `cli/tests/cortex.bats` (14 cases).
- **Verbal-confidence assumption.** τ thresholds are taken from published
  cascade work (dossier §3.2); calibration on production telemetry is a
  follow-up (spec OQ-2, OQ-5).

## References

- Spec: `.spectra/plans/eidolons-cortex-spec.md` (605 lines, 11 sections,
  V1–V14 gates, OQ-1–OQ-12 carried-forward assumptions).
- Frontier-research dossier: `.spectra/research/eidolons-cortex-research-dossier.md`
  (38 citations: RouteLLM ICLR 2025, X-MAS, Anthropic Skills, Anthropic
  multi-agent research-system, Self-Consistency, Self-Refine, Reflexion
  NeurIPS 2023, "Revisiting o1" ACL 2025, Plan-and-Act ICML 2025).
- Local foundation: `.spectra/research/eidolons-cortex-foundation.md`
  (capability inventory §1–§3, declared-edge graph §4 with documented gaps,
  routing-mechanism-today §5, mis-routing examples §6, harness affordances §7,
  15 cortex invariants §9).
- Cortex self-test surface: `methodology/cortex/validation-gates.md`
  (V1 pure-discovery, V2 TRANCE scatter, V5 second-attempt → VIGIL, V10
  free-form headline case, V11 refusal re-route, V13 cost ceiling, V14
  direct-implementation bypass).

# Cortex Deep — ELITE Tier Matrix

> Load this file when evaluating or authorizing an ELITE escalation.
> See `EIDOLONS.md` for the always-loaded routing cortex and activation
> gates.

---

## Per-Eidolon ELITE Capability Matrix

| Eidolon | ELITE form | Granted | Forbidden at ELITE |
|---|---|---|---|
| ATLAS | Scatter sub-agents per module | Parallel fan-out (G1); worktree isolation; Abstract-phase aggregation | Writing, editing — D2 refusal stands |
| SPECTRA | Evaluator-optimizer loop on draft spec | Generator + evaluator + termination gate (G3); cap 3 iterations | Implementing code; > 3 cycles |
| APIVR-Δ | Parallel feature branches in worktrees + verifier cascade | Multi-track implementation (G4); per-track verifier; reflection memory bounded ≤ 3 retries | Re-attempting beyond category budget; writing in shared tree without `isolation: worktree` |
| IDG | Parallel doc-section synthesis | Per-section parallelism with topological respect (G5); CHT verification per section | Retrieval; > 1 revision per section |
| FORGE | Self-consistency on reasoning chains | N=3 (or N=5 high-stakes) sampled traces with majority-vote / judge-merge (G2) | Tool calls, retrieval, code emission; debate without heterogeneity |
| VIGIL | Parallel hypothesis testing on isolated bisects | Counterfactual fan-out on worktrees (G6); 5-intervention budget preserved | Auto-apply patches; writing outside `verified-patch.diff` |

---

## Cost Ceiling Rules

| Rule | Value | Rationale |
|---|---|---|
| C1 — Max parallel branches | 5 | Anthropic empirical sweet spot for orchestrator-workers |
| C2 — Max model-tier upgrade | lead = reasoning-class, workers = speed-class | Mirrors Anthropic research-system topology; D9 |
| C3 — Max wall-clock | Host-enforced; cortex emits `wall_clock_budget_seconds` hint | Cortex never spins indefinite background jobs without user opt-in |
| C4 — Token budget warning | Emit `[DECISION]` at ≥ 5× standard-tier budget | Anthropic 15× lift number is upper bound, not default |
| C5 — Surface-size threshold | > 25 files OR > 5 modules = large surface | Heuristic; configurable |
| C6 — Auto-trigger requirement | Both complexity flag AND stakes flag must hold | Either alone keeps cortex at standard tier |

---

## Refusal Gates (ELITE MUST NOT override these)

- **R1** — Refused capabilities remain refused at ELITE. ATLAS still does not write. SPECTRA still does not implement. IDG still does not retrieve. FORGE still does not tool-call. VIGIL still does not auto-apply patches.
- **R2** — FORGE parallel fan-out is reasoning-only. FORGE's ELITE is self-consistency on reasoning chains; it does not gain tool access.
- **R3** — Bounded budgets are inviolable. Per-Eidolon retry budgets remain enforced inside ELITE. ELITE adds parallelism, not a fresh budget.
- **R4** — D5 unbounded reflection forbidden. ELITE may not extend reflection loops past published caps (SPECTRA 3 cycles, IDG 1 revision, APIVR ≤ 3 same-category attempts).
- **R5** — Partial-team deployment degrades gracefully. If a needed Eidolon is not installed (`eidolons.lock` check), ELITE is degraded: cortex emits a `[GAP]` and a fallback chain rather than spawning fan-out into a member that doesn't exist.

---

## Confidence Thresholds

| Threshold | Value | Source |
|---|---|---|
| τ_standard (min to dispatch) | 0.6 | Hybrid-LLM dial behavior [D §3.2] |
| τ_elite (min to auto-escalate) | 0.8 | RouteLLM preference data [D §2 #1] |
| FORGE consensus floor | 60% | Self-Consistency threshold [D §3.6] |

`[OQ-2]` Assumption: τ values are reasonable defaults until calibration experiment shows optimal point is far off. Tune from routing-decision logs.

---

## Open Questions Carried Forward

| ID | Assumption | Mitigation |
|---|---|---|
| OQ-1 | LLM-self-routing against descriptors is good enough for v1. | Migrate to calibrated classifier (RouteLLM) when mis-routing > 10% in telemetry. |
| OQ-4 | ELITE-on-demand is the right v1 stance. | Add ELITE-default flag in `eidolons.yaml`; cortex still emits `[DECISION]` at C4 ceilings. |
| OQ-7 | Self-consistency at N=3/N=5 is right for FORGE-ELITE. | Tune from logs; drop N back to 3 or standard if empirical evidence disagrees. |

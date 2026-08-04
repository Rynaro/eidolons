# Campaign Resolution — crystalium-rrf-fusion-38

## Lifecycle

**proposed** (2026-08-03, ramza) → **deliberated** (2026-08-03, FORGE 10 rulings) → **in_progress** (2026-08-03, vivi 3+2 commits) → **FAIL round 1** (AC-130, vigil) → **remediation** (vivi 1 test commit) → **verified** (2026-08-03, vigil fresh-context, 1152 lines) → **drift_checked** (2026-08-03, kupo) → **shipped** `56c8510` (v1.10.0, 2026-08-04)

**Roster bump** → **in_progress** (2026-08-04, mcp-crystalium-1-10-0) → **verified** (kupo, dual-roster) → **archived** (2026-08-04, idg)

## The Load-Bearing Lesson: Oracles Fail When They Are Wrong

Three successive models of the dense arm were offered by different agents across the campaign, and **all three were demonstrably wrong**:

1. **Revision 1.0.0 (proposal, vivi).** Modeled both graph/completion spokes **absent** from `dense_ranking`. Inferred consequence: static down-weighting is measurably worse (0.4615 → 0.3077 collapse), so family-merge + weighted fusion is mandatory. **Predicted outcome:** H-A fails, H-B wins decisively.

2. **Vigil F1 critique.** Corrected revision 1.0.0 as "unjustified model" and modeled spokes at **positions 25/26–29/30**. Recomputed the H-A collapse and found it inverted under this model, withdrawing the empirical rejection. **Predicted outcome:** H-A and H-B are empirically equivalent; H-B wins on principled structural grounds only.

3. **Real-stack measurement (FORGE ordering).**  Fresh `docker compose` on the real gate, real retrieval stack. Measured: spoke1 at **dense rank 17**, spoke2 **absent from dense_ranking entirely** (30-element cap vs. 31-crystal corpus). **Ground truth:** Neither model was correct; the truth was mixed. **Measured outcome:** H-A fails decisively (0.4615 → 0.3077 at all 6 hash seeds), H-B passes and fixes the issue's sketch.

**Binding discovery (R-7, FORGE ruling):** An oracle that correctly predicts the outcome must be shown to *differ* across the implementations it claims to distinguish. Revision 1.0.0's prediction (H-A fails) was correct but rested on a wrong model. Vigil's revised prediction (H-A passes) was incorrect. Both oracles failed to flag this disagreement as requiring measurement before a tiebreak was declared — until the measurement ran, the wrong oracle's revision looked local to its model. The standing rule going forward: **before a tiebreak between competing models is accepted, produce at least one empirical outcome that the models predict differently, and measure it.**

This rule is load-bearing because deliberation must not regress to "which spec-writer sounds more persuasive" — the spec writers were both confident, both wrong in different directions, and the third model wasn't even on the table until measurement forced it. Measurement is not optional when oracles disagree.

## Key Findings

- **Measurement fixed DP-1, DP-2, D2, and D3 (vigil A-6).** H-A is rejected on measurement (gate failure 6/6 hash seeds) AND on structure (anomaly B: down-weighting derived arms cannot demote top-of-dense competitors). D2's family-merge corrects the measured P1 inversion alone (`2/61` vs `1/61 + 1/77`), 11.6% margin. D3's sparse boost adds 65.6% margin, landing the issue's sketch.

- **Anomaly A (follow-up F-A, high priority).** Graph/completion arm return sets; rank order is set-iteration order which Python randomizes via `PYTHONHASHSEED`. Real-gate observation: `context_rank.both` takes {2, 4, 5} across 6 seeds. Consumer-side fix (sorted order) landed in-scope (D5), but deeper fixes (returning ordered lists from store) are deferred.

- **AC-140 (issue's literal acceptance bar) is RED.** The bar is "without relying on the fetch-width floor" — the change must solve it *on the gated path* where the floor is active, and it does (sketch resolves). The red is a **finding about the change's nature** — it layers on the guard rather than replacing it — not a correctness failure. Routed to DP-1 as post-hoc input (DP-4(ii), vigil C-12).

- **AC-130 (a gate mutation criterion for AC-126) cannot redden its own criterion.** The test scaffolding injects a false `cross_layer=True`, but the mutation criterion asserts `cross_layer=False` was supplied. The assertion can never redden on the injected state. Remedied by editing the test only (no `src/` change implied).

- **AC-136's contingency (six frozen criteria) all green:** AC-121 (32 #36 criteria), AC-122 (four-cell non-regression probe), AC-123 (full pytest suite), AC-124 (retrieval-gate non-inferiority), AC-125 (new fusion gate). Therefore `recall_weighted_fusion` ships ON.

## Provenance

| Artifact | Agent | Date | Authority |
|----------|-------|------|-----------|
| `spec.md` v1.4.0 | ramza (vivi authored, vigil APPROVE-FOR-ASSEMBLE) | 2026-08-03 | Proposal authority; 42 frozen criteria (spec.criteria.md sha256 e644052e) |
| `measurement.md` | measurement agent (FORGE ordered) | 2026-08-03 | Empirical data: 26 gate runs + 2 probes on real stack |
| `deliberation.md` | FORGE (10 rulings) | 2026-08-03 | Binding decision-point resolutions; R-7 standing rule |
| `verification.md` | vigil (fresh context, 1152 lines) | 2026-08-03 | Gate-attack forensics; AC-130 remedy; anomaly A discovery |
| `change.json` | tonberry (status=archived, drift_checked=true) | 2026-08-04 | Final manifest; canonical change identity |
| `promotion.envelope.json` | tonberry (INFORM performative) | 2026-08-04 | Promotion-intent routing to CRYSTALIUM Semantic layer |

Every claim above is traceable to one of these artifacts (file + line range):
- P1/P2/P3 definitions → `spec.md` §Problem Statement
- Modelled dense ranks (revisions 1.0.0 / vigil F1 / measurement) → `measurement.md` §2, §Headline
- Gate failure (H-A 0.4615 → 0.3077, 6/6 seeds) → `measurement.md` table row "H-A w_g=0.35 w_c=0.25", `deliberation.md` §2 DP-1 "Line 1 — measurement"
- Anomaly B (derived arms structurally barred from top-of-dense) → `deliberation.md` §2 DP-1 "Line 2 — structure"
- AC-140 red + C-12 conditions → `verification.md` Verdict + Steps F-V1/C-12
- AC-136 contingency status → `verification.md` Step 2 "AC-123 GREEN", Step 5 "AC-124/125 GREEN"
- Commit hashes → `spec.md` line 12–13, `verification.md` line 11–12
- Release date / v1.10.0 digest → upstream Rynaro/crystalium releases, independently verified by `mcp-crystalium-1-10-0` acceptance checks

## Archived at

- **Change folder:** `.spectra/changes/archive/2026-08-04-crystalium-rrf-fusion-38/`
- **Upstream release:** Rynaro/crystalium v1.10.0 (released 2026-08-04T02:38:42Z)
- **Nexus roster bump:** `b2ee4f2` (mcp-crystalium-1-10-0, archived 2026-08-04)

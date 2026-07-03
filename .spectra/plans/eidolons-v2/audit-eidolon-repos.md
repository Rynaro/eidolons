# v2.0 Audit — Eight Eidolon Repos, Weaker-Model Readiness (2026-07-02)

> Fan-out audit agent report (condensed, faithful). Baseline: all 8 declare EIIS 1.4 +
> ECL 2.0; same host surface set; all ship blocking symmetric verify-incoming + crystalium
> recall preflight with graceful skip; all release via the nexus reusable workflow.

## Cross-repo table

| Eidolon | Ver | Always-loaded | Methodology shape | Verification | ECL status | ESL hop | Weak-model |
|---|---|---|---|---|---|---|---|
| ATLAS | 1.12.1 | 727w agent.md (+SPEC 2952w!) | Mechanical: numeric probe caps, three-strike halt, deterministic-first retrieval | Blocking verify-incoming; scatter subagents; no self-consistency on final report | v1 schema + v1.0 prose (4 refs) | ✗ | **5** |
| SPECTRA | 4.10.0 | 489w | Rubric library, 6-layer checklist, 3-decomposition self-consistency, **cross-model calibration protocol** (anchor plans, Krippendorff α≥0.67, "new model → recalibrate") | Self-review+consistency; MAKER at ESL specify | **2.0 clean** | ✓ MAKER | **5** |
| Vivi | 1.2.0 | 422w (no frontmatter) | Substrate-driven loop; env-var interface; ITERATE vs FANOUT host-tier branch | **External: sandbox loop + judge + pass^k + sealed holdout**; tonberry C4 maker≠checker | mixed prose, v1 schema | ✓ MAKER | **3** (loop core frontier-gated; weak-host story = "degrade to APIVR-Δ" prose) |
| APIVR-Δ | 3.7.1 | 658w (no frontmatter) | Most table-dense: Complexity Router, USE→EXTEND→WRAP→CREATE, Always/Ask/Never | Self-review + evidence gates; **no ESL hop; success path has no checker** | **install.sh hardcodes ECL_VERSION_VAL="1.0"** | ✗ | **4** |
| IDG | 1.9.0 | 393w | Markers, grounding rules ("write from provided context only"), checklists | **Single self-review CHT gate + 1 revision (weakest)**; warn-only v1.0 intake variant | v1.0 intake divergence | ✓ archive | **4** |
| FORGE | 1.9.1 | 716w | **Best reasoning scaffold**: 5-dim rubrics with anchors, 4 named stress-tests, convergence deltas | **Self-review only, zero external ground truth** — exactly the intrinsic self-correction its own citations say degrades on weak models | v1.0 prose | ✗ | **4** |
| VIGIL | 1.7.0 | 747w; **SPEC 3479w** | Reproduction gates attribution (≥2 runs); counterfactual-flip blame; ≤5 interventions | **External: sandbox counterfactual = oracle**; escalation handoff | v1.0 prose | ✓ CHECKER-fail | **4** |
| Kupo | 1.2.0 | 625w | **Pure decision tree**, first-failure-exits; "KEEP iff a verifier can be NAMED"; economic gate | **External-only verifier; PROPOSE-only (parent commits) = maker≠checker built into role** | **2.0 clean** | ✓ CHECKER | **5** |

Verification taxonomy: External ground truth → Kupo, Vivi, VIGIL. Self-review →
SPECTRA, FORGE, APIVR-Δ, IDG. Integrity-gate-only → ATLAS.
ESL maker≠checker in 5/8 (missing ATLAS, APIVR-Δ, FORGE).
**ECL 2.0 clean in only 2/8; all 8 vendor the v1 envelope schema — no ISE fields anywhere.**
SPECTRA externalizes planning state to `.spectra/{plans,state,logs,setup}`.
Bats coverage skew: ATLAS 16 files; Vivi 8; APIVR 6; SPECTRA/IDG/FORGE/VIGIL/Kupo 2 each.

## Notable per-repo v2.0 items

- ATLAS: fresh-context anchor re-verification of cited path:line (fabricated-citation
  catch); ESL discover hop; ECL v2 adoption.
- SPECTRA: make calibration protocol runnable (`spectra calibrate` + shipped anchor
  plans) not documentary; local conformance tests; cap on-demand SPEC loads.
- Vivi: FANOUT default on undeclared/weak hosts; automatic (declared) APIVR-Δ fallback;
  no-substrate degraded mode that still has external verification.
- APIVR-Δ: **add ESL maker≠checker hop + external-verifier gate** (it's the weak-host
  fallback — must not be a verification downgrade); fix ECL 1.0 hardcode.
- IDG: retire warn-only v1.0 intake; cheap fresh-context dual-read vs source citations.
- FORGE: N-sample deliberation + rubric-agreement selection on weak hosts (sampling
  replaces unreliable self-correction); checker handoff for irreversible verdicts.
- VIGIL: split 3479w SPEC into ≤1-screen core + chapters; script the repro/counterfactual
  harness (weak models skip the ≥2-run gate under pressure).
- Kupo: lift "named external verifier or REFUSE" into shared primitive; broaden KEEP
  taxonomy carefully; commit verified edit-patterns to memory (fix library).

## Five ecosystem-wide standardizations (agent's ranked list)

1. **Maker≠checker default everywhere** — ESL hop in all 8; Kupo's named-verifier-or-
   REFUSE as a shared primitive for the self-review agents. Highest priority APIVR-Δ.
2. **Host-tier capability contract + mandatory degraded weak-host path per Eidolon** —
   generalize Vivi's ITERATE/FANOUT + declared automatic fallback; substitute sampling +
   external selection for single-trace self-correction.
3. **ECL 2.0 envelope + ISE fields adopted for real; kill version drift** — typed
   trust/entitlement fields instead of in-context trust judgment; conformance check that
   ECL_VERSION == vendored schema == prose == install.sh.
4. **Hard always-loaded budget + strict progressive disclosure** — always-loaded =
   agent.md + ≤1-screen core; explicit load/unload; shrink VIGIL/SPECTRA/ATLAS SPECs.
5. **One canonical blocking verify-incoming + schema-generated per-edge acceptance
   tables; retire stale variants; make commit-on-success a standard obligation**
   (today only Vivi/VIGIL) so weak-host fix patterns accumulate.

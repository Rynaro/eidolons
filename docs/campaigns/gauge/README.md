# Eidolons v4 — evidence-producing adaptive delivery

**Execution campaign, revision 3 · September 21, 2026 · PR #598.** Final research-informed planning adjustment before implementation. This revision changes plans only: no runtime code, version stamp, behavior default, merge, release, deployment, paid execution, or repository archival.

## Outcome and first assignment

One bounded brownfield assignment reaches an accepted runnable result, or preserved and explicitly incomplete progress. Optimize the whole delivery trajectory, including failures, verification, recovery and human intervention. Preserve named expertise without requiring one worker per specialist. Adapt methods and resources only inside authorized policy and acceptance boundaries.

**Start with V4-01 only.** Read [HANDOFF.md](HANDOFF.md), the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries, [plan.yaml](plan.yaml), and the assigned stage section. [RESEARCH.md](RESEARCH.md) maps research mechanisms and limitations to the authored requirements; it is not another implementation checklist.

The campaign has **23 packages and 182 EARS/planned-verification pairs**: all 128 revision-2 IDs remain, with 54 appended obligations. Counts describe traceability, not quality or coverage. No requirement or planned test is represented as already implemented or passing.

Original code control: `Rynaro/eidolons@752194ef5ceaa8cee1f5995fd0d374888696d8fc` (v3.3.1). Revision-2 plan: `7a3840ed6c304a006e9c22ac6561423486c0e23f`. First plan: `4ef8aa38f28b8e0e8e6869cb35607e7007cd4ca3`. Re-pin actual source, host and sibling versions per assignment while preserving the original control. A future v4.0.0 release depends on implemented breaking changes and accepted migration evidence; no date or savings percentage is promised.

## Execution order, not an architectural migration marathon

**The package dependency graph is authoritative; stage numbers are navigation, not all-to-all barriers.**

| Work | Packages and gate |
|---|---|
| [Stabilize](00-stabilization.md) | V4-01, then V4-02/V4-03. Integrity, affected legacy upgrades and real validation/wiring regressions. |
| [Establish correctness](01-foundations.md) | V4-04–V4-06. Ordered journal, current-candidate acceptance and one narrow typed Go seam. |
| [Qualify and measure early](02-policy-and-observation.md) | V4-07–V4-09. Persistent policy, honest resources, one host qualification and a working baseline/comparison recorder. |
| [Demonstrate delivery](03-managed-delivery.md) | V4-11–V4-15. Native execution, conditional skills/workers, protected qualified acceptance, recovery and minimal operator controls. |
| [Extend evaluation](05-evaluation-and-rollout.md#v4-21) | V4-21 runs immediately after V4-15, without waiting for migration, roster-wide adoption or optional clients. |
| [Adopt measured mechanisms](04-methodology-and-ecosystem.md) | V4-10 and V4-16–V4-20 follow their individual dependencies. Consolidation and methods retain canonical source/trust boundaries. |
| [Calibrate and promote](05-evaluation-and-rollout.md) | V4-22 evaluates implemented arms; V4-23 separates correctness, live qualification and performance/default promotion. |

V4-10 moved from Stage 2 to Stage 4. V4-11 no longer depends on consolidation. V4-09 owns the early instrument; V4-21 extends it rather than first inventing measurement after migration. V4-15 owns minimum inspect/status/resume/cancel visibility; V4-20 extends that interface. The manifest lists conditional mechanism prerequisites for V4-22 so unavailable arms are pending/ineligible, not simulated successes.

## What revision 3 adds

Stable task continuity across process/context/environment replacement; method-level host qualification; explicit skill input/output and execution forms; evidence-qualified acceptance criteria; actual behavioral checks; root-bounded tool and recursive information access; optional memory provenance/invalidation; versioned offline adaptation with no self-promotion; and full-trajectory, environment-controlled evaluation.

Research supports investigating these mechanisms, not asserting universal gains. Native harness APIs remain qualification candidates, not mandatory vendor dependencies. A runtime layer may provide integrity benefits without outperforming the native baseline; report those outcomes separately.

## Historical assignment migration

Old Gxx IDs remain retired. Their original wording remains in the first-plan commit; this mapping locates intent rather than reinstating obsolete instructions.

| Old | Current |
|---|---|
| G01 | V4-04, V4-06 |
| G02 | V4-05, V4-14 |
| G03 | V4-03, V4-05 |
| G04 | V4-07 |
| G05 | V4-08 |
| G06 | V4-09 |
| G07 | V4-11 |
| G08 | V4-12 |
| G09 | V4-13, V4-15 |
| G10 | V4-15 |
| G11 | V4-16 |
| G12 | V4-17 |
| G13 | V4-10, V4-13, V4-18 |
| G14 | V4-19 |
| G15 | V4-20 |
| G16 | V4-21 |
| G17 | V4-22 |
| G18 | V4-23 |

## Evidence and scope

Stage tables own EARS wording; the manifest owns dependency metadata and ID references. Receipts/tests link those IDs. A structural check does not prove semantic completeness, execution conformance, statistical independence, or EARS-to-test generation. Preserve existing ESL requirements where applicable without inventing ceremony for every small fix.

Implementation review readiness, deterministic conformance, observed CI, live-host qualification and release authorization are separate. Missing required evidence is a named blocker. Optional feature deferral is explicit and cannot erase an applicable requirement. No paid probes or trials without an operator-supplied allowance and permitted billing mode.

Non-goals: no wholesale native-loop rewrite; mandatory cloud, memory, GUI, graph database or recursive runtime; universal quota conversion; credential scraping; subscription circumvention; silent API overage; automatic archive; blanket `.spectra/` deletion; forced global rename; private-client disclosure; automatic policy/oracle mutation; or greenfield work through a specialist refusal loophole. Preserve external packages, legacy consumers, deployment boundaries and rollback state.

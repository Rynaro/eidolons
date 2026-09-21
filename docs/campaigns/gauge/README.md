# Eidolons v4 — capability contracts, Gauge, and verified delivery

**Proposed execution campaign, revision 2 · revised September 21, 2026.** This recomposes PR #598 in place. It replaces the earlier G01–G18 assignment plan; it does not implement any runtime augmentation, change a version, merge a PR, or authorize a release. Existing history remains accessible at `4ef8aa38f28b8e0e8e6869cb35607e7007cd4ca3`.

## Product outcome

One bounded user assignment should reach an accepted runnable result, or preserved and explicitly incomplete progress, with less unnecessary orchestration. Optimize resources per accepted task, including failures and verification, not the price of a single response. Preserve named expertise without equating each method with another worker. The Gauge controls economic preferences, never permissions or acceptance.

Source baseline: `Rynaro/eidolons@752194ef5ceaa8cee1f5995fd0d374888696d8fc` (v3.3.1). Re-pin actual code and relevant sibling revisions at assignment start; keep this original control for comparisons. The proposed breaking release target is v4.0.0, not a colliding new v3 tag. No target date or savings percentage is promised.

## Start with V4-01

Read [HANDOFF.md](HANDOFF.md), [ARCHITECTURE.md](ARCHITECTURE.md), and only the assigned stage section. [plan.yaml](plan.yaml) owns dependency/assignment metadata; the stage tables own requirement text. Each of the 23 packages has EARS requirements, paired planned verification cases, scope, implementation steps, prerequisites, and a stop/rollback boundary. There are 128 requirement/test pairs in this revision; this count is descriptive, not a coverage score.

| Stage | Packages | Delivery gate |
|---|---|---|
| [0 — Stabilize](00-stabilization.md) | V4-01–V4-03 | Current integrity, affected legacy upgrade and publication validation regressions. |
| [1 — Evidence and Go seam](01-foundations.md) | V4-04–V4-06 | Ordered journal, current-candidate evidence, narrow typed controller seam with compatibility. |
| [2 — Policy and packaging](02-policy-and-observation.md) | V4-07–V4-10 | Persistent Gauge, honest usage/entitlement signals, frozen protocol, compiled coupled packages. |
| [3 — Managed demonstrator](03-managed-delivery.md) | V4-11–V4-15 | One qualified host; atomic reservations; conditional worker boundaries; protected verification; runnable delivery and recovery. |
| [4 — Specialist adoption](04-methodology-and-ecosystem.md) | V4-16–V4-20 | Explicit lean/continuity profile amendments, roster adoption, context economy and usable CLI. |
| [5 — Evaluate and release](05-evaluation-and-rollout.md) | V4-21–V4-23 | Honest comparisons, calibrated presets, migration and scope-limited promotion; no evidence means no default flip. |

Stage gates and package dependencies both apply. V4-02/V4-03 may run in separate lanes after V4-01; V4-16/V4-17/V4-19 after the managed demonstrator can also proceed independently. Overlapping sources/state remain serialized. A ready-for-review fixture implementation is not an accepted live-managed capability. Missing live evidence is a scoped blocker, not an excuse to invent it or substitute a smoke result.

## What changed from the previous plan

The design now includes a narrow Go controller, profile/worker/context identity separation, conditional method fusion, explicit role/authority transitions, durable dispatch intent and recovery, protected frozen-candidate verification, compiled source packaging, and billing-mode eligibility. Current security fixes come first. A typed stateful implementation is not built fully in Bash just to be ported later. Consolidation preserves protocol/deployment/trust boundaries; archive and purge operations are deferred until tested consumer migration and explicit authorization.

Old IDs are retired rather than silently reassigned. Their original requirements remain historical at the previous plan commit; the following map describes where their intent went, not a claim that all old wording is still normative.

| Previous package | Revised packages |
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

V4-01/V4-02 add urgent stabilization; V4-06/V4-10/V4-13/V4-14 deepen architecture and execution boundaries beyond the earlier plan. Do not run an old Gxx handoff against this revision.

## Planning versus execution evidence

All listed requirements are authored targets. All listed Txx cases are planned verification. Local structural checks of these documents do not prove the future system works, authenticate checker independence, validate every semantic interpretation, or demonstrate EARS-generated executable tests. EARS is requirements notation, not Gherkin and not a test runner.

Keep one canonical requirement statement and reference its ID from tests, receipts and issues. Do not manufacture additional plan/critique/promotion documents for every small correction. Existing ESL applies where the target project requires it; this folder is a campaign, not a falsely verified ESL change.

## Source anchors and limits

| Evidence | Use in this plan |
|---|---|
| [Current integrity helper](https://github.com/Rynaro/eidolons/blob/752194ef5ceaa8cee1f5995fd0d374888696d8fc/cli/src/lib.sh), [#562](https://github.com/Rynaro/eidolons/issues/562) | Reproduce and repair policy fail-open behavior in V4-01. |
| [#566](https://github.com/Rynaro/eidolons/issues/566) | Include affected v1.41.0-or-earlier installs, not only v2/v3. |
| [#563](https://github.com/Rynaro/eidolons/issues/563), [#564](https://github.com/Rynaro/eidolons/issues/564) | Validate authored/published metadata; do not infer every existing record is corrupt. |
| [Current MCP templates](https://github.com/Rynaro/eidolons/tree/752194ef5ceaa8cee1f5995fd0d374888696d8fc/cli/templates/mcp) | Recheck actual wiring; historical #205/#465 reports are not proof the current generator still lacks their fixes. |
| [Cortex](https://github.com/Rynaro/eidolons/blob/752194ef5ceaa8cee1f5995fd0d374888696d8fc/EIDOLONS.md), [ledger](https://github.com/Rynaro/eidolons/blob/752194ef5ceaa8cee1f5995fd0d374888696d8fc/cli/src/ledger.sh) | Existing delegate-by-default and experimental evidence semantics must be changed explicitly. |
| [Live eval workflow](https://github.com/Rynaro/eidolons/blob/752194ef5ceaa8cee1f5995fd0d374888696d8fc/.github/workflows/live-eval.yml) | Gold-patch smoke is plumbing evidence, not measured coding capability. |
| [Mavin's EARS guide](https://alistairmavin.com/ears/) | Pattern reference for the authored requirements. |

The source review did not execute the product tests. Existing research motivates candidate strategies, not a performance guarantee. Runtime dependency versions, authentication permissions, native capabilities and billing modes must be rechecked during the responsible package.

## Non-goals

No new mandatory cloud service, universal quota conversion, credential scraping, subscription circumvention, automatic paid overage, all-host parity promise, wholesale native coding-loop rewrite, instantaneous removal of context already seen, one-page normative-spec target, or arbitrary repository/doc-size quota. No automatic deletion of `.spectra/`, archival of sibling repositories, private-client disclosure, or blanket weakening of specialist refusals.

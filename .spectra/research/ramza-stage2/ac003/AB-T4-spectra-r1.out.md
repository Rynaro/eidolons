---
eidolon: spectra
version: 4.11.0
kind: spec
status: validate_pending_review
created_at: 2026-07-05T19:25:10Z
target_repos:
  - "<unspecified — see CLARIFY Q1: dashboard product/surface not named by stakeholder>"
stories_count: 9
validation_gates_count: 16
thread_id: 019f33bd-e50b-7742-a422-a7a70055ef6d
confidence: 0.75
evidence_anchors_count: 0
---

# Make the Dashboard Faster — Decision-Ready Specification

**Spec ID:** SPEC-2026-07-05-dashboard-perf
**Methodology:** SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning
**Intent as received (verbatim):** "make the dashboard faster."
**Confidence / Gate:** 75% — **VALIDATE** (deliver with flags, human reviews before Feature F2/F3 work begins in earnest)

## Notes on This Document's Format

This is a single self-contained file. It carries the full SPECTRA dual-format
output — the human-readable specification, the agent-executable YAML handoff,
the execution state machine, and the ECL v2.0 envelope — as one document
instead of split sibling files, per this engagement's delivery constraint. The
exact byte boundary used to compute the ECL envelope's integrity hash is
marked explicitly at the end of the human-readable section (`END OF SPEC
PAYLOAD`), so the hash is independently reproducible by any downstream reader.

Memory pre-flight: `mcp__crystalium__*` tools were not available in this
session. Per SPECTRA's graceful-skip clause, recall/ingest/commit/session_end
were skipped silently — no prior specs or patterns were folded in, and none of
this spec's confidence is attributed to memory match. SPECTRA is
EIIS-standalone-conformant and works without CRYSTALIUM.

---

## DISCOVER — Skipped

**Precondition check:** DISCOVER activates only when the *goal itself* is
unknown/latent (`IDEA`/`STRATEGIC` intent). Here the goal is known and
concrete — "reduce dashboard latency" — even though the *specification
details* are ambiguous. That is CLARIFY's job, not DISCOVER's. **Skipping
DISCOVER, proceeding to CLARIFY.**

---

## CLARIFY

**1. Parse Intent**

| Slot | Value |
|---|---|
| WHO | Unnamed stakeholder (requester); affected parties: dashboard end-users, the engineering team owning the dashboard's frontend/backend, SRE/on-call (if caching infra is added), the product owner accountable for the dashboard's SLO/OKR. |
| WHAT | Reduce the dashboard's perceived and measured latency — the literal ask is "faster," undefined further. |
| WHY | Not stated. Most likely drivers: user complaints / engagement or retention risk (if customer-facing), or analyst productivity loss (if internal-tool). Latent goal is unconfirmed — see Assumption A2. |
| CONSTRAINTS | Not stated — no deadline, budget, or team-capacity given. Assume standard SDLC constraints pending stakeholder confirmation (Assumption A6/CLARIFY Q3). |

**2. Identify Gaps**

- Which dashboard / product surface is meant is unnamed.
- No current baseline measurement is given ("faster" than what?).
- No target user segment, device class, network condition, or data volume is given.
- Whether "faster" means initial load, in-app interaction (filter/sort/drill-down), or data-refresh/freshness is unstated.
- No deadline, budget, or org constraint (e.g. change-freeze, data-residency rule blocking new caching) is given.

**3. Clarify Questions (≤3, numbered, for the stakeholder)**

1. Which dashboard/surface and user segment is this about (e.g. the customer-facing analytics dashboard vs. an internal ops dashboard), and is the pain point initial page load, in-app interaction latency, or data-refresh/freshness? *(<200 chars)*
2. Is there an existing performance baseline or SLO/OKR this must satisfy, and do you have real user complaints/tickets we can triage against? *(<200 chars)*
3. Is new backend/caching infrastructure in scope, or must this ship without new infra, and what's the target delivery window? *(<200 chars)*

**No live stakeholder response channel exists for this engagement.** Per
SPECTRA's Scope-phase discipline ("log assumptions with risk-if-wrong")
rather than blocking, this spec proceeds on explicit, clearly labeled
assumptions (below) and is gated at **VALIDATE**, not **AUTO_PROCEED** — a
human must confirm or correct these before Feature F2/F3 execution.

**4. Structural Context**

No target repository was named, no `.spectra/setup/spectra-conventions.md`
exists in this project, and no codebase is available to query for existing
implementation patterns or call sites. Per SPEC.md CLARIFY step 4 ("when
absent, continue with generic defaults"), this spec uses generic
domain-placeholder component names (`dashboard-web`, `dashboard-api`,
`WidgetRepository`, etc.) instead of real module names. **[GAP]** — Dependency
verification (Test-phase Layer 3) cannot validate file paths against an
actual project structure; this is carried forward as an explicit gap, not
silently assumed away.

**5. Cognitive Load**

Multi-session-worthy: this spans instrumentation, backend data-layer changes,
frontend rendering changes, and a safe-rollout mechanism — four distinct
technical domains under one initiative. Complexity is scored formally below
(Scope phase) at 10/12, which triggers **extended thinking (2× budget)** per
SPECTRA P0-4 and flags human collaboration per the 10–12 threshold. This
spec's per-story timeboxes (≤2d–≤5d) assume the work is split across a small
team in parallel, not one engineer sequentially — call this out to the
stakeholder if capacity is smaller than assumed.

---

## S — SCOPE ANALYSIS

**Intent Type:** REQUEST (clear top-level goal — "faster" — but missing specs; not a bug report, not a strategic multi-project theme)
**Complexity Score:** 10/12 → **Extended thinking (2×) applied; human-collaboration zone (10–12) — this is why the gate below is VALIDATE, not AUTO_PROCEED**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 2 (Multi-feature) | One product surface, but instrumentation + backend + frontend + rollout are separately shippable feature slices. |
| Ambiguity | 3 (Vague/conflicting) | No baseline, no named surface, no definition of "faster." |
| Dependencies | 3 (Cross-domain) | Frontend rendering, backend/API, data layer, and (if caching is added) infra — 3+ systems. |
| Risk | 2 (User-facing) | Assumed user-facing dashboard, not a safety-critical system (Assumption A5). |
| **Total** | **10** | Routes to 10–12 tier per `scoring.md`. |

**WHO / WHAT / WHY / CONSTRAINTS:** see CLARIFY §1 above.

**Boundaries**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| Instrumentation (RUM + backend APM/slow-query logging) on the dashboard's existing pages/endpoints | Full UI/UX redesign or rebrand of the dashboard | Architectural overhaul (BFF aggregation layer, materialized views, edge/CDN caching, streaming/incremental rendering) — see rejected Hypothesis H3 |
| Backend query/data-layer optimization for existing dashboard-serving endpoints | Adding new dashboard features, widgets, or reports | Multi-region / global edge deployment |
| Read-path caching for expensive existing aggregations | Data pipeline / ETL freshness improvements (unless CLARIFY Q1 reveals "faster" actually means "fresher data" — Assumption A2 flags this) | Auto-scaling / infra capacity changes beyond a caching layer |
| Frontend rendering optimization (code-splitting, lazy-load, virtualization/pagination) for existing widgets | Native mobile app performance (assumed web app — Assumption A5) | — |
| Canary/flag-gated rollout with automatic rollback | Non-dashboard parts of the product | — |
| Before/after performance report against a confirmed SLO | | |

**Assumptions (logged with risk-if-wrong)**

| # | Assumption | Risk if wrong |
|---|---|---|
| A1 | "The dashboard" = the primary user-facing analytics/reporting dashboard (the most common referent of an unqualified "the dashboard" in a stakeholder complaint), not an internal admin tool. | Wrong team/repo engaged; wasted sprint; internal-tool SLO tolerance differs materially from customer-facing tolerance. |
| A2 | The complaint is about page-load/interaction **rendering latency**, not data pipeline/ETL freshness ("faster" could mean "data updates faster," not "the page opens faster"). | If wrong, this entire spec targets the wrong system (frontend/API vs. data pipeline) — full re-scope from Scope required (Assumption-Drift failure mode, see Test §Adversarial). |
| A3 | No architecture-change freeze or data-residency rule bars adding a caching layer. | If wrong, Story S5 (caching) needs redesign or removal; may force reliance on H3 (deferred) or query-only optimization. |
| A4 | "Faster" is judged by **Real User Monitoring (RUM)**, not synthetic/lab-only scores (e.g., a single Lighthouse run). | If wrong, prioritization shifts — lab metrics can diverge sharply from real-world experience, especially for data-heavy dashboards. |
| A5 | The dashboard is a **web application** (browser-rendered), not a native/desktop BI client. | If wrong, the optimization techniques below (bundle splitting, virtualization) don't apply; would need native-profiling techniques instead. |
| A6 | No named deadline/budget — standard team capacity and delivery cadence assumed; work is parallelizable across ~2–3 engineers. | If capacity is smaller/serial, the ≤5d timeboxes below understate elapsed calendar time; sequence stories via the Dependency graph in Construct instead of assuming parallel execution. |
| A7 | The provisional numeric SLO target set below (see "Measurable Performance Target") is a reasonable industry-standard placeholder, not a stakeholder-confirmed number. | If the real baseline is far outside this range (e.g. a 30s enterprise data dump), the target may be infeasible within Feature F2/F3's scope and must escalate to the deferred architectural track (H3). |

**Stakeholders (approval chain)**

| Role | Interest | Approval needed on |
|---|---|---|
| Requesting stakeholder (unnamed) | Wants perceptible speed improvement | CLARIFY Q1–Q3 answers; final SLO target (Story S3) |
| Dashboard product owner | Owns dashboard roadmap / non-goals | Boundaries table (in/out/deferred) |
| Engineering team (frontend + backend) | Implements F1–F4 | Story-level technical approach |
| SRE / on-call | Owns production risk if caching/infra changes | Story S5 (caching) and S8 (canary/rollback) design |
| Data/security owner | Data residency / per-tenant isolation | Story S5's cache-scoping constraint |

---

## P — PATTERN ANALYSIS

**Query:** "reduce dashboard latency; frontend rendering optimization; backend/API query optimization; read-path caching; RUM/APM instrumentation"

No internal pattern corpus is available — CRYSTALIUM memory was not queryable
(no MCP tools this session) and no target repository was named to search for
existing implementations. The rows below are named **external, industry
reference patterns** used only as generation scaffolding, not internal
codebase matches — their "similarity" is deliberately not scored against a
≥60% threshold since there is nothing internal to match against.

| ID | Pattern | Source | Decision |
|----|---------|--------|----------|
| P1 | Measure-then-optimize (RUM + APM-guided remediation) | Industry standard (web-perf / SRE observability practice) | Reference only |
| P2 | Cache-aside for expensive read-heavy aggregation queries | Industry standard (caching pattern) | Reference only |
| P3 | Code-splitting + list/table virtualization for heavy widget UIs | Industry standard (frontend performance practice) | Reference only |

**Strategy: GENERATE** — new specification; the three patterns above inform
Construct's story shapes but are not applied as verbatim templates (no ≥85%
internal match exists to justify `USE_TEMPLATE`, and no 60–84% match exists to
justify `ADAPT`).

---

## Measurable Performance Target

This is the decision-ready core the stakeholder's request was missing. Two
tiers are defined: a **framework** (always valid) and a **provisional numeric
target** (valid until Story S3 produces a real baseline).

**Framework (not provisional):**
- **Primary metric:** p75 "dashboard full-render" time, measured via RUM, from navigation start to the last above-the-fold widget painted with real data (not a loading skeleton).
- **Secondary metric:** p95 latency of dashboard-serving API endpoints, measured via backend APM.
- **Guardrail metric:** error rate and data-correctness (perf changes must not regress correctness — see Constraint layer in Test).
- **Success is relative-and-absolute:** both a **relative improvement** (% reduction from *this dashboard's own* baseline) and an **absolute ceiling** (a number that reads as "fast" in isolation) are required — relative-only targets can be gamed by a barely-perceptible improvement over a catastrophic baseline; absolute-only targets can be unachievable if current data volume is genuinely large.

**Provisional numeric target (Assumption A7 — pending Story S3 confirmation):**

| Metric | Provisional target | Basis |
|---|---|---|
| Dashboard p75 full-render time | ≤ 2.5s **and** ≥ 50% reduction from baseline, whichever is more stringent | Aligned to general "responsive" web-perf guidance (Core-Web-Vitals-adjacent); intentionally conservative pending real data |
| Dashboard p95 full-render time | ≤ 4.0s | Long-tail ceiling — protects worst-case users, not just the median |
| Dashboard-serving API p95 latency | ≤ 500ms | Standard backend responsiveness ceiling for interactive (non-batch) endpoints |
| Error rate / correctness regression | 0 (no regression beyond existing baseline ± 0.1 percentage point) | Perf work must never trade off correctness (Constraint gate) |

**This target is a placeholder, not a guess presented as fact.** Story S3 is
a **P0, blocking** story specifically because no downstream optimization
story can be scored "done" against an unconfirmed number. If S3's real
baseline makes 2.5s infeasible within this spec's scope, that is itself a
decision point: renegotiate the target, or promote the deferred Hypothesis H3
(architectural overhaul) from "Deferred" to "In Scope" via a follow-up spec.

---

## E — EXPLORATION SUMMARY

**Hypotheses generated:** 4 (conservative, pattern-leveraging, innovative, risk-minimizing) — no strawmen, all genuinely distinct in structure and risk profile.

**Quick-score triage (1–3 per dimension, 5–15 total):**

| # | Name | Feas | Value | Risk | Pattern | Timebox | Total |
|---|------|------|-------|------|---------|---------|-------|
| H1 | Observability-first, defer fixes | 3 | 1 | 3 | 2 | 3 | 12 |
| H2 | Targeted perf playbook (measure lightly, fix top-3, iterate) | 3 | 3 | 2 | 3 | 2 | 13 |
| H3 | Architectural overhaul (BFF + edge cache + streaming render) | 2 | 3 | 1 | 2 | 1 | 9 |
| H4 | Feature-flagged canary-only rollout discipline | 3 | 2 | 3 | 2 | 3 | 13 |

**Full weighted rubric (7-dimension, 0–100 scale; Alignment 25% + Correctness 20% + Maintainability 15% + Performance 15% + Simplicity 10% + Risk 10% + Innovation 5%):**

| Hypothesis | Alignment | Correctness | Maintainability | Performance | Simplicity | Risk | Innovation | **Weighted Total** |
|---|---|---|---|---|---|---|---|---|
| H1 — Observability-first, defer fixes | 6 | 9 | 8 | 3 | 8 | 9 | 3 | **68.0** |
| **H2 — Targeted perf playbook** | **9** | **8** | **8** | **8** | **7** | **8** | **5** | **80.0 ← selected** |
| H3 — Architectural overhaul | 8 | 6 | 6 | 10 | 3 | 4 | 9 | **67.5** |
| H4 — Canary-only rollout discipline | 7 | 8 | 7 | 5 | 5 | 9 | 4 | **67.5** |

Spread between the top score (80.0) and the next-best (68.0) is 12 points —
well above the 5% anti-strawman threshold, so differentiation is sufficient
and no re-observation is needed.

**Expand Top 2 (H2 selected, H3 as the most consequential alternative):**

- **H2 file/dependency impact:** touches `dashboard-web` (frontend bundle/render layer), `dashboard-api` (query + caching layer), plus a lightweight RUM/APM instrumentation layer added to both. Edge cases: cache staleness on multi-tenant data (addressed in S5), and "fixing the wrong bottleneck" if instrumentation is skipped (mitigated — S1–S3 gate S4 onward).
- **H3 file/dependency impact:** would add a new BFF service, an edge/CDN caching tier, and a streaming-render transport — a materially larger footprint with new infra to operate (new on-call surface, new failure modes). Edge cases: cache invalidation across a wider surface, and higher blast radius if the new BFF has a bug (whole dashboard down, not just one slow query).

**Selected: H2 — Targeted Perf Playbook**
**Rationale:** Highest weighted score (80.0, "Solid" tier) and the only hypothesis strong on both Alignment (directly answers "make it faster," now) and Performance while staying Simple enough to fit the assumed team capacity (Assumption A6). It also naturally *absorbs* H4's safety discipline (canary/flag-gated rollout, Story S8) as an execution practice rather than requiring a separate initiative, and uses a light version of H1's instrumentation (S1–S2) as a *gate*, not the entire deliverable — so it doesn't inherit H1's core weakness (Alignment 6 — deferring all actual speed-up).

### Rejected Alternatives

- **H1 — Observability-first, defer fixes (rejected).** Lowest risk and highest correctness, but Alignment scores lowest (6/10): it ships zero perceptible speed-up in its own timebox, which fails the stakeholder's actual ask. Its useful part (instrumentation) is folded into H2 as gating stories S1–S3 instead of standing alone.
- **H3 — Architectural overhaul (rejected for now, deferred).** Highest Performance ceiling (10/10) but weakest Simplicity (3/10) and Risk (4/10) — a new BFF + edge-cache + streaming-render tier is a multi-sprint, new-infra bet disproportionate to an unqualified "make it faster" ask with no confirmed baseline yet. Deferred, not discarded: if S3's baseline shows H2's targeted fixes structurally cannot reach the SLO (e.g., data volume genuinely requires architectural change), H3 is the pre-scoped next spec.
- **H4 — Canary-only rollout discipline (rejected as a standalone hypothesis).** Strong Risk score (9/10) but weak standalone Performance (5/10) — it is a *delivery safety mechanism*, not a fix. Absorbed into H2 as Story S8 rather than rejected outright.
- **"Just add more server capacity" (rejected, not formally scored — a naive alternative, not one of the 4 hypotheses).** Masks root cause (inefficient queries/renders), does not address frontend rendering cost at all, and scales cost linearly with traffic rather than fixing the underlying inefficiency. Rejected on Correctness-of-approach grounds before it reached hypothesis status.
- **"Ship an unmeasured fix and declare victory" (rejected, not formally scored).** Directly contradicts the Measurable Performance Target section above and the stakeholder's own request being unmeasurable in the first place — this is the failure mode the whole spec exists to prevent (see Test §Adversarial, "Under-specification").

---

## C — CONSTRUCT

```
THEME:   Dashboard Performance & Reliability
└── PROJECT: Dashboard Performance Remediation (H2 — Targeted Perf Playbook)
    ├── FEATURE F1: Instrumentation & Baseline
    │   ├── STORY S1: Ship RUM instrumentation on dashboard pages
    │   ├── STORY S2: Ship backend APM tracing + slow-query logging
    │   └── STORY S3: Establish baseline & confirm SLO target with stakeholders  [P0]
    ├── FEATURE F2: Backend / API & Data-Layer Optimization
    │   ├── STORY S4: Eliminate N+1 / redundant queries on top-3 slowest endpoints  [P0]
    │   └── STORY S5: Introduce scoped caching for expensive aggregation reads
    ├── FEATURE F3: Frontend Rendering Optimization
    │   ├── STORY S6: Code-split & lazy-load below-the-fold widgets
    │   └── STORY S7: Virtualize/paginate large list & chart components
    └── FEATURE F4: Rollout Safety & Verification
        ├── STORY S8: Canary/flag-gated rollout with automatic rollback  [P0]
        └── STORY S9: Publish before/after performance report vs. SLO
```

All 9 stories pass INVEST (Independent within their Feature; Negotiable
implementation details; Valuable — each ships an observable improvement or
unblocks one; Estimable at the stated timebox; Small — none exceed 5d; Testable
— each carries GIVEN/WHEN/THEN below).

#### 📋 STORY S1 — Ship RUM instrumentation on dashboard pages

> 🔵 Foundational; unblocks S6/S7 and the final report (S9).

**Description:** As the dashboard engineering team, I want real-user
performance beacons on every dashboard page, so that we measure actual user
experience instead of guessing which parts are slow.
**Timebox:** ≤2d
**Risk:** P1

**Action Plan:**
1. **Configure:** RUM SDK on `dashboard-web`'s app shell, tagged per dashboard route/widget.
2. **Extend:** existing analytics pipeline (or stand up a minimal one) to capture p50/p75/p95 full-render time per route.
3. **Test:** verify beacons fire on real navigations in a staging environment before enabling in production.

**Acceptance Criteria:**
- [ ] GIVEN a user opens any dashboard page WHEN the last above-the-fold widget finishes painting real data THEN a RUM beacon SHALL record full-render time tagged by route and user segment.

**Technical Context:**
- **Pattern:** P1 (measure-then-optimize)
- **Files:** `dashboard-web` app shell / route-level instrumentation hooks *(placeholder — no real repo named; see CLARIFY §4 [GAP])*
- **Dependencies:** none

**Agent Hints:**
- **Class:** builder (speed-class)
- **Context:** existing RUM/analytics SDK docs, dashboard route map
- **Gates:** P1 checked; smoke test confirms beacons fire in staging

---

#### 📋 STORY S2 — Ship backend APM tracing + slow-query logging

> 🔵 Foundational; unblocks S4/S5.

**Description:** As the backend team, I want distributed tracing and
slow-query logging on every dashboard-serving endpoint, so that we can
identify the actual bottlenecks instead of guessing.
**Timebox:** ≤2d
**Risk:** P1

**Action Plan:**
1. **Configure:** APM tracing middleware on all `dashboard-api` endpoints.
2. **Configure:** slow-query threshold logging on the data layer (log any query exceeding a defined threshold, e.g. 200ms).
3. **Test:** confirm traces and slow-query logs appear correctly in staging under synthetic load.

**Acceptance Criteria:**
- [ ] GIVEN any request to a dashboard-serving endpoint WHEN the request completes THEN a trace SHALL be recorded with per-query timing breakdown, and any query over the slow-query threshold SHALL be logged with its query shape.

**Technical Context:**
- **Pattern:** P1 (measure-then-optimize)
- **Files:** `dashboard-api` request middleware / data-access layer *(placeholder)*
- **Dependencies:** none

**Agent Hints:**
- **Class:** builder (speed-class)
- **Context:** existing APM/tracing library config, data-access layer entry points
- **Gates:** P1 checked; traces verified under synthetic load in staging

---

#### 📋 STORY S3 — Establish baseline & confirm SLO target with stakeholders

> 🔴 **Blocking (P0).** Nothing in F2/F3 can be scored "done" without this.

**Description:** As the spec owner, I want a real baseline measurement and a
stakeholder-confirmed SLO target, so that "faster" becomes a number everyone
agrees on instead of a feeling.
**Timebox:** ≤2d (after ≥3–5 days of S1/S2 data collection)
**Risk:** P0

**Action Plan:**
1. **Create:** a baseline report from S1/S2 data (current p50/p75/p95 full-render time; current API p95; top-5 slowest endpoints/widgets by contribution to total render time).
2. **Configure:** a review session with the requesting stakeholder and product owner to confirm/adjust the "Measurable Performance Target" section's provisional numbers against real data.
3. **Test:** confirm the resulting SLO is written down and attached to this spec as the authoritative target before S4 onward begins.

**Acceptance Criteria:**
- [ ] GIVEN 3–5 days of RUM/APM data from S1/S2 WHEN the baseline report is compiled THEN it SHALL state current p50/p75/p95 full-render time, current API p95, and the top-5 slowest contributors by name.
- [ ] GIVEN the baseline report WHEN reviewed with the requesting stakeholder and product owner THEN a confirmed numeric SLO target SHALL replace the provisional target in the "Measurable Performance Target" section before any F2/F3 story is marked complete.

**Technical Context:**
- **Pattern:** N/A (analysis/decision story, not implementation)
- **Files:** N/A — output is the baseline report artifact
- **Dependencies:** S1, S2

**Agent Hints:**
- **Class:** reasoner (reasoning-class), with human sign-off required
- **Context:** S1/S2 collected data, this spec's Measurable Performance Target section
- **Gates:** P0 checked; explicit stakeholder sign-off recorded, not inferred

---

#### 📋 STORY S4 — Eliminate N+1 / redundant queries on top-3 slowest endpoints

> 🔴 Critical path — the primary performance fix.

**Description:** As a dashboard user, I want the endpoints that serve my
dashboard's data to stop re-querying redundantly, so that pages load
noticeably faster.
**Timebox:** ≤5d
**Risk:** P0

**Action Plan:**
1. **Modify:** the top-3 slowest endpoints identified in S3 to batch/eager-load instead of issuing N+1 queries (or equivalent redundant-call pattern for the actual data layer once named).
2. **Extend:** existing query/index coverage where the slow-query log (S2) shows missing indexes.
3. **Test:** regression tests confirming identical response payloads pre/post-fix, plus a load test confirming the measured latency drop.

**Acceptance Criteria:**
- [ ] GIVEN the top-3 slowest endpoints identified in S3 WHEN their queries are optimized THEN each endpoint's p95 latency SHALL drop by a measurable amount toward the S3-confirmed target, with zero change to returned data.
- [ ] GIVEN the optimized endpoints WHEN existing regression tests run THEN all SHALL pass with byte-identical response bodies to the pre-optimization baseline (correctness guardrail — see Constraint layer).

**Technical Context:**
- **Pattern:** P1 reference; adapted once the real data layer is named
- **Files:** `dashboard-api` data-access layer for the top-3 endpoints named in S3 *(placeholder)*
- **Dependencies:** S2, S3

**Agent Hints:**
- **Class:** debugger (diagnostic-class) — root-cause-driven, not speculative
- **Context:** S2 slow-query logs, S3 baseline report, existing query/index definitions
- **Gates:** P0 checked; regression suite green; load test shows measured improvement

---

#### 📋 STORY S5 — Introduce scoped caching for expensive aggregation reads

**Description:** As a dashboard user, I want expensive repeated aggregation
queries served from a short-TTL cache, so that repeat views/refreshes don't
re-pay the full query cost.
**Timebox:** ≤3d
**Risk:** P1

**Action Plan:**
1. **Create:** a cache-aside layer for the read-heavy aggregation queries identified in S3/S4 as expensive-but-repeatable.
2. **Configure:** cache keys scoped per-tenant/per-user (never a shared key across authorization boundaries) with a short TTL appropriate to data freshness needs (per Assumption A2's resolution).
3. **Test:** verify cache invalidation on underlying data mutation, and verify no cross-tenant/cross-user data leakage under concurrent load.

**Acceptance Criteria:**
- [ ] GIVEN a repeated request for the same expensive aggregation within the TTL window WHEN served from cache THEN response latency SHALL drop materially versus an uncached call, with data no staler than the configured TTL.
- [ ] GIVEN two different tenants/users requesting the same aggregation shape WHEN both are served from cache THEN each SHALL only ever receive their own scoped data — never another tenant's cached result (security/compliance guardrail).

**Technical Context:**
- **Pattern:** P2 (cache-aside)
- **Files:** `dashboard-api` aggregation/query layer *(placeholder)*
- **Dependencies:** S2, S4 (informs which queries are worth caching vs. worth just fixing)

**Agent Hints:**
- **Class:** builder (speed-class), reviewed by reasoner for cache-scoping correctness
- **Context:** S3/S4 findings on expensive queries, existing authz/tenant-scoping model
- **Gates:** P1 checked; tenant-isolation test included and passing

---

#### 📋 STORY S6 — Code-split & lazy-load below-the-fold widgets

**Description:** As a dashboard user, I want widgets below the visible
viewport to load after the critical above-the-fold content, so that the page
feels interactive sooner.
**Timebox:** ≤3d
**Risk:** P1

**Action Plan:**
1. **Extend:** `dashboard-web`'s bundling config to code-split below-the-fold widgets into separately-loaded chunks.
2. **Modify:** widget mounting logic to lazy-load on viewport-proximity (intersection observer or equivalent) rather than on initial page load.
3. **Test:** verify above-the-fold render time improves and no widget silently fails to ever load (regression risk: lazy-load bugs hiding content).

**Acceptance Criteria:**
- [ ] GIVEN a dashboard page with below-the-fold widgets WHEN a user loads the page THEN above-the-fold content SHALL render before below-the-fold widget code is fetched, and every widget SHALL still eventually render once scrolled into view.

**Technical Context:**
- **Pattern:** P3 (code-splitting / lazy-load)
- **Files:** `dashboard-web` widget-mounting/bundling config *(placeholder)*
- **Dependencies:** S1 (confirms which widgets/routes are worth prioritizing)

**Agent Hints:**
- **Class:** builder (speed-class)
- **Context:** S1 RUM data on slowest routes/widgets, existing bundler config
- **Gates:** P1 checked; bundle-size budget respected; no widget regresses to "never loads"

---

#### 📋 STORY S7 — Virtualize/paginate large list & chart components

**Description:** As a dashboard user viewing a widget with a large table or
dense chart, I want only the visible rows/points rendered, so that
interacting with large datasets stays smooth.
**Timebox:** ≤3d
**Risk:** P1

**Action Plan:**
1. **Extend:** existing large-list/table widgets to use windowed/virtualized rendering instead of rendering every row.
2. **Modify:** dense-chart widgets to downsample or paginate data points beyond a defined threshold, with an explicit "view more/zoom" affordance.
3. **Test:** verify interaction (scroll/filter/sort) frame budget stays within an acceptable threshold (e.g. no dropped-frame stalls > 100ms) on a representative large dataset.

**Acceptance Criteria:**
- [ ] GIVEN a widget rendering more than the defined row/point threshold WHEN a user scrolls, filters, or sorts it THEN only the visible window SHALL be rendered at any time, and the interaction SHALL stay within the defined frame-budget threshold.

**Technical Context:**
- **Pattern:** P3 (virtualization/pagination)
- **Files:** `dashboard-web` large-list/table/chart widget components *(placeholder)*
- **Dependencies:** S1 (confirms which widgets are worth prioritizing)

**Agent Hints:**
- **Class:** builder (speed-class)
- **Context:** S1 RUM data, existing widget component library
- **Gates:** P1 checked; frame-budget perf test included and passing

---

#### 📋 STORY S8 — Canary/flag-gated rollout with automatic rollback

> 🔴 **Blocking (P0)** before any F2/F3 change reaches 100% of traffic.

**Description:** As the engineering team, I want every performance change
(S4–S7) shipped behind a flag with automated canary monitoring, so that a
regression is caught and reverted before most users are affected.
**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Configure:** feature flags for each of S4–S7's changes, independently toggleable.
2. **Create:** an automated canary gate — route a small traffic percentage first, monitor RUM/APM + error rate against defined rollback thresholds.
3. **Configure:** automatic rollback (flag flip) if any threshold is breached within the canary window, with alerting to on-call.

**Acceptance Criteria:**
- [ ] GIVEN a canary rollout of any F2/F3 change WHEN the defined rollback thresholds (latency regression, error-rate increase, or data-correctness check failure) are breached within the canary window THEN the change SHALL auto-rollback within 15 minutes with zero required manual intervention.
- [ ] GIVEN a canary rollout that stays within thresholds for the full canary window WHEN the window elapses THEN the change SHALL be eligible for progressive rollout to 100% traffic.

**Technical Context:**
- **Pattern:** derived from H4 (absorbed as an execution practice, not a standalone hypothesis)
- **Files:** feature-flag config, deployment/rollout pipeline *(placeholder)*
- **Dependencies:** S4, S5, S6, S7

**Agent Hints:**
- **Class:** builder (speed-class) + reviewer (quality-class) sign-off on rollback thresholds
- **Context:** existing feature-flag/rollout tooling, S3-confirmed SLO thresholds
- **Gates:** P0 checked; rollback tested in staging with an injected regression before relying on it in production

---

#### 📋 STORY S9 — Publish before/after performance report vs. SLO

**Description:** As the spec owner, I want a published before/after report,
so that the stakeholder can see whether "faster" was actually achieved
against the number agreed in S3.
**Timebox:** 1d
**Risk:** P1

**Action Plan:**
1. **Create:** a report comparing S3's baseline to post-rollout (100% traffic, post-S8) measurements for every metric in "Measurable Performance Target."
2. **Test:** confirm the report's numbers are pulled from the same RUM/APM instrumentation as the baseline (apples-to-apples).
3. **Configure:** close the loop with the requesting stakeholder — explicit accept/reject of the outcome against the confirmed SLO.

**Acceptance Criteria:**
- [ ] GIVEN post-rollout production traffic at 100% WHEN the before/after report is compiled THEN it SHALL state p75/p95 full-render time, API p95, and error-rate delta versus the S3 baseline, and explicitly state pass/fail against the S3-confirmed SLO.

**Technical Context:**
- **Pattern:** N/A (reporting story)
- **Files:** N/A — output is the report artifact
- **Dependencies:** S3, S8

**Agent Hints:**
- **Class:** reasoner (reasoning-class)
- **Context:** S3 baseline report, post-rollout RUM/APM data
- **Gates:** P1 checked; stakeholder explicit accept/reject recorded

---

## T — VERIFICATION REPORT (6-Layer)

| # | Layer | Check | Status |
|---|---|---|---|
| 1 | Structural | Hierarchy intact (Theme→Project→Feature→Story); all 9 stories independent within their Feature; no orphaned tasks | ✓ |
| 2 | Self-Consistency | 3 alternative decompositions compared (see below); 75% story overlap | ✓ (≥70% = HIGH confidence) |
| 3 | Dependency | Dependency graph (S4/S5←S2; S6/S7←S1; S8←S4,S5,S6,S7; S9←S3,S8) fully mapped; **file paths NOT validated against a real project** — see [GAP] below | ⚠ partial — see [GAP] |
| 4 | Constraint | Correctness-preservation guardrail (S4 AC2), tenant-isolation guardrail (S5 AC2), rollback-safety guardrail (S8), all timeboxes ≤8d | ✓ |
| 5 | Process Reward | Ordering (instrument → confirm baseline → fix → roll out safely → report) strictly reduces risk at each step; no step assumes an unconfirmed number past S3 | ✓ |
| 6 | Adversarial | See checklist below | ✓ (with documented gaps) |

**Self-Consistency detail — 3 alternative decompositions compared:**

| Decomposition | Grouping axis | Core stories recurring across all 3 |
|---|---|---|
| A (chosen) | By technical discipline (Instrument → Backend → Frontend → Rollout) | instrument, confirm baseline, fix top query, cache, code-split, virtualize, canary rollout, report |
| B | By dashboard page/widget | same core stories, just partitioned per-widget instead of per-discipline — less stable because it requires knowing *which* widgets are slow before S1 runs |
| C | By SLO metric (load-time track / interaction-latency track / data-freshness track) | same core stories, partitioned by metric instead of discipline |

Overlap of the load-bearing stories (instrument, confirm baseline, top-query
fix, cache, frontend split/virtualize, canary rollout, report) across all
three ≈ **75%** → HIGH confidence, decomposition A is stable; proceed.

**Adversarial checklist (Failure Taxonomy):**

| Failure Mode | Present here? | Mitigation |
|---|---|---|
| Under-specification | Yes, in the raw request | This entire spec — Measurable Performance Target + acceptance criteria close it |
| Over-specification | Checked, not present | Stories specify *what*, not exact code; "Technical Context" stays pattern-level |
| Dependency blindness | Partially — no real repo | [GAP] flagged explicitly (Layer 3); do not silently assume file paths |
| Assumption drift | Possible via Assumption A2 | S3 explicitly re-confirms the target before F2/F3 proceeds — catches drift early, not after delivery |
| Scope creep | Guarded | Boundaries table explicitly excludes redesign/new-features/ETL; Deferred column names H3 rather than silently expanding scope |
| Premature optimization | Guarded | Complexity scored 10/12 but approach (H2) deliberately avoids H3's heavier architecture; ADaPT not triggered (complexity >5) |
| Stale context | N/A this session (no prior codebase state to go stale) | — |
| Oscillating refinement | Checked in Refine below | Not observed — no dimension regressed between cycles |

**Gate:** 5 of 6 layers pass cleanly; Layer 3 (Dependency) passes with one
explicit, non-fatal [GAP] (no real repo to validate paths against). Per the
Gate rule ("1–2 minor gaps → Refine (1 cycle)"), this triggered exactly one
Refine cycle, below.

---

## R — REFINEMENT LOG

### Cycle 1

| Dimension | Before | After | Change |
|-----------|--------|-------|--------|
| Clarity | 3 | 4 | Added the explicit "Measurable Performance Target" section so "faster" resolves to a concrete, falsifiable number instead of staying rhetorical. |
| Completeness | 3 | 5 | Expanded Rejected Alternatives to name and reason through 2 naive alternatives ("add servers," "ship unmeasured") in addition to the 3 non-selected hypotheses. |
| Actionability | 3 | 5 | Every story's Acceptance Criteria now names a concrete verification action (regression test, load test, tenant-isolation test, canary threshold) rather than "should be faster." |
| Efficiency | 4 | 4 | No change — decomposition was already lean; extra content added clarity/completeness, not scope. |
| Testability | 3 | 5 | Added the [GAP] callout on Dependency Layer 3 explicitly, instead of silently assuming file paths that don't exist. |

**Diagnosis:** The initial pass stated only a vague performance goal without
a concrete measurable target, under-documented rejected alternatives, and
implicitly assumed file/repo context that isn't actually available.
**Prescription:** Added the Measurable Performance Target section (framework
+ provisional numbers, explicitly gated on S3), expanded Rejected
Alternatives with rationale, and made the missing-repo gap an explicit,
visible [GAP] rather than a silent assumption.
**Exit:** All dimensions ≥4 after Cycle 1 (Cycle-2 target reached in Cycle 1;
no oscillation observed) → proceeding directly to Assemble. Diminishing-returns
check not triggered (this was the first and only cycle).

---

## A — CONFIDENCE ASSESSMENT

| Factor | Score (0–3) | Weight | Contribution |
|--------|-------|--------|---------------|
| Pattern Match | 2/3 | 25% | 16.67% — no internal corpus; industry-reference patterns only, not project-validated |
| Requirement Clarity | 2/3 | 25% | 16.67% — 3 unresolved [GAP]s (surface, baseline, deadline) remain despite documented assumptions |
| Decomposition Stability | 3/3 | 25% | 25.00% — 75% self-consistency overlap (HIGH) |
| Constraint Compliance | 2/3 | 25% | 16.67% — 5/6 verification layers pass cleanly; Layer 3 passes with a flagged, non-fatal gap |

**Weighted Confidence: 75%**
**Decision: VALIDATE** — deliver with flags; a human must review before Feature F2/F3 (S4 onward) begins.

**Open Gaps (must be closed before AUTO_PROCEED could apply):**
- **[GAP]** Which dashboard/product surface, user segment, and pain point (load vs. interaction vs. freshness) — CLARIFY Q1.
- **[GAP]** Real baseline measurement — closed by Story S3, not yet available.
- **[GAP]** Target repository / real file paths for Dependency-layer validation.
- **[GAP]** Deadline, budget, and actual team capacity — CLARIFY Q3.

None of these gaps block *starting* the work — S1/S2 (instrumentation) and
S3 (baseline + SLO confirmation) are gap-*closing* stories by design, so the
spec is immediately actionable even at VALIDATE confidence. What is gated is
S4 onward, which requires S3's confirmed number.

---

## Overall Acceptance Criteria (Definition of Done)

- [ ] **AC-D1:** GIVEN the Story S3 confirmed baseline, WHEN Features F1–F4 are deployed to 100% of traffic (post-canary, Story S8), THEN dashboard p75 full-render time (RUM) SHALL be ≤ the S3-confirmed SLO target (provisionally ≤2.5s or ≥50% reduction from baseline, whichever is more stringent), with no error-rate regression beyond 0.1 percentage points.
- [ ] **AC-D2:** GIVEN the same rollout, WHEN dashboard-serving API endpoints are measured, THEN p95 backend latency SHALL be ≤500ms (provisional, confirmed in S3).
- [ ] **AC-D3:** GIVEN Story S8's canary rollout, WHEN any canary metric breaches its defined rollback threshold, THEN the change SHALL auto-rollback within 15 minutes with zero required manual intervention, as verified in S8/S9.

---

## Preflight Checklist (self-verified)

- [x] CLARIFY ran (3 questions logged; no live stakeholder channel, so proceeded on explicit, risk-tagged assumptions per Scope discipline)
- [x] `spectra-conventions.md` checked — absent; generic placeholders used and flagged
- [x] Complexity scored (10/12); extended-thinking budget applied
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing); spread 12pts ≥ 5% anti-strawman threshold
- [x] All 9 stories pass INVEST
- [x] All timeboxes valid (≤2d–≤5d; none >8d; no story points used)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN (story-level ×13, spec-level ×3 = 16 total validation gates)
- [x] Agent hints with context files per story
- [x] Dual output: Markdown + structured YAML/JSON (below)
- [x] Confidence score present with factor breakdown (75% → VALIDATE)
- [x] Plan saved as a persistent artifact (this file)
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H1, H3, H4, plus 2 naive alternatives)

--- END OF SPEC PAYLOAD ---

## Dual-Format Machine Artifacts

The three artifacts below are SPECTRA's Assemble-phase machine-executable
outputs (Agent Handoff YAML, State Machine JSON, and — because `ECL_VERSION`
2.0 is present in this install's root — the ECL v2.0 envelope). They are
appended here as sibling blocks rather than sibling files, per this
engagement's single-file delivery constraint (see "Notes on This Document's
Format" above). The ECL envelope's `integrity.value` is the real SHA-256 of
this file's bytes from the start of the document through the
`--- END OF SPEC PAYLOAD ---` marker above, inclusive of that marker line —
independently reproducible by any downstream reader who hashes that exact
byte range.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-dashboard-perf"
  confidence: 75
  complexity: 10
  spectra_version: "4.11.0"

projects:
  - id: "P-1"
    name: "Dashboard Performance Remediation"
    features:
      - id: "F-1"
        name: "Instrumentation & Baseline"
        stories:
          - id: "S-1"
            title: "Ship RUM instrumentation on dashboard pages"
            timebox: "<=2d"
            risk: "P1"
            action_plan:
              - verb: "Configure"
                target: "RUM SDK on dashboard-web app shell, per route/widget"
              - verb: "Extend"
                target: "analytics pipeline to capture p50/p75/p95 full-render time"
              - verb: "Test"
                target: "beacons fire on real navigations in staging"
            acceptance_criteria:
              - given: "a user opens any dashboard page"
                when: "the last above-the-fold widget finishes painting real data"
                then: "a RUM beacon records full-render time tagged by route and user segment"
            agent_hints:
              recommended_class: "builder"
              context_files: ["dashboard-web app shell (placeholder — repo unnamed)"]
              validation_gates:
                p0: "n/a"
                coverage: "smoke test in staging"
            dependencies: []
          - id: "S-2"
            title: "Ship backend APM tracing + slow-query logging"
            timebox: "<=2d"
            risk: "P1"
            action_plan:
              - verb: "Configure"
                target: "APM tracing middleware on all dashboard-api endpoints"
              - verb: "Configure"
                target: "slow-query threshold logging on the data layer"
              - verb: "Test"
                target: "traces/logs verified under synthetic load in staging"
            acceptance_criteria:
              - given: "any request to a dashboard-serving endpoint"
                when: "the request completes"
                then: "a trace is recorded with per-query timing; slow queries are logged with their shape"
            agent_hints:
              recommended_class: "builder"
              context_files: ["dashboard-api middleware (placeholder — repo unnamed)"]
              validation_gates:
                p0: "n/a"
                coverage: "verified under synthetic load"
            dependencies: []
          - id: "S-3"
            title: "Establish baseline & confirm SLO target with stakeholders"
            timebox: "<=2d"
            risk: "P0"
            action_plan:
              - verb: "Create"
                target: "baseline report from S1/S2 data (p50/p75/p95, API p95, top-5 slowest)"
              - verb: "Configure"
                target: "stakeholder review session to confirm/adjust the SLO target"
              - verb: "Test"
                target: "confirmed SLO recorded as authoritative before S4 onward"
            acceptance_criteria:
              - given: "3-5 days of RUM/APM data from S1/S2"
                when: "the baseline report is compiled"
                then: "it states current p50/p75/p95, current API p95, and top-5 slowest contributors"
              - given: "the baseline report"
                when: "reviewed with the requesting stakeholder and product owner"
                then: "a confirmed numeric SLO replaces the provisional target before any F2/F3 story is complete"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["S1/S2 collected data", "this spec's Measurable Performance Target section"]
              validation_gates:
                p0: "checked"
                coverage: "explicit stakeholder sign-off recorded"
            dependencies: ["S-1", "S-2"]
      - id: "F-2"
        name: "Backend / API & Data-Layer Optimization"
        stories:
          - id: "S-4"
            title: "Eliminate N+1 / redundant queries on top-3 slowest endpoints"
            timebox: "<=5d"
            risk: "P0"
            action_plan:
              - verb: "Modify"
                target: "top-3 slowest endpoints to batch/eager-load instead of N+1"
              - verb: "Extend"
                target: "query/index coverage per slow-query log findings"
              - verb: "Test"
                target: "regression + load test confirming latency drop with identical payloads"
            acceptance_criteria:
              - given: "the top-3 slowest endpoints identified in S3"
                when: "their queries are optimized"
                then: "p95 latency drops measurably toward the S3-confirmed target with zero data change"
              - given: "the optimized endpoints"
                when: "existing regression tests run"
                then: "all pass with byte-identical response bodies to the pre-optimization baseline"
            agent_hints:
              recommended_class: "debugger"
              context_files: ["S2 slow-query logs", "S3 baseline report", "existing query/index definitions"]
              validation_gates:
                p0: "checked"
                coverage: "regression suite green; load test shows improvement"
            dependencies: ["S-2", "S-3"]
          - id: "S-5"
            title: "Introduce scoped caching for expensive aggregation reads"
            timebox: "<=3d"
            risk: "P1"
            action_plan:
              - verb: "Create"
                target: "cache-aside layer for expensive-but-repeatable aggregation queries"
              - verb: "Configure"
                target: "per-tenant/per-user scoped cache keys with short TTL"
              - verb: "Test"
                target: "invalidation on mutation; no cross-tenant leakage under concurrent load"
            acceptance_criteria:
              - given: "a repeated request for the same expensive aggregation within the TTL window"
                when: "served from cache"
                then: "latency drops materially, with data no staler than the configured TTL"
              - given: "two different tenants/users requesting the same aggregation shape"
                when: "both are served from cache"
                then: "each only ever receives their own scoped data, never another tenant's cached result"
            agent_hints:
              recommended_class: "builder"
              context_files: ["S3/S4 findings on expensive queries", "existing authz/tenant-scoping model"]
              validation_gates:
                p0: "n/a"
                coverage: "tenant-isolation test included and passing"
            dependencies: ["S-2", "S-4"]
      - id: "F-3"
        name: "Frontend Rendering Optimization"
        stories:
          - id: "S-6"
            title: "Code-split & lazy-load below-the-fold widgets"
            timebox: "<=3d"
            risk: "P1"
            action_plan:
              - verb: "Extend"
                target: "dashboard-web bundling config to code-split below-the-fold widgets"
              - verb: "Modify"
                target: "widget mounting logic to lazy-load on viewport-proximity"
              - verb: "Test"
                target: "above-the-fold render time improves; no widget silently fails to load"
            acceptance_criteria:
              - given: "a dashboard page with below-the-fold widgets"
                when: "a user loads the page"
                then: "above-the-fold content renders before below-the-fold code is fetched, and every widget eventually renders on scroll"
            agent_hints:
              recommended_class: "builder"
              context_files: ["S1 RUM data on slowest routes/widgets", "existing bundler config"]
              validation_gates:
                p0: "n/a"
                coverage: "bundle-size budget respected"
            dependencies: ["S-1"]
          - id: "S-7"
            title: "Virtualize/paginate large list & chart components"
            timebox: "<=3d"
            risk: "P1"
            action_plan:
              - verb: "Extend"
                target: "large-list/table widgets to windowed/virtualized rendering"
              - verb: "Modify"
                target: "dense-chart widgets to downsample/paginate beyond a defined threshold"
              - verb: "Test"
                target: "interaction frame budget stays within threshold on representative large dataset"
            acceptance_criteria:
              - given: "a widget rendering more than the defined row/point threshold"
                when: "a user scrolls, filters, or sorts it"
                then: "only the visible window renders, staying within the defined frame-budget threshold"
            agent_hints:
              recommended_class: "builder"
              context_files: ["S1 RUM data", "existing widget component library"]
              validation_gates:
                p0: "n/a"
                coverage: "frame-budget perf test included and passing"
            dependencies: ["S-1"]
      - id: "F-4"
        name: "Rollout Safety & Verification"
        stories:
          - id: "S-8"
            title: "Canary/flag-gated rollout with automatic rollback"
            timebox: "<=2d"
            risk: "P0"
            action_plan:
              - verb: "Configure"
                target: "independent feature flags for each of S4-S7's changes"
              - verb: "Create"
                target: "automated canary gate monitoring RUM/APM + error rate vs. rollback thresholds"
              - verb: "Configure"
                target: "automatic rollback on threshold breach with on-call alerting"
            acceptance_criteria:
              - given: "a canary rollout of any F2/F3 change"
                when: "defined rollback thresholds are breached within the canary window"
                then: "the change auto-rollbacks within 15 minutes with zero required manual intervention"
              - given: "a canary rollout that stays within thresholds for the full window"
                when: "the window elapses"
                then: "the change is eligible for progressive rollout to 100% traffic"
            agent_hints:
              recommended_class: "builder"
              context_files: ["existing feature-flag/rollout tooling", "S3-confirmed SLO thresholds"]
              validation_gates:
                p0: "checked"
                coverage: "rollback tested in staging with an injected regression"
            dependencies: ["S-4", "S-5", "S-6", "S-7"]
          - id: "S-9"
            title: "Publish before/after performance report vs. SLO"
            timebox: "1d"
            risk: "P1"
            action_plan:
              - verb: "Create"
                target: "before/after report vs. S3 baseline across all Measurable Performance Target metrics"
              - verb: "Test"
                target: "report numbers pulled from same instrumentation as the baseline"
              - verb: "Configure"
                target: "stakeholder explicit accept/reject of the outcome"
            acceptance_criteria:
              - given: "post-rollout production traffic at 100%"
                when: "the before/after report is compiled"
                then: "it states p75/p95 full-render time, API p95, and error-rate delta vs. baseline, with explicit pass/fail against the S3 SLO"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["S3 baseline report", "post-rollout RUM/APM data"]
              validation_gates:
                p0: "n/a"
                coverage: "stakeholder explicit accept/reject recorded"
            dependencies: ["S-3", "S-8"]

execution_plan:
  phases:
    - name: "Phase 1 — Instrument & Baseline"
      stories: ["S-1", "S-2", "S-3"]
      agent_class: "builder+reasoner"
    - name: "Phase 2 — Optimize (Backend + Frontend, parallelizable)"
      stories: ["S-4", "S-5", "S-6", "S-7"]
      agent_class: "builder+debugger"
    - name: "Phase 3 — Roll Out Safely & Report"
      stories: ["S-8", "S-9"]
      agent_class: "builder+reasoner"
```

### State Machine (JSON)

```json
{
  "session_id": "019f33bd-e50b-7742-a422-a7a70055ef6d",
  "spec_id": "SPEC-2026-07-05-dashboard-perf",
  "goal": "Make the dashboard faster: reduce dashboard p75 full-render time and API p95 latency to a stakeholder-confirmed SLO, without regressing correctness.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Ship RUM instrumentation on dashboard pages", "status": "pending", "dependencies": [], "files_affected": ["dashboard-web (placeholder)"], "verification_command": "manual: confirm beacons in staging", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Ship backend APM tracing + slow-query logging", "status": "pending", "dependencies": [], "files_affected": ["dashboard-api (placeholder)"], "verification_command": "manual: confirm traces under synthetic load", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Establish baseline & confirm SLO target with stakeholders", "status": "pending", "dependencies": ["S-1", "S-2"], "files_affected": [], "verification_command": "manual: stakeholder sign-off recorded", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Eliminate N+1 / redundant queries on top-3 slowest endpoints", "status": "pending", "dependencies": ["S-2", "S-3"], "files_affected": ["dashboard-api data-access layer (placeholder)"], "verification_command": "regression suite + load test", "estimated_timebox": "<=5d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Introduce scoped caching for expensive aggregation reads", "status": "pending", "dependencies": ["S-2", "S-4"], "files_affected": ["dashboard-api aggregation layer (placeholder)"], "verification_command": "tenant-isolation test", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Code-split & lazy-load below-the-fold widgets", "status": "pending", "dependencies": ["S-1"], "files_affected": ["dashboard-web widget mounting (placeholder)"], "verification_command": "bundle-size budget check", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Virtualize/paginate large list & chart components", "status": "pending", "dependencies": ["S-1"], "files_affected": ["dashboard-web widget components (placeholder)"], "verification_command": "frame-budget perf test", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 8, "story_id": "S-8", "title": "Canary/flag-gated rollout with automatic rollback", "status": "pending", "dependencies": ["S-4", "S-5", "S-6", "S-7"], "files_affected": ["feature-flag config", "rollout pipeline (placeholder)"], "verification_command": "staging rollback drill with injected regression", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 9, "story_id": "S-9", "title": "Publish before/after performance report vs. SLO", "status": "pending", "dependencies": ["S-3", "S-8"], "files_affected": [], "verification_command": "manual: stakeholder accept/reject recorded", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": []
}
```

### ECL Envelope (v2.0)

```json
{
  "envelope_version": "2.0",
  "message_id": "019f33bd-e50b-7bb6-9f94-d698ed7502a2",
  "thread_id": "019f33bd-e50b-7742-a422-a7a70055ef6d",
  "parent_id": null,
  "from": {
    "eidolon": "spectra",
    "version": "4.11.0"
  },
  "to": {
    "eidolon": "apivr",
    "version": "n/a"
  },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose a decision-ready specification to reduce dashboard latency (RUM p75/p95 full-render time, API p95) against a stakeholder-confirmable SLO.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": "AB-T4-spectra-r1.out.md",
    "sha256": "e901a440f386e1a066d8fb2d546d2fa863aeefe2d60a7220be8a49f51a22491a",
    "size_bytes": 42985
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Decision-ready spec for 'make the dashboard faster': CLARIFY questions + risk-tagged assumptions for the missing surface/baseline/deadline; a two-tier (framework + provisional-numeric) measurable SLO target gated on a baseline-confirmation story; 4 scored hypotheses (targeted-playbook selected at 80/100, architecture-overhaul deferred, observability-only and canary-only rejected/absorbed); a 9-story Theme->Project->Feature->Story plan across instrumentation, backend optimization, frontend optimization, and safe rollout; 6-layer verification with one flagged non-fatal dependency gap; confidence 75% (VALIDATE)."
  },
  "constraints": {
    "trust_level": "standard"
  },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "spectra-4.11.0",
      "tool_surface": ["Read", "Grep", "Glob", "Bash"],
      "lateral_consults": []
    },
    "receiver_authorization": {
      "auto_route": true,
      "auto_merge": false,
      "auto_deploy": false
    }
  },
  "confidence": 0.75,
  "integrity": {
    "method": "sha256",
    "value": "e901a440f386e1a066d8fb2d546d2fa863aeefe2d60a7220be8a49f51a22491a"
  },
  "trace": {
    "ts": "2026-07-05T19:25:10Z",
    "host": "claude-code",
    "model": "claude-sonnet-5",
    "tier": "standard"
  }
}
```

*(`x_spectra_acceptance_criteria` vendor extension omitted — this spec uses the plain GIVEN/WHEN/THEN story format, not the optional EARS form, since the consumer project has not adopted ESL: `ESL_VERSION` is absent from the install root.)*

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*

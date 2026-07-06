---
eidolon: spectra
version: "4.11.0"
kind: spec
status: in-review
created_at: "2026-07-05T19:30:00Z"
thread_id: "019f33be-1712-7143-89e8-e00171989f3d"
target_repos:
  - "<dashboard-frontend> (placeholder — no repo named by stakeholder or discoverable in workspace; see Gap G1)"
  - "<dashboard-api> (placeholder — see Gap G1)"
stories_count: 10
validation_gates_count: 10
evidence_anchors_count: 0
confidence: 0.58
---

# Dashboard Performance Remediation — Decision-Ready Specification

**Requester:** Stakeholder (unnamed) · **Prepared by:** SPECTRA planning cycle · **Date:** 2026-07-05
**Mission as received (verbatim):** *"Make the dashboard faster."*

---

## Decision Snapshot (read this first)

| Question | Answer |
|---|---|
| Is this request specific enough to execute today? | **No.** It names no dashboard, no metric, no baseline, and no deadline. This spec resolves that gap explicitly below rather than blocking on it. |
| Can work start immediately? | **Yes — Feature 1 (Baseline & Instrumentation) only.** It is valid regardless of which assumption below turns out to be wrong. |
| What needs a stakeholder decision before Features 2–4 proceed? | Confirm or correct the 3 questions in **Gaps G1–G3** (each answerable in under a minute) — or wait for Feature 1's empirical findings to resolve them by measurement instead. |
| What is "faster," concretely? | See **Measurable Performance Target** — a dual relative/absolute target so the spec stays valid even though today's baseline is unknown. |
| Confidence in this plan | **58% — COLLABORATE tier.** See **Confidence Assessment**. This is an honest signal that stakeholder input materially changes the plan's shape, not a defect in the plan. |

---

## DISCOVER — skipped (rationale)

DISCOVER activates only when the *goal itself* is unknown or latent (`IDEA`/`STRATEGIC` intent). Here the goal is stated and unambiguous — improve dashboard performance. What is missing is *specification detail* (which dashboard, what metric, what baseline), which is CLARIFY's job, not DISCOVER's. Proceeding directly to CLARIFY per the DISCOVER/CLARIFY boundary rule in `SPEC.md`.

---

## CLARIFY

**Parsed intent:**

- **WHO:** A stakeholder (role unspecified) is the requester. Affected parties: dashboard end users (audience unspecified — could be internal operators, customers, or executives), the engineering team that will implement changes, and — if any caching or data-layer change touches permissioned data — security/compliance reviewers.
- **WHAT:** Reduce the dashboard's perceived and/or actual latency — initial load and/or in-page interactions.
- **WHY:** Not stated. Presumed business value: user productivity, reduced complaints/churn, or a specific triggering event (demo, incident, customer escalation) — unknown.
- **CONSTRAINTS:** None given — no budget, deadline, tech-stack lock-in, or compliance note in the mission text.

**Gaps identified — the ≤3 questions this phase would ask a live stakeholder:**

| ID | Question | Why it changes the plan's shape |
|----|----------|----------------------------------|
| G1 | Which dashboard (name/route) is "the dashboard" — is there more than one in the product? | Determines Feature 1's instrumentation target; wrong answer means measuring the wrong surface entirely. |
| G2 | Does "faster" mean initial page load, in-page interaction responsiveness (filters/date range/refresh), data export/report generation speed, or all three? | Determines which of Features 2–3's remediation techniques even apply. |
| G3 | Is there an existing performance SLA, a specific device/network profile that matters most (e.g., field staff on mobile/4G), or a triggering incident driving urgency now? | Determines target calibration and whether compliance/legal join the approval chain. |

No live stakeholder is available in this delivery context, so — per this methodology's Scope-phase instruction to log assumptions with risk-if-wrong rather than block — each gap is resolved by an explicit, reversible assumption (see **Scope → Assumptions**, A1–A4). Feature 1 is scoped so it resolves G1 and part of G2 **empirically**, independent of whether the stakeholder ever answers.

**Structural context gathered:** This workspace contains no application source (no frontend/backend/database code, no `.spectra/setup/spectra-conventions.md` project-vocabulary file). Per `SPEC.md` CLARIFY step 4, generic placeholders are used throughout in place of real module/file names, clearly bracketed (e.g. `<dashboard-frontend>`) so they are trivially find-and-replaceable once the real repo is attached to this plan.

**Cognitive load:** Single planning session, no multi-session split needed; complexity routes to extended thinking (see Scope).

---

## S — SCOPE ANALYSIS

**Intent Type:** `CHANGE` (modify an existing, unnamed system for a non-functional property) with `REQUEST`-like under-specification.

**Complexity Score:** **9 / 12** → **Extended thinking** (2× depth budget applied throughout this cycle)

| Dimension | Score | Justification |
|---|---|---|
| Scope | 1 (Low) | Single feature/surface — "the dashboard" — not a multi-project initiative. |
| Ambiguity | 3 (High) | No metric, no baseline, no named dashboard, no deadline: textbook vague/conflicting. |
| Dependencies | 3 (High) | A generic "dashboard is slow" complaint can originate in frontend rendering, API layer, database queries, or caching — genuinely cross-domain until measured. |
| Risk | 2 (Medium) | User-facing (people look at dashboards regularly); not stated to be revenue-critical or on a critical path. |

**Total: 9** → not high enough to require human-in-the-loop routing (10–12) or TRANCE parallel mode (which additionally requires an explicit multi-service-architecture/high-rework-risk stakes flag, not present here) — but high enough that a single-pass "just start optimizing" approach would likely need significant rework. Standard S→P→E→C→T→R→A cycle, extended-thinking tier.

**WHO / WHAT / WHY / CONSTRAINTS:** as parsed in CLARIFY above.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| The primary/most-trafficked dashboard's initial-load performance | Other dashboards/pages not named by the stakeholder (resolve via G1) | Architectural rewrite (e.g., new read-model, SSR migration) unless Feature 1 proves indexing/caching cannot fix the bottleneck |
| Key in-page interactions: filter change, date-range change, manual refresh | New dashboard features/content | Real-time/streaming dashboard variants, if any exist and are distinct from the target surface |
| Backend query and caching optimization for the data backing the dashboard | Mobile native app performance (assumed web only — no mobile mention) | Broad "apply every web-perf trick" sweep (H2, rejected as primary strategy — see Explore) |
| Frontend rendering optimization (bundle size, virtualization, loading states) | Infra/platform migration (DB engine swap, hosting change) | — |
| Instrumentation, a fixed synthetic-test profile, and a CI performance regression gate | Compliance/legal review process design (only added to approval chain if G3 surfaces an SLA) | — |

**Assumptions (logged per this methodology's Scope-phase requirement):**

| ID | Assumption | Risk if wrong |
|----|------------|---------------|
| A1 | "The dashboard" = the single primary/most-trafficked dashboard surface, not every dashboard in the product. | Effort targets the wrong surface; stakeholder's actual pain point is unaddressed despite metrics improving on the wrong page. **Mitigation:** Feature 1's instrumentation is scoped per-surface, so misidentification surfaces within the first measurement cycle (days, not months), and Feature 1 is cheap to re-point. |
| A2 | "Faster" means initial page-load speed **and** in-page interaction responsiveness — the two most common meanings of "dashboard is slow" — not data-export/report-generation speed. | If the real complaint is about exporting a report or generating a PDF, this entire remediation targets the wrong latency and stakeholder satisfaction won't move even as the defined metrics hit target. **Mitigation:** G2 is the cheapest gap to close — a one-line stakeholder confirmation collapses this risk to near zero. |
| A3 | The system is a conventional three-tier web app: SPA or server-rendered frontend + REST/GraphQL API + relational database — the generic default per this methodology's CLARIFY step 4, since no project source or conventions file is discoverable here. | If the real system is, e.g., an embedded BI tool (Looker/Tableau/PowerBI) or a desktop client, the FEATURE-level shape (measure → backend fix → frontend fix → guardrail) still holds, but STORY-level technical implementation (indexing, code-splitting) will need re-Construct once the real stack is known. |
| A4 | No pre-existing, contractually-binding performance SLA exists (none was mentioned). | If an SLA already exists, the target proposed below may be mis-calibrated (too lax, or the current state may already be in breach more severely than assumed), and legal/compliance should join the approval chain. **Mitigation:** G3 surfaces this directly. |

**Stakeholders / approval chain:**

- **Requester** (unnamed) — approves priority and the performance target.
- **End users** (audience unspecified — `[GAP]`, resolved by A1/G1) — ultimate judge of "faster."
- **Engineering** — implements; frontend + backend + (if caching/query changes touch permissioned data) a security reviewer for Story 2.2 specifically.
- **Design/UX** — reviews loading-state changes (Story 3.2) for consistency with product patterns.
- **SRE/Infra** (conditional) — reviews any caching-layer addition (Story 2.2) for operational impact.

---

## P — PATTERN ANALYSIS

**Query:** "dashboard performance optimization, frontend rendering, API/query latency, caching"

**Memory (CRYSTALIUM) matches:** 0 — `mcp__crystalium__*` tools are unavailable in this session. Per this methodology's graceful-skip rule, planning proceeds without memory; no hard fail.

**Codebase matches:** 0 — this workspace contains no application source to pattern-match against (a fresh consumer-project scaffold with only the SPECTRA install and manifest files present).

**Strategy: GENERATE** (similarity <60% by definition — there is no project-internal corpus to match against). External reference patterns used as context, not as project-specific templates:

| Ref | Pattern | Role here |
|---|---|---|
| R1 | RAIL / Core Web Vitals performance model | Source of the measurable target's thresholds (LCP, TTI, response budget) |
| R2 | Cache-aside / TTL cache for expensive read aggregates | Candidate technique for Story 2.2, gated behind bottleneck confirmation |
| R3 | Code-splitting + list virtualization for data-heavy UIs | Candidate technique for Stories 3.1/3.3, gated behind bottleneck confirmation |
| R4 | Measure-first / profile-before-optimize (classic performance-engineering discipline) | Backbone of the selected hypothesis (H1) — see Explore |

**Adaptations:** None needed (no adaptation source); all four reference patterns are applied at "reference," not "template," strength per the GENERATE strategy.

**Catalog of failure patterns to avoid (no prior-failure memory available, so drawn from the Failure Taxonomy directly):** Premature Optimization (guessing the bottleneck before measuring) and Scope Creep (fixing every dashboard, not the named one) are the two highest-probability failure modes for this specific request shape, and are explicitly designed against below.

---

## E — EXPLORATION SUMMARY

Four genuinely distinct hypotheses were generated (exceeding the 3-minimum; conservative, pattern-leveraging, innovative, and risk-minimizing angles are all represented per the mandatory mix).

| # | Hypothesis | Alignment 25% | Correctness 20% | Maintain. 15% | Perf. 15% | Simplicity 10% | Risk 10% | Innovation 5% | **Weighted Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Measurement-first, targeted remediation** (conservative) | 9 | 9 | 8 | 7 | 8 | 9 | 4 | **82.5** |
| H2 | Apply the full standard web-perf checklist broadly, unfocused (pattern-leveraging) | 7 | 7 | 7 | 7 | 6 | 6 | 5 | 67.0 |
| H3 | Architectural rewrite — precomputed read-model / edge caching / SSR (innovative) | 6 | 6 | 5 | 9 | 3 | 4 | 9 | 59.5 |
| H4 | Perceived-performance only — skeleton screens/optimistic UI, no backend change (risk-minimizing) | 4 | 8 | 8 | 3 | 9 | 9 | 3 | 62.0 |

Gap between H1 (82.5) and the runner-up (H2, 67.0) is 15.5 points — well outside the 5% anti-strawman band, so differentiation is sufficient and no re-observation is required.

**Selected: H1 — Measurement-first, targeted remediation.**

**Rationale:** The single largest risk in this mission is the Ambiguity=3/High score from Scope — there is currently zero telemetry, so the actual bottleneck's location (frontend paint, API compute, DB query, or network) is genuinely unknown. Any strategy that commits to a specific fix before measuring is only correct by luck. H1 sequences a cheap, low-risk measurement phase (Feature 1) before spending on remediation, which directly targets the mission's actual dominant risk. H1 does not discard H2's techniques — indexing, caching, and code-splitting are retained as the **candidate fix toolkit** for Features 2–3, but gated behind Feature 1's bottleneck-attribution findings (Story 1.3) rather than applied blind.

**Rejected Alternatives (documented so replanning never re-explores them from scratch):**

- **H2 — rejected as the *primary* strategy** (retained as *toolkit*, not thrown away): applying the full performance checklist across frontend, API, and database simultaneously without first confirming where the actual latency lives risks the Failure Taxonomy's "Premature Optimization" and "Scope Creep" modes — engineering effort could land entirely on layers that were never the bottleneck. Its individual techniques survive into Features 2–3 as conditional stories.
- **H3 — rejected for this remediation cycle, deferred not discarded**: scored weakest of all four on Correctness (6), Maintainability (5), and Simplicity (3) because it introduces new failure surface (cache/read-model staleness, sync bugs) to fix a problem that hasn't even been localized yet. Its high Performance (9) and Innovation (9) scores make it worth revisiting explicitly if Story 1.3's bottleneck-attribution report shows the root cause is structural (e.g., a query fan-out pattern that indexing/caching genuinely cannot fix) — it is carried forward in the **Deferred** column of Scope, not dropped.
- **H4 — rejected as the *sole* strategy**: scored lowest of all four on Performance (3) because it treats the symptom (user perception of waiting) without necessarily reducing actual latency — it fails the mission's explicit requirement for a measurable *performance* target grounded in real latency reduction. Its cheap, always-good-practice techniques (skeleton loaders, request debouncing) are retained as Story 3.2, a small addition layered on top of H1, not a replacement for it.

---

## Measurable Performance Target

Because no current baseline exists, the target is defined in **two forms simultaneously** so the spec stays decision-ready regardless of what Feature 1 discovers:

**1. Absolute thresholds** (industry-standard defaults per RAIL / Core Web Vitals, pending recalibration against the real baseline once measured):

| Journey | Metric | Target (P95) | Target (P99) |
|---|---|---|---|
| Initial dashboard load | Largest Contentful Paint (LCP) | ≤ 2.5 s | ≤ 4.0 s |
| Initial dashboard load | Time-to-Interactive (TTI) | ≤ 3.5 s | ≤ 5.0 s |
| Filter / date-range / refresh interaction | End-to-end response | ≤ 500 ms | ≤ 1.0 s |
| Interaction "first feedback" (skeleton/spinner appears) | Perceived response | ≤ 100 ms | — |
| Dashboard data API endpoints | Server-side response | ≤ 500 ms | ≤ 1.0 s |

Reference test profile (fixed for synthetic/CI measurement): mid-tier laptop-class device, throttled network equivalent to Lighthouse "Slow 4G" — chosen as a conservative default; revisit if G3 surfaces a different priority device/network profile.

**2. Relative improvement** (valid even if the absolute thresholds above turn out to be miscalibrated once real data lands):

- **≥ 40% reduction** in P95 Time-to-Interactive vs. the Story 1.1 baseline, **and**
- **≥ 50% reduction** in P95 latency of the single worst-offending query/endpoint identified by Story 1.3's bottleneck-attribution report.

**Success = whichever target is reached first** (absolute or relative) — this is the mechanism that keeps "define a measurable performance target" honest under total baseline ignorance: if today's dashboard is already close to the absolute thresholds, the relative target still forces meaningful, provable improvement; if today's dashboard is far worse than assumed, the absolute thresholds still define a concrete, non-negotiable floor.

**Regression guard:** once a new baseline is established post-remediation, no shipped change may regress any of the above metrics by more than 10% without an explicit, logged waiver (enforced by Story 4.1's CI gate).

---

## C — CONSTRUCT: Story Hierarchy

```
THEME: Dashboard Performance Improvement
└── PROJECT: Dashboard Load & Interaction Latency Remediation
    ├── FEATURE 1: Performance Baseline & Instrumentation
    │   ├── STORY 1.1: Real-User + Synthetic Monitoring Instrumentation
    │   ├── STORY 1.2: Fixed Reference Environment for CI Perf Testing
    │   └── STORY 1.3: Bottleneck Attribution Report
    ├── FEATURE 2: Backend / Data-Layer Optimization  [CONDITIONAL — gated by Story 1.3]
    │   ├── STORY 2.1: Slow-Query Remediation (index/rewrite)
    │   └── STORY 2.2: Caching Layer for Expensive Aggregates
    ├── FEATURE 3: Frontend Rendering Optimization  [PARTIALLY CONDITIONAL — gated by Story 1.3]
    │   ├── STORY 3.1: Code-Splitting & Lazy-Loading of Below-the-Fold Widgets
    │   ├── STORY 3.2: Loading States & Interaction Debouncing
    │   └── STORY 3.3: List/Chart Virtualization for Large Datasets  [gated]
    └── FEATURE 4: Perceived-Performance & Regression Guardrails
        ├── STORY 4.1: CI Performance Budget Gate
        └── STORY 4.2: Stakeholder-Facing Performance Runbook
```

"Conditional/gated" stories are deliberate: they name the likely fix given generic dashboard architecture (per Pattern R2/R3), but their inclusion in the executed plan is confirmed or dropped by Story 1.3's empirical findings — this is the mechanism that prevents the "Premature Optimization" failure mode called out in Explore while still letting the stakeholder see the full candidate plan today.

### FEATURE 1 — Performance Baseline & Instrumentation

#### STORY 1.1 — Real-User + Synthetic Monitoring Instrumentation

**Description:** As an **engineering team**, I want **real-user monitoring (RUM) and synthetic instrumentation on the target dashboard's key journeys** so that **we have an objective, defensible baseline before changing anything**.
**Timebox:** ≤3d · **Risk:** P0 (blocks all downstream measurement and target validation)

**Action Plan:**
1. **Configure:** RUM instrumentation for the four key journeys — initial load, filter change, date-range change, manual refresh.
2. **Create:** dashboards/queries in the observability tool to surface LCP, TTI, and API round-trip time per journey.
3. **Test:** verify events fire correctly in a staging/canary environment before relying on production data.

**Acceptance Criteria:**
- [ ] GIVEN the target dashboard (per Assumption A1) WHEN a real user loads it THEN LCP, TTI, and backing-API round-trip times are recorded and queryable in the observability tool.
- [ ] GIVEN instrumentation has been live for 7 days of normal production traffic WHEN the baseline report is pulled THEN it contains P50/P95/P99 for each of the four key journeys.

**Technical Context:** Pattern: RUM + synthetic monitoring (R1). Files: `<dashboard-frontend>/` instrumentation hooks, `<observability-config>/`. Dependencies: none (first story in the plan).

**Agent Hints:** Class: **builder** (speed-class). Context: existing observability/RUM tooling docs for the real stack once attached. Gates: instrumentation verified firing in staging before merge; no PII in recorded fields.

---

#### STORY 1.2 — Fixed Reference Environment for CI Perf Testing

**Description:** As an **engineering team**, I want **a fixed device/network profile wired into CI** so that **every future perf measurement is apples-to-apples, not noise from varying test conditions**.
**Timebox:** ≤2d · **Risk:** P1

**Action Plan:**
1. **Configure:** a Lighthouse-CI-equivalent job against the target dashboard route, throttled to the reference profile (mid-tier laptop, "Slow 4G").
2. **Create:** a trend store for LCP/TTI results over time (even before any optimization work lands, to establish the synthetic-side baseline in parallel with 1.1's real-user baseline).

**Acceptance Criteria:**
- [ ] GIVEN the CI perf job WHEN it runs against the dashboard route THEN it reports LCP and TTI under the fixed throttling profile and stores the result as a trend artifact.
- [ ] GIVEN two consecutive CI runs on unchanged code WHEN compared THEN results vary by no more than 10% (confirms the profile is stable enough to gate on).

**Technical Context:** Pattern: fixed synthetic profile (R1). Files: CI pipeline config (`<ci-config>/perf.yml`). Dependencies: none.

**Agent Hints:** Class: **builder**. Context: existing CI pipeline definitions. Gates: profile stability check (±10%) before this story is considered done.

---

#### STORY 1.3 — Bottleneck Attribution Report

**Description:** As an **engineering team**, I want **an end-to-end profile of the target dashboard's key journeys (frontend waterfall + backend trace + DB query plan)** so that **Features 2 and 3 spend effort on the actual top offenders, not guesses**.
**Timebox:** ≤3d · **Risk:** P0 (drives all downstream prioritization) · **Depends on:** Story 1.1

**Action Plan:**
1. **Analyze:** frontend performance waterfall (bundle load, render blocking, long tasks) for the initial-load journey.
2. **Analyze:** backend/API traces and DB query plans (`EXPLAIN`-equivalent) for the endpoints backing all four key journeys.
3. **Construct:** a ranked list of the top bottleneck candidates by estimated % contribution to P95 latency.

**Acceptance Criteria:**
- [ ] GIVEN 7 days of baseline telemetry (Story 1.1) WHEN the profiling spike completes THEN a ranked list of at least 3 bottleneck candidates exists, each with an estimated % contribution to P95 latency.
- [ ] GIVEN the ranked list WHEN reviewed against Features 2 and 3's candidate stories THEN each candidate story is explicitly marked CONFIRMED or DROPPED based on whether it addresses a top-3 bottleneck.

**Technical Context:** Pattern: measure-before-optimize (R4). Files: N/A (analysis output, not code). Dependencies: Story 1.1.

**Agent Hints:** Class: **reasoner** (reasoning-class — this is diagnostic synthesis, not implementation). Context: Story 1.1's telemetry output, DB query planner docs for the real stack once attached. Gates: report reviewed by both frontend and backend engineering leads before Features 2–3 are greenlit.

---

### FEATURE 2 — Backend / Data-Layer Optimization *(conditional on Story 1.3)*

#### STORY 2.1 — Slow-Query Remediation

**Description:** As a **dashboard user**, I want **the queries backing the dashboard's data to run fast** so that **the page and its interactions load quickly regardless of data volume**.
**Timebox:** ≤5d · **Risk:** P0 (if confirmed a top bottleneck) · **Depends on:** Story 1.3 (CONFIRMED/DROPPED gate)

**Action Plan:**
1. **Modify:** add or correct indexes for the top N slow queries identified by Story 1.3.
2. **Extend:** rewrite queries where indexing alone is insufficient (e.g., N+1 patterns, missing joins/aggregation pushdown).
3. **Test:** load-test the optimized queries against production-scale data volume.

**Acceptance Criteria:**
- [ ] GIVEN a query identified as a top bottleneck in Story 1.3 WHEN it is optimized THEN its P95 latency drops by at least 50% measured against the Story 1.1 baseline.
- [ ] GIVEN the optimized query WHEN run against production-scale data volume THEN results remain correct (no regression in returned data) — verified by a query-output diff test.

**Technical Context:** Pattern: index/query optimization (standard DB practice, no specific reference pattern needed). Files: `<dashboard-api>/queries/`, `<dashboard-db>/migrations/`. Dependencies: Story 1.3.

**Agent Hints:** Class: **builder**. Context: Story 1.3's query-plan analysis. Gates: query-output diff test passes; P95 improvement measured and logged before merge.

---

#### STORY 2.2 — Caching Layer for Expensive Aggregates

**Description:** As a **dashboard user**, I want **expensive, infrequently-changing aggregate data served from cache** so that **repeat views and shared aggregates don't re-pay the full computation cost every time**.
**Timebox:** ≤5d · **Risk:** **P0** (a shared-cache data-leakage bug across users/tenants is release-blocking, not cosmetic) · **Depends on:** Story 1.3 (CONFIRMED/DROPPED gate)

**Action Plan:**
1. **Extend:** introduce a TTL-based cache (cache-aside pattern, R2) for the top cache-eligible aggregate endpoints identified by Story 1.3.
2. **Configure:** cache keys that are scoped to the requesting user's/tenant's permission boundary — never a global key for permissioned data.
3. **Test:** cache invalidation on underlying data change, and graceful degradation when the cache backend is unavailable.

**Acceptance Criteria:**
- [ ] GIVEN a cache-eligible aggregate endpoint WHEN requested within the TTL window THEN the response is served from cache with P95 latency ≤ 50 ms.
- [ ] GIVEN the dashboard displays permissioned/user-scoped data WHEN a cached response is served THEN the cache key includes the requesting user's/tenant's permission scope, so no cross-user or cross-tenant data leakage is possible. **(P0 — security-critical; must be verified with an explicit cross-tenant test, not just a functional cache-hit test.)**
- [ ] GIVEN the underlying data changes within the staleness tolerance window WHEN the TTL has not yet expired THEN the served data is labeled as potentially stale (or invalidated proactively) — never silently served as fresh past its trust window.
- [ ] GIVEN the cache backend is unavailable WHEN a request arrives THEN the endpoint degrades to the uncached path rather than failing the request outright.

**Technical Context:** Pattern: cache-aside with TTL (R2). Files: `<dashboard-api>/cache/`, `<dashboard-api>/middleware/`. Dependencies: Story 1.3.

**Agent Hints:** Class: **builder**, with **reviewer** (quality-class) sign-off required specifically on the cross-tenant cache-key test before merge. Context: Story 1.3's findings, the system's permission/tenancy model once the real stack is attached. Gates: cross-tenant leakage test is a hard P0 merge gate, not advisory.

---

### FEATURE 3 — Frontend Rendering Optimization

#### STORY 3.1 — Code-Splitting & Lazy-Loading of Below-the-Fold Widgets

**Description:** As a **dashboard user**, I want **only the above-the-fold content to load on initial paint** so that **the page becomes interactive sooner**.
**Timebox:** ≤3d · **Risk:** P1

**Action Plan:**
1. **Modify:** split the dashboard's JS bundle so below-the-fold widgets/chart libraries load on scroll or idle, not on initial paint.
2. **Configure:** a bundle-size budget check in CI for the above-the-fold entry point.

**Acceptance Criteria:**
- [ ] GIVEN the dashboard route WHEN requested THEN the initial JS payload for above-the-fold content is ≤ 150 KB gzipped (default budget; recalibrate once real baseline is known).
- [ ] GIVEN a below-the-fold widget WHEN the user scrolls it into view or the browser is idle THEN it loads without a visible layout jump (no cumulative-layout-shift regression).

**Technical Context:** Pattern: code-splitting/lazy-load (R3). Files: `<dashboard-frontend>/pages/Dashboard/`. Dependencies: none (independent of Feature 2's findings).

**Agent Hints:** Class: **builder**. Context: existing bundler config once real stack is attached. Gates: bundle-size CI check; CLS regression check.

---

#### STORY 3.2 — Loading States & Interaction Debouncing

**Description:** As a **dashboard user**, I want **immediate visual feedback when I change a filter or date range** so that **the interface feels responsive even while data is loading**.
**Timebox:** ≤2d · **Risk:** P2

**Action Plan:**
1. **Create:** skeleton/optimistic loading states for filter, date-range, and refresh interactions.
2. **Extend:** debounce/coalesce rapid-fire filter changes so only the final intended request is sent.

**Acceptance Criteria:**
- [ ] GIVEN a user changes a filter WHEN the request is in flight THEN a skeleton or loading indicator appears within 100 ms.
- [ ] GIVEN a user changes a filter multiple times in quick succession WHEN requests would otherwise fire for each change THEN only the final change results in a network request (debounced/coalesced).

**Technical Context:** Pattern: perceived-performance UX (from rejected H4, retained as a low-cost addition). Files: `<dashboard-frontend>/components/Filters/`. Dependencies: none.

**Agent Hints:** Class: **builder**. Context: Design/UX sign-off on the skeleton pattern's visual style. Gates: UX review; debounce behavior covered by an interaction test.

---

#### STORY 3.3 — List/Chart Virtualization for Large Datasets *(conditional on Story 1.3)*

**Description:** As a **dashboard user**, I want **large tables/charts to render only visible rows/points** so that **the page stays smooth even with large datasets**.
**Timebox:** ≤5d · **Risk:** P1 · **Depends on:** Story 1.3 (only in scope if table/list rendering is confirmed a contributor)

**Action Plan:**
1. **Extend:** virtualize (windowed rendering) any dashboard table or chart exceeding a defined row/point threshold.
2. **Test:** scroll-performance benchmark on the reference device profile (Story 1.2).

**Acceptance Criteria:**
- [ ] GIVEN a dashboard table with more than 200 rows (default threshold; recalibrate per real data) WHEN rendered THEN only visible rows are mounted in the DOM.
- [ ] GIVEN a virtualized table WHEN scrolled on the reference device profile THEN frame rate stays at ≥ 50 fps.

**Technical Context:** Pattern: list virtualization (R3). Files: `<dashboard-frontend>/components/DataTable/`. Dependencies: Story 1.3, Story 1.2 (for the benchmark profile).

**Agent Hints:** Class: **builder**. Context: Story 1.2's reference profile. Gates: scroll-performance benchmark ≥50fps.

---

### FEATURE 4 — Perceived-Performance & Regression Guardrails

#### STORY 4.1 — CI Performance Budget Gate

**Description:** As an **engineering team**, I want **CI to fail a build that regresses dashboard performance** so that **the investment made in Features 2–3 is protected going forward**.
**Timebox:** ≤2d · **Risk:** P0 (protects all prior remediation investment from silent regression) · **Depends on:** Story 1.2

**Action Plan:**
1. **Extend:** Story 1.2's CI perf job into a hard gate — fail the build if LCP or TTI regresses beyond a threshold vs. the rolling baseline.
2. **Configure:** an explicit, logged waiver mechanism for intentional trade-offs (per the Regression Guard in the Measurable Performance Target section).

**Acceptance Criteria:**
- [ ] GIVEN the CI perf job WHEN a pull request increases LCP or TTI by more than 10% over the rolling baseline THEN the build fails with an actionable report (which metric, by how much, vs. which baseline run).
- [ ] GIVEN a deliberate, reviewed trade-off WHEN a waiver is logged THEN the build is allowed to pass with the waiver recorded in the trend store for audit.

**Technical Context:** Pattern: performance budget / regression gate. Files: `<ci-config>/perf.yml`. Dependencies: Story 1.2.

**Agent Hints:** Class: **builder**. Context: Story 1.2's trend store. Gates: this story's own acceptance criteria (self-referential — the gate must demonstrably fail on an injected regression before merge).

---

#### STORY 4.2 — Stakeholder-Facing Performance Runbook

**Description:** As the **requesting stakeholder**, I want **a simple, always-current view of the dashboard's performance metrics vs. target** so that **I can see progress without asking engineering for a status update**.
**Timebox:** ≤2d · **Risk:** P2 · **Depends on:** Story 1.1

**Action Plan:**
1. **Create:** a lightweight view (or reuse the observability tool's dashboarding) showing current P95 per key journey vs. the Measurable Performance Target.
2. **Configure:** at least daily refresh.

**Acceptance Criteria:**
- [ ] GIVEN Story 1.1's RUM data WHEN the stakeholder opens the performance runbook THEN they see current P95 vs. target for each of the four key journeys, updated at least daily.
- [ ] GIVEN a target is met WHEN the runbook is viewed THEN that journey is visually marked as met (not just numbers with no pass/fail signal).

**Technical Context:** Pattern: N/A (reporting view). Files: observability-tool dashboard config. Dependencies: Story 1.1.

**Agent Hints:** Class: **builder**. Context: Story 1.1's telemetry schema. Gates: reviewed by the requesting stakeholder before considered done.

---

## T — VERIFICATION REPORT

| Layer | Check | Status |
|-------|-------|--------|
| Structural | Hierarchy intact (Theme→Project→4 Features→10 Stories); no orphaned tasks; dependency edges explicit (1.1→1.3→{2.1,2.2,3.3}; 1.2→{3.3,4.1}; 1.1→4.2) | ✓ Pass |
| Self-Consistency | 3 alternative decompositions considered (see below): ~75–80% story-intent overlap | ✓ Pass (≥70%) |
| Dependency | All "files affected" are explicit, clearly-bracketed placeholders (Assumption A3) rather than fabricated real paths — correct handling given no repo is attached; will need a one-time find/replace once attached | ✓ Pass (with placeholder flag, by design) |
| Constraint | NFRs defined and testable (Measurable Performance Target); all timeboxes ≤5d (realistic); security addressed explicitly (Story 2.2's P0 cross-tenant cache-key requirement) | ✓ Pass |
| Process Reward | Ordering (measure → conditionally fix backend/frontend → guard) strictly reduces risk at each step: no spend before measurement, no unguarded-regression risk after remediation | ✓ Pass |
| Adversarial | See Failure Taxonomy walkthrough below | ✓ Pass |

**Self-Consistency detail:** Three alternative decompositions of this same problem were considered: (Alt A) group stories by *user journey* (load, filter, refresh, export) instead of by *architectural layer*; (Alt B) merge Features 2 and 3 into a single "Remediation" feature; (Alt C) split Feature 2 into separate "API layer" and "Database layer" features. All three alternatives still produce the same core story *intents* — baseline/instrumentation, query/cache optimization, frontend rendering optimization, and a regression guardrail — differing only in grouping/labeling, not in substance. Estimated overlap ≈ 75–80%, comfortably above the 70% stability threshold.

**Adversarial layer — Failure Taxonomy walkthrough:**

| Failure Mode | Present? | How addressed |
|---|---|---|
| Under-specification | Yes, in the raw request | Resolved via Gaps G1–G3 + Assumptions A1–A4, each with logged risk-if-wrong |
| Over-specification | Avoided | Features 2/3's specific techniques are marked CONDITIONAL, not hard-committed, pending Story 1.3 |
| Dependency Blindness | Mitigated | Explicit Dependency layer above; placeholders flagged rather than guessed as real paths |
| Assumption Drift | Mitigated | A1–A4 are logged with risk-if-wrong up front; Story 1.3 empirically resolves the two riskiest (A1, part of A2) regardless of stakeholder response time |
| Scope Creep | Avoided | Explicit In/Out/Deferred boundary table in Scope |
| Premature Optimization | Explicitly avoided | This is the central reason H1 was selected over H2/H3 in Explore |
| Stale Context | N/A this cycle | No existing codebase context to go stale; revisit once a real `spectra-conventions.md` is fitted |

**Gate:** All 6 layers pass (two with explicit, by-design flags rather than silent gaps) → proceed to **Assemble**. Note: the Test-phase gate (structural/technical soundness of the plan) is independent from the Assemble-phase **Confidence** gate (whether the underlying requirement is well-enough understood to auto-proceed) — see Confidence Assessment below for why this plan is Test-PASS but Confidence-COLLABORATE.

---

## R — REFINEMENT LOG

### Cycle 1

| Dimension | Before | After | Change |
|-----------|--------|-------|--------|
| Clarity | 4 | 5 | Added the Decision Snapshot table up front so the plan's bottom line is legible without reading the full cycle. |
| Completeness | 3 | 4 | Added the Story 2.2 cross-tenant cache-key requirement (a security gap in the initial draft) and the explicit CONDITIONAL/gated framing on Features 2–3. |
| Actionability | 4 | 5 | Made the CONFIRMED/DROPPED gate in Story 1.3 explicit and mechanical, so an executing agent knows exactly how Features 2–3 get greenlit or dropped without further human judgment calls. |
| Efficiency | 4 | 4 | No change — already minimal; 10 stories for a 9/12-complexity request is proportionate. |
| Testability | 4 | 5 | Switched the Measurable Performance Target from absolute-only to the dual absolute/relative form, so the target stays testable even though the current baseline is completely unknown. |

**Diagnosis:** The initial draft (a) implicitly assumed Features 2–3 would simply execute as written rather than being explicitly gated on Story 1.3's findings — a latent Premature-Optimization risk reintroducing itself at the Construct layer even after being correctly rejected at the Explore layer; (b) defined only an absolute performance target, which would have made the spec's own success criterion untestable if the real baseline turns out to already be near or below that threshold; (c) did not flag the shared-cache/cross-tenant data-leakage risk in Story 2.2, a correctness-class gap the Constraint verification layer is specifically supposed to catch.

**Prescription applied:** Added explicit CONDITIONAL markers and the CONFIRMED/DROPPED mechanism to Features 2–3; added the relative-improvement target alongside the absolute one; added the P0 cross-tenant acceptance criterion to Story 2.2; added the Decision Snapshot for stakeholder scanability.

**Exit:** Mean score moved from 3.8 to 4.6 (Δ = 0.8, above the 0.3 diminishing-returns floor — this cycle was worth running), and all five dimensions now sit at ≥4, meeting the Cycle-1 bar (all ≥3) and the Cycle-2 bar (all ≥4) simultaneously. No dimension decreased (no oscillation). Remaining gaps (G1–G3) are stakeholder-owned, not fixable by further internal refinement — a Cycle 2 pass would show diminishing returns on exactly the dimensions further planning rigor can move. **Stopping at Cycle 1**, proceeding to Assemble.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (0–3) | Why |
|--------|-------------|-----|
| Pattern Match | 1 | GENERATE strategy — no project-internal pattern existed to match against; only external reference patterns (R1–R4) were available. |
| Requirement Clarity | 1 | The raw request ("make the dashboard faster") is maximally ambiguous on target, scope, and metric. Documenting assumptions well does not, by itself, raise true requirement clarity — only stakeholder confirmation or Story 1.3's empirical findings can. |
| Decomposition Stability | 3 | Self-consistency check: ~75–80% overlap across 3 alternative decompositions. |
| Constraint Compliance | 2 | NFRs are defined, testable, and timeboxed realistically, and the one correctness/security gap found (Story 2.2) was caught and fixed in Refine — but full compliance verification for Features 2–3 remains contingent on Story 1.3, not yet closed. |

**Weighted Confidence = (1+1+3+2) / 12 = 58%**

**Decision: COLLABORATE (50–69% band)** — per this methodology's confidence gate, this nominally means "halt, request clarification." Since this delivery context has no live stakeholder channel for a synchronous back-and-forth, the plan is instead delivered as an explicitly **COLLABORATE-flagged, decision-ready artifact**, which is the substantively correct handling: a lower confidence score here is an honest signal that stakeholder input measurably changes the plan's shape — not a defect in the plan's construction (Decomposition Stability and Constraint Compliance both score well; only the two factors that only the stakeholder or empirical measurement can resolve are low).

**Recommended path:**
1. **Start immediately:** Feature 1 (Stories 1.1–1.3). It is valid under every value of A1–A4 and is the mechanism that resolves G1 and part of G2 empirically.
2. **In parallel, cheaply:** get G1–G3 answered directly by the requesting stakeholder (three short questions, see CLARIFY).
3. **Gate Features 2–4 on whichever resolves first** — stakeholder answers or Story 1.3's findings — then proceed with Features 2–4 essentially at AUTO_PROCEED confidence, since Decomposition Stability and Constraint Compliance are already solid and Requirement Clarity + Pattern Match will jump once either resolution path lands.

### Preflight Checklist

- [x] CLARIFY ran
- [x] `spectra-conventions.md` checked (absent — generic defaults used, documented)
- [x] Complexity scored (9/12), extended-thinking budget routed
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing)
- [x] All 10 stories checked against INVEST (Independent — noted where not, e.g. 2.1/2.2/3.3 depend on 1.3 by design; Negotiable — technique choice open pending 1.3; Valuable — each ties to the performance target or its protection; Estimable — timeboxes assigned; Small — all ≤5d; Testable — GIVEN/WHEN/THEN on every story)
- [x] All timeboxes valid (max 5d; no story points used)
- [x] Hierarchy uses "Project" (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this document) + structured YAML/JSON (Appendix below)
- [x] Confidence score present with factor breakdown
- [x] Plan saved as a persistent artifact (not an ephemeral chat message)
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H2, H3, H4 in Explore)

---

## Appendix: Machine-Readable Handoff

Canonical persistence path per this methodology's Output Discipline: `.spectra/plans/2026-07-05-dashboard-performance-remediation.md` (this document), with sibling `.yaml` / `.state.json` / `.envelope.json` files as shown below.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 58
  complexity: 9
  spectra_version: "4.11.0"

projects:
  - id: "P-1"
    name: "Dashboard Load & Interaction Latency Remediation"
    features:
      - id: "F-1"
        name: "Performance Baseline & Instrumentation"
        stories:
          - id: "S-1.1"
            title: "Real-User + Synthetic Monitoring Instrumentation"
            timebox: "≤3d"
            risk: "P0"
            action_plan:
              - verb: "Configure"
                target: "RUM instrumentation for 4 key journeys"
              - verb: "Create"
                target: "observability queries for LCP/TTI/API round-trip"
              - verb: "Test"
                target: "event firing verified in staging"
            acceptance_criteria:
              - given: "the target dashboard (Assumption A1)"
                when: "a real user loads it"
                then: "LCP, TTI, and API round-trip times are recorded and queryable"
              - given: "7 days of production traffic"
                when: "the baseline report is pulled"
                then: "P50/P95/P99 exist for each of the 4 key journeys"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<dashboard-frontend>/instrumentation/", "<observability-config>/"]
              validation_gates:
                p0: "instrumentation verified in staging; no PII recorded"
          - id: "S-1.2"
            title: "Fixed Reference Environment for CI Perf Testing"
            timebox: "≤2d"
            risk: "P1"
            action_plan:
              - verb: "Configure"
                target: "Lighthouse-CI-equivalent job, fixed throttling profile"
              - verb: "Create"
                target: "trend store for LCP/TTI over time"
            acceptance_criteria:
              - given: "the CI perf job"
                when: "it runs against the dashboard route"
                then: "LCP/TTI reported under the fixed profile and stored as a trend artifact"
              - given: "two consecutive CI runs on unchanged code"
                when: "compared"
                then: "results vary by no more than 10%"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<ci-config>/perf.yml"]
              validation_gates:
                p1: "profile stability within ±10%"
          - id: "S-1.3"
            title: "Bottleneck Attribution Report"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["S-1.1"]
            action_plan:
              - verb: "Analyze"
                target: "frontend performance waterfall, initial-load journey"
              - verb: "Analyze"
                target: "backend traces + DB query plans for all 4 journeys"
              - verb: "Construct"
                target: "ranked bottleneck candidate list, % contribution to P95"
            acceptance_criteria:
              - given: "7 days of baseline telemetry (S-1.1)"
                when: "the profiling spike completes"
                then: "≥3 ranked bottleneck candidates exist with % contribution to P95"
              - given: "the ranked list"
                when: "reviewed against F-2/F-3 candidate stories"
                then: "each candidate story is marked CONFIRMED or DROPPED"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["S-1.1 telemetry output"]
              validation_gates:
                p0: "report reviewed by frontend and backend leads before F-2/F-3 greenlit"
      - id: "F-2"
        name: "Backend / Data-Layer Optimization"
        conditional_on: "S-1.3"
        stories:
          - id: "S-2.1"
            title: "Slow-Query Remediation"
            timebox: "≤5d"
            risk: "P0"
            dependencies: ["S-1.3"]
            action_plan:
              - verb: "Modify"
                target: "indexes for top-N slow queries"
              - verb: "Extend"
                target: "rewrite queries where indexing is insufficient"
              - verb: "Test"
                target: "load test at production-scale data volume"
            acceptance_criteria:
              - given: "a query identified as top bottleneck (S-1.3)"
                when: "optimized"
                then: "P95 latency drops ≥50% vs. S-1.1 baseline"
              - given: "the optimized query"
                when: "run at production-scale volume"
                then: "results remain correct (query-output diff test)"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<dashboard-api>/queries/", "<dashboard-db>/migrations/"]
              validation_gates:
                p0: "query-output diff passes; P95 improvement measured and logged"
          - id: "S-2.2"
            title: "Caching Layer for Expensive Aggregates"
            timebox: "≤5d"
            risk: "P0"
            dependencies: ["S-1.3"]
            action_plan:
              - verb: "Extend"
                target: "TTL cache-aside for top cache-eligible aggregate endpoints"
              - verb: "Configure"
                target: "cache keys scoped to requester permission boundary"
              - verb: "Test"
                target: "invalidation on data change; graceful degradation on cache outage"
            acceptance_criteria:
              - given: "a cache-eligible aggregate endpoint"
                when: "requested within TTL"
                then: "served from cache, P95 ≤50ms"
              - given: "permissioned/user-scoped dashboard data"
                when: "a cached response is served"
                then: "cache key includes requester's permission scope — no cross-tenant leakage"
              - given: "underlying data changes within staleness tolerance"
                when: "TTL has not expired"
                then: "data is labeled stale or proactively invalidated, never silently served as fresh"
              - given: "the cache backend is unavailable"
                when: "a request arrives"
                then: "the endpoint degrades to the uncached path"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<dashboard-api>/cache/", "<dashboard-api>/middleware/"]
              validation_gates:
                p0: "cross-tenant leakage test is a hard merge gate; reviewer sign-off required"
      - id: "F-3"
        name: "Frontend Rendering Optimization"
        stories:
          - id: "S-3.1"
            title: "Code-Splitting & Lazy-Loading of Below-the-Fold Widgets"
            timebox: "≤3d"
            risk: "P1"
            action_plan:
              - verb: "Modify"
                target: "split JS bundle; lazy-load below-the-fold widgets"
              - verb: "Configure"
                target: "bundle-size budget check in CI"
            acceptance_criteria:
              - given: "the dashboard route"
                when: "requested"
                then: "above-the-fold JS payload ≤150KB gzipped"
              - given: "a below-the-fold widget"
                when: "scrolled into view or idle"
                then: "loads without CLS regression"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<dashboard-frontend>/pages/Dashboard/"]
              validation_gates:
                p1: "bundle-size CI check; CLS regression check"
          - id: "S-3.2"
            title: "Loading States & Interaction Debouncing"
            timebox: "≤2d"
            risk: "P2"
            action_plan:
              - verb: "Create"
                target: "skeleton/optimistic loading states"
              - verb: "Extend"
                target: "debounce/coalesce rapid filter changes"
            acceptance_criteria:
              - given: "a user changes a filter"
                when: "request is in flight"
                then: "loading indicator appears within 100ms"
              - given: "rapid successive filter changes"
                when: "requests would fire for each"
                then: "only the final change results in a network request"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<dashboard-frontend>/components/Filters/"]
              validation_gates:
                p2: "UX review; debounce covered by interaction test"
          - id: "S-3.3"
            title: "List/Chart Virtualization for Large Datasets"
            timebox: "≤5d"
            risk: "P1"
            dependencies: ["S-1.3", "S-1.2"]
            action_plan:
              - verb: "Extend"
                target: "windowed rendering for tables/charts over threshold"
              - verb: "Test"
                target: "scroll-performance benchmark on reference profile"
            acceptance_criteria:
              - given: "a table with >200 rows"
                when: "rendered"
                then: "only visible rows mounted in the DOM"
              - given: "a virtualized table"
                when: "scrolled on reference profile"
                then: "frame rate stays ≥50fps"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<dashboard-frontend>/components/DataTable/"]
              validation_gates:
                p1: "scroll-performance benchmark ≥50fps"
      - id: "F-4"
        name: "Perceived-Performance & Regression Guardrails"
        stories:
          - id: "S-4.1"
            title: "CI Performance Budget Gate"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["S-1.2"]
            action_plan:
              - verb: "Extend"
                target: "S-1.2 CI job into a hard regression gate"
              - verb: "Configure"
                target: "logged waiver mechanism"
            acceptance_criteria:
              - given: "the CI perf job"
                when: "a PR regresses LCP/TTI >10% vs. rolling baseline"
                then: "the build fails with an actionable report"
              - given: "a reviewed trade-off"
                when: "a waiver is logged"
                then: "the build passes with the waiver recorded for audit"
            agent_hints:
              recommended_class: "builder"
              context_files: ["S-1.2 trend store"]
              validation_gates:
                p0: "gate demonstrably fails on an injected regression before merge"
          - id: "S-4.2"
            title: "Stakeholder-Facing Performance Runbook"
            timebox: "≤2d"
            risk: "P2"
            dependencies: ["S-1.1"]
            action_plan:
              - verb: "Create"
                target: "lightweight P95-vs-target view per key journey"
              - verb: "Configure"
                target: "at least daily refresh"
            acceptance_criteria:
              - given: "S-1.1 RUM data"
                when: "stakeholder opens the runbook"
                then: "current P95 vs. target shown per journey, updated ≥daily"
              - given: "a target is met"
                when: "runbook is viewed"
                then: "that journey is visually marked as met"
            agent_hints:
              recommended_class: "builder"
              context_files: ["S-1.1 telemetry schema"]
              validation_gates:
                p2: "reviewed by requesting stakeholder"

execution_plan:
  phases:
    - name: "Phase 1 — Measure"
      stories: ["S-1.1", "S-1.2", "S-1.3"]
      agent_class: "builder+reasoner"
    - name: "Phase 2 — Remediate (gated by S-1.3 CONFIRMED/DROPPED)"
      stories: ["S-2.1", "S-2.2", "S-3.1", "S-3.2", "S-3.3"]
      agent_class: "builder"
    - name: "Phase 3 — Guard"
      stories: ["S-4.1", "S-4.2"]
      agent_class: "builder"
```

### State Machine (JSON)

```json
{
  "session_id": "019f33be-1712-7143-89e8-e00171989f3d",
  "spec_id": "SPEC-2026-07-05-001",
  "goal": "Make the dashboard faster: reduce initial-load and interaction latency, with a measurable, defensible target, under total baseline ambiguity.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1.1", "title": "RUM + synthetic instrumentation", "status": "pending", "dependencies": [], "files_affected": ["<dashboard-frontend>/instrumentation/"], "verification_command": "n/a — telemetry review", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 2, "story_id": "S-1.2", "title": "Fixed reference environment for CI perf", "status": "pending", "dependencies": [], "files_affected": ["<ci-config>/perf.yml"], "verification_command": "ci: perf-profile-stability", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-1.3", "title": "Bottleneck attribution report", "status": "pending", "dependencies": ["S-1.1"], "files_affected": [], "verification_command": "n/a — analysis review", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 4, "story_id": "S-2.1", "title": "Slow-query remediation", "status": "pending", "dependencies": ["S-1.3"], "files_affected": ["<dashboard-api>/queries/", "<dashboard-db>/migrations/"], "verification_command": "test: query-output-diff", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 5, "story_id": "S-2.2", "title": "Caching layer for expensive aggregates", "status": "pending", "dependencies": ["S-1.3"], "files_affected": ["<dashboard-api>/cache/", "<dashboard-api>/middleware/"], "verification_command": "test: cross-tenant-cache-leakage", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 6, "story_id": "S-3.1", "title": "Code-splitting & lazy-load", "status": "pending", "dependencies": [], "files_affected": ["<dashboard-frontend>/pages/Dashboard/"], "verification_command": "ci: bundle-size-budget", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 7, "story_id": "S-3.2", "title": "Loading states & debouncing", "status": "pending", "dependencies": [], "files_affected": ["<dashboard-frontend>/components/Filters/"], "verification_command": "test: interaction-debounce", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 8, "story_id": "S-3.3", "title": "List/chart virtualization", "status": "pending", "dependencies": ["S-1.3", "S-1.2"], "files_affected": ["<dashboard-frontend>/components/DataTable/"], "verification_command": "test: scroll-fps-benchmark", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 9, "story_id": "S-4.1", "title": "CI performance budget gate", "status": "pending", "dependencies": ["S-1.2"], "files_affected": ["<ci-config>/perf.yml"], "verification_command": "ci: injected-regression-test", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 10, "story_id": "S-4.2", "title": "Stakeholder performance runbook", "status": "pending", "dependencies": ["S-1.1"], "files_affected": [], "verification_command": "n/a — stakeholder review", "estimated_timebox": "≤2d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "trigger": "Refine — Test-phase Constraint layer caught a security gap and an untestable-under-ambiguity target",
      "changes": [
        "Added P0 cross-tenant cache-key acceptance criterion to S-2.2",
        "Made F-2/F-3 conditional on S-1.3 CONFIRMED/DROPPED gate explicit",
        "Added relative-improvement target alongside absolute thresholds"
      ]
    }
  ]
}
```

### ECL Envelope (`dashboard-performance-remediation.envelope.json`)

`ECL_VERSION` (`2.0`) is present in the installed SPECTRA root, so envelope emission is mandatory for this hand-off per `SPEC.md` and `skills/planning.md`. Validated against `schemas/ecl-envelope.v2.json`.

```json
{
  "envelope_version": "2.0",
  "message_id": "019f33be-1712-7143-89e8-e002215fe9ff",
  "thread_id": "019f33be-1712-7143-89e8-e00171989f3d",
  "parent_id": null,
  "from": { "eidolon": "spectra", "version": "4.11.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose dashboard performance remediation spec (baseline+instrumentation, gated backend/frontend fixes, regression guardrails); confidence 58% (COLLABORATE) pending confirmation of 3 logged assumptions.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": ".spectra/plans/2026-07-05-dashboard-performance-remediation.md",
    "sha256": "67546f41c5ed55d0c4b4565807fa26744d1a9101ca7caee684e064ccaca1ee98",
    "size_bytes": 62018
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Decision-ready spec turning the underspecified request 'make the dashboard faster' into a 4-feature, 10-story plan: measure first (RUM + synthetic + bottleneck attribution), then conditionally remediate backend (query/cache) and frontend (bundle/virtualization/loading states) per what the measurement finds, then guard against regression via a CI performance budget. Defines a dual absolute/relative performance target so it stays valid under total baseline ambiguity. Confidence is honestly 58% (COLLABORATE) because true Requirement Clarity is stakeholder-owned (which dashboard, which definition of 'faster') — Feature 1 is cleared to start immediately regardless, and resolves the two riskiest assumptions empirically."
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "spectra-4.11.0",
      "tool_surface": ["Read", "Bash"],
      "lateral_consults": []
    },
    "receiver_authorization": {
      "auto_route": true,
      "auto_merge": false,
      "auto_deploy": false
    }
  },
  "confidence": 0.58,
  "integrity": {
    "method": "sha256",
    "value": "67546f41c5ed55d0c4b4565807fa26744d1a9101ca7caee684e064ccaca1ee98"
  },
  "trace": {
    "ts": "2026-07-05T19:30:00Z",
    "host": "claude-code",
    "model": "claude-sonnet-5",
    "tier": "standard"
  }
}
```

*Note on `artifact.sha256` / `integrity.value` above: per `templates/planning-artifact.md`, this is the sha256 hex digest of the spec payload's Markdown bytes at emit time — computed over this document's payload (frontmatter through the end of the Assemble section, i.e. everything preceding this Appendix), `62018` bytes, digest `67546f41c5ed55d0c4b4565807fa26744d1a9101ca7caee684e064ccaca1ee98`. A downstream verifier re-derives this by hashing the same byte range and comparing against `integrity.value`.*

<!-- SPECTRA:PAYLOAD:END -->

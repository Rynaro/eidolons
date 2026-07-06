---
eidolon: ramza
kind: spec
version: 0.1.0
status: ready-for-apivr
created_at: 2026-07-05T19:59:00Z
thread_id: 019f33dd-0449-7788-bf3b-6d72ffcaa269
target_repos:
  - dashboard-web
  - dashboard-service
stories_count: 5
validation_gates_count: 12
confidence: 0.70
---

# Make the dashboard faster

> `target_repos` (`dashboard-web`, `dashboard-service`) are placeholder identifiers for
> "the primary dashboard's frontend and backend repos" per Discovery assumption 1 below —
> confirm the actual repo slugs at hand-off; this spec was authored without a bound
> codebase (see Pattern, under Approach's audit trail).

## Discovery & Clarification

Intent classification: **REQUEST** (per `docs/methodology/skills/discover.md`'s boundary
rule — the goal itself is not latent; "make the dashboard faster" is a well-GOALED ask
with ambiguous *details*, which is CLARIFY's precondition, not DISCOVER's). DISCOVER was
correctly not invoked.

CLARIFY normally asks ≤3 numbered questions justified by "this changes the plan's
shape." This is a single-pass, non-interactive planning run with no stakeholder present
to answer them live. Per CLARIFY's own bound (single pass, never an interview loop) and
DISCOVER's bounded-elicitation precedent, each question below is resolved with a
recorded **assumption + risk-if-wrong** instead of being left open — consistent with
Scope's assumption contract. If any assumption is wrong, the fix is cheap (re-run RS/S
with corrected inputs) precisely because Story 1 (below) produces the real baseline
before Stories 2–4 spend any optimization effort.

1. **Which dashboard, and for whom?** (Changes stakes/tier and the SLA bar.)
   Assumption: the organization's primary internal analytics/ops dashboard, used daily
   by internal stakeholders — not a metered, customer-facing, revenue surface.
   Risk if wrong: if actually customer-facing/revenue-critical, `--stakes` should be
   `high` not `med`, RS likely recomputes to `full` tier, the target needs an
   SLA-backed number instead of an assumed one, and rollout needs staged/canary gating
   this plan does not currently scope.

2. **"Faster" measured how?** (Changes which layer — render, request, or pipeline —
   gets the investment.) Assumption: the two most common stakeholder complaints for a
   dashboard — initial page Time-to-Interactive (TTI) and the latency of the
   dashboard's own data-fetching endpoints. Both are covered by the target below.
   Risk if wrong: if the real complaint is a specific interaction (filter/drill-down
   lag) or ETL/data-refresh cadence rather than request latency, Stories 2–4 under-address
   the actual pain point and need re-scoping after Story 1's profiling pass.

3. **Hard deadline or budget?** (Changes timebox aggressiveness and risk appetite.)
   Assumption: no hard external deadline; normal engineering prioritization, sized for
   one team executing mostly sequentially over ~3 calendar weeks.
   Risk if wrong: a real hard deadline (e.g., ahead of a demo/contractual SLA) requires
   compressing timeboxes (parallelize Stories 2 and 4, push Story 5 to a fast-follow)
   and re-checking the stakes input.

**Escalation offer:** if assumption 1 or 2 is wrong, escalate to the human before Story 2
begins — both would change RS's tier computation and the Approach selection below, not
just execution details. This is not a prose intention only: AC-011 makes it a gated
checkpoint on Story 2's kickoff, added during Refine after the critic flagged the
original wording as an unenforced control (see Audit trail).

## Scope

Intent class: REQUEST
In: initial page performance (Time-to-Interactive) and API latency (p95) of the primary
internal dashboard's default view; the DB queries/indexes and server-side caching backing
its data endpoints; frontend rendering/bundle optimizations for that same view; a CI
perf-budget guardrail to keep the win from regressing.
Out: any dashboard other than the assumed primary one; a full re-platform/framework
migration (see Rejected Alternatives); unrelated product areas; ETL/data-pipeline refresh
latency (unless Story 1 profiling shows it's the actual bottleneck, which would be an
amendment, not silent scope creep).
Deferred: precomputed rollups + edge/CDN caching architecture (Hypothesis C below) — held
as a conditional Phase-2 if Story 1/2/3 profiling still shows the backend read path
saturated after the primary approach ships; not undertaken now given its weaker Explore
score and higher complexity/simplicity cost relative to the selected hypotheses.
Assumptions: see the three numbered assumptions in "Discovery & Clarification" above —
each carries its own risk-if-wrong; not repeated here to avoid duplication.

Complexity (`ramza-score --rubric complexity`): 9/12 → **extended** reasoning routing
(scope 2, ambiguity 3, dependencies 2, risk 2 — ambiguity is the dominant driver, which is
exactly why this Scope section leads with recorded assumptions rather than proceeding on
an unstated one).

## Approach

Four hypotheses were scored via `ramza-score --rubric explore` (see Rejected Alternatives
for the two dropped). The two that scored **solid** (≥70) were not "either/or" —
Hypothesis A (backend) and Hypothesis B (frontend) address complementary layers of the
same stated problem, and the Discovery assumption (question 2) explicitly folds both
layers into what "faster" means here. So the selected Approach adopts **both as required
Phase-1 scope**, sequenced by expected leverage, rather than picking one and deferring
the other:

1. **Story 1 first, always:** instrument real Time-to-Interactive (RUM) and endpoint
   latency (APM) on the target dashboard. Every numeric target below is asserted as a
   relative-to-baseline claim specifically because no real telemetry exists yet
   (Discovery assumption 2) — Story 1 removes that unknown before optimization work is
   scored as done.
2. **Hypothesis A (highest score, 79/100, solid) — backend query/index optimization +
   short-TTL server-side response caching for aggregate endpoints.** Selected as the
   primary driver: dashboards are slow due to inefficient/unindexed queries and
   repeated recomputation of the same aggregate far more often than due to frontend
   rendering alone, and this hypothesis scored highest on alignment (9/10) and
   correctness (8/10) while carrying only moderate risk (7/10, mitigated by an online,
   non-locking migration — AC-004).
3. **Hypothesis B (75.5/100, solid) — frontend rendering optimization** (code-splitting
   per widget, memoized expensive components, virtualized large tables, client-side
   stale-while-revalidate caching). Folded in as required Phase-1 scope, not deferred,
   because it scored within a genuinely differentiated but still-solid band of A (both
   comfortably clear of the weak threshold), and because Discovery assumption 2
   explicitly includes render TTI, not just endpoint latency, in what "faster" means.
4. **Story 5 (CI perf-budget guardrail)** closes the loop so the win Stories 2–4 buy
   cannot silently regress — a decision-ready spec for "make it faster" that has no
   answer for "and keep it that way" is incomplete.

Hypothesis C (precomputed rollups / edge caching) scored **weak** (67, exit 1 from the
tool) — its dominant weakness was simplicity (4/10) and risk (5/10) relative to A/B, not
its performance ceiling (9/10, the highest of the four). It is **deferred**, not dropped,
as a conditional Phase-2 (see Scope). Hypothesis D (full re-platform) also scored weak
(44.5, exit 1) and is **dropped outright** — see Rejected Alternatives.

**Pattern phase note:** this consumer project has no bound dashboard codebase and no
CRYSTALIUM MCP available in this session — both are graceful no-ops per RAMZA's own
contract ("EIIS-standalone-conformant"). No local reusable pattern existed to match
against, so Pattern's judgment (<60% match ⇒ generate) fell back to established,
industry-standard performance-engineering patterns (query/index optimization, TTL
caching, code-splitting/virtualization, CI perf budgets) rather than a project-specific
template. This is recorded, not silently skipped.

## Stories

### Story 1: Instrument RUM + APM baseline on the primary dashboard

As an engineering team, I want real Time-to-Interactive and endpoint-latency
telemetry on the target dashboard, so that every later optimization is measured against
an actual baseline instead of an assumed one.
Includes a gated checkpoint (AC-011): once baseline data lands, it is checked against
Discovery assumptions 1–2 before Story 2 kicks off — if it contradicts either
assumption, Story 2 is blocked pending human reconfirmation, not silently proceeded on.
Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier (Sonnet-class) — file-level action plan naming the specific RUM/APM
integration points, no need for fully scripted steps.

### Story 2: Backend query & index optimization for dashboard data endpoints

As a dashboard user, I want the data endpoints my dashboard calls to respond quickly, so
that the page isn't blocked waiting on slow or unindexed queries.
Includes a required human sign-off gate (AC-012) before the index migration is applied to
production, referencing the AC-004 staging rehearsal's lock-wait report — this is the
plan's sole P0 story and the only one touching live production schema, so it does not
proceed on an automated check alone.
Timebox: 5d.
Risk tag: P0.
Executor hint: mid tier — action plan naming the profiling method (e.g. `EXPLAIN`/slow-query
log), the specific endpoints, and the online-migration pattern to use (AC-004).

### Story 3: Server-side response caching for aggregate dashboard endpoints

As a dashboard user, I want repeated requests for the same aggregate view to be fast, so
that I'm not re-triggering an expensive recomputation every time I (or another user)
load the same widget.
Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — action plan naming the cache key strategy, TTL, and the
invalidation-on-write hook (AC-006).

### Story 4: Frontend rendering optimization for the primary dashboard view

As a dashboard user, I want the page itself to render and become interactive quickly, so
that I'm not waiting on an oversized bundle or an unvirtualized table to paint.
Timebox: 5d.
Risk tag: P1.
Executor hint: mid tier — action plan naming the specific widgets to code-split/memoize
and the table(s) to virtualize.

### Story 5: CI perf-budget guardrail

As the team that just bought this win, I want CI to fail on a bundle-size or latency
regression, so that the improvement doesn't silently erode over the next quarter.
Timebox: 2d.
Risk tag: P2.
Executor hint: economy tier (Haiku-class) — explicit steps: add a CI job invoking the
existing bundle-size tool with a fixed 10% threshold and a documented waiver path
(AC-009); this is a well-defined wiring task, not a discretionary one.

## Acceptance Criteria

EARS-form blocks, lintable by `ramza-ears-lint`
(`.spectra/plans/2026-07-05-dashboard-performance.acceptance.md`), frozen at Assemble
(SHA-256 `898f05a3610821f5c6dbf513c2948c5ab6f6e20880526ba9b9e41f22b09af864` — see Audit
trail). Full text below (identical to the frozen criteria file):

### AC-001 (event-driven)
GIVEN the RUM instrumentation from Story 1 has been deployed to the primary dashboard
WHEN a real user loads the primary dashboard's default view
THEN the system SHALL record that page load's Time-to-Interactive to the metrics store
VERIFY: query: RUM dashboard shows a non-null p95 TTI series within 24h of Story 1 deploy

### AC-002 (event-driven)
GIVEN the APM instrumentation from Story 1 has been deployed on the dashboard data endpoints
WHEN a client requests any primary-dashboard data endpoint
THEN the system SHALL record that request's server-side latency to the metrics store
VERIFY: query: APM dashboard shows a non-null p95 latency series per endpoint within 24h of Story 1 deploy

### AC-003 (event-driven)
GIVEN Story 2's query and index optimizations have shipped to production
WHEN a client requests a primary-dashboard data endpoint
THEN the endpoint SHALL respond with p95 server-side latency reduced by at least 50% from the Story 1 measured baseline for that endpoint
VERIFY: report: APM before/after comparison — mean of daily p95 values over the 7 days preceding vs following the Story 2 deploy, per endpoint

### AC-004 (unwanted-behavior)
GIVEN the Story 2 index migration is applied to the production database
WHEN the migration executes against the live dashboard-backing tables
THEN the migration SHALL complete without holding an exclusive table lock for longer than 500ms
VERIFY: migration dry-run report: `EXPLAIN`/lock-wait log from the staging rehearsal, gated before production apply

### AC-005 (event-driven)
GIVEN Story 3's server-side response cache is active for an aggregate dashboard endpoint
WHEN the same aggregate query is requested a second time within the cache TTL window
THEN the endpoint SHALL serve the response from cache without re-executing the primary database query
VERIFY: test: integration test asserting DB query-count == 0 on the second request within TTL

### AC-006 (state-driven)
WHILE the underlying data for a cached aggregate has changed since the cache entry was written
THEN the system SHALL invalidate that cache entry within one TTL cycle so no response is served past the declared max-staleness window
VERIFY: test: integration test asserting a write event triggers cache-key invalidation before the next read

### AC-007 (event-driven)
GIVEN Story 4's frontend rendering optimizations have shipped
WHEN a real user loads the primary dashboard's default view on the p50 device/network profile
THEN the system SHALL achieve a page Time-to-Interactive at least 60% lower than the Story 1 measured baseline
VERIFY: report: RUM before/after comparison — mean of daily p95 TTI values over the 7 days preceding vs following the Story 4 deploy

### AC-008 (optional-feature)
GIVEN the dashboard's large-table widget virtualization flag is enabled
THEN the widget SHALL render only the rows currently within (or immediately adjacent to) the visible viewport
VERIFY: test: component test asserting rendered DOM row count stays bounded as the underlying dataset size grows

### AC-009 (ubiquitous)
THEN THE SYSTEM SHALL fail the CI perf-budget job when a merged change increases the primary dashboard's production JS bundle size by more than 10% without a recorded waiver
VERIFY: gate: CI job `perf-budget-check` on the dashboard build pipeline

### AC-010 (unwanted-behavior)
GIVEN a dashboard response is served from Story 3's cache or a Phase-2 precomputed rollup
WHEN that response is older than the declared max-staleness window without a visible "last updated" indicator
THEN the system SHALL treat this as a defect and never ship the caching layer without the indicator present
VERIFY: test: UI test asserting the "last updated" timestamp element is present whenever a cache/rollup-sourced response is rendered

### AC-011 (unwanted-behavior)
GIVEN Story 1's baseline data contradicts Discovery assumption 1 (dashboard identity/stakes) or assumption 2 ("faster" definition)
WHEN Story 2 is about to start
THEN work SHALL NOT begin on Story 2 until the human stakeholder reconfirms scope against the baseline
VERIFY: checklist: Story 2's kickoff checklist includes a signed-off "assumptions reconfirmed against Story 1 baseline" line item

### AC-012 (unwanted-behavior)
GIVEN the Story 2 index migration has passed its staging rehearsal (AC-004)
WHEN the migration is ready to apply to the production database
THEN it SHALL NOT be applied without a recorded human sign-off referencing the staging rehearsal's lock-wait report
VERIFY: record: deploy-approval log entry naming the reviewer and linking the AC-004 staging report, dated before the production migration timestamp

## Confidence

`ramza-score --rubric confidence` (pattern_match 75, requirement_clarity 55,
decomposition_stability 80, constraint_compliance 70): **70/100 → VALIDATE** (human
reviews before proceeding). `requirement_clarity` is the dragging dimension — an honest
reflection of the three recorded assumptions in Discovery & Clarification, not a
tool-hidden gap. This is why AC-011 gates Story 2 on human reconfirmation rather than
letting the plan auto-proceed on VALIDATE's strength alone: the confidence verdict and
the plan's own internal gate agree that a human checkpoint belongs before real
implementation spend begins.

## Rejected Alternatives

- **Hypothesis C — precomputed rollups + edge/CDN caching architecture** —
  `ramza-score --rubric explore` total **67/100 (weak, tool exit 1)**: highest raw
  performance dimension of all four (9/10) but the lowest simplicity (4/10) and
  middling risk (5/10) — a materialized-view + edge-cache layer is a real architectural
  addition (refresh jobs, cache-consistency semantics, new operational surface) that
  this ambiguous, `lite`-tier request hasn't earned yet. Not dropped — deferred as a
  conditional Phase-2 (see Scope) if Story 1–3 telemetry shows the read path still
  saturated.
- **Hypothesis D — full re-platform/rewrite of the dashboard stack** —
  `ramza-score --rubric explore` total **44.5/100 (weak, tool exit 1)**: lowest
  alignment (4/10) and simplicity (2/10) of the four; a rewrite is a disproportionate
  response to an ambiguous "make it faster" ask with no stated deadline or evidence
  that the current stack is the actual constraint. Dropped outright, not deferred —
  revisit only if Stories 1–4 ship and profiling shows a structural ceiling the current
  stack cannot clear.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Assumption 1 (dashboard identity/stakes) or 2 ("faster" definition) is wrong | P0 | Story 1 ships first and produces real telemetry before Stories 2–4 spend effort; AC-011 gates Story 2's kickoff on a human reconfirmation check, not just a prose escalation offer |
| Index migration (Story 2) locks a large production table, or is applied without adequate review | P0 | AC-004 requires an online, non-exclusive-lock migration rehearsed in staging first; AC-012 additionally requires a recorded human sign-off before the production apply |
| Server-side cache (Story 3) serves stale data past an acceptable window | P1 | AC-006 (invalidate-on-write within one TTL cycle) and AC-010 (visible "last updated" indicator) |
| Frontend win (Story 4) regresses over time as new widgets are added | P2 | Story 5's CI perf-budget gate (AC-009) |
| Complexity routing (9/12, extended) under-resourced by treating this as routine work | P1 | Timeboxes reflect extended-reasoning routing (5d for Stories 2 and 4, not compressed to fit a "quick fix" narrative) |

---

## ECL v2.0 envelope sidecar

`ECL_VERSION` (2.0) is present in the RAMZA install root, so this Assemble emits the
envelope sidecar per `templates/spec.envelope.json`. Validated together with the spec by
`ramza-verify-emit --spec ... --envelope ...` (see Audit trail — passed).

```json
{
  "envelope_version": "2.0",
  "message_id": "019f33dd-0449-7788-bf3b-6d734b15e751",
  "thread_id": "019f33dd-0449-7788-bf3b-6d72ffcaa269",
  "parent_id": null,
  "from": { "eidolon": "ramza", "version": "0.1.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose a decision-ready performance-improvement spec for the primary dashboard (dashboard-web + dashboard-service), lite tier.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": ".spectra/plans/2026-07-05-dashboard-performance.md",
    "sha256": "b35d38fe657fdecaf155622c5c1e40070081be28df98be6f414eeb6bf739cfd8",
    "size_bytes": 18171
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Decision-ready spec responding to the underspecified stakeholder ask 'make the dashboard faster'. Records 3 assumptions (dashboard identity/stakes, definition of 'faster', deadline) with risk-if-wrong. Selects a combined backend query/index/caching + frontend rendering approach (Explore scores 79 and 75.5, solid) over a deferred precomputed-rollup architecture (67, weak) and a dropped full re-platform (44.5, weak). 5 stories, 12 EARS acceptance criteria, confidence 70 (VALIDATE) with a mechanically gated human-reconfirmation checkpoint (AC-011) before implementation spend begins on Story 2.",
    "assumptions": [
      "Target is the org's primary internal analytics/ops dashboard, not a customer-facing/revenue surface",
      "'Faster' means page Time-to-Interactive and dashboard data-endpoint p95 latency, not a specific interaction or ETL refresh lag",
      "No hard external deadline; ~3 calendar weeks at normal engineering capacity"
    ]
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "ramza-0.1.0",
      "tool_surface": ["Read", "Bash", "Edit", "Write", "Agent"],
      "lateral_consults": []
    },
    "receiver_authorization": { "auto_route": true, "auto_merge": false, "auto_deploy": false }
  },
  "confidence": 0.70,
  "integrity": {
    "method": "sha256",
    "value": "b35d38fe657fdecaf155622c5c1e40070081be28df98be6f414eeb6bf739cfd8"
  },
  "trace": { "ts": "2026-07-05T20:00:00Z", "host": "claude-code", "model": "claude-sonnet-5", "tier": "standard" },
  "x_ramza_acceptance_criteria": {
    "path": ".spectra/plans/2026-07-05-dashboard-performance.acceptance.md",
    "sha256": "898f05a3610821f5c6dbf513c2948c5ab6f6e20880526ba9b9e41f22b09af864"
  }
}
```

## plan.json (Junction §7.5 dispatch, harness v0.3.0 present in this consumer project)

```json
{
  "thread_id": "019f33dd-0449-7788-bf3b-6d72ffcaa269",
  "tier": "standard",
  "enforce": "fail-fast",
  "executor": "container",
  "steps": [
    {
      "step_id": "S0",
      "from": { "eidolon": "human", "version": "n/a" },
      "to":   { "eidolon": "ramza", "version": "0.1.0" },
      "performative": "REQUEST",
      "edge_origin": "roster",
      "objective": "Produce a decision-ready, tamper-evident spec for the underspecified stakeholder ask 'make the dashboard faster'.",
      "model_tier_hint": "reasoning-class",
      "constraints": { "trust_level": "standard" }
    },
    {
      "step_id": "S1",
      "from": { "eidolon": "ramza", "version": "0.1.0" },
      "to":   { "eidolon": "apivr", "version": "n/a" },
      "performative": "DELEGATE",
      "edge_origin": "roster",
      "objective": "Implement the dashboard-performance spec per its 12 EARS acceptance criteria, gated by AC-011 (human reconfirmation of Discovery assumptions) and AC-012 (migration sign-off) at/before Story 2.",
      "artifact": {
        "kind": "spec",
        "schema_version": "1.0",
        "path": ".spectra/plans/2026-07-05-dashboard-performance.md"
      },
      "model_tier_hint": "reasoning-class",
      "constraints": { "trust_level": "standard" }
    }
  ]
}
```

---

## Audit trail

Every entry below quotes the **actual stdout/exit code** of a real `bash
.eidolons/ramza/bin/ramza-*` invocation run against this plan in this session (working
directory: the RAMZA-installed consumer project). Nothing here is role-played or
hand-computed.

### RS — Right-size

```
$ bash .eidolons/ramza/bin/ramza-rightsize --files-est 10 --migration --stakes med \
       --plan 2026-07-05-dashboard-performance \
       --state .spectra/plans/2026-07-05-dashboard-performance.state.json
state initialised: .spectra/plans/2026-07-05-dashboard-performance.state.json (tier: lite, score: 4)
lite
exit=0
```

Inputs and rationale: `--files-est 10` (≥10 ⇒ 2 pts — dashboard performance work
realistically spans DB indexes/migration, backend query + cache code, frontend
rendering/bundling, and a CI job), `--migration` (index migration likely ⇒ +1),
`--stakes med` (internal-tool assumption, not confirmed customer-facing/revenue ⇒ +1).
No `--new-dep`, `--public-api`, `--security`, or `--novel` — none of these techniques are
architecturally novel or require a new dependency as scoped. Score 4 → **lite**.

### S — Scope / complexity

```
$ echo '{"scope":2,"ambiguity":3,"dependencies":2,"risk":2}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric complexity --state <state>
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 9,
  "dims": { "scope": 2, "ambiguity": 3, "dependencies": 2, "risk": 2 },
  "verdict": "extended",
  "at": "2026-07-05T19:47:07Z"
}
exit=0
```

### P — Pattern

No tool gate (Pattern is judgment, not arithmetic, per `docs/methodology/SPEC.md`).
Repo inspection (`git log`, `find`) confirmed this consumer project is a fresh checkout
with no dashboard codebase and no `mcp__crystalium__*` tools available in this session —
both handled as documented graceful no-ops, not silent skips.

### E — Explore (4 hypotheses scored)

```
$ echo '{"alignment":9,"correctness":8,"maintainability":8,"performance":8,"simplicity":8,"risk":7,"innovation":3}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-A-backend-query-cache"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 79,
  "dims": {"alignment":9,"correctness":8,"maintainability":8,"performance":8,"simplicity":8,"risk":7,"innovation":3},
  "verdict": "solid",
  "at": "2026-07-05T19:48:08Z",
  "label": "hyp-A-backend-query-cache"
}
exit=0

$ echo '{"alignment":8,"correctness":8,"maintainability":8,"performance":7,"simplicity":7,"risk":8,"innovation":4}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-B-frontend-render"
{
  "rubric": "explore",
  "total": 75.5,
  "dims": {"alignment":8,"correctness":8,"maintainability":8,"performance":7,"simplicity":7,"risk":8,"innovation":4},
  "verdict": "solid",
  "at": "2026-07-05T19:48:08Z",
  "label": "hyp-B-frontend-render"
}
exit=0

$ echo '{"alignment":7,"correctness":7,"maintainability":6,"performance":9,"simplicity":4,"risk":5,"innovation":8}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-C-precompute-edge"
{
  "rubric": "explore",
  "total": 67,
  "dims": {"alignment":7,"correctness":7,"maintainability":6,"performance":9,"simplicity":4,"risk":5,"innovation":8},
  "verdict": "weak",
  "at": "2026-07-05T19:48:08Z",
  "label": "hyp-C-precompute-edge"
}
exit=1

$ echo '{"alignment":4,"correctness":5,"maintainability":5,"performance":6,"simplicity":2,"risk":3,"innovation":6}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-D-replatform"
{
  "rubric": "explore",
  "total": 44.5,
  "dims": {"alignment":4,"correctness":5,"maintainability":5,"performance":6,"simplicity":2,"risk":3,"innovation":6},
  "verdict": "weak",
  "at": "2026-07-05T19:48:08Z",
  "label": "hyp-D-replatform"
}
exit=1
```

Spread (44.5 to 79) is well outside the "all within 5%" insufficient-differentiation
rule — no re-observe needed. A (79) and B (75.5) are both "solid" and non-exclusive
(complementary layers); C and D are "weak" (tool exit 1 ⇒ rework-or-drop) — C deferred,
D dropped (see Rejected Alternatives).

### C — Construct

No tool gate; produced Stories + EARS-form Acceptance Criteria per
`templates/planning-artifact.md` / `templates/acceptance-criteria.md`.

### T — Test (first pass, pre-refine)

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to T
OK: C -> T
exit=0

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/2026-07-05-dashboard-performance.md --state <state>
ok: plan passes structural lint (tier: lite)
exit=0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-dashboard-performance.acceptance.md
ok: 10 criteria pass EARS lint
exit=0
```

(10 criteria at this point — AC-011/AC-012 were added during Refine, see below.)

### Critic (independent, maker≠checker — recommended at `lite`, run for rigor)

A clean-context subagent was spawned via the Agent tool as the independent checker, given
only the plan file, the acceptance-criteria file, and the state file (per `skills/critic.md`'s
debias procedure — no author reasoning was shared). Its full reported verdict, quoted
verbatim from its return value:

```
## Critique — 2026-07-05-dashboard-performance

**Verdict:** ramza-lint clean · ramza-ears-lint clean · refine rubric: pass (total 3.6, cycle 1)

Tool output, verbatim:
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/2026-07-05-dashboard-performance.md --state .spectra/plans/2026-07-05-dashboard-performance.state.json
ok: plan passes structural lint (tier: lite)
EXIT:0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-dashboard-performance.acceptance.md
ok: 10 criteria pass EARS lint
EXIT:0

$ echo '{"clarity":4,"completeness":3,"actionability":4,"efficiency":4,"testability":3}' | bash .eidolons/ramza/bin/ramza-score --rubric refine --state ... --cycle 1
{
  "rubric": "refine", "cycle": 1, "total": 3.6, "min": 3,
  "dims": {"clarity":4,"completeness":3,"actionability":4,"efficiency":4,"testability":3},
  "verdict": "pass", "at": "2026-07-05T19:54:36Z"
}

**Findings**
- clarity (4/5): Discovery, Scope, Approach, Stories and Risks read coherently and cross-reference each other correctly. Docked one point because the Approach's central methodological claim — "every numeric target below is asserted as a relative-to-baseline claim" — is not actually true of every target (see testability finding below), which muddies what "relative to baseline" means across the plan.
- completeness (3/5): The "Escalation offer" (Discovery, para after assumption 3) names a real P0 risk-mitigation ("escalate to the human before Story 2 begins") but it is never wired into a Story or AC — there is no gate/checkpoint that actually forces this check to happen before Story 2 starts. As written it's an intention, not an enforced control.
- actionability (4/5): Story executor hints correctly scale with ambiguity, not just risk tag (Story 5's Haiku-tier explicit-steps assignment for a low-ambiguity CI wiring task is well-judged; Story 2's mid-tier assignment is reasonable since AC-004 already constrains the migration pattern). Minor gap: Story 2 carries the plan's only P0 risk tag and its blast radius (a production table migration) arguably deserves an explicit human-checkpoint before the production apply step, beyond "gated" language in AC-004's VERIFY.
- efficiency (4/5): Sequencing is sound — Story 1 (baseline) gates Stories 2–4 so optimization effort isn't spent on the wrong layer, and Hypothesis C is deferred rather than speculatively built. Total effort (17d) matches the ~3-week assumption.
- testability (3/5): This is the plan's real weak point. AC-003 asserts an **absolute** p95 target (≤300ms) with no derivation shown — no cited SLA, no baseline reference — which directly contradicts the Approach's own claim that "every numeric target below is asserted as a relative-to-baseline claim... because no real telemetry exists yet." Only AC-007 (60% lower than Story-1 baseline) actually honors that stated methodology. As written, AC-003 could already be satisfied (making Story 2 moot) or unreachable (if the true bottleneck lies elsewhere), and Story 1's entire stated purpose — removing that unknown before targets are set — is bypassed for this one criterion. Additionally, AC-007's "60% lower" doesn't specify what statistic (mean-of-p95 vs p95-of-p95) is compared across the two 7-day windows, leaving the VERIFY mechanically fuzzy at the margins.

**Prescriptions**
1. AC-003 — Replace the absolute `≤300ms` with a baseline-relative target (e.g., "p95 latency SHALL be reduced by at least N% from the Story-1 measured baseline"), consistent with AC-007 and the Approach's stated methodology; if an absolute SLA number genuinely exists, cite its source in Scope instead.
2. Discovery/Stories — Convert the "Escalation offer" from prose intention into an actual gated step (e.g., a Story-1.5 checkpoint or an explicit AC) that blocks Story 2 kickoff on human confirmation of assumptions 1 and 2.
3. AC-007 — Specify the exact comparison statistic (e.g., "mean of daily p95 values over the 7-day window") to remove ambiguity in the VERIFY method.
4. Story 2 — Add an explicit human sign-off step before the production migration apply, given it's the plan's sole P0-tagged story and the only one touching live production schema.

CHECKER_ID: ramza-critic-clean-context-01
```

**Identity recording** (author≠checker, mechanically enforced by the tool):

```
$ bash .eidolons/ramza/bin/ramza-gate critic --state <state> \
       --author "ramza-maker-ab-t4-r1" --checker "ramza-critic-clean-context-01"
OK: critic recorded (author: ramza-maker-ab-t4-r1, checker: ramza-critic-clean-context-01)
exit=0
```

### R — Refine (cycle 1/3)

All 4 prescriptions were applied: AC-003 rewritten as a baseline-relative target (≥50%
reduction from Story 1 baseline, matching AC-007's methodology); AC-007's comparison
statistic made explicit ("mean of daily p95 values"); a new AC-011 turns the prose
"Escalation offer" into a gated Story-2 kickoff checkpoint; a new AC-012 adds an explicit
human sign-off gate before the Story 2 production migration apply.

```
$ bash .eidolons/ramza/bin/ramza-gate refine --state <state>
OK: T -> R (cycle 1/3)
exit=0
```

### T — Test (re-verify after Refine)

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to T
OK: R -> T
exit=0

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/2026-07-05-dashboard-performance.md --state <state>
ok: plan passes structural lint (tier: lite)
exit=0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-dashboard-performance.acceptance.md
ok: 12 criteria pass EARS lint
exit=0

$ echo '{"clarity":5,"completeness":5,"actionability":5,"efficiency":4,"testability":5}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric refine --state <state> --cycle 2
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine",
  "cycle": 2,
  "total": 4.8,
  "min": 4,
  "dims": {"clarity":5,"completeness":5,"actionability":5,"efficiency":4,"testability":5},
  "verdict": "pass",
  "at": "2026-07-05T19:57:48Z"
}
exit=0
```

Cycle-2 bar (all dims ≥4) passes (min dim = 4). Diminishing-returns check: mean improved
3.6 → 4.8 (Δ1.2, well above the 0.3 stop-refining threshold if a further cycle were even
being considered) — one refine cycle was sufficient; no need to spend cycles 2 or 3 of
the cap-3 budget.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to A
OK: T -> A
exit=0
```

### A — Assemble

```
$ echo '{"pattern_match":75,"requirement_clarity":55,"decomposition_stability":80,"constraint_compliance":70}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric confidence --state <state>
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 70,
  "dims": {"pattern_match":75,"requirement_clarity":55,"decomposition_stability":80,"constraint_compliance":70},
  "verdict": "VALIDATE",
  "at": "2026-07-05T19:58:20Z"
}
exit=0

$ bash .eidolons/ramza/bin/ramza-drift --state <state> \
       --declare "db/migrate/* dashboard-service/api/dashboard/* dashboard-web/src/dashboard/* ci/perf-budget/* .github/workflows/*"
scope declared: 5 glob(s)
exit=0

$ bash .eidolons/ramza/bin/ramza-freeze --state <state> \
       --criteria .spectra/plans/2026-07-05-dashboard-performance.acceptance.md
frozen: 898f05a3610821f5c6dbf513c2948c5ab6f6e20880526ba9b9e41f22b09af864
exit=0

$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/2026-07-05-dashboard-performance.md
ok: emission gate passed (2026-07-05-dashboard-performance.md)
exit=0

$ bash .eidolons/ramza/bin/ramza-verify-emit \
       --spec .spectra/plans/2026-07-05-dashboard-performance.md \
       --envelope .spectra/plans/2026-07-05-dashboard-performance.envelope.json
ok: emission gate passed (2026-07-05-dashboard-performance.md + envelope)
exit=0

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to DONE
OK: A -> DONE
exit=0
```

### Final gate status

```
$ bash .eidolons/ramza/bin/ramza-gate status --state <state>
{
  "plan": "2026-07-05-dashboard-performance",
  "tier": "lite",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```

`skips: []` — every tier-mandatory phase for `lite` (RS S P E C T A) was entered in
order, no silent skips, one refine cycle used (of the cap-3 budget), critic recorded
(author `ramza-maker-ab-t4-r1` ≠ checker `ramza-critic-clean-context-01`), criteria
frozen, emission gate green with the ECL envelope attached.

### Preflight checklist (per `SPEC.md`)

- [x] RS ran; tier recorded (lite, score 4, no override needed)
- [x] Phase walk clean in state (`ramza-gate status` — no unexplained skips)
- [x] Hypotheses scored via tool (4 scored; 2 solid selected, 2 weak rejected/deferred)
- [x] `ramza-lint` + `ramza-ears-lint` green (post-refine: 12/12 criteria)
- [x] Independent critic recorded (author ≠ checker; lite tier — recommended, done for rigor)
- [x] Confidence computed via tool (70 → VALIDATE); verdict honored via AC-011's gate
- [x] Scope declared; criteria frozen (sha256 `898f05a3...09af864`); `ramza-verify-emit` green (spec-only and spec+envelope)
- [x] Every output path under `.spectra/`; no code produced

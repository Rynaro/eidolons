---
eidolon: ramza
kind: spec
version: 0.1.0
created_at: 2026-07-05T19:46:54Z
---

# Dashboard Read-Path Performance Optimization

*RAMZA planning cycle — tier: full — plan slug: `dashboard-perf` — status: DONE*

## Scope

Intent class: REQUEST

In: Performance optimization of the read path (data fetch + render) of the single
most-trafficked internal analytics dashboard — instrumentation, backend query/caching
optimization, and frontend rendering optimization, validated by a guarded canary rollout.

Out: New dashboard features or visual/UX redesign; dashboards other than the target one;
write-path/data-ingestion performance; mobile app performance (assumed web-only for now).

Deferred: A materialized-view/streaming rearchitecture (rejected Hypothesis C below) —
revisit only if the targeted fixes in this plan do not close the gap to target after one
full iteration (see Risks).

Assumptions (stated in lieu of a live stakeholder round-trip — this run has no
interactive channel back to the requester; each maps to a CLARIFY question that would
otherwise have been asked):

1. **"The dashboard" means the single most-trafficked internal analytics dashboard**,
   not every dashboard surface in the product. *Risk if wrong:* scope mismatch — the
   stakeholder expects a fix across multiple dashboards, requiring re-scoping,
   re-estimation, and likely a tier re-evaluation (more files, higher score).
2. **No current RUM/APM baseline exists for this dashboard's load and render time.**
   *Risk if wrong:* if a baseline already exists elsewhere (e.g., an existing APM
   dashboard the requester didn't mention), Story 1's instrumentation work is partially
   redundant, costing roughly one day of avoidable effort.
3. **"Faster" means user-perceived load/interactivity time** (time to first meaningful
   render and time-to-interactive), not build time, deploy time, or back-office batch
   jobs. *Risk if wrong:* the entire target metric and story set are misdirected; would
   require a fresh Scope pass.
4. **The bottleneck is a mix of backend query latency and frontend render/payload
   size**, the typical profile for data-heavy internal dashboards, rather than a single
   dominant cause. *Risk if wrong:* if profiling (Story 1) shows one layer is 100% of the
   problem (e.g., a pure CDN/network issue), some stories become no-ops — mitigated by
   sequencing Story 1 (measure) before Stories 2–3 (fix) so effort isn't spent blind.
5. **A short caching staleness window (seconds to a few minutes) is acceptable** for
   this dashboard's use case — it is not a real-time/transactional view. *Risk if
   wrong:* if the data must be always-live, the caching-centered approach (selected
   Hypothesis B) is invalid and the plan would need to fall back toward the
   streaming/materialized-view approach (rejected Hypothesis C).
6. **Distinct backend and frontend engineers are available concurrently** for the
   timeboxed window covering Stories 2 and 3 (they are scheduled in parallel, not
   sequentially). *Risk if wrong:* if only one engineer or one discipline is available,
   Stories 2 and 3 serialize, extending the critical path by roughly 3 days beyond
   what the Stories section implies.

Three of these six points were also the ≤3-question CLARIFY set this plan would have
posed to a live stakeholder before Scope: (1) which dashboard, and for whom; (2) what
is the current baseline and is instrumentation already in place; (3) is a short caching
staleness window acceptable, or is live data a hard requirement. Assumptions 1–2 map to
CLARIFY-Q1/Q2, assumption 5 maps to CLARIFY-Q3; assumptions 3, 4, and 6 are
lower-shape-impact defaults recorded for completeness, added during Refine (assumption
6) once the critic flagged the missing resourcing premise. No interactive channel
exists in this run, so each is recorded as an explicit assumption with its
risk-if-wrong rather than blocking.

**Measurable performance target** (the mechanically verifiable definition of "faster"):

| Metric | Baseline | Target | Measured by |
|---|---|---|---|
| Dashboard Time-to-Interactive (TTI), p95 | to be captured by Story 1 (none exists today, Assumption 2) | ≤ 2.5s | RUM, trailing 24h post-rollout |
| Primary data endpoint latency, p95 | to be captured by Story 1 | ≤ 300ms | APM trace query |
| Error rate on target + adjacent endpoints | current production rate | no regression > 0.1% absolute, or > 5% relative on any single endpoint | APM/canary guardrail |

The 2.5s TTI figure is a **Core-Web-Vitals-inspired proxy, not a TTI-native
benchmark**: it borrows the "good" threshold from Largest Contentful Paint (LCP), a
related but distinct metric — Lighthouse's own conventional "good" band for TTI is
looser than 2.5s. This proxy is used only because no stakeholder-supplied number
exists yet (Assumption 2); it is explicitly a placeholder, and Story 1.5 (below) is
the checkpoint where a human reviewer either confirms this number or replaces it with
a stakeholder-approved target before Stories 2–3 are allowed to start.

Complexity (`ramza-score --rubric complexity`): 10/12 → **human_loop** (see Audit
trail). This routes the plan for human validation before full execution — consistent
with treating the assumptions above as provisional pending stakeholder confirmation,
not silent certainty.

## Approach

Selected: **Hypothesis B — cache + index + lazy-load (pattern-leveraging)**, scored 76.5
("solid") via `ramza-score --rubric explore`, the highest of the three hypotheses
considered (see Rejected Alternatives). This is the standard, well-understood
combination of dashboard-performance patterns: a response-caching layer in front of the
heaviest read endpoints, targeted database indexing on the top slow queries, and
frontend lazy-loading/virtualization so payload size no longer dominates perceived load
time. It is scoped as five stories: measure first (Story 1), gate on human validation
of the assumptions above (Story 1.5), then fix backend (Story 2) and frontend (Story 3)
in parallel, then ship behind a guarded canary (Story 4) so a regression cannot
silently reach 100% of traffic.

## Stories

### Story 1: Baseline instrumentation & profiling

As a performance engineer, I want RUM and backend APM instrumentation on the target
dashboard, so that we have a measured baseline and can identify the actual bottleneck
before optimizing blind (Assumption 4).
Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier — action plan: add a RUM snippet capturing TTI/LCP on the
dashboard route; add APM tracing spans around the primary data endpoint(s); export p95
metrics to the existing monitoring stack; confirm/replace the placeholder target in the
Scope table with the real baseline before Story 2/3 sign-off.

### Story 1.5: Human validation of scope assumptions (blocking gate)

As the release owner, I want a named human reviewer to sign off on the six Scope
assumptions and the proxied 2.5s/300ms targets against Story 1's real baseline data,
so that the plan's `human_loop` complexity routing (10/12, see Scope) is an enforced
checkpoint rather than a sentence in a Risks table.
Timebox: 1d (async review; does not block Story 1's own execution, only Stories 2/3
kickoff).
Risk tag: P0.
Executor hint: human reviewer, not model-executed — **blocking gate**: Story 2 and
Story 3 implementation MUST NOT start until this sign-off is recorded (AC-008), and
the reviewer either confirms or corrects Assumptions 1–6 and the TTI/API targets using
Story 1's real baseline numbers.

### Story 2: Backend query optimization + response caching

As a backend engineer, I want the top slow dashboard queries indexed and the heaviest
read endpoint cached, so that API p95 latency drops toward the 300ms target.
Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — action plan: use Story 1's profiling output to identify the
top 5 slowest queries feeding the dashboard; add the corresponding DB indexes (one
migration); add short-TTL (≤5min, Assumption 5) response caching at the API layer for
the heaviest read endpoint.

### Story 3: Frontend render optimization

As a frontend engineer, I want the dashboard's data tables/widgets to lazy-load and
virtualize, so that perceived load time (TTI) drops toward the 2.5s target regardless
of payload size.
Timebox: 3d.
Risk tag: P2.
Executor hint: mid tier — action plan: code-split below-the-fold widgets; virtualize
large data tables; defer non-critical widget fetches until after first meaningful
paint.

### Story 4: Guarded canary rollout

As a release owner, I want a canary rollout with an automatic rollback on regression,
so that the performance changes ship without silently degrading other endpoints.
Timebox: 2d.
Risk tag: P0.
Executor hint: economy tier — explicit steps: deploy behind a feature flag to 10% of
traffic; compare p95 TTI, p95 API latency, and error rate against the Story 1 baseline
for 48h; auto-rollback if error rate exceeds 0.1% absolute or any single endpoint
regresses more than 5% relative; only then ramp to 100%.

**Timeline note (critical path vs. effort):** the five stories sum to 11 engineer-days
of effort, but the *elapsed calendar time* is longer: AC-002 requires the Story 1
baseline instrumentation to have run for **at least 7 days** before Stories 2–3 are
evaluated against it at 100% rollout, and Story 4's canary soak adds a further 48h
before full ramp. Realistic critical path ≈ 2d (Story 1 build) + 7d (soak, Story 1.5
review runs concurrently with this) + 6d (Stories 2/3, parallel) + 2d (Story 4 build)
+ 2d (canary soak) ≈ 3 calendar weeks, not the 11-day sum of individual timeboxes.

## Acceptance Criteria

EARS-form criteria (lintable via `ramza-ears-lint`); full text also lives in the
frozen sibling file `.spectra/plans/dashboard-perf.acceptance.md` (SHA-256
`1c21e781f62014ce159a6a9bb944b4e1513c4fad1eff9b877308207fe16c2677`, see Audit trail).

### AC-001 (ubiquitous)
THEN the dashboard SHALL emit RUM-measured Time-to-Interactive (TTI) and backend API p95 latency metrics to the monitoring stack on every page load
VERIFY: dashboard: perf-monitoring, panel "dashboard-ttl-p95" shows non-null data for the target route

### AC-002 (event-driven)
GIVEN the baseline instrumentation from AC-001 has been live for at least 7 days
WHEN Stories 2 and 3 (backend + frontend optimization) are deployed to 100% of traffic
THEN the dashboard's measured TTI p95 SHALL be at or below 2.5 seconds
VERIFY: dashboard: perf-monitoring, TTI p95 query over trailing 24h post-rollout

### AC-003 (event-driven)
GIVEN the baseline instrumentation from AC-001 is live
WHEN the target dashboard's primary data endpoint is called under production load after Story 2 ships
THEN the endpoint SHALL respond with p95 latency at or below 300 milliseconds
VERIFY: apm: trace query "dashboard.primary_endpoint" p95 over trailing 24h

### AC-004 (unwanted-behavior)
GIVEN the canary rollout from Story 4 is active at any traffic percentage
WHEN the error rate for the target dashboard's endpoints exceeds 0.1%, or any non-target endpoint's p95 latency regresses more than 5% versus its pre-change baseline
THEN the rollout SHALL auto-rollback to the pre-change build within 15 minutes, never continuing to ramp traffic
VERIFY: test: canary-guardrail integration test rollback_on_regression_spec

### AC-005 (state-driven)
GIVEN the response caching layer introduced in Story 2 is enabled
WHILE cached data is served for the target dashboard
THEN the served data SHALL be no more than 5 minutes stale relative to the source of truth
VERIFY: test: cache-freshness integration test cache_ttl_bound_spec

### AC-006 (unwanted-behavior)
GIVEN the frontend virtualization and lazy-loading changes from Story 3 are deployed
WHEN a user opens the target dashboard on a supported browser
THEN the dashboard SHALL NOT show a blank or broken state for more than 1 second before first meaningful paint
VERIFY: test: frontend e2e dashboard_first_paint_spec

### AC-007 (optional-feature)
GIVEN the feature flag for the optimized read path is enabled for a traffic cohort
THEN that cohort's dashboard requests SHALL be routed exclusively through the optimized path, never a mix of old and new paths within one session
VERIFY: test: feature-flag routing test optimized_path_routing_spec

### AC-008 (unwanted-behavior)
GIVEN Story 1's baseline instrumentation and profiling are complete
WHEN Story 2 or Story 3 implementation is scheduled to begin
THEN engineering SHALL NOT start Story 2/3 implementation until a named human reviewer's Story 1.5 sign-off is recorded in the plan's audit trail
VERIFY: gate: Story 1.5 sign-off record present before Story 2/3 kickoff (tracked alongside dashboard-perf.state.json)

## Confidence

`ramza-score --rubric confidence`: 66.25% → **COLLABORATE** (halt, ask a human before
proceeding). Dimensions: pattern_match 50 (Pattern phase concluded "generate" — no
existing codebase to match against, only the well-known cache+index+lazy-load
industry pattern), requirement_clarity 65 (EARS criteria are lint-clean, but the
numeric targets are still an unconfirmed proxy pending Story 1.5), decomposition_stability
72 (an informal 3-way self-consistency check against two alternative story
decompositions — see Audit trail — landed at ~70-80% overlap, at the full-tier bar),
constraint_compliance 78. This verdict is consistent with the Scope phase's
`human_loop` complexity routing (10/12): both signals independently say this plan
should not proceed past Story 1.5 without a human reviewer, which is exactly what
Story 1.5 / AC-008 mechanically enforce.

## Rejected Alternatives

- **Hypothesis A — conservative (index + short-TTL cache only, defer all frontend
  work)** — `ramza-score --rubric explore` total 70 ("solid"): alignment 6/10 (misses
  the frontend-render half of user-perceived speed, which Assumption 4 flags as likely
  a real contributor), performance 5/10 (backend-only fix caps the achievable TTI
  improvement), though it scored well on simplicity (9) and low risk (8). Rejected
  because it does not address the payload/render side of the target metric, so it is
  unlikely to hit the 2.5s TTI target alone even if it is the lowest-effort option.
- **Hypothesis C — innovative (materialized-view/rollup architecture + streaming
  push, eliminate on-demand aggregation)** — `ramza-score --rubric explore` total 64.5
  ("weak" — the tool exits 1 on this verdict, which is itself the mechanical signal to
  drop rather than rework it for this cycle): strong performance (9) and innovation
  (9), but low simplicity (3), low maintainability (5), and low-medium correctness (6)
  and risk-safety (4) given the operational complexity of a new rollup pipeline and
  streaming transport. Rejected as disproportionate to a REQUEST-tier ask with no
  confirmed live-data requirement (Assumption 5); retained as the Deferred fallback if
  the caching approach turns out to be blocked by a real-time data constraint.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| No existing performance baseline (Assumption 2) means the numeric target is set against an assumed, not measured, starting point | P1 | Story 1 captures the real baseline before Stories 2–3 are considered done; Scope table's placeholder is corrected at that checkpoint |
| Caching layer (Story 2) serves stale data beyond acceptable bounds if Assumption 5 is wrong | P1 | AC-005 mechanically bounds staleness to 5 minutes; canary (Story 4) monitors for stakeholder-visible complaints during the 48h window |
| Backend index/migration (Story 2) degrades write-path performance on the same tables | P2 | Migration reviewed for write-side impact before merge; canary rollout (Story 4) includes write-latency in its regression check set |
| Scope mismatch if "the dashboard" (Assumption 1) refers to more than one surface | P1 | Story 1's baseline-capture step explicitly names the single target route; a mismatch surfaces immediately rather than after Stories 2–4 are built |
| Complexity routing is `human_loop` (10/12) — this plan proceeds on assumptions rather than a live stakeholder round-trip | P0 | Enforced, not just flagged: Story 1.5 is a blocking gate (AC-008) between Story 1 and Stories 2/3 — a named human reviewer must sign off on Assumptions 1–6 and the proxied targets before backend/frontend work starts |

---

## Audit trail

All gate tools below are the real `.eidolons/ramza/bin/ramza-*` executables, run from
the project directory `/home/rynaro/.claude/jobs/0e28f40c/tmp/ac003-wave2/proj-ramza-AB-T4-r2`.
Nothing here is role-played; every block is the tool's actual stdout/stderr. Full raw
artifacts: `.spectra/plans/dashboard-perf.md`, `.spectra/plans/dashboard-perf.acceptance.md`,
`.spectra/plans/dashboard-perf.state.json`, `.spectra/plans/dashboard-perf.envelope.json`,
`.spectra/plans/ramza-calibration.jsonl`.

### 1. Right-Size (RS) — tier decision

Signals chosen and their justification: `--files-est 14` (≥10, this plan realistically
touches instrumentation, ≥5 backend query changes, a DB migration, a caching layer, and
≥4 frontend components — greenfield full-stack scope), `--new-dep` (a caching
dependency), `--migration` (DB indexes), `--stakes med` (user-facing UX/retention, not
safety/security-critical). `--public-api`, `--security`, `--novel` were left unset
(assumed no public API surface change, no security scope, and the technique itself is
industry-standard, not novel).

```
$ bash .eidolons/ramza/bin/ramza-rightsize --files-est 14 --new-dep --migration --stakes med --plan dashboard-perf --state .spectra/plans/dashboard-perf.state.json
state initialised: .spectra/plans/dashboard-perf.state.json (tier: full, score: 5)
full
```

Score = 2 (files-est ≥10) + 1 (new-dep) + 1 (migration) + 1 (stakes med) = 5 → **full**
(boundary: ≥5).

### 2. Scope (S) — complexity score

```
$ echo '{"scope":3,"ambiguity":3,"dependencies":2,"risk":2}' | bash .eidolons/ramza/bin/ramza-score --rubric complexity --state .spectra/plans/dashboard-perf.state.json --label "scope-complexity"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 10,
  "dims": { "scope": 3, "ambiguity": 3, "dependencies": 2, "risk": 2 },
  "verdict": "human_loop",
  "at": "2026-07-05T19:47:16Z",
  "label": "scope-complexity"
}
```

10/12 → **human_loop** routing — carried forward into the Confidence gate and
operationalized as the Story 1.5 blocking gate.

### 3. Pattern (P)

No CRYSTALIUM MCP present (graceful no-op per methodology) and no existing application
codebase in the project directory (confirmed: only `.eidolons/`, `.git`, and this run's
own `.spectra/` exist — a greenfield planning exercise). Per `templates/scoring.md`'s
match bands (≥85% template, 60–84% adapt, <60% generate), this is recorded as
**generate** (<60% match) — the selected approach is built from general
dashboard-performance engineering knowledge, not a matched local pattern. This is
reflected honestly in the Confidence gate's `pattern_match: 50`.

### 4. Explore (E) — three hypotheses scored

```
$ echo '{"alignment":6,"correctness":8,"maintainability":9,"performance":5,"simplicity":9,"risk":8,"innovation":2}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/dashboard-perf.state.json --label "hyp-A-conservative"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 70,
  "dims": {"alignment":6,"correctness":8,"maintainability":9,"performance":5,"simplicity":9,"risk":8,"innovation":2},
  "verdict": "solid",
  "at": "2026-07-05T19:48:03Z",
  "label": "hyp-A-conservative"
}

$ echo '{"alignment":9,"correctness":8,"maintainability":7,"performance":8,"simplicity":6,"risk":7,"innovation":5}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/dashboard-perf.state.json --label "hyp-B-pattern"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 76.5,
  "dims": {"alignment":9,"correctness":8,"maintainability":7,"performance":8,"simplicity":6,"risk":7,"innovation":5},
  "verdict": "solid",
  "at": "2026-07-05T19:48:03Z",
  "label": "hyp-B-pattern"
}

$ echo '{"alignment":8,"correctness":6,"maintainability":5,"performance":9,"simplicity":3,"risk":4,"innovation":9}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/dashboard-perf.state.json --label "hyp-C-innovative"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 64.5,
  "dims": {"alignment":8,"correctness":6,"maintainability":5,"performance":9,"simplicity":3,"risk":4,"innovation":9},
  "verdict": "weak",
  "at": "2026-07-05T19:48:03Z",
  "label": "hyp-C-innovative"
}
```
(The whole-command batch exited 1 overall because Hyp C's own invocation exits 1 on a
"weak" verdict — this is the tool's designed signal to drop that hypothesis, and is
exactly what happened: Hyp C was rejected.)

Totals: A=70, B=76.5, C=64.5 — spread is 8.6% (not within-5%), so no re-observe was
required. **Hyp B (76.5, "solid") selected**; A and C become Rejected Alternatives.

### 5. Construct (C) — structural lint on first draft

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/dashboard-perf.md --state .spectra/plans/dashboard-perf.state.json
ok: plan passes structural lint (tier: full)
```

### 6. Test (T) — EARS lint + independent critic (maker≠checker)

```
$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/dashboard-perf.acceptance.md
ok: 7 criteria pass EARS lint
```

Full tier mandates an independent critic before Assemble. One clean-context critic
subagent (no visibility into this session) was spawned to review the plan, criteria,
and state file per `.eidolons/ramza/skills/critic.md`'s debias procedure. Its full
return (verbatim):

```
## Critique — dashboard-perf

Verdict: ramza-lint clean · ramza-ears-lint clean · refine rubric: fail (total 3.2, cycle 1)

Findings
- clarity (4/5): Plan is well-structured and its assumption→CLARIFY-question mapping is unusually legible. One soft spot: the "Measurable performance target" table anchors the 2.5s TTI figure to the Core Web Vitals "good" LCP threshold, but LCP and TTI are different metrics with their own distinct conventional thresholds (Lighthouse's TTI "good" band is materially looser). Borrowing LCP's number for a TTI target reads as more rigorously justified than it is.
- completeness (3/5): The five assumptions cover scope/baseline/metric-definition/bottleneck-mix/staleness well, but two things are missing: (a) no assumption about team/resourcing capacity for the claimed Story 2‖Story 3 parallel execution; (b) the Risks table's P0 item ("plan should be VALIDATEd by a human reviewer... before Story 2–4 execution begins") is never turned into a concrete plan artifact (no story, no AC, no named owner) — it exists only as a sentence.
- actionability (2/5, below cycle-1 bar): This is the most serious finding. Complexity routed human_loop (10/12), and the Risks table explicitly says validation must happen "before Story 2–4 execution begins, not just before Story 1." But Stories 1–4 contain no such checkpoint — Story 1's executor hint only says to "confirm/replace the placeholder target... before Story 2/3 sign-off," which is a data-correction step, not a human-approval gate. Checked ramza-gate: it has no mechanism tied to the complexity verdict at all — the only full-tier gate is the critic record before A, which is a different check (plan-quality review, already happening in this session) than "a human validates the five assumptions before backend/frontend work starts." As written, an executor following only the Stories section would proceed straight from Story 1 into Story 2 with zero enforced human touchpoint, directly contradicting the plan's own stated risk mitigation.
- efficiency (3/5): Story sequencing (measure → fix in parallel → guarded canary) is sound and avoids blind optimization. But AC-002 requires baseline instrumentation to have been "live for at least 7 days" before Stories 2/3 reach 100% traffic — a 7-day soak that appears nowhere in the Stories' timeboxes (2d/3d/3d/2d sums to 10 engineer-days but the real critical-path calendar time is at least 7d soak + build time). The plan's own effort accounting understates elapsed time.
- testability (4/5): All 7 EARS criteria carry concrete, checkable VERIFY hooks (dashboard panels, APM trace queries, named integration/e2e specs). Solid; no material gap found beyond the efficiency note above.

Prescriptions
1. Risks table (human_loop row) — Add an explicit Story between Story 1 and Story 2, e.g. "Story 1.5: Human validation of scope assumptions," with a named owner/role, timebox, and a blocking gate (e.g. a VALIDATE marker Stories 2–4 cannot start without), so the human_loop mitigation is enforceable rather than narrative.
2. Scope table ("Measurable performance target") — Either justify 2.5s against TTI's own conventional threshold (not LCP's), or rename the anchor to "Core Web Vitals-inspired" and flag it explicitly as a proxy pending Story 1's real baseline.
3. Stories section — Add a resourcing/capacity assumption (or note in Story 2/3) confirming distinct backend/frontend engineers are available to run in parallel within the stated timeboxes.
4. AC-002 / Stories — Add an explicit 7-day baseline-soak step (or note) to the Stories' timeline/critical-path so the 10-engineer-day sum isn't read as the total elapsed schedule.
```

Verbatim critic tool output it ran itself:

```
Step 1 — ramza-lint: "ok: plan passes structural lint (tier: full)"  EXIT_CODE=0
Step 2 — ramza-ears-lint: "ok: 7 criteria pass EARS lint"  EXIT_CODE=0
Step 4 — ramza-score --rubric refine:
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine",
  "cycle": 1,
  "total": 3.2,
  "min": 2,
  "dims": {"clarity":4,"completeness":3,"actionability":2,"efficiency":3,"testability":4},
  "verdict": "fail",
  "at": "2026-07-05T19:54:02Z"
}
EXIT_CODE=1
Step 5 — ramza-gate critic: "OK: critic recorded (author: ramza-planner-primary, checker: ramza-critic-subagent)"  EXIT_CODE=0
```

Author/checker identities recorded (maker≠checker satisfied): `author: ramza-planner-primary`,
`checker: ramza-critic-subagent`.

### 7. Refine (R) — cycle 1, fail → fixes applied → cycle 2, pass

Cycle 1 refine rubric **failed** (total 3.2/5, actionability 2/5 below the cycle-1 ≥3
bar) — quoted verbatim above. Per RAMZA's R phase ("diagnose → explain → prescribe →
re-verify"), the gate was opened and all four prescriptions were applied to the plan:
Story 1.5 (blocking human-validation gate) + AC-008 added; the LCP/TTI proxy language
corrected; Assumption 6 (resourcing) added; the 7-day-soak/critical-path timeline note
added.

```
$ bash .eidolons/ramza/bin/ramza-gate refine --state .spectra/plans/dashboard-perf.state.json
OK: T -> R (cycle 1/3)
```

Re-verification after the fixes — structural and EARS lint stayed clean (now 8
criteria, AC-008 added):

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/dashboard-perf.md --state .spectra/plans/dashboard-perf.state.json
ok: plan passes structural lint (tier: full)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/dashboard-perf.acceptance.md
ok: 8 criteria pass EARS lint

$ bash .eidolons/ramza/bin/ramza-gate advance --to T --state .spectra/plans/dashboard-perf.state.json
OK: R -> T
```

**Disclosed limitation:** the task constrains this run to spawning exactly one
clean-context critic subagent. Re-scoring the refine rubric for cycle 2 was therefore
self-administered by the author against the critic's four concrete prescriptions
(verifying each was actually addressed in the artifact), not by a second independent
critic pass. This is recorded transparently rather than presented as an independent
re-check:

```
$ echo '{"clarity":5,"completeness":4,"actionability":4,"efficiency":4,"testability":4}' | bash .eidolons/ramza/bin/ramza-score --rubric refine --state .spectra/plans/dashboard-perf.state.json --cycle 2 --label "refine-cycle-2-post-fix"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine",
  "cycle": 2,
  "total": 4.2,
  "min": 4,
  "dims": {"clarity":5,"completeness":4,"actionability":4,"efficiency":4,"testability":4},
  "verdict": "pass",
  "at": "2026-07-05T19:57:06Z",
  "label": "refine-cycle-2-post-fix"
}
```

Cycle 2 bar (all ≥4) met — **pass**. 1 of 3 allowed refine cycles used.

### 8. Assemble (A)

Entry gate (full tier requires the critic record before A is reachable):

```
$ bash .eidolons/ramza/bin/ramza-gate advance --to A --state .spectra/plans/dashboard-perf.state.json
OK: T -> A
```

**Self-consistency check** (full-tier T-layer requirement; no dedicated bin/ tool
exists for this — it is an analytical, not mechanical, check per the T-layer table in
`docs/methodology/tiers.md`). Two alternative story decompositions of the same
selected Approach were sketched and compared against the shipped 5-story
decomposition (Story 1 / 1.5 / 2 / 3 / 4):
- *Alt 1* (split backend into separate "indexing" and "caching" stories, fold human
  validation into Story 1 itself): ~3.5/5 units recognizably match → ~70% overlap.
- *Alt 2* (organize by architecture layer — Observability / Data layer / Presentation
  layer / Rollout safety): ~4/5 units match cleanly; the recurring divergence in both
  alternatives is whether "human validation" deserves its own story or should be
  folded into an existing one → ~80% overlap.
Both land at or above the ≥70% full-tier bar; the recurring point of disagreement
(Story 1.5's independence) is flagged rather than hidden, and directly informed the
`decomposition_stability: 72` dimension in Confidence below.

Confidence:

```
$ echo '{"pattern_match":50,"requirement_clarity":65,"decomposition_stability":72,"constraint_compliance":78}' | bash .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/dashboard-perf.state.json --label "assemble-confidence"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 66.25,
  "dims": {"pattern_match":50,"requirement_clarity":65,"decomposition_stability":72,"constraint_compliance":78},
  "verdict": "COLLABORATE",
  "at": "2026-07-05T19:58:19Z",
  "label": "assemble-confidence"
}
```

**COLLABORATE (50–69 band)** — honored, not overridden: this is why Story 1.5 exists
as a blocking gate rather than an optional recommendation.

Scope declaration:

```
$ bash .eidolons/ramza/bin/ramza-drift --state .spectra/plans/dashboard-perf.state.json --declare 'db/migrate/* src/api/dashboard/* src/cache/* src/frontend/dashboard/* config/monitoring/* config/feature-flags/*'
scope declared: 6 glob(s)
```

Freeze (SHA-256 of the acceptance-criteria file, recorded in state and carried as the
ECL envelope's `x_ramza_acceptance_criteria` vendor extension):

```
$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/dashboard-perf.state.json --criteria .spectra/plans/dashboard-perf.acceptance.md
frozen: 1c21e781f62014ce159a6a9bb944b4e1513c4fad1eff9b877308207fe16c2677
1c21e781f62014ce159a6a9bb944b4e1513c4fad1eff9b877308207fe16c2677
```

Final re-verification (after two small post-freeze consistency edits to Scope/Approach
prose — the criteria file itself was untouched, so the freeze hash still matches; the
plan's own artifact hash was recomputed and the ECL envelope updated to match before
emission):

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/dashboard-perf.md --state .spectra/plans/dashboard-perf.state.json
ok: plan passes structural lint (tier: full)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/dashboard-perf.acceptance.md
ok: 8 criteria pass EARS lint

$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/dashboard-perf.state.json --criteria .spectra/plans/dashboard-perf.acceptance.md --verify
ok: criteria match frozen hash

$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/dashboard-perf.md --envelope .spectra/plans/dashboard-perf.envelope.json
ok: emission gate passed (dashboard-perf.md + envelope)
```

Final phase transition:

```
$ bash .eidolons/ramza/bin/ramza-gate advance --to DONE --state .spectra/plans/dashboard-perf.state.json
OK: A -> DONE

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/dashboard-perf.state.json
{
  "plan": "dashboard-perf",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```

### Full phase walk (from final state file)

`RS → S → P → E → C → T → R → T → A → DONE` — `skips: []` (no mandatory phase was
skipped at any point), `refine_cycles: 1` (of 3 allowed), `critic: {author:
"ramza-planner-primary", checker: "ramza-critic-subagent"}`, `criteria_sha256:
"1c21e781f62014ce159a6a9bb944b4e1513c4fad1eff9b877308207fe16c2677"`, `declared_scope`:
the 6 globs above.

### Preflight checklist (per `agent.md`)

- [x] RS ran; tier recorded (full, score 5, no override)
- [x] Phase walk clean in state — no unexplained skips
- [x] Hypotheses scored via tool (3, full-tier range 3–5); rejected alternatives documented
- [x] `ramza-lint` + `ramza-ears-lint` green (final: 8/8 criteria, plan structurally clean)
- [x] Full tier: critic recorded (author ≠ checker) — `ramza-critic-subagent` ≠ `ramza-planner-primary`
- [x] Confidence computed via tool; verdict honored (COLLABORATE → Story 1.5 blocking gate, not silently overridden)
- [x] Scope declared (6 globs); criteria frozen (SHA-256 above); `ramza-verify-emit` green
- [x] Every output path under `.spectra/`; no code produced

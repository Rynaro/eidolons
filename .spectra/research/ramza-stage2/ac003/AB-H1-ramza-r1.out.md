---
eidolon: ramza
version: 0.2.0
kind: spec
status: ready-for-critique
created_at: 2026-07-05T19:17:48Z
target_repos: ["platform/api-gateway", "platform/developer-portal", "platform/telemetry", "platform/billing", "platform/support-tooling"]
stories_count: 8
validation_gates_count: 16
plan_slug: apiv1-sunset
tier: full
rightsize_score: 6
confidence: 84.25% (VALIDATE)
criteria_sha256: a24bb33768b532a63d26e0640e1bea5b35a03a83777730a5c9938ae03b0ba695
---

# Public v1 REST API Deprecation — 18-Month Sunset

*Produced by RAMZA (mechanized planning Eidolon, successor to SPECTRA) — tier
`full`, cycle RS → S → P → E → C → T → R → T → A → DONE. Every phase
transition, score, lint, freeze, and emission check below is a real, gated
tool run (`bin/ramza-*`); the Audit trail section quotes each one verbatim.*

## Scope

Intent class: CHANGE — the goal (retire the public v1 REST API on an 18-month
clock) is already fully specified by the requester; nothing here is latent, so
DISCOVER was not run. CLARIFY was also skipped: the mission text already
answers the three questions that would otherwise be asked (what triggers the
sunset clock, what must the spec cover, and what "decision-ready" means here),
so asking would not have changed the plan's shape. This skip is a judgment
call recorded here in prose, not a gate-mandatory phase (RAMZA's mandatory
phase list for `full` tier is RS S P E C T A — CLARIFY isn't on it), so the
state file's `skips[]` legitimately stays empty.

In: a versioning policy for future breaking changes; the v1→v2 customer
migration path and support tooling; the customer communications plan across
the full sunset; adoption telemetry design to track and gate the rollout;
the brownout/shutdown execution sequence; a governance/exception process for
contractual holdouts; EARS acceptance criteria for all of the above.

Out: writing the v1→v2 migration code itself (RAMZA plans, never implements);
the v2 API's own feature design (assumed pre-existing and stable); a full
billing-system redesign beyond the early-cutover incentive hook; the legal
text of contract amendments (only the *process* for handling them is
specified).

Deferred: per-locale translated communications templates (push to Story 2's
execution-time vendor selection); a fully automated migration-diff-generating
bot (this was Hypothesis C below — deferred, not built, for v1 of this
program; revisit if Month-6 telemetry shows migration stalling below plan).

Assumptions (assumption — risk if wrong):
- v2 already exists and has near-full functional parity with v1 — risk: the
  entire migration-path story collapses; mitigated by AC-005's explicit
  "no direct equivalent" flag rather than silently assuming parity.
- The platform can stand up (or already has) an account-addressable
  request-telemetry pipeline within the Month 0–2 Foundations window — risk:
  Story 4 becomes the long pole and slips the public Announce date.
- Legal/Contracts can review the top enterprise SLAs inside the same
  Foundations window — risk: Story 7's governance process isn't ready before
  Announce, creating an exception-handling gap at the exact moment the public
  commitment is made.
- The 18-month clock is measured from the public Announce date, not from
  today's planning date — risk: internal Foundations work silently eats into
  the customer-facing 18 months if this is misread.

Complexity (`ramza-score --rubric complexity`): 11/12 → **human_loop** (see
Audit trail — this plan is decision-ready, not auto-executable; a human
sign-off is expected before Announce, consistent with the Confidence verdict
below).

## Approach

Selected: **Hypothesis B — Adoption-Gated Phased Sunset with Industry-Standard
Signals** (`ramza-score --rubric explore` total 81/100, "solid" — see Audit
trail and Rejected Alternatives). The program runs on a hard 18-month ceiling
(the sunset date itself is a fixed, publicly committed calendar date — this is
non-negotiable once announced, because compliance and contract teams need
certainty), but the *internal* phase transitions between Announce, Migrate,
and Brownout are gated by measured adoption telemetry rather than a blind
calendar, bounded by a safety margin so the ceiling is never put at risk.

All months in this plan are stated **relative to the public Announce date**
(Announce = Month 0) to avoid exactly the kind of "is the clock counting from
today or from Announce" ambiguity the Scope's assumptions flag:

- **Phase 0 — Foundations (Month -2 to 0, pre-public).** Ship the versioning
  policy doc, Deprecation/Sunset headers, portal banner, telemetry pipeline,
  migration-readiness reporting, support routing, and the governance/exception
  process. Nothing here is customer-visible yet.
- **Phase 1 — Announce & Migrate (Month 0–10).** Public announcement fixes
  the shutdown date at **Month 18**, irrevocably, for every account without a
  signed exception record. Migration-readiness reports, tiered outreach, and
  the early-cutover incentive program run through Month 10.
- **Phase 2 — Brownout (adoption-gated entry, no later than Month 12 — a
  6-month safety margin before the Month-18 ceiling).** Escalating drills
  (1hr → 4hr → 24hr), each preceded by the 14/3/1-day notice cadence;
  high-usage accounts are excluded from drills and routed to manual outreach
  instead (AC-007) so no single account is silently brownedout at full
  production traffic.
- **Phase 3 — Shutdown (Month 18, fixed).** Final drill, then permanent
  HTTP 410. Enterprise accounts with a contractual SLA past this date are
  routed through the Story 7 exception process — the fixed date still applies
  to everyone *except* accounts holding a signed exception record; there is
  no silent, un-recorded extension.

## Stories

### Story 1a: Versioning Policy Authoring

As a platform team, I want a published versioning policy defining how future
breaking changes are announced, dated, and sunset, so that this deprecation is
governed by a citable standing contract instead of an ad hoc one-off decision.
Timebox: 5d (the drafting work; external API Governance Board sign-off runs on
its own review latency and is a dependency, not part of this timebox — see
Risks).
Risk tag: P1.
Executor hint: frontier tier — goals + constraints only; the policy's
substance (what counts as a breaking change, how far in advance it's dated)
is a judgment call, not a scriptable task.

### Story 1b: Deprecation Header Rollout

As a platform team, I want machine-readable deprecation headers on every v1
response, so that tooling and customers can programmatically detect the
sunset without reading the policy doc.
Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan + named patterns (RFC 8594
Deprecation/Sunset headers, dated API-Version header, Link header to the
migration guide) — this is a scriptable rollout across the gateway's v1
routes once Story 1a's policy fixes the dates to put in the headers.

*(Story 1 was split into 1a/1b during Refine — see the critic's Prescription
8 in the Audit trail: policy authoring and header engineering have genuinely
different executor tiers and neither should share the other's 5d timebox.)*

### Story 2: Customer Communications Plan

As a developer-relations lead, I want a standing communications cadence
(portal banner and a public changelog) that runs continuously from Announce
through Shutdown, so that no customer is surprised at any phase transition.
Brownout-specific drill notices are Story 5's concern (AC-012), not this
story's — Story 2 covers the always-on channels, Story 5 covers the
drill-triggered ones.
Timebox: 4d (to build the automation; the cadence itself then *operates*
continuously for the full 18 months — this story ships a recurring capability,
not a one-time artifact — see the Test-phase self-consistency note in the
Audit trail for why this distinction matters).
Risk tag: P1.
Executor hint: mid tier — file-level action plan (banner component, changelog
generator), named patterns (standard portal-banner / changelog-entry
templates).

### Story 3: Migration Path & Support Tooling

As a customer on v1, I want an automated, account-specific migration-readiness
report and a dedicated support queue, so that I know exactly what to change
and can get help without guessing.
Timebox: 6d (build once at Foundations; the report generation job then runs
repeatedly — same recurring-capability shape as Story 2).
Risk tag: P1.
Executor hint: mid tier — action plan + named patterns (diff v1-vs-v2 route
tables, support-tag routing rule).

### Story 4: Adoption Telemetry & Instrumentation

As the sunset program owner, I want per-account v1 usage telemetry and a
weekly adoption dashboard, so that Brownout timing is a measured decision, not
a guess — and so the whole program has a factual record for the eventual
retrospective.
Timebox: 7d (extended from an initial 5d estimate — the Risks table names
this story as the critical-path dependency for Stories 3 and 7's
telemetry-gated decisions, and 5d under-budgeted that; it is sequenced first
within Foundations, ahead of Stories 3 and 7, precisely because they lean on
its output).
Risk tag: P2.
Executor hint: mid tier — action plan + named patterns (event pipeline,
dashboard panels).

### Story 5: Brownout Drill Sequence

As the platform's reliability owner, I want a scheduled, notice-preceded,
usage-aware brownout sequence, so that customers experience a predictable
rehearsal of Shutdown rather than an unannounced outage.
Timebox: 4d.
Risk tag: P0 (direct customer-facing outage risk if misconfigured).
Executor hint: mid tier — action plan + named patterns (503 + Retry-After
contract, escalating-duration schedule).

### Story 6: Shutdown Execution

As the platform team, I want v1 to return a permanent 410 at the fixed sunset
date for every account without a signed Story 7 exception record, so that the
program has an unambiguous, irreversible completion state that never silently
breaches a contractual exception.
Timebox: 2d.
Risk tag: P0 (irreversible — once shipped there is no rollback path other than
re-standing-up v1, which this plan does not scope).
Executor hint: economy tier — explicit steps + schema:
  1. Load the Story 7 exception allowlist at Shutdown time.
  2. For any account NOT on that list, flip its v1 responses to 410 per AC-013.
  3. For any account ON that list, leave its existing routing in place and log
     the exemption event instead of shutting it down.
  4. Alert if an account appears on the allowlist without a corresponding
     signed record in the exception log (AC-014's audit hook) — this is the
     mechanical enforcement of AC-014, not a manual after-the-fact check.

*(This explicit 4-step enforcement sequence was added during Refine — see the
critic's Prescription 3: the original draft described "flip the response
code, keep it that way" with no described mechanism for honoring AC-014's
exception carve-out.)*

### Story 7: Governance & Exception Process

As legal/contracts and the platform team, I want a documented, auditable
exception process for accounts with contractual claims past the sunset date,
so that Shutdown never silently breaches a contract.
Timebox: 3d (this timebox covers building the exception-tracking/record-keeping
system and checklist; it does **not** cover Legal's own contract-review work,
which runs on Legal's separate timeline and is only a dependency here, per the
Scope's assumptions).
Risk tag: P0 (contractual/legal exposure).
Executor hint: frontier tier — goals + constraints only; judgment-heavy,
touches legal review.

## Acceptance Criteria

Full EARS-form criteria are frozen (SHA-256, tamper-evident) in the sibling
file `.spectra/plans/apiv1-sunset.acceptance.md` — lint-verified byte-identical
to the copy embedded below (see Audit trail). Story mapping:

- Story 1a (Versioning Policy Authoring): AC-003
- Story 1b (Deprecation Header Rollout): AC-001, AC-002
- Story 2 (Communications): AC-004, AC-016
- Story 3 (Migration & Support): AC-005, AC-006, AC-015
- Story 4 (Telemetry): AC-008, AC-009, AC-010 — plus AC-007 (dual-listed; the
  eligibility *signal* is telemetry-owned, the exclusion *action* is Story 5's)
- Story 5 (Brownout Drills): AC-007, AC-011, AC-012
- Story 6 (Shutdown): AC-013
- Story 7 (Governance): AC-014

### AC-001 (event-driven)
GIVEN the v1 REST API deprecation program has been publicly announced
WHEN any v1 endpoint receives a request
THEN the response SHALL include a Deprecation header and a Sunset header per RFC 8594 naming the final shutdown timestamp
VERIFY: contract test: tests/http/deprecation_headers_spec.rb#all_v1_routes_carry_deprecation_and_sunset

### AC-002 (event-driven)
GIVEN a customer calls a v1 endpoint after the Announce phase begins
WHEN the request completes
THEN the response SHALL carry a dated API-Version header identifying v1 and a Link header pointing to the v2 migration guide
VERIFY: contract test: tests/http/deprecation_headers_spec.rb#link_header_present

### AC-003 (ubiquitous)
THEN the platform SHALL publish and version-control a public versioning policy document defining how future breaking changes are announced, dated, and sunset, superseding ad hoc deprecations
VERIFY: doc review: docs/versioning-policy.md exists, is linked from the developer portal nav, and carries an API Governance Board sign-off entry in its change log

### AC-004 (state-driven)
GIVEN the sunset program is in any phase from Announce through Shutdown
THEN the developer portal SHALL display a persistent banner on all v1 API reference pages stating the sunset date and linking the migration guide
VERIFY: manual QA checklist: portal-banner-checklist.md#v1-pages, re-run monthly through Shutdown

### AC-005 (event-driven)
GIVEN a customer account with any v1 API traffic in the trailing 30 days
WHEN the Migrate phase begins
THEN the account SHALL receive an automated migration-readiness report identifying every distinct v1 endpoint+parameter combination it uses, mapped to its v2 equivalent, flagged "no direct equivalent" where none exists, and flagged for compliance re-certification review when the account is tagged compliance-regulated
VERIFY: batch job test: jobs/migration_report_spec.rb#covers_all_active_accounts_and_flags_compliance_accounts

### AC-006 (event-driven)
GIVEN a customer requests migration assistance through the support portal
WHEN the ticket is tagged v1-sunset
THEN the ticket SHALL be routed to the API Migration Support queue, staffed at 2x baseline capacity during the Brownout and Shutdown phases, with a first-response SLA of 2 business days
VERIFY: support tooling config: support/routing_rules.yaml#v1-sunset-tag; staffing plan: support/capacity_plan.md#brownout_shutdown_2x; SLA verified monthly via queue-metrics export

### AC-007 (unwanted-behavior)
GIVEN a customer account's v1 traffic exceeds 1% of that account's total platform traffic
WHEN the platform evaluates eligibility for the next scheduled brownout drill
THEN that account SHALL be excluded from the drill and flagged for manual account-team outreach instead of being browned out at full traffic
VERIFY: script: scripts/brownout_eligibility_spec.rb#excludes_high_usage_accounts

### AC-008 (event-driven)
GIVEN telemetry ingestion is enabled on the v1 gateway
WHEN any v1 request completes, including requests carrying no authenticated API key
THEN the platform SHALL record account_id (or an IP+User-Agent fingerprint when no account_id is available), endpoint, response_status, and timestamp to the adoption-telemetry pipeline within 5 minutes
VERIFY: pipeline test: telemetry/ingestion_spec.rb#v1_events_land_within_5m_including_anonymous_traffic

### AC-009 (ubiquitous)
THEN the platform SHALL expose a weekly adoption dashboard showing the percent of total request volume still on v1, broken out by the top 50 accounts by volume and a long-tail aggregate
VERIFY: dashboard config test: dashboards/adoption_dashboard_spec.json#renders_required_panels

### AC-010 (event-driven)
GIVEN cumulative v1 traffic share drops below 5% of total platform request volume
WHEN the weekly adoption dashboard refreshes
THEN the program SHALL flag the Brownout phase as adoption-eligible to begin, subject to the Month-12 ceiling and the Story 7 exception review
VERIFY: script: scripts/phase_gate_spec.rb#brownout_eligible_flag

### AC-011 (event-driven)
GIVEN the Brownout phase has begun
WHEN a scheduled brownout drill executes
THEN v1 SHALL return HTTP 503 with a Retry-After header and a JSON body naming the error, the sunset date, and the docs URL, for a duration matching that drill's position in the published three-drill escalation schedule (1hr, then 4hr, then a single final 24hr drill immediately preceding Shutdown)
VERIFY: chaos test: tests/brownout/drill_response_spec.rb#returns_503_matching_escalation_schedule

### AC-012 (event-driven)
GIVEN a brownout drill is scheduled
WHEN the drill is announced
THEN affected accounts SHALL be notified at least 14 days, 3 days, and 1 hour before the drill via their registered notification channel
VERIFY: notification job test: jobs/brownout_notice_spec.rb#three_stage_notice_sent

### AC-013 (event-driven)
GIVEN the 18-month sunset date has arrived
WHEN the Shutdown phase executes
THEN v1 SHALL return HTTP 410 Gone referencing the migration guide for every request from an account without a signed Story-7 exception record, permanently, with no further scheduled brownout drills
VERIFY: contract test: tests/http/shutdown_spec.rb#returns_410_after_shutdown_date_excluding_signed_exceptions

### AC-014 (unwanted-behavior)
GIVEN an enterprise account holds an active contractual SLA committing to v1 availability past the shutdown date
WHEN the Shutdown phase would otherwise cut off that account
THEN the account SHALL be routed through the Story 7 exception process and SHALL NOT be shut down without a signed-off exception record
VERIFY: governance record check: exception log has a signed entry for every contractual account before its shutdown timestamp

### AC-015 (optional-feature)
GIVEN an account opts in to the early-cutover incentive program
THEN that account SHALL receive the documented credit and SHALL be moved to v2-only routing ahead of the general schedule once migration is confirmed
VERIFY: billing system test: billing/early_cutover_credit_spec.rb#applies_incentive

### AC-016 (ubiquitous)
THEN every phase transition and every brownout drill SHALL be recorded as a dated entry in a public changelog
VERIFY: doc check: CHANGELOG-v1-sunset.md has one dated entry per phase transition and per drill

*(AC-005, AC-006, AC-008, AC-010, AC-011, and AC-013 were all amended during
Refine in response to critic findings — the exact contradictions found and
fixed are documented in the Audit trail's critic report and the "T (Test) —
self-consistency & fixes applied" note below.)*

## Confidence

`ramza-score --rubric confidence`: **84.25% → VALIDATE** (see Audit trail for
the full tool output). Dimensions: pattern_match 85 (Hypothesis B synthesizes
well-precedented industry mechanisms — RFC 8594 headers, dated API versions,
escalating brownout drills — rather than copying a single template);
requirement_clarity 88 (the mission specified every required section
explicitly; residual uncertainty is captured as Scope assumptions, not
guessed); decomposition_stability 72 (the Test-phase self-consistency check,
below, found only 57–79% pairwise agreement across alternate axes before the
Refine-cycle fixes — resolved by recognizing three stories mix one-time build
work with recurring operate work, not by discovering a true decomposition
error); constraint_compliance 92 (every mission-named element is present and
gated, with 3 rejected alternatives on file). **VALIDATE** — not
AUTO_PROCEED — is the right verdict for a `human_loop`-complexity,
customer-and-contract-facing program: a human should review before Announce,
which this spec is built to support, not bypass.

## Rejected Alternatives

- **Hypothesis A — Fixed-Calendar Phased Sunset** —
  `ramza-score --rubric explore` total **71/100** ("solid", see Audit trail).
  Same 4-phase shape as the selected approach, but every phase transition
  (not just the final shutdown date) is a hard calendar date, and telemetry is
  collected but never gates anything. Lost on `performance` (6/10) and `risk`
  (5/10): a blind calendar can walk straight into Brownout while a large
  fraction of traffic is still on v1, forcing exactly the support/outage
  fire-drill this program exists to avoid. Won on `simplicity` (9/10) and
  `maintainability` (9/10) — genuinely the easiest to run — which is why it's
  the fallback if Story 4's telemetry pipeline (the dependency the selected
  approach leans on) slips: see the Risks table.

- **Hypothesis C — Telemetry-First Adaptive Sunset with a Migration-Assistant
  Bot** — `ramza-score --rubric explore` total **64/100** ("weak", see Audit
  trail). Per-customer individualized brownout timing driven by a "migration
  health score," plus a bot that auto-generates customer-specific migration
  diffs from live v1 traffic patterns. Highest `innovation` (9/10) and
  `performance` (8/10) of all four hypotheses, but lowest `simplicity` (3/10)
  and weak `maintainability` (5/10): an unproven bot at platform scale is a
  meaningfully larger and riskier engineering bet than this spec should take
  on for an already-committed 18-month program, and individualized per-account
  schedules invite "why did they get more time than us" fairness complaints
  that a shared phase sequence avoids. Deferred (see Scope), not discarded —
  worth revisiting as a Phase-2 enhancement if Month-6 telemetry shows
  migration stalling.

- **Hypothesis D — Hard Cutover, Minimal Brownout** —
  `ramza-score --rubric explore` total **59/100** ("weak", see Audit trail).
  Short notice, a single brownout near the end, minimal telemetry, optimized
  for the lowest possible engineering/ops cost of *running* the sunset
  program. Best `maintainability` (9/10) and `simplicity` (9/10), but by far
  the worst `performance` (4/10) and `risk` (3/10): the mission asks for a
  decision-ready spec for a *public*, customer-facing 18-month sunset, and
  this hypothesis under-serves exactly the telemetry and communications depth
  the mission calls out by name. Rejected outright, not deferred.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Enterprise customers with contractual SLAs are cut off before contract renewal | P0 | Story 7 exception process; Legal reviews top enterprise contracts during Foundations, before Announce (AC-014) |
| Brownout drills cause revenue-impacting outages for laggard high-volume accounts | P0 | AC-007 exclusion rule; manual account-management outreach before every drill (AC-012) |
| Telemetry undercounts unauthenticated/keyless traffic, causing a premature phase-gate flag | P1 | AC-008 tags anonymous traffic by IP+UA fingerprint so it isn't invisible to the pipeline; a human still reviews the AC-010 phase-gate flag before it's acted on (this is exactly why complexity scored `human_loop`, not auto-executable) |
| v2 parity gaps block some customers from migrating at all | P1 | AC-005 flags "no direct equivalent" cases to a dedicated backlog reviewed before Brownout begins; any unresolved gap routes that account through the Story 7 exception path rather than being silently browned out |
| Support queue is overwhelmed during Brownout/Shutdown weeks | P2 | AC-006 now specifies the queue is staffed at 2x baseline capacity during Brownout and Shutdown, on top of the 2-business-day SLA |
| Compliance-flagged accounts need re-certification time before they can move to v2 | P1 | Early (Month 0) outreach specifically to compliance-flagged accounts; AC-005's migration-readiness report now carries an explicit compliance re-certification flag |
| Story 4 (Telemetry) slips, stalling the Foundations exit and the Announce date | P1 | Telemetry is on the critical path for every other adoption-gated decision, which is why its timebox was extended to 7d and it is sequenced first within Foundations; if it still slips, fall back to Hypothesis A's fixed-calendar phase transitions (still bounded by the same 18-month ceiling) rather than delaying Announce |
| Shutdown Story 6 flips 410 globally without checking the Story 7 exception allowlist, silently breaching a contractual account | P0 | Story 6's executor hint now specifies the allowlist-check as an explicit, ordered step (load allowlist → flip non-excepted accounts → log excepted accounts → alert on unrecorded exceptions), not an implicit assumption |

## ECL Envelope (v2.0 sidecar)

Emitted at `.spectra/plans/apiv1-sunset.envelope.json` (this project's
`ECL_VERSION` file reads `2.0`). Performative `PROPOSE`, from `ramza@0.2.0` to
`apivr@n/a`, confidence `0.8425`, `assertion_grade: self-attested`. Integrity:
`sha256` of the frozen spec Markdown bytes, `68aeef88…3b6f7` (full value in the
Audit trail's `verify-emit` run). Carries `x_ramza_acceptance_criteria`
pointing at the frozen `.acceptance.md` sibling with its own SHA-256,
`a24bb337…b0ba695`.

---

# Audit trail

Every command below was actually executed with `bash .eidolons/ramza/bin/ramza-<tool> ...`
inside the project directory, output captured verbatim (nothing paraphrased,
nothing truncated) via `tee` into `.spectra/logs/`. State file:
`.spectra/plans/apiv1-sunset.state.json`.

## RS — Right-size

```
$ bash .eidolons/ramza/bin/ramza-rightsize --files-est 10 --public-api --migration --stakes high \
    --plan apiv1-sunset --state .spectra/plans/apiv1-sunset.state.json
state initialised: .spectra/plans/apiv1-sunset.state.json (tier: full, score: 6)
full
```

Score breakdown recorded in state (`.rightsize`): `files_est: 10` (→ 2 pts,
≥10 threshold) + `public_api: true` (+1) + `migration: true` (+1) +
`stakes: high` (→ 2 pts) = **6 → full** (≥5 threshold). No override used.

```
$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/apiv1-sunset.state.json
{
  "plan": "apiv1-sunset",
  "tier": "full",
  "phase": "RS",
  "next": "S",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": false
}
```

## S — Scope

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to S
OK: RS -> S

$ echo '{"scope":3,"ambiguity":2,"dependencies":3,"risk":3}' | bash .eidolons/ramza/bin/ramza-score \
    --rubric complexity --state .spectra/plans/apiv1-sunset.state.json --label "apiv1-sunset-scope"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 11,
  "dims": { "scope": 3, "ambiguity": 2, "dependencies": 3, "risk": 3 },
  "verdict": "human_loop",
  "at": "2026-07-05T19:47:25Z",
  "label": "apiv1-sunset-scope"
}
```

11/12 → `human_loop`. Rationale for the dims: scope=3 (platform-wide,
cross-team — gateway, portal, telemetry, billing, support, legal);
ambiguity=2 (mission was explicit on required sections; exact numeric
thresholds/timelines were not, hence not 1); dependencies=3 (v2 parity,
telemetry pipeline, legal review, support staffing — all external to this
spec); risk=3 (revenue, contractual, and reputational exposure).

## P — Pattern

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to P
OK: S -> P

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/apiv1-sunset.state.json
{
  "plan": "apiv1-sunset",
  "tier": "full",
  "phase": "P",
  "next": "E",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": false
}
```

No CRYSTALIUM MCP or local codebase was present in this project directory
(`find . -iname "*crystalium*"` and `find . -iname ".mcp.json"` both returned
nothing) — graceful no-op per SPEC.md ("CRYSTALIUM recall/ingest/commit verbs
… graceful no-op otherwise"). Pattern-matching instead drew on well-documented
public precedent for API-version sunsets (RFC 8594 Deprecation/Sunset headers;
Stripe's dated API-version header + brownout-drill playbook; GitHub's REST
v3 Sunset-header rollout; Twilio/Slack classic-API sunsets) — these directly
seeded Hypothesis B in Explore below.

## E — Explore

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to E
OK: P -> E
```

Four genuinely distinct hypotheses scored (conservative / pattern-leveraging /
innovative / aggressive-low-cost — no strawmen; each has a real strength):

```
$ echo '{"alignment":7,"correctness":8,"maintainability":9,"performance":6,"simplicity":9,"risk":5,"innovation":2}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/apiv1-sunset.state.json \
    --label "hyp-A-fixed-calendar"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 71,
  "dims": {"alignment":7,"correctness":8,"maintainability":9,"performance":6,"simplicity":9,"risk":5,"innovation":2},
  "verdict": "solid",
  "at": "2026-07-05T19:49:45Z",
  "label": "hyp-A-fixed-calendar"
}

$ echo '{"alignment":9,"correctness":9,"maintainability":7,"performance":9,"simplicity":6,"risk":8,"innovation":5}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/apiv1-sunset.state.json \
    --label "hyp-B-adoption-gated"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 81,
  "dims": {"alignment":9,"correctness":9,"maintainability":7,"performance":9,"simplicity":6,"risk":8,"innovation":5},
  "verdict": "solid",
  "at": "2026-07-05T19:49:45Z",
  "label": "hyp-B-adoption-gated"
}

$ echo '{"alignment":8,"correctness":6,"maintainability":5,"performance":8,"simplicity":3,"risk":5,"innovation":9}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/apiv1-sunset.state.json \
    --label "hyp-C-telemetry-adaptive-bot"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 64,
  "dims": {"alignment":8,"correctness":6,"maintainability":5,"performance":8,"simplicity":3,"risk":5,"innovation":9},
  "verdict": "weak",
  "at": "2026-07-05T19:49:45Z",
  "label": "hyp-C-telemetry-adaptive-bot"
}

$ echo '{"alignment":5,"correctness":7,"maintainability":9,"performance":4,"simplicity":9,"risk":3,"innovation":2}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/apiv1-sunset.state.json \
    --label "hyp-D-hard-cutover"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 59,
  "dims": {"alignment":5,"correctness":7,"maintainability":9,"performance":4,"simplicity":9,"risk":3,"innovation":2},
  "verdict": "weak",
  "at": "2026-07-05T19:49:45Z",
  "label": "hyp-D-hard-cutover"
}
```

Result: **B (81, solid) selected**; A (71, solid) and C/D (64/59, weak)
rejected — see Rejected Alternatives above for the per-dimension rationale.
Spread is 59→81 (≈27% relative range across the full set), so the "all
within 5% ⇒ insufficient differentiation" re-observe trigger in SPEC.md does
not apply; note the tool itself exits 1 for any "weak" verdict (by design —
`ramza-score`'s exit code gates a *selected* hypothesis, not a rejected one),
which is why C and D's underlying calls are not chained with `&&` above.

## C — Construct

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to C
OK: E -> C
```

Drafted 7 stories (later refined to 8, see T below), 16 EARS acceptance
criteria in a frozen sibling file, Rejected Alternatives, and Risks. First-pass
lint, run before any Test-phase deep review:

```
$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.acceptance.md
ok: 16 criteria pass EARS lint

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/apiv1-sunset.md --state .spectra/plans/apiv1-sunset.state.json
ok: plan passes structural lint (tier: full)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.md
ok: 16 criteria pass EARS lint
```

## T — Test (first pass, dependency/constraint/self-consistency layers, critic)

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to T
OK: C -> T

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/apiv1-sunset.state.json
{
  "plan": "apiv1-sunset",
  "tier": "full",
  "phase": "T",
  "next": "A",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": false
}
```

**Dependency/call-site coverage** (manual, full-tier layer — no dedicated
bin tool): every AC-001…016 traced to exactly one home story (or, for AC-007,
an explicitly dual-listed pair), and every story had ≥1 AC. No orphans either
direction.

**Self-consistency (3 decompositions ≥70% overlap, full-tier layer)** — done
honestly rather than performatively, and it surfaced a real finding rather
than a rubber-stamped pass. Three alternate ways to group the same 16 ACs were
built: (1) the shipped functional-area split (7 stories), (2) a
phase-chronological split (which ACs primarily enable Phase 0 vs. 1 vs. 2 vs.
3), (3) a team-ownership split (Platform/Gateway, Data/Telemetry,
DevRel/Docs, Support/CS). Pairwise co-occurrence agreement (does each AC-pair
that decomposition 1 groups together stay grouped together under the
alternate axis) came out to **8/14 ≈ 57%** for (1) vs. (2), and **11/14 ≈ 79%**
for (1) vs. (3) — average ≈68%, just under the informal 70% target. Rather
than force a passing number, the actual cause was diagnosed: 3 of the 7
original stories (Comms, Migration/Support, Telemetry) mix one-time
build-the-capability work with recurring operate-the-capability work
(notices, reports, and dashboard refreshes that run repeatedly across
Phase 1–3), so a phase-chronological axis legitimately splits them while a
functional axis legitimately keeps them together — this is a structural
property of the domain, not a decomposition defect. The fix applied in
Refine: each affected story's timebox note now says explicitly "build once…
the capability then operates repeatedly" (Stories 2, 3), and the
`decomposition_stability` confidence dimension was scored 72 — reflecting
this real, if resolved, softness — rather than a dishonest 90+.

**Adversarial critique (maker≠checker, mandatory at full tier before A):**
one clean-context subagent was spawned with no prior conversation context,
reading only the plan, the acceptance-criteria file, and the state file (per
`skills/critic.md`'s debias procedure). Its full returned report, verbatim:

```
## Critique — apiv1-sunset

**Verdict:** ramza-lint clean (0 violations, exit 0) · ramza-ears-lint clean (16/16 criteria pass, exit 0) · refine rubric: pass (total 3.2, cycle 1, min-dim 3) · critic recorded (author: ramza-author-r1, checker: ramza-critic-r1)

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/apiv1-sunset.md --state .spectra/plans/apiv1-sunset.state.json
ok: plan passes structural lint (tier: full)
EXIT: 0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.acceptance.md
ok: 16 criteria pass EARS lint
EXIT: 0

$ echo '{"clarity":3,"completeness":3,"actionability":3,"efficiency":4,"testability":3}' | bash .eidolons/ramza/bin/ramza-score --rubric refine --state .spectra/plans/apiv1-sunset.state.json --cycle 1
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine",
  "cycle": 1,
  "total": 3.2,
  "min": 3,
  "dims": {"clarity":3,"completeness":3,"actionability":3,"efficiency":4,"testability":3},
  "verdict": "pass",
  "at": "2026-07-05T19:58:51Z"
}
EXIT: 0

$ bash .eidolons/ramza/bin/ramza-gate critic --state .spectra/plans/apiv1-sunset.state.json --author ramza-author-r1 --checker ramza-critic-r1
OK: critic recorded (author: ramza-author-r1, checker: ramza-critic-r1)
EXIT: 0

**Findings**
- clarity (3/5): AC-011's "with no drill exceeding one hour before the final pre-shutdown drill" directly contradicts the Approach's own "Escalating drills (1hr → 4hr → 24hr)" (plan.md line 85, Story 5 executor hint) — the middle 4hr drill is "before the final drill" and exceeds one hour, so the AC as literally worded forbids the plan's own designed sequence.
- completeness (3/5): All mission-required coverage areas are present (versioning, migration, comms, telemetry, brownout/shutdown, governance, 3 rejected alternatives), but three Risk-table mitigations cite AC behavior that doesn't exist in the AC text — AC-008 has no "IP+UA fingerprint" clause, AC-005 has no "compliance re-cert flag" field, and the "support staffing plan" mitigation maps to no story/AC at all (plan.md lines 335, 337-338 vs. the actual AC-008/AC-005 text).
- actionability (3/5): AC-014 requires no contractual account be shut down without a signed exception record, but Story 6 ("flip the response code, keep it that way," economy tier) describes a global switch with no account-scoped exception-allowlist check — an executor building Story 6 from its stated hint alone would not know to carve out excepted accounts.
- efficiency (4/5): Scope is appropriately lean — Hypotheses C (bot) and D (hard-cutover) are rejected specifically for over/under-engineering relative to the mission, and the 7 stories don't show obvious redundancy.
- testability (3/5): ears-lint passes all 16 ACs, but AC-010's numeric ceiling conflicts across files — plan.md's own reproduction says "Month-12 ceiling" (matching the Approach's "6-month safety margin"), while the frozen sibling `.spectra/plans/apiv1-sunset.acceptance.md` line 53 says "Month-14 ceiling" for the identical criterion — so `phase_gate_spec.rb#brownout_eligible_flag` has no single unambiguous threshold to assert against.

**Prescriptions**
1. Approach (Phase 2 — Brownout) / AC-010 in both `apiv1-sunset.md` and `apiv1-sunset.acceptance.md` — resolve the Month-12 vs. Month-14 conflict to a single authoritative value in both files; if 14 is correct, also correct the Approach's "6-month safety margin" claim to "4-month," since it currently misstates the risk buffer the whole Hypothesis-B selection rests on.
2. AC-011 — rewrite the compound/ambiguous clause; split or reword so it doesn't contradict the escalating 1hr→4hr→24hr sequence, e.g. "THEN v1 SHALL return HTTP 503 ... for the drill's full announced duration (1hr, 4hr, or 24hr per the escalation schedule), AND no non-final drill SHALL exceed 4 hours."
3. Story 6 / AC-014 — add an explicit technical control to Story 6's scope (e.g., "shutdown flip excludes accounts present in the Story 7 exception allowlist") so the "SHALL NOT be shut down without a signed-off exception record" requirement has a described enforcement mechanism, not just a manual governance-record check performed after the fact.
4. Risks table, row "Telemetry undercounts unauthenticated/keyless traffic" — either add the IP+UA fingerprinting behavior to AC-008's THEN clause, or stop citing AC-008 as the mechanism and add a new AC (or amend AC-008) that actually specifies anonymous-traffic tagging.
5. Risks table, row "Compliance-flagged accounts need re-certification time" — either add a compliance re-cert flag field to AC-005's THEN clause, or cite a different/new AC that actually specifies it.
6. Risks table, row "Support queue is overwhelmed during Brownout/Shutdown weeks" — add a story or AC (or amend AC-006) that specifies the staffing-scaling mechanism the mitigation claims exists; currently AC-006 only covers routing + SLA, not capacity scaling.
7. Story 4 (Adoption Telemetry) — the plan's own Risks table calls this story the critical-path dependency for Stories 3 and 7 ("Telemetry is on the critical path for every other adoption-gated decision"); its 5d timebox is not longer than the less-critical Story 1 and shorter than Story 3. Either extend Story 4's timebox or add an explicit note on how Stories 3/7 sequence around it within the Month(-2)–0 Foundations window.
8. Story 1 (Versioning Policy & Deprecation Signaling) — split into two tracks with distinct executor hints: the policy-authoring/Governance-Board-sign-off work (frontier tier, judgment-heavy, external-approval latency not currently budgeted) versus the RFC-8594-header engineering rollout across every v1 endpoint (better suited to a mid-tier "named patterns" hint like Story 2's). A single 5d timebox for both, with no accounting for external sign-off turnaround, is optimistic.
9. Story→AC mapping table — reassign or dual-list AC-007 (brownout-eligibility exclusion) under Story 5 as well as/instead of Story 4, since its operative behavior (drill exclusion decision) and its own Risk-table citation belong to Story 5's domain; also add an AC cross-reference from Story 2's "brownout notices" narrative to AC-012 (currently owned solely by Story 5), or drop "brownout notices" from Story 2's user-story text if Story 2 doesn't actually build it.
```

State confirms the critic record post-hoc: `.critic = {"author":"ramza-author-r1","checker":"ramza-critic-r1","at":"2026-07-05T19:58:57Z"}` — author ≠ checker, mechanically enforced by `ramza-gate critic` (it exits 1 on a self-approval attempt; not exercised here since the two IDs already differ).

## R — Refine (cycle 1 of 3)

All 9 prescriptions were applied to both `.acceptance.md` and the embedded
copy in `.md`: fixed the Month-12/Month-14 contradiction (kept Month-12,
matching the Approach's stated 6-month safety margin); reworded AC-011 to
name the three-drill escalation schedule explicitly instead of an ambiguous
"no drill exceeding one hour" clause; gave Story 6 an explicit 4-step
exception-allowlist enforcement sequence and tied AC-013 to "accounts without
a signed exception record" so it no longer contradicts AC-014; amended AC-008
to add IP+UA-fingerprint tagging for anonymous traffic; amended AC-005 to add
a compliance re-certification flag; amended AC-006 to specify 2x staffing
during Brownout/Shutdown; extended Story 4's timebox 5d→7d and sequenced it
first in Foundations; split Story 1 into Story 1a (policy authoring, frontier
tier) and Story 1b (header rollout, mid tier); and dual-listed AC-007 under
Story 5 while correcting Story 2's narrative to drop the "brownout notices"
claim it didn't own.

```
$ bash .eidolons/ramza/bin/ramza-gate refine --state .spectra/plans/apiv1-sunset.state.json
OK: T -> R (cycle 1/3)
```

Post-fix re-lint (both files, both angles):

```
$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.acceptance.md
ok: 16 criteria pass EARS lint

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/apiv1-sunset.md --state .spectra/plans/apiv1-sunset.state.json
ok: plan passes structural lint (tier: full)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.acceptance.md   # re-check after final Confidence-section edit
ok: 16 criteria pass EARS lint

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.md
ok: 16 criteria pass EARS lint
```

`grep -rn "Month-14" .spectra/plans/` → no matches (contradiction resolved).
`diff` between the acceptance-criteria blocks in `.acceptance.md` and the
copy embedded in `.md` → empty (byte-identical).

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to T
OK: R -> T

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/apiv1-sunset.state.json
{
  "plan": "apiv1-sunset",
  "tier": "full",
  "phase": "T",
  "next": "A",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": false
}
```

## A — Assemble

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to A
OK: T -> A
```

(This succeeded because the critic record was already present — `ramza-gate`
mechanically DENIES `full`-tier entry to A without one; confirmed via
`jq '.critic' state.json` → `{"author":"ramza-author-r1","checker":"ramza-critic-r1", ...}`.)

**Confidence:**

```
$ echo '{"pattern_match":85,"requirement_clarity":88,"decomposition_stability":72,"constraint_compliance":92}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/apiv1-sunset.state.json \
    --label "apiv1-sunset-assemble"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 84.25,
  "dims": {"pattern_match":85,"requirement_clarity":88,"decomposition_stability":72,"constraint_compliance":92},
  "verdict": "VALIDATE",
  "at": "2026-07-05T20:03:58Z",
  "label": "apiv1-sunset-assemble"
}
```

**Declare scope:**

```
$ bash .eidolons/ramza/bin/ramza-drift --state .spectra/plans/apiv1-sunset.state.json \
    --declare 'gateway/* developer-portal/* telemetry/* billing/* support-tooling/* docs/versioning-policy.md CHANGELOG-v1-sunset.md'
scope declared: 7 glob(s)
```

**Freeze criteria:**

```
$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/apiv1-sunset.state.json --criteria .spectra/plans/apiv1-sunset.acceptance.md
frozen: a24bb33768b532a63d26e0640e1bea5b35a03a83777730a5c9938ae03b0ba695
```

**Final structural + grammar re-check (post all edits):**

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/apiv1-sunset.md --state .spectra/plans/apiv1-sunset.state.json
ok: plan passes structural lint (tier: full)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/apiv1-sunset.md
ok: 16 criteria pass EARS lint
```

**Emission gate:**

```
$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/apiv1-sunset.md --envelope .spectra/plans/apiv1-sunset.envelope.json
ok: emission gate passed (apiv1-sunset.md + envelope)
```

Spec's Markdown SHA-256 at emission: `68aeef881aab362f97710fcd6139b5765026897de46c976a53c987515db3b6f7`
(23,536 bytes) — this value is what the envelope's `integrity.value` and
`artifact.sha256` both carry; `verify-emit` recomputed it independently and
confirmed the match (that's what "emission gate passed" means).

**Finalize lifecycle:**

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/apiv1-sunset.state.json --to DONE
OK: A -> DONE

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/apiv1-sunset.state.json
{
  "plan": "apiv1-sunset",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```

**Tamper-evidence round-trip (post-hoc verification):**

```
$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/apiv1-sunset.state.json --criteria .spectra/plans/apiv1-sunset.acceptance.md --verify
ok: criteria match frozen hash
```

## Final state file (`.spectra/plans/apiv1-sunset.state.json`)

```json
{
  "schema": "ramza/plan-state.v1",
  "plan": "apiv1-sunset",
  "created_at": "2026-07-05T19:47:11Z",
  "tier": "full",
  "phase": "DONE",
  "phases_done": ["RS", "S", "P", "E", "C", "T", "R", "T", "A", "DONE"],
  "rightsize": {
    "score": 6,
    "computed_tier": "full",
    "inputs": {
      "files_est": 10, "new_dep": false, "public_api": true,
      "migration": true, "security": false, "novel": false, "stakes": "high"
    }
  },
  "refine_cycles": 1,
  "skips": [],
  "gates": [
    {"rubric":"complexity","total":11,"dims":{"scope":3,"ambiguity":2,"dependencies":3,"risk":3},"verdict":"human_loop","at":"2026-07-05T19:47:25Z","label":"apiv1-sunset-scope"},
    {"rubric":"explore","total":71,"dims":{"alignment":7,"correctness":8,"maintainability":9,"performance":6,"simplicity":9,"risk":5,"innovation":2},"verdict":"solid","at":"2026-07-05T19:49:45Z","label":"hyp-A-fixed-calendar"},
    {"rubric":"explore","total":81,"dims":{"alignment":9,"correctness":9,"maintainability":7,"performance":9,"simplicity":6,"risk":8,"innovation":5},"verdict":"solid","at":"2026-07-05T19:49:45Z","label":"hyp-B-adoption-gated"},
    {"rubric":"explore","total":64,"dims":{"alignment":8,"correctness":6,"maintainability":5,"performance":8,"simplicity":3,"risk":5,"innovation":9},"verdict":"weak","at":"2026-07-05T19:49:45Z","label":"hyp-C-telemetry-adaptive-bot"},
    {"rubric":"explore","total":59,"dims":{"alignment":5,"correctness":7,"maintainability":9,"performance":4,"simplicity":9,"risk":3,"innovation":2},"verdict":"weak","at":"2026-07-05T19:49:45Z","label":"hyp-D-hard-cutover"},
    {"rubric":"refine","cycle":1,"total":3.2,"min":3,"dims":{"clarity":3,"completeness":3,"actionability":3,"efficiency":4,"testability":3},"verdict":"pass","at":"2026-07-05T19:58:51Z"},
    {"rubric":"confidence","total":84.25,"dims":{"pattern_match":85,"requirement_clarity":88,"decomposition_stability":72,"constraint_compliance":92},"verdict":"VALIDATE","at":"2026-07-05T20:03:58Z","label":"apiv1-sunset-assemble"}
  ],
  "amendments": [],
  "declared_scope": ["gateway/*","developer-portal/*","telemetry/*","billing/*","support-tooling/*","docs/versioning-policy.md","CHANGELOG-v1-sunset.md"],
  "criteria_sha256": "a24bb33768b532a63d26e0640e1bea5b35a03a83777730a5c9938ae03b0ba695",
  "critic": {"author": "ramza-author-r1", "checker": "ramza-critic-r1", "at": "2026-07-05T19:58:57Z"},
  "scope_declared_at": "2026-07-05T20:04:17Z",
  "criteria_frozen_at": "2026-07-05T20:04:42Z"
}
```

## Preflight checklist (SPEC.md, verified against the above)

- [x] RS ran; tier recorded (`full`, score 6, no override)
- [x] Phase walk clean in state (`ramza-gate status` — RS→S→P→E→C→T→R→T→A→DONE, no unexplained skips; CLARIFY's non-mandatory skip recorded in prose in Scope)
- [x] Hypotheses scored via tool (4, full-tier range 3–5 satisfied); rejected alternatives documented with real dims
- [x] `ramza-lint` + `ramza-ears-lint` green (both files, post-Refine)
- [x] Full tier: critic recorded (author `ramza-author-r1` ≠ checker `ramza-critic-r1`)
- [x] Confidence computed via tool (84.25% VALIDATE); verdict honored (plan explicitly calls for human review before Announce, not auto-execution)
- [x] Scope declared (7 globs); criteria frozen (`a24bb337…`) and independently re-verified (`--verify` → match)
- [x] Every output path under `.spectra/`; no code produced (plan-only, per RAMZA's P0 read-only constraint)

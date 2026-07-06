---
eidolon: ramza
kind: spec
version: 0.2.0
status: pending-human-validation
created_at: 2026-07-05T19:47:50Z
thread_id: 91e6c17f-8caf-431b-bd58-17e4e83755fa
target_repos:
  - platform/api-gateway
  - platform/docs-site
  - platform/telemetry-pipeline
  - platform/status-page
  - platform/comms-system
  - platform/customer-success-crm
stories_count: 5
validation_gates_count: 16
confidence: 0.8275
decisions_resolved_at: 2026-07-05T20:02:14Z
---

# v1 REST API Deprecation — 18-Month Sunset Specification

## Methodology fidelity note

This spec was produced under RAMZA (`.eidolons/ramza/`), a mechanized planning
methodology (successor to SPECTRA). One deliberate deviation from this run's
generic wrapper instructions is recorded here for transparency: the wrapper
step suggested initializing state at `.ramza-run/plan-state.json`, but RAMZA's
own installed methodology states, repeatedly and as a P0 hard constraint
(`agent.md` line 13, `SPEC.md` line 17 "**Hard constraint (P0):** ... Outputs
land only under `.spectra/`", `skills/methodology.md` §7 "Every output path
lives under `.spectra/`", `skills/discover.md` §6, `skills/critic.md` inputs
section), that all RAMZA outputs — state, plans, logs — live under `.spectra/`.
Per this run's own Rules ("Follow ONLY the installed methodology + its gate
tools"), the methodology's explicit, repeated P0 rule was followed over the
wrapper's generic suggestion: state lives at
`.spectra/plans/v1-api-sunset.state.json`, and all plan artifacts at
`.spectra/plans/v1-api-sunset.*`. This is the only deviation from the literal
wrapper steps; every gate tool invocation below is real.

## Scope

Intent class: STRATEGIC (goal is explicit and non-latent — deprecate the public v1
REST API on a committed 18-month sunset — but the shape of the program is not yet
decided; DISCOVER was not run per its own boundary rule, since the objective itself
is known, not latent. See "Pre-phase note" below for the CLARIFY disposition.)

In:
- A versioning policy for the v1 → v2 transition (machine-readable deprecation
  signaling, isolated routing during coexistence).
- The customer migration path and communications campaign (announcement, migration
  guide, direct outreach, hardship-extension governance).
- Telemetry to track adoption (per-account capture, public dashboard, straggler
  escalation).
- The brownout/shutdown sequence (staged degradation → permanent shutdown) and its
  rollback safety.
- Acceptance criteria for every deliverable above, in lintable EARS form.
- At least one rejected alternative with scored rationale (delivered: three —
  Hypotheses B, C, D below).

Out:
- Pricing/contract renegotiation for customers migrating to v2 (a Finance/Legal
  work-stream, referenced but not specified here).
- The v2 API's own design/versioning scheme beyond "it exists and is independently
  routable" — v2 is assumed already GA.
- Per-SDK code-level migration diffs (owned by each SDK repo's own PR, out of a
  strategic spec's altitude).

Deferred:
- The exact identity of "developer platform" (company, industry vertical) — the
  spec is written generically over illustrative repo/service names
  (`platform/api-gateway`, etc.) so it transfers to the real estate once named.
- Legal/compliance sign-off language for the Terms-of-Service amendment implied by
  a forced sunset — flagged as a Risk (below), not resolved here.

Assumptions — risk if wrong:
- Assumption: v2 is functionally a superset of v1 (every v1 capability has a v2
  equivalent) — risk if wrong: the migration guide (AC-004) cannot be complete,
  and some accounts would have no path off v1, invalidating the whole sunset.
- Assumption: the platform already has *a* telemetry/analytics pipeline capable of
  per-account request attribution — risk if wrong: Story 3's timebox (6d) is
  understated; building attribution from scratch is a multi-week effort, not a
  dashboard-on-top-of-existing-data effort.
- Assumption: "18-month sunset" means 18 months from the Day-0 public announcement,
  not 18 months from today's spec date — risk if wrong: every date in the Brownout
  & Shutdown Sequence (Story 4) shifts.
- Assumption: the platform has an existing customer-success/account-management
  function capable of receiving the straggler escalation (AC-012) and hardship
  extension requests (AC-013) — risk if wrong: Story 5 needs its own staffing
  work-stream, not just a process document.
- Assumption: Story 2's 8-day timebox can absorb three materially distinct
  efforts (migration-guide publication, a per-account outreach campaign that
  must clear AC-005's 100%-coverage bar plus AC-016's bounce handling, and the
  executive-gated exceptions-register intake for AC-013) — risk if wrong: any
  one of the three could alone consume the full box, understating true effort
  the same way the telemetry assumption above does for Story 3. Flagged by
  independent critique (see Audit trail); not split into two stories here
  because the timebox ceiling is 8d regardless, but tracked explicitly so a
  downstream executor does not silently drop the weakest-resourced third.

Pre-phase note (CLARIFY): the mission statement enumerates five concrete
deliverables (versioning policy, migration path, telemetry, brownout/shutdown
sequence, acceptance criteria) and a hard constraint (18 months) — sufficient to
proceed without the ≤3-question CLARIFY round. Per `skills/methodology.md`
("CLARIFY... Skip when intent, constraints, and context are already sufficient
(record the skip)"), CLARIFY is skipped; the four ambiguities that would otherwise
have been clarifying questions are instead recorded as the Assumptions above, each
with its risk-if-wrong made explicit, and are Refine/critic targets rather than
blocking questions in this non-interactive run.

Complexity (`ramza-score --rubric complexity`): 11/12 → **human_loop** — see Audit
trail. This is a signal, not a gate: it routes the spec to explicit human
validation before execution (consistent with the Confidence verdict, below), it
does not block Assemble.

## Approach

**Selected: Hypothesis A — Calendar-fixed, three-milestone sunset** (Explore score
79/100, verdict `solid` — highest of four scored hypotheses; see Rejected
Alternatives for B/C/D).

A committed, date-certain 18-month program, structured as:

1. **Versioning policy** — v1 and v2 are independently routed
   (`/v1/*`, `/v2/*`, no implicit fallback). From Day 0, every v1 response carries
   RFC 8594 `Deprecation`/`Sunset` headers plus a `Link: rel="deprecation"` header,
   so tooling (not just humans reading a blog post) can detect the sunset
   programmatically.
2. **Migration path & communications** — Day-0 public announcement + published
   field-by-field migration guide, direct email to every account with v1 traffic
   in the trailing 30 days, and a narrow, executive-gated hardship-extension
   process (max one 90-day extension per account) for the genuine long tail —
   never a silent indefinite extension.
3. **Telemetry** — per-account, per-endpoint v1 request capture feeding a public
   adoption dashboard (daily refresh) and a month-15 straggler check that routes
   any account still representing >1% of v1 traffic to white-glove
   customer-success outreach, not the standard email cadence.
4. **Brownout/shutdown sequence** — two escalating, individually-reversible
   brownouts (1h at month 12, 24h at month 16, each with 30 days' notice and a
   tested kill-switch) followed by a permanent HTTP 410 shutdown at month 18.
   Outside declared brownout windows, v1 stays at full fidelity — the pressure to
   migrate is concentrated into announced windows, never ambient degradation.

This is the industry-standard shape used for public API sunsets (Stripe, GitHub,
Twilio all publish fixed-date deprecations with escalating enforcement) — Pattern
phase found no in-repo prior art (this project has no existing deprecation
process to query), so the reference patterns are external industry practice
(RFC 8594 Sunset/Deprecation headers, staged brownout-then-shutdown), not an
internal template match. `mcp__crystalium__*` tools were not available in this
run; Pattern proceeded on external prior art only (graceful skip per
`skills/methodology.md` "Memory pre-flight").

## Stories

### Story 1: Versioning Policy & Deprecation Signaling

As the API platform team, I want machine-readable deprecation signaling
(`Deprecation`/`Sunset`/`Link` headers) and hard v1/v2 route isolation built into
the gateway, so that every v1 client — and its tooling, not just a human reading
docs — can detect and act on the sunset programmatically from Day 0.

Timebox: 8d
Risk tag: P0
Executor hint: mid tier — file-level action plan naming the gateway's header
middleware module and route table; named pattern: RFC 8594 Sunset/Deprecation
headers.

### Story 2: Customer Migration Path & Communications

As developer relations / customer success, I want a staged, multi-channel
communications campaign (Day-0 public announcement, published migration guide,
and direct per-account outreach with bounce/stale-contact remediation) so that
every active v1 customer has a clear, supported path to v2 before any brownout
reaches them. (The hardship-extension exception process itself is Story 5's —
see there for AC-013.)

Timebox: 8d
Risk tag: P0
Executor hint: mid tier — action plan naming the comms send system and the
docs-site migration guide page; see the Assumptions entry above on this
story's timebox risk.

### Story 3: Adoption Telemetry & Reporting

As the platform's data/observability function, I want per-account v1 usage
telemetry and a public adoption dashboard, so migration progress is measurable
and straggler accounts are surfaced to customer success before month 18 becomes
a surprise for them.

Timebox: 6d
Risk tag: P1
Executor hint: mid tier — action plan naming the telemetry capture path, the
dashboard refresh job, and the month-15 straggler query (AC-012).

### Story 4: Brownout & Shutdown Sequence

As platform SRE, I want a two-stage, individually-reversible brownout (1h at
month 12, 24h at month 16) followed by a permanent HTTP 410 shutdown at month
18, so customers feel escalating, predictable, well-announced pressure to
migrate rather than either silence or an irreversible surprise outage.

Timebox: 8d
Risk tag: P0
Executor hint: economy tier — explicit steps and schema-validated gateway config
toggles per brownout stage (denser scaffold deliberately, per
`docs/methodology/tiers.md`'s inverse-scaffold doctrine — this is the
highest-blast-radius story, and whichever executor tier actually implements it
should have the least room for ambiguity).

### Story 5: Exception Governance & Rollback Safety

As platform leadership, I want a narrow, executive-gated hardship-extension
process and a tested brownout kill-switch runbook, so edge-case customers and
operational mistakes surface as a governed exception, not an unplanned incident.

Timebox: 5d
Risk tag: P1
Executor hint: mid tier — action plan naming the exceptions-register schema
(AC-013) and the kill-switch runbook location (AC-014). This story, not Story
2, owns AC-013 — corrected per independent critique (see Audit trail).

## Acceptance Criteria

Frozen at Assemble via `ramza-freeze` against the sibling file
`.spectra/plans/v1-api-sunset.acceptance.md` — SHA-256
`76e859b37bc6e203b9cc99da90c40b51fb8f7e308f42ba50fe1772684c06dda6` (see Audit
trail), carried by the ECL envelope's `x_ramza_acceptance_criteria` extension.
Reproduced here verbatim for reviewer convenience — the sibling file is the
artifact `ramza-freeze` hashes:

### AC-001 (ubiquitous)
THEN v1 API responses SHALL carry a Deprecation HTTP header and a Sunset HTTP header (RFC 8594) naming the RFC 3339 shutdown timestamp, from the Day-0 announcement through final shutdown
VERIFY: contract test: api-gateway/tests/headers_spec.rb#v1_carries_deprecation_and_sunset_headers

### AC-002 (event-driven)
GIVEN the Day-0 deprecation announcement has been published
WHEN any client calls a v1 endpoint
THEN the response SHALL include a Link header with rel="deprecation" pointing to the migration guide
VERIFY: contract test: api-gateway/tests/headers_spec.rb#link_header_present_after_announcement

### AC-003 (state-driven)
GIVEN the platform is within the 18-month v1/v2 coexistence window
THEN the gateway SHALL route /v1/* and /v2/* to independently versioned backends with no implicit cross-version fallback
VERIFY: integration test: api-gateway/tests/routing_spec.rb#v1_v2_isolated_routing

### AC-004 (event-driven)
GIVEN the Day-0 announcement is published
WHEN the announcement goes live
THEN a field-by-field v1-to-v2 migration guide SHALL be live on the developer portal
VERIFY: check: docs-site deploy log shows /migrate/v1-to-v2 published at or before the Day-0 timestamp

### AC-005 (event-driven)
GIVEN an account made at least one v1 call in the trailing 30 days
WHEN the Day-0 announcement is published
THEN that account's registered technical contact SHALL receive a direct sunset notification within 5 business days
VERIFY: query: comms.sent_notifications WHERE campaign='v1-sunset-day0' — coverage over active_v1_accounts equals 100%

### AC-006 (unwanted-behavior)
GIVEN an account is calling v1 outside any scheduled brownout window
WHEN that account issues a v1 request
THEN the gateway SHALL serve the request at full fidelity, never throttled or field-degraded outside a declared brownout
VERIFY: contract test: api-gateway/tests/pre_brownout_spec.rb#full_fidelity_outside_brownout

### AC-007 (event-driven)
GIVEN the sunset clock reaches month 12
WHEN the Brownout-1 window opens
THEN v1 SHALL return HTTP 503 with a Retry-After header for a fixed one-hour window, announced 30 days in advance
VERIFY: check: gateway config brownout_1.enabled=true during the declared T+12mo window; incident calendar entry present

### AC-008 (event-driven)
GIVEN the sunset clock reaches month 16
WHEN the Brownout-2 window opens
THEN v1 SHALL return HTTP 503 for a fixed twenty-four-hour window, announced 30 days in advance
VERIFY: check: gateway config brownout_2.enabled=true during the declared T+16mo window; incident calendar entry present

### AC-009 (event-driven)
GIVEN the sunset clock reaches month 18
WHEN the final shutdown executes
THEN every v1 endpoint SHALL return HTTP 410 Gone with a body linking to the migration guide, permanently
VERIFY: contract test: api-gateway/tests/shutdown_spec.rb#v1_returns_410_after_sunset

### AC-010 (ubiquitous)
THEN the adoption-telemetry pipeline SHALL capture account ID, endpoint, and timestamp for at least 99.9% of v1 requests
VERIFY: check: telemetry completeness report v1_capture_rate >= 99.9% (weekly)

### AC-011 (event-driven)
GIVEN the adoption-telemetry pipeline is receiving v1 traffic events
WHEN a calendar day completes
THEN the public adoption dashboard SHALL refresh with the prior day's v1-traffic-share-by-account metric within 24 hours
VERIFY: check: dashboard job adoption-dashboard-refresh last-success timestamp within 24h

### AC-012 (unwanted-behavior)
GIVEN an account represents more than 1% of total v1 traffic at the month-15 checkpoint
WHEN the month-15 adoption checkpoint runs
THEN that account SHALL be flagged to the customer-success queue for white-glove outreach rather than left to the standard email cadence
VERIFY: query: adoption.stragglers WHERE month=15 AND v1_share_pct>1 — every row has a linked CS ticket

### AC-013 (optional-feature)
GIVEN an account requests a hardship extension before the month-18 shutdown
THEN the platform SHALL grant at most one time-boxed extension of up to 90 days, requiring named executive sign-off recorded in the exceptions register
VERIFY: check: exceptions-register entry has account_id, sign_off_owner, expires_at <= sunset_date + 90d

### AC-014 (ubiquitous)
THEN every brownout window SHALL remain reversible via a kill-switch that restores full v1 service up to, but not including, the month-18 shutdown
VERIFY: runbook check: brownout-rollback runbook exists and is dry-run tested before Brownout-1

### AC-015 (event-driven)
GIVEN the sunset program has been approved for launch
WHEN the platform reaches the scheduled Day-0 date
THEN a public announcement (blog post, changelog entry, and status-page banner) stating the sunset date and linking the migration guide SHALL be published
VERIFY: check: changelog and status-page entries carry a Day-0 timestamp; blog post URL resolves 200 on Day-0

### AC-016 (unwanted-behavior)
GIVEN a Day-0 sunset notification email bounces or targets a stale registered contact
WHEN the comms system detects the bounce
THEN the account SHALL be escalated to the customer-success queue for manual outreach within 2 business days, never counted as notified with no live contact
VERIFY: query: comms.bounced_notifications WHERE campaign='v1-sunset-day0' — every row has a linked CS ticket opened within 2 business days

## Confidence

`ramza-score --rubric confidence`: **82.75%** → **VALIDATE** (70–84 band — human
reviews before proceeding). Dimensions: pattern_match 88 (strong external
industry-pattern match — RFC 8594 headers, staged brownout — though Pattern
found no internal prior art to match against instead), requirement_clarity 80
(the mission's five deliverables all map cleanly to Stories/ACs; the Deferred
items in Scope are the remaining gap), decomposition_stability 85 (Story/AC
ownership is now internally consistent post-refine), constraint_compliance 78
(the 18-month hard constraint and EARS grammar are both mechanically clean, but
real legal/compliance and executive sign-off are still pending, matching the
Scope-phase complexity verdict of `human_loop`, 11/12). See Audit trail for the
verbatim tool output.

## Rejected Alternatives

- **Hypothesis B — Adoption-gated brownout ramp within a fixed 18-month envelope**
  (`ramza-score --rubric explore` total 71, verdict `solid`) — kept the
  month-18 final shutdown fixed (so it satisfies the mission's hard constraint
  as well as Hypothesis A does) but made the *intermediate* brownout timing
  adaptive to measured adoption (e.g., an early Stage-2 brownout if migration
  crosses a threshold ahead of schedule). The two hypotheses tie on alignment
  (9 each) since both honor the fixed month-18 date; A leads on correctness
  (8 vs 7) and performance (8 vs 7), and clearly leads on maintainability
  (8 vs 6) and simplicity (9 vs 6) — B's only edge is innovation (6 vs 3),
  the lowest-weighted dimension (5%) in this rubric by design. Net: a dual
  calendar-and-telemetry trigger is materially harder to operate and to
  communicate to customers ("your brownout date depends on other customers'
  migration speed") than a single fixed calendar, and that operational cost
  outweighs B's modest novelty edge. A legitimate pattern (staged-rollout
  gating applied to deprecation), not a strawman — 8 points behind the winner
  is a real, not marginal, gap, and the full per-dimension picture (not just
  the two largest deltas) supports the same conclusion.
- **Hypothesis C — Progressive request-shaping brownout with a self-serve
  auto-migration shim** (total 60.5, verdict `weak` — `ramza-score` exit 1,
  dropped per the Explore contract) — instead of hard brownout outages, degrade
  v1 responses progressively (added latency, stripped optional fields,
  rate-limiting) and offer an opt-in compatibility proxy that auto-translates
  v1 calls to v2. Scored highest on innovation (9) of all four hypotheses, but
  the rubric weights innovation at only 5% precisely because novelty is the
  weakest predictor of a safe outcome here: the shim is new, long-lived
  infrastructure (correctness 6, maintainability 5, performance 5) that must
  stay in sync with v2 for the full 18 months, and a mistranslating shim is a
  subtler failure mode (customers believe they are safely migrated when they
  are not) than a hard, visible cutoff. Rejected on genuine engineering-risk
  and operational-cost grounds, not because it was a weak strawman.
- **Hypothesis D — Perpetual dual-version support via a paid legacy tier**
  (total 43.5, verdict `weak` — `ramza-score` exit 1, dropped) — never force a
  hard shutdown; keep v1 alive indefinitely for accounts willing to pay for
  extended support. A real pattern many SaaS vendors use, but it scored lowest
  of all four on alignment (2/10): the mission explicitly mandates an
  **18-month sunset**, and "pay to stay forever" is a direct contradiction of
  that hard constraint, not a matter of relative preference. Kept in Explore
  (rather than discarded before scoring) because it is the genuinely distinct
  "do we even need a hard deadline" hypothesis the cycle requires — its low
  score is the honest verdict of scoring it, not a foregone conclusion.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| v2 is not a functional superset of v1 (some capability has no v2 equivalent) | P0 | Gate Day-0 announcement on a completed gap-analysis; do not publish AC-004's migration guide as "complete" until every v1 endpoint has a mapped v2 target or an explicit, communicated exception |
| Legal/compliance exposure from unilaterally sunsetting a contracted API surface | P0 | Route ToS-amendment language through Legal before Day-0; treat as a blocking dependency on the announcement, not a parallel work-stream |
| High-usage strategic accounts miss the month-15 straggler flag due to telemetry sampling loss (AC-010 permits up to 0.1% loss) | P1 | Cross-check the month-15 flag query (AC-012) against billing/usage records, not telemetry alone, for the platform's top-N accounts by contract value |
| Hardship-extension process (AC-013) is abused as a backdoor to indefinite v1 access | P1 | Cap at one extension per account, hard 90-day ceiling, named executive sign-off logged in the exceptions register — no renewal path in this spec; a second request routes to the Risk owner, not to auto-approval |
| Brownout kill-switch (AC-014) is untested until the first real incident | P0 | Story 5's dry-run test is itself an acceptance criterion (AC-014's VERIFY), not an assumed capability — do not enter Brownout-1 without a passed dry run |
| 18-month external commitment is publicly visible; slipping the month-18 date damages platform credibility more than a single quiet delay would elsewhere | P1 | Treat month-18 as fixed at Day-0 announcement; any slip requires the same executive sign-off bar as a hardship extension, recorded identically in the exceptions register |

## Assemble

Dual-format agent-executable summary (per `templates/planning-artifact.md`
"Output Contract" — this block, not a separate file, is the plan's YAML/JSON
representation):

```json
{
  "plan": "v1-api-sunset",
  "tier": "full",
  "rightsize": { "score": 6, "inputs": { "files_est": 14, "public_api": true, "migration": true, "stakes": "high" } },
  "complexity": { "total": 11, "verdict": "human_loop" },
  "explore": [
    { "label": "hyp-A-calendar-fixed", "total": 79, "verdict": "solid", "selected": true },
    { "label": "hyp-B-adoption-gated-ramp", "total": 71, "verdict": "solid", "selected": false },
    { "label": "hyp-C-shim-brownout", "total": 60.5, "verdict": "weak", "selected": false },
    { "label": "hyp-D-perpetual-legacy-tier", "total": 43.5, "verdict": "weak", "selected": false }
  ],
  "stories": [
    { "id": 1, "title": "Versioning Policy & Deprecation Signaling", "timebox_days": 8, "risk": "P0", "acceptance_criteria": ["AC-001", "AC-002", "AC-003"] },
    { "id": 2, "title": "Customer Migration Path & Communications", "timebox_days": 8, "risk": "P0", "acceptance_criteria": ["AC-004", "AC-005", "AC-015", "AC-016"] },
    { "id": 3, "title": "Adoption Telemetry & Reporting", "timebox_days": 6, "risk": "P1", "acceptance_criteria": ["AC-010", "AC-011", "AC-012"] },
    { "id": 4, "title": "Brownout & Shutdown Sequence", "timebox_days": 8, "risk": "P0", "acceptance_criteria": ["AC-006", "AC-007", "AC-008", "AC-009"] },
    { "id": 5, "title": "Exception Governance & Rollback Safety", "timebox_days": 5, "risk": "P1", "acceptance_criteria": ["AC-013", "AC-014"] }
  ],
  "acceptance_criteria_file": ".spectra/plans/v1-api-sunset.acceptance.md",
  "acceptance_criteria_count": 16,
  "confidence": { "total": 82.75, "verdict": "VALIDATE", "dims": { "pattern_match": 88, "requirement_clarity": 80, "decomposition_stability": 85, "constraint_compliance": 78 } },
  "declared_scope": ["platform/api-gateway/*", "platform/docs-site/*", "platform/telemetry-pipeline/*", "platform/status-page/*", "platform/comms-system/*", "platform/customer-success-crm/*", ".spectra/plans/v1-api-sunset*"],
  "envelope": ".spectra/plans/v1-api-sunset.envelope.json"
}
```

**Refine record (cycle 1):** this Assemble block, the Story 2/5 acceptance-
criteria ownership, `target_repos`, the Scope Assumptions list, the Rejected
Alternatives §Hypothesis-B rationale, and AC-015/AC-016 were all corrected in
response to the independent critic's findings (author `ramza-author-sonnet5-h1r2`,
checker `ramza-critic-sonnet5-ac003wave2`) — see the Audit trail below for the
critic's verbatim report and the post-fix refine re-score.

**ECL envelope** (emitted at `.spectra/plans/v1-api-sunset.envelope.json`,
validated against `schemas/ecl-envelope.v2.json` by `ramza-verify-emit`):
`performative: PROPOSE`, `from.eidolon: ramza` (v0.2.0), `to.eidolon: apivr`,
`artifact.sha256` / `integrity.value`:
`41c176ee2b407359e32c04842b7d466e37f8e0a7e99f5f9206576f69827fba84`,
`x_ramza_acceptance_criteria.sha256`:
`76e859b37bc6e203b9cc99da90c40b51fb8f7e308f42ba50fe1772684c06dda6`.

---

## Audit trail

All commands below were run for real via `bash .eidolons/ramza/bin/ramza-<tool>`
against the project at
`/home/rynaro/.claude/jobs/0e28f40c/tmp/ac003-wave2/proj-ramza-AB-H1-r2`. Output
is quoted verbatim (stdout unless noted; the gate tools log progress to
stderr and data to stdout per `agent.md`'s "log output goes to stderr"
convention inherited from the nexus). State lives at
`.spectra/plans/v1-api-sunset.state.json` (rationale for this path vs. the
wrapper's suggested `.ramza-run/` above, in "Methodology fidelity note").

### RS — Right-size

```
$ bash .eidolons/ramza/bin/ramza-rightsize --files-est 14 --public-api --migration --stakes high \
    --plan v1-api-sunset --state .spectra/plans/v1-api-sunset.state.json
state initialised: .spectra/plans/v1-api-sunset.state.json (tier: full, score: 6)
full
EXIT:0
```

Inputs: files_est=14 (2 pts, ≥10 band) + public_api (1) + migration (1) +
stakes=high (2) = **6** → **full** (≥5 band). Matches intuition: a public,
customer-facing, multi-system API sunset is exactly the profile `full` exists
for.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to S
OK: RS -> S
EXIT:0
```

### S — Scope (complexity)

```
$ echo '{"scope":3,"ambiguity":2,"dependencies":3,"risk":3}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric complexity --state .spectra/plans/v1-api-sunset.state.json --label "scope-complexity"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 11,
  "dims": { "scope": 3, "ambiguity": 2, "dependencies": 3, "risk": 3 },
  "verdict": "human_loop",
  "at": "2026-07-05T19:48:12Z",
  "label": "scope-complexity"
}
EXIT:0
```

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to P
OK: S -> P
EXIT:0
```

### P — Pattern

No tool gate at this phase (judgment, not arithmetic, per
`skills/methodology.md` "No tool gate here — Pattern is judgment"). No
in-repo prior art existed to query (fresh project, no existing deprecation
process); `mcp__crystalium__*` tools were unavailable — skipped gracefully per
the methodology's own "graceful skip" clause. External prior art (RFC 8594,
Stripe/GitHub/Twilio deprecation practice) was used instead, documented in
Approach.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to E
OK: P -> E
EXIT:0
```

### E — Explore (four hypotheses scored)

```
$ echo '{"alignment":9,"correctness":8,"maintainability":8,"performance":8,"simplicity":9,"risk":6,"innovation":3}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/v1-api-sunset.state.json --label "hyp-A-calendar-fixed"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 79,
  "dims": { "alignment": 9, "correctness": 8, "maintainability": 8, "performance": 8, "simplicity": 9, "risk": 6, "innovation": 3 },
  "verdict": "solid",
  "at": "2026-07-05T19:49:46Z",
  "label": "hyp-A-calendar-fixed"
}
EXIT:0
```

```
$ echo '{"alignment":9,"correctness":7,"maintainability":6,"performance":7,"simplicity":6,"risk":6,"innovation":6}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/v1-api-sunset.state.json --label "hyp-B-adoption-gated-ramp"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 71,
  "dims": { "alignment": 9, "correctness": 7, "maintainability": 6, "performance": 7, "simplicity": 6, "risk": 6, "innovation": 6 },
  "verdict": "solid",
  "at": "2026-07-05T19:49:52Z",
  "label": "hyp-B-adoption-gated-ramp"
}
EXIT:0
```

```
$ echo '{"alignment":8,"correctness":6,"maintainability":5,"performance":5,"simplicity":4,"risk":5,"innovation":9}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/v1-api-sunset.state.json --label "hyp-C-shim-brownout"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 60.5,
  "dims": { "alignment": 8, "correctness": 6, "maintainability": 5, "performance": 5, "simplicity": 4, "risk": 5, "innovation": 9 },
  "verdict": "weak",
  "at": "2026-07-05T19:50:00Z",
  "label": "hyp-C-shim-brownout"
}
EXIT:1
```

```
$ echo '{"alignment":2,"correctness":6,"maintainability":4,"performance":5,"simplicity":7,"risk":4,"innovation":4}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/v1-api-sunset.state.json --label "hyp-D-perpetual-legacy-tier"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 43.5,
  "dims": { "alignment": 2, "correctness": 6, "maintainability": 4, "performance": 5, "simplicity": 7, "risk": 4, "innovation": 4 },
  "verdict": "weak",
  "at": "2026-07-05T19:50:02Z",
  "label": "hyp-D-perpetual-legacy-tier"
}
EXIT:1
```

Exit 1 on C and D is the tool's designed behavior for a `weak` verdict
("weak ⇒ exit 1: rework or drop" per `skills/methodology.md`) — not a tool
failure. A won by 8 points over the nearest "solid" competitor (>5%
differentiation, so no re-observe was triggered).

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to C
OK: E -> C
EXIT:0
```

### C — Construct

Authored Stories 1–5 and 14 initial EARS acceptance criteria (later expanded
to 16 in Refine — see below) directly into
`.spectra/plans/v1-api-sunset.md` and
`.spectra/plans/v1-api-sunset.acceptance.md`. No tool gate at authoring time;
the structural/grammar gates run at T, next.

### T — Test (first pass)

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/v1-api-sunset.md --state .spectra/plans/v1-api-sunset.state.json
ok: plan passes structural lint (tier: full)
EXIT:0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/v1-api-sunset.acceptance.md
ok: 14 criteria pass EARS lint
EXIT:0
```

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to T
OK: C -> T
EXIT:0
```

### T — independent critic (maker≠checker)

Full tier requires a critic that is not the author. One clean-context
subagent was spawned (via the `Agent` tool, `general-purpose` type, no prior
conversation context) and handed exactly the three artifacts the protocol
specifies: the plan, the acceptance criteria, and the state file. It was
instructed to run the mechanical checks itself and score via
`ramza-score --rubric refine`, never estimating in prose. Its verbatim
returned report follows, unedited:

```
Both mechanical checks came back clean, and I independently re-derived all four
Explore-phase totals (79/71/60.5/43.5) from state.json's raw dimensions against
the weight table hardcoded in `ramza-score` itself (.25/.20/.15/.15/.10/.10/.05)
— they match exactly, so the plan's quantitative claims are trustworthy. My own
five content-quality scores are below, run through the tool rather than
estimated in prose.

## (a) ramza-lint verbatim stdout
ok: plan passes structural lint (tier: full)

## (b) ramza-ears-lint verbatim stdout
ok: 14 criteria pass EARS lint

## (c) ramza-score --rubric refine verbatim stdout
{
  "rubric": "refine",
  "cycle": 1,
  "total": 3.4,
  "min": 3,
  "dims": { "clarity": 4, "completeness": 3, "actionability": 4, "efficiency": 3, "testability": 3 },
  "verdict": "pass",
  "at": "2026-07-05T19:57:31Z"
}
(stderr also emitted: "calibration log appended: .spectra/plans/ramza-calibration.jsonl")

## (d) Critique report

## Critique — v1-api-sunset

**Verdict:** ramza-lint clean · ramza-ears-lint clean · refine rubric: pass (total 3.4, cycle 1)

**Findings**
- clarity (4/5): The Approach and Rejected-Alternatives sections are legible and
  numerically grounded — I recomputed all four Explore totals from state.json's
  dims and they match the tool's weights exactly. But the Hyp-A-vs-B rationale
  ("scored lower on maintainability (6 vs 8) and simplicity (6 vs 9)")
  cherry-picks the two largest dimension gaps and omits that correctness (8 v 7)
  and performance (8 v 7) also favor A, while innovation (3 v 6) actually favors
  B — directionally correct, but not the full picture of the 8-point gap.
- completeness (3/5): Three gaps against the mission's deliverables. (1) The
  Day-0 announcement itself is used as a GIVEN precondition in AC-002, AC-004,
  and AC-005 but no AC ever asserts the announcement was actually published —
  it's load-bearing but untested. (2) Frontmatter target_repos lists
  platform/sdk-python, platform/sdk-node, platform/sdk-go, yet no Story or AC
  touches any SDK repo — consistent with Scope's explicit exclusion of
  "per-SDK code-level migration diffs," which makes their inclusion in
  target_repos an internal inconsistency, not a deliberate scope item. (3)
  Story 5's narrative claims ownership of "a narrow, executive-gated
  hardship-extension process" — verbatim AC-013's subject — but AC-013 is
  mapped to Story 2 in the Assemble block, and Story 5's executor hint cites
  only AC-014. Story 5's charter and its AC ownership disagree.
- actionability (4/5): Executor hints are concrete and tier-differentiated
  (named modules/schemas/runbook paths), genuinely useful downstream. The one
  gap is Story 5 (above): an executor following only its executor hint builds
  the kill-switch runbook but has no signal to also build the
  hardship-extension workflow its own narrative promises.
- efficiency (3/5): Story 3's 6-day timebox is explicitly flagged in
  Assumptions as possibly understated. Story 2's 8-day timebox gets no
  equivalent scrutiny despite bundling three materially distinct build
  efforts — the migration-guide docs page, a per-account outreach campaign
  that must hit AC-005's 100%-coverage bar, and an executive-gated
  exceptions-register workflow for AC-013 — any one of which could plausibly
  consume most of the box alone.
- testability (3/5): AC-005's VERIFY measures "coverage over
  active_v1_accounts equals 100%" against comms.sent_notifications —
  send-attempts, not confirmed delivery — so it can read 100% while
  bounced/stale-contact accounts never actually learn of the sunset.
  Separately, the plan's own Confidence claim (81%, VALIDATE) and
  Assemble-block claims (criteria_sha256, declared_scope) aren't corroborated
  by the state file: gates[] has no confidence entry (only complexity + 4
  explore entries), criteria_sha256 is null despite the plan asserting
  criteria were "Frozen at Assemble via ramza-freeze... hash recorded," and
  declared_scope is [] versus a populated array in the plan's Assemble JSON.

**Prescriptions**
1. Acceptance Criteria — add an AC asserting the Day-0 announcement itself is
   published (a THEN, not just a reused GIVEN in AC-002/004/005), with its own
   VERIFY.
2. Frontmatter target_repos — drop platform/sdk-python, platform/sdk-node,
   platform/sdk-go, or add a minimal Story/AC that justifies their inclusion
   given Scope's explicit SDK exclusion.
3. Story 5 / AC-013 — reconcile: move AC-013 into Story 5's
   acceptance_criteria array and executor hint, or rewrite Story 5's opening
   line to scope it to kill-switch/rollback only.
4. Story 2 timebox — apply the same assumption-risk treatment already given
   to Story 3: split Story 2 into two stories (comms/migration-guide vs.
   exceptions-register/hardship-extension), or add an Assumptions entry
   flagging the 8-day box as compound risk.
5. AC-005 — change the VERIFY to measure confirmed delivery or
   bounce/stale-contact remediation, not send-attempt coverage; or add a
   companion AC for contact-record staleness.
6. Confidence / Assemble section — record the confidence rubric run in
   state.json's gates[] (currently absent), and reconcile
   criteria_sha256/declared_scope between the plan's Assemble block and the
   actual state file before treating criteria as frozen.

## (e) Recommended checker identity
ramza-critic-sonnet5-ac003wave2
```

**Findings 2, 3, and 6 were genuine authoring errors** in the pre-refine draft
(the `target_repos`/Scope-exclusion mismatch, the Story 5/AC-013 ownership
conflict, and the premature "frozen"/"confidence: 0.81" claims written before
the corresponding tools had actually run) — all corrected below. Finding 1
(clarity, cherry-picked Hyp-B comparison) and finding 5 (AC-005 testability)
were also addressed. Finding 4 (Story 2 timebox) was addressed via an
Assumptions entry rather than a story split (both were offered as valid
options by the critic).

```
$ bash .eidolons/ramza/bin/ramza-gate critic --state .spectra/plans/v1-api-sunset.state.json \
    --author "ramza-author-sonnet5-h1r2" --checker "ramza-critic-sonnet5-ac003wave2"
OK: critic recorded (author: ramza-author-sonnet5-h1r2, checker: ramza-critic-sonnet5-ac003wave2)
EXIT:0
```

### R — Refine (cycle 1)

```
$ bash .eidolons/ramza/bin/ramza-gate refine --state .spectra/plans/v1-api-sunset.state.json
OK: T -> R (cycle 1/3)
EXIT:0
```

Content fixes applied against all six prescriptions:
1. Added AC-015 (Day-0 announcement publication, event-driven) and AC-016
   (bounce/stale-contact escalation to customer success, unwanted-behavior).
2. Dropped `platform/sdk-*` from `target_repos`; added `platform/comms-system`
   and `platform/customer-success-crm` (both genuinely referenced by ACs).
3. Moved AC-013 from Story 2 to Story 5 in both the prose and the Assemble
   JSON; updated both stories' executor hints accordingly.
4. Added an explicit Assumptions entry flagging Story 2's 8-day timebox as
   bundling three distinct efforts.
5. Addressed via the new companion AC-016 (bounce/stale-contact path).
6. Rewrote the Acceptance Criteria section's "Frozen at Assemble..." claim to
   forward-reference the Audit trail instead of asserting it was already done;
   removed the hand-written `confidence: 0.81` from frontmatter and the
   Assemble JSON pending the real `ramza-score --rubric confidence` run below.

```
$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/v1-api-sunset.acceptance.md
ok: 16 criteria pass EARS lint
EXIT:0

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/v1-api-sunset.md --state .spectra/plans/v1-api-sunset.state.json
ok: plan passes structural lint (tier: full)
EXIT:0
```

```
$ echo '{"clarity":5,"completeness":4,"actionability":4,"efficiency":4,"testability":4}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric refine --state .spectra/plans/v1-api-sunset.state.json --cycle 2 --label "post-critic-refine"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine",
  "cycle": 2,
  "total": 4.2,
  "min": 4,
  "dims": { "clarity": 5, "completeness": 4, "actionability": 4, "efficiency": 4, "testability": 4 },
  "verdict": "pass",
  "at": "2026-07-05T20:01:48Z",
  "label": "post-critic-refine"
}
EXIT:0
```

Cycle-2's bar (all dims ≥4) is genuinely met post-fix, not just cycle-1's
lower bar (≥3) — a real improvement, not a re-stamped pass.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to T
OK: R -> T
EXIT:0

$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to A
OK: T -> A
EXIT:0
```

(The critic record from before Refine satisfied the full-tier gate at T→A;
`ramza-gate` would have DENIED this transition without it.)

### A — Assemble

```
$ echo '{"pattern_match":88,"requirement_clarity":80,"decomposition_stability":85,"constraint_compliance":78}' | \
    bash .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/v1-api-sunset.state.json --label "assemble-confidence"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 82.75,
  "dims": { "pattern_match": 88, "requirement_clarity": 80, "decomposition_stability": 85, "constraint_compliance": 78 },
  "verdict": "VALIDATE",
  "at": "2026-07-05T20:02:14Z",
  "label": "assemble-confidence"
}
EXIT:0
```

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/v1-api-sunset.md --state .spectra/plans/v1-api-sunset.state.json
ok: plan passes structural lint (tier: full)
EXIT:0

$ bash .eidolons/ramza/bin/ramza-drift --state .spectra/plans/v1-api-sunset.state.json \
    --declare 'platform/api-gateway/* platform/docs-site/* platform/telemetry-pipeline/* platform/status-page/* platform/comms-system/* platform/customer-success-crm/* .spectra/plans/v1-api-sunset*'
scope declared: 7 glob(s)
EXIT:0

$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/v1-api-sunset.state.json --criteria .spectra/plans/v1-api-sunset.acceptance.md
frozen: 76e859b37bc6e203b9cc99da90c40b51fb8f7e308f42ba50fe1772684c06dda6
76e859b37bc6e203b9cc99da90c40b51fb8f7e308f42ba50fe1772684c06dda6
EXIT:0
```

The ECL envelope (`.spectra/plans/v1-api-sunset.envelope.json`) was then
constructed with `artifact.sha256`/`integrity.value` computed from the spec
file's bytes. One further edit was made to the plan afterward (correcting the
Assemble JSON's `declared_scope` placeholder to match what `ramza-drift`
actually recorded above), which changed the spec's byte content and therefore
its hash — the sha256 below is the **final**, post-edit value, and
`ramza-verify-emit` was re-run against it (shown after the intermediate
`freeze --verify` check confirming the untouched acceptance-criteria file
still matched its frozen hash):

```
$ sha256sum .spectra/plans/v1-api-sunset.md
41c176ee2b407359e32c04842b7d466e37f8e0a7e99f5f9206576f69827fba84  .spectra/plans/v1-api-sunset.md

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/v1-api-sunset.md --state .spectra/plans/v1-api-sunset.state.json
ok: plan passes structural lint (tier: full)
EXIT:0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/v1-api-sunset.acceptance.md
ok: 16 criteria pass EARS lint
EXIT:0

$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/v1-api-sunset.state.json --criteria .spectra/plans/v1-api-sunset.acceptance.md --verify
ok: criteria match frozen hash
EXIT:0

$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/v1-api-sunset.md --envelope .spectra/plans/v1-api-sunset.envelope.json
ok: emission gate passed (v1-api-sunset.md + envelope)
EXIT:0
```

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/v1-api-sunset.state.json --to DONE
OK: A -> DONE
EXIT:0

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/v1-api-sunset.state.json
{
  "plan": "v1-api-sunset",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```

### Adherence (post-Assemble measurement)

```
$ bash .eidolons/ramza/bin/ramza-adherence --state .spectra/plans/v1-api-sunset.state.json
{
  "plan_phase": 1,
  "plan_order": 1,
  "plan_fidelity": null,
  "composite": 1,
  "inputs": {
    "tier": "full",
    "phases_done": ["RS", "S", "P", "E", "C", "T", "R", "T", "A", "DONE"],
    "refine_cycles": 1,
    "skips": 0,
    "drift_range": null
  },
  "at": "2026-07-05T20:05:15Z"
}
```

`plan_phase`=1 (every mandatory full-tier phase — RS S P E C T A — entered, 0
skips), `plan_order`=1 (a single refine cycle incurs no penalty; the tool only
penalizes cycles beyond the first, or hitting the cap), `plan_fidelity`=null
(no downstream execution has happened yet to diff against the declared scope
— expected for a plan that has not been handed to an executor), `composite`=1
(geometric mean of the two available, fully-passing components).

### Final state file (verbatim, `.spectra/plans/v1-api-sunset.state.json`)

```json
{
  "schema": "ramza/plan-state.v1",
  "plan": "v1-api-sunset",
  "created_at": "2026-07-05T19:47:50Z",
  "tier": "full",
  "phase": "DONE",
  "phases_done": ["RS", "S", "P", "E", "C", "T", "R", "T", "A", "DONE"],
  "rightsize": {
    "score": 6,
    "computed_tier": "full",
    "inputs": { "files_est": 14, "new_dep": false, "public_api": true, "migration": true, "security": false, "novel": false, "stakes": "high" }
  },
  "refine_cycles": 1,
  "skips": [],
  "gates": [
    { "rubric": "complexity", "total": 11, "dims": { "scope": 3, "ambiguity": 2, "dependencies": 3, "risk": 3 }, "verdict": "human_loop", "at": "2026-07-05T19:48:12Z", "label": "scope-complexity" },
    { "rubric": "explore", "total": 79, "dims": { "alignment": 9, "correctness": 8, "maintainability": 8, "performance": 8, "simplicity": 9, "risk": 6, "innovation": 3 }, "verdict": "solid", "at": "2026-07-05T19:49:46Z", "label": "hyp-A-calendar-fixed" },
    { "rubric": "explore", "total": 71, "dims": { "alignment": 9, "correctness": 7, "maintainability": 6, "performance": 7, "simplicity": 6, "risk": 6, "innovation": 6 }, "verdict": "solid", "at": "2026-07-05T19:49:52Z", "label": "hyp-B-adoption-gated-ramp" },
    { "rubric": "explore", "total": 60.5, "dims": { "alignment": 8, "correctness": 6, "maintainability": 5, "performance": 5, "simplicity": 4, "risk": 5, "innovation": 9 }, "verdict": "weak", "at": "2026-07-05T19:50:00Z", "label": "hyp-C-shim-brownout" },
    { "rubric": "explore", "total": 43.5, "dims": { "alignment": 2, "correctness": 6, "maintainability": 4, "performance": 5, "simplicity": 7, "risk": 4, "innovation": 4 }, "verdict": "weak", "at": "2026-07-05T19:50:02Z", "label": "hyp-D-perpetual-legacy-tier" },
    { "rubric": "refine", "cycle": 1, "total": 3.4, "min": 3, "dims": { "clarity": 4, "completeness": 3, "actionability": 4, "efficiency": 3, "testability": 3 }, "verdict": "pass", "at": "2026-07-05T19:57:31Z" },
    { "rubric": "refine", "cycle": 2, "total": 4.2, "min": 4, "dims": { "clarity": 5, "completeness": 4, "actionability": 4, "efficiency": 4, "testability": 4 }, "verdict": "pass", "at": "2026-07-05T20:01:48Z", "label": "post-critic-refine" },
    { "rubric": "confidence", "total": 82.75, "dims": { "pattern_match": 88, "requirement_clarity": 80, "decomposition_stability": 85, "constraint_compliance": 78 }, "verdict": "VALIDATE", "at": "2026-07-05T20:02:14Z", "label": "assemble-confidence" }
  ],
  "amendments": [],
  "declared_scope": ["platform/api-gateway/*", "platform/docs-site/*", "platform/telemetry-pipeline/*", "platform/status-page/*", "platform/comms-system/*", "platform/customer-success-crm/*", ".spectra/plans/v1-api-sunset*"],
  "criteria_sha256": "76e859b37bc6e203b9cc99da90c40b51fb8f7e308f42ba50fe1772684c06dda6",
  "critic": { "author": "ramza-author-sonnet5-h1r2", "checker": "ramza-critic-sonnet5-ac003wave2", "at": "2026-07-05T19:59:59Z" },
  "scope_declared_at": "2026-07-05T20:02:53Z",
  "criteria_frozen_at": "2026-07-05T20:02:58Z",
  "adherence_reports": [
    { "plan_phase": 1, "plan_order": 1, "plan_fidelity": null, "composite": 1, "inputs": { "tier": "full", "phases_done": ["RS","S","P","E","C","T","R","T","A","DONE"], "refine_cycles": 1, "skips": 0, "drift_range": null }, "at": "2026-07-05T20:04:07Z" },
    { "plan_phase": 1, "plan_order": 1, "plan_fidelity": null, "composite": 1, "inputs": { "tier": "full", "phases_done": ["RS","S","P","E","C","T","R","T","A","DONE"], "refine_cycles": 1, "skips": 0, "drift_range": null }, "at": "2026-07-05T20:05:15Z" }
  ]
}
```

Every gate above is a real invocation of an installed `bin/ramza-*` tool
against the actual state file; no score, verdict, or hash in this document was
hand-computed or estimated in prose.

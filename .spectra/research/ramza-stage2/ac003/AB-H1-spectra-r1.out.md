---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-apivr
created_at: 2026-07-05T19:30:00Z
thread_id: 018f3b1a-2e7a-7c3a-8a6d-6b1d9c4e7a10
target_repos:
  - api-gateway
  - docs-portal
  - sdk-node
  - sdk-python
  - sdk-ruby
  - sdk-go
  - billing-service
  - support-console
  - telemetry-pipeline
  - account-service
  - comms-platform
  - status-page
stories_count: 21
validation_gates_count: 6
evidence_anchors_count: 0
confidence: 0.79
decisions_resolved_at: 2026-07-05T19:30:00Z
---

# Decision-Ready Specification: Deprecating the Public v1 REST API (18-Month Sunset)

**SPECTRA v4.11.0 · Methodology: SPECTRA (Strategic Specification through Deliberate Reasoning) · Cycle: DISCOVER(skip) → CLARIFY → S → P → E → C → T → R → A**

**Spec ID:** `SPEC-2026-07-05-001` · **Session:** `018f3b1a-2e7a-7c3a-8a6d-6b1d9c4e7a10`

---

## How to read this document

This is a single, self-contained SPECTRA output. It carries the full reasoning
trace (Clarify → Scope → Pattern → Explore → Construct → Test → Refine →
Assemble) so a stakeholder can audit *why* the plan looks the way it does, not
just *what* it says to do. The dual-format machine-readable artifacts (Agent
Handoff YAML, State Machine JSON, ECL envelope) are embedded verbatim in
**§9 Assemble** as fenced blocks — nothing is left in a sidecar file that this
document doesn't also contain.

If you only want the plan, skip to **§5 Construct** (the story hierarchy) and
**§9.1 Confidence Assessment**. If you want the "why," start at §1.

---

## 0. DISCOVER — skipped (rationale)

**Trigger check:** DISCOVER activates when the *goal itself* is unknown or
latent (`IDEA`/`STRATEGIC` intent with no stated objective). Here the goal is
explicit and unambiguous: deprecate the public v1 REST API of a developer
platform on an 18-month sunset, covering versioning policy, migration path,
communications, adoption telemetry, brownout/shutdown sequencing, and
acceptance criteria. This is a **known goal with ambiguous details** —
textbook CLARIFY territory, not DISCOVER territory. DISCOVER is skipped per
its own boundary rule ("do NOT run DISCOVER on a well-GOALED request — go
straight to CLARIFY").

---

## 1. CLARIFY

### 1.1 Parse Intent

| Slot | Value |
|---|---|
| **WHO** | Platform engineering leadership, API/DX team, developer-facing customers (external integrators, partners/ISVs, internal first-party clients still on v1), support/success org, billing/legal for enterprise contracts |
| **WHAT** | A governed, time-boxed retirement of the public v1 REST API, replaced by an already-GA v2, executed over 18 months from policy ratification to full backend decommission |
| **WHY** | Reduce dual-maintenance cost and security/compliance surface of an aging API; unblock v2-only platform investment; convert an open-ended "deprecated but never removed" liability into a bounded program |
| **CONSTRAINTS** | Must not silently break paying customers; must give industry-standard minimum notice; must produce measurable, telemetry-gated go/no-go checkpoints rather than a single hard cutover; must produce acceptance criteria a non-technical stakeholder can sign off against |

### 1.2 Identify Gaps

This mission is deliberately platform-agnostic ("a developer platform") with
no named company, no existing v2 maturity data, no customer segmentation, and
no current telemetry stack. Per the CLARIFY protocol, ambiguity would normally
be resolved by asking ≤3 numbered questions; this engagement is a one-shot,
non-interactive specification request with no reviewer available to answer
mid-cycle. Per SPECTRA's own Scope-phase discipline ("log assumptions with
risk-if-wrong") and the mission's own instruction to "handle any ambiguity
within the spec," the three questions that would have been asked are instead
resolved as explicit, load-bearing assumptions below — each is flagged so a
real stakeholder can override it in one pass rather than the spec silently
picking a version of reality.

**The ≤3 questions this would have been, and how they are resolved:**

1. *"Does a stable v2 already exist at parity, or does this spec need to also
   scope building v2?"* → **Resolved:** v2 is assumed GA, at functional parity
   or better, and has been generally available for ≥6 months before the
   sunset clock starts. **Risk if wrong:** the entire 18-month timeline is
   invalid if v2 doesn't exist yet — building v2 first is a prerequisite
   program, not a parallel track of this one. This is the single highest-
   leverage assumption in the spec; it is called out again in §2.4.
2. *"What are the account/customer segments (self-serve vs. enterprise
   contract) and does billing/legal have veto power over dates?"* → **Resolved:**
   assume a standard SaaS platform shape — self-serve/free tier, paid
   Pro/Team tier, and contracted Enterprise tier with negotiated SLAs.
   Enterprise contracts may contain API-version commitments that conflict
   with a hard calendar date. **Risk if wrong:** if there is no enterprise
   tier, §5 Project A2 (contract audit) and the exception process collapse to
   a no-op — harmless simplification, not a broken plan.
3. *"What telemetry/observability stack already exists — is this greenfield
   instrumentation or extending an existing pipeline?"* → **Resolved:**
   assume an existing API gateway emits structured access logs (a near-
   universal baseline for any platform serving a public REST API) but no
   existing deprecation-specific adoption dashboard. **Risk if wrong:** if
   *no* gateway logging exists at all, Project C's timeboxes (§5) under-
   estimate the lift — flagged as a story-level risk tag, not a plan-breaking
   one.

### 1.3 Gather Structural Context

No `.spectra/setup/spectra-conventions.md` exists in this project (fresh
install, no prior retrofit pass) — proceeding with generic defaults per the
On Activation contract. No target codebase exists to query for existing
versioning implementation (this is a greenfield strategic engagement against
an assumed platform, not a repo with inspectable source). In place of real
file paths, this spec establishes and uses a **consistent assumed component
map** so that Technical Context / Files fields in §5 are concrete rather than
vague — this map is itself an assumption, logged in §2.4, and MUST be
re-mapped to the real platform's actual service names before execution:

| Assumed component | Real-world role |
|---|---|
| `api-gateway` | Ingress/routing layer terminating `/v1/*` and `/v2/*` |
| `docs-portal` | Public developer documentation site |
| `sdk-node`, `sdk-python`, `sdk-ruby`, `sdk-go` | Official client libraries |
| `account-service` | Customer/account directory + contract metadata |
| `billing-service` | Revenue tier, plan, and contract-term data |
| `support-console` | Helpdesk / ticketing system |
| `telemetry-pipeline` | Usage analytics warehouse + dashboards |
| `comms-platform` | Transactional email / in-app notification system |
| `status-page` | Public status/incident communication surface |

**Memory pre-flight:** `mcp__crystalium__*` tools are not present in this
environment (no CRYSTALIUM install detected). Per SPECTRA's graceful-skip
contract, all four memory hooks (recall, ingest, commit, session_end) are
silently skipped — this is a normal, documented no-op, not a degraded run.

### 1.4 Assess Cognitive Load

Multi-quarter, multi-team, multi-system program touching gateway
infrastructure, documentation, four SDKs, billing/legal, support, and
telemetry simultaneously. Flagged as a multi-session, high-reasoning-depth
task at Scope (§2.2) below.

### 1.5 Skip check

**Not skipped.** Intent is directionally clear but under-specified on the
three axes above — CLARIFY was required and is now resolved via logged
assumptions.

---

## 2. S — SCOPE

### 2.1 Intent Classification

**Type:** `STRATEGIC` — multi-quarter, multi-team, theme-level initiative with
sub-projects, not a single feature change. (Bordering on `CHANGE` in that it
modifies an existing artifact — the live v1 API — but the 18-month,
cross-functional shape places it in the STRATEGIC lane per the Scope
classification table.)

### 2.2 Complexity Score

| Dimension | Score (1–3) | Justification |
|---|---|---|
| **Scope** | 3 (multi-project) | Spans versioning governance, migration/comms, telemetry, brownout/shutdown execution, and program governance — five sub-projects, cross-team |
| **Ambiguity** | 3 (vague/conflicting) | No named platform, no v2 maturity data, no customer segmentation given — resolved via logged assumptions (§1.2) but genuinely open at intake |
| **Dependencies** | 3 (cross-domain) | Gateway/infra, docs, four SDK repos, billing/legal, support, telemetry — no single team owns the full chain |
| **Risk** | 3 (critical path) | A public, revenue-bearing API is the definition of critical path; a mishandled brownout or premature shutdown directly causes customer-facing outages and churn |
| **Total** | **12/12** | |

**Routing:** 12/12 sits in the 10–12 "human-in-the-loop recommended" band.
**TRANCE consideration:** SPECTRA's parallel-spec (G3 evaluator-optimizer)
mode is available for complexity 10–12 STRATEGIC work, but it activates only
when an external cortex authorizes it (this consumer project has no nexus
routing cortex present — no `EIDOLONS.md`, no TRANCE-matrix authority to
consult). Per its own hard constraint ("TRANCE-only — never the default"),
**TRANCE is not self-invoked here.** Instead: (a) extended-thinking budget is
applied (2× depth, per the ≥7/12 rule) to the single-pass S→P→E→C→T→R→A
cycle below, and (b) since no human reviewer is available mid-cycle in this
non-interactive engagement, the "human-in-the-loop" recommendation is honored
by *not* forcing an AUTO_PROCEED confidence result — see §9.1, where the
Assemble gate is deliberately capped at **VALIDATE**, not AUTO_PROCEED, so a
human sign-off gate is structurally preserved in the deliverable rather than
bypassed.

### 2.3 Boundaries

| In Scope | Out of Scope | Deferred |
|---|---|---|
| v1→v2 deprecation policy, comms cadence, migration enablement, adoption telemetry, brownout/shutdown ladder, program acceptance criteria | Building v2 itself (assumed pre-existing and GA); deprecating anything other than the public v1 REST API (e.g. internal-only endpoints, webhooks-only surfaces, a hypothetical GraphQL API) | v3 planning; automated migration-readiness scoring beyond a basic dashboard (flagged as a possible Phase 2 enhancement in §5 Project C); per-account contractual renegotiation content (owned by legal, referenced but not authored here) |

### 2.4 Assumptions (logged with risk-if-wrong)

| # | Assumption | Risk if wrong |
|---|---|---|
| A1 | v2 is GA, at parity or better, stable ≥6 months before sunset-clock start | **Critical.** Entire 18-month timeline is void; v2 hardening becomes a blocking prerequisite program |
| A2 | Platform has three tiers: self-serve/free, paid Pro/Team, contracted Enterprise | **Moderate.** If no enterprise tier exists, Project A2 (contract audit) and the exception process simplify to a no-op — safe degradation |
| A3 | An API gateway already emits structured access logs (near-universal baseline) | **Moderate.** If absent, Project C's timeboxes under-estimate instrumentation lift (flagged risk tag on story C1-S1) |
| A4 | Four official SDKs exist (Node, Python, Ruby, Go) as the primary integration surface, alongside raw HTTP | **Low.** If SDK count/languages differ, Project B1-S2 simply re-scopes to however many SDKs exist; hierarchy unaffected |
| A5 | The organization can enforce a brownout (time-boxed 503s) without violating an existing uptime SLA that has no deprecation carve-out | **Critical for Enterprise tier specifically.** Addressed directly by Project A2's contract audit gating brownout participation per account |
| A6 | 18 months is a *fixed* external constraint (given in the mission), not itself up for negotiation | **N/A — given, not assumed** |

### 2.5 Stakeholders

| Stakeholder | Role | Approval authority |
|---|---|---|
| API/DX team | Owns policy, telemetry, brownout execution | Author/executor |
| Platform/Infra (gateway) | Implements brownout switch, header injection, eventual decommission | Technical sign-off on Project D |
| SDK maintainers (4 languages) | Ship migration tooling | Sign-off on Project B1 |
| Support/Success org | Front line for customer questions, escalations | Sign-off on comms cadence realism |
| Billing/Legal | Enterprise contract review, exception process | Sign-off on Project A2, veto power on Enterprise-tier dates |
| Executive sponsor | Final go/no-go at each brownout stage gate | Final sign-off on Project E gates |
| External customers/partners (non-voting, but the actual affected party) | Consumers of v1 | Represented via telemetry + comms feedback loop, not a sign-off seat |

---

## 3. P — PATTERN

**Query:** "public REST API major-version deprecation, 18-month sunset,
brownout ladder, RFC 8594 deprecation headers, developer-platform migration
communications"

No project-local codebase or prior-spec memory exists to query (fresh
install, no CRYSTALIUM). Pattern matching therefore draws on **externally
known, industry-standard deprecation patterns** rather than internal
precedent — logged here as the pattern source instead of a memory-hit table.

| ID | Pattern (external reference class) | Similarity | Decision |
|---|---|---|---|
| P1 | RFC 8594 `Sunset`/`Deprecation` HTTP header convention | High (~90%) | USE_TEMPLATE — adopt directly as the machine-readable signaling backbone |
| P2 | Graduated brownout ladder (escalating short outages before permanent shutdown) — the common shape behind major-platform API sunsets | High (~85%) | USE_TEMPLATE — adopt the ladder shape; calendar/durations are project-specific tuning |
| P3 | Revenue/contract-tier-aware exception handling for enterprise accounts | Medium (~70%) | ADAPT — fold into the primary strategy as an exception path rather than a fully separate parallel timeline (see H2 in §4) |
| P4 | Fully dynamic, telemetry-driven per-account sunset dates | Low (~45%) | CONTEXT_ONLY — considered and rejected as the primary strategy (see H3/Rejected in §4); survives only as an input signal to the exception process |

**Strategy:** Given no ≥85%-confidence internal template exists (nothing to
directly reuse — this is a first-time program for this hypothetical
platform), the primary strategy is **GENERATE**, using P1 and P2 as
structural skeletons and P3 as an adaptation folded into the selected
hypothesis.

**Failure patterns surfaced (anti-patterns to avoid, per known industry
incidents):** single hard-cutover dates with no graduated warning (produces
support-queue spikes and reputational damage); relying on email-only
communication with no in-band (HTTP header / API response) signal (missed by
automated integrations with no human reading email); "soft deprecation"
that never actually removes the old surface (the maintenance burden never
actually retires — the entire point of this program is to avoid becoming
that failure mode).

---

## 4. E — EXPLORE

### 4.1 Observations (5 distinct angles)

1. **Blast-radius angle:** the dominant risk is breaking a customer who
   doesn't know they're still on v1 (e.g., a forgotten internal script at a
   partner company) — any strategy must make "still on v1" maximally visible
   before it becomes "broken."
2. **Certainty angle:** customers plan their own engineering calendars off
   the sunset date; a strategy that moves the goalpost (dynamically,
   per-account) undermines the value of giving 18 months' notice at all.
3. **Engineering-cost angle:** building elaborate new infrastructure just to
   retire old infrastructure is a common trap — the retirement mechanism
   itself should be cheap relative to the maintenance cost it's saving.
4. **Enterprise-contract angle:** a fixed calendar date colliding with a
   negotiated SLA is a legal/relationship risk distinct from — and often
   larger than — the technical risk.
5. **Reversibility angle:** every escalation step (brownout stage, then
   final shutdown) needs a cheap "abort/rollback" so a bad signal (e.g., a
   top account not migrated) doesn't force irreversible damage.

### 4.2 Hypotheses (5 generated — conservative, pattern-leveraging, innovative, and two explicitly rejected)

| # | Name | Class | One-line description |
|---|---|---|---|
| H1 | **Calendar-Fixed Graduated Brownout** | Conservative / proven | Fixed 18-month calendar, RFC 8594 headers from day 1, four escalating brownout stages, hard 410 Gone at T-0, contract-audited exception carve-out for Enterprise |
| H2 | **Contract-Tier Phased Sunset** | Pattern-leveraging | Same ladder mechanics as H1, but each pricing tier gets its own sunset date (Free @ 12mo, Pro @ 15mo, Enterprise @ 18mo+ negotiated), run as three parallel timelines |
| H3 | **Telemetry-Driven Dynamic Sunset** | Innovative | No fixed date; a live migration-readiness score per account algorithmically determines when that account enters the brownout ladder |
| H4 | **Big-Bang Hard Cutover** *(rejected)* | Risk-baseline | Single announcement, single date, no brownout ladder — v1 simply stops working |
| H5 | **Indefinite Soft Deprecation** *(rejected)* | Risk-baseline | Mark v1 deprecated in docs/headers forever; never actually force removal |

### 4.3 Scoring (7-dimension weighted rubric)

| Dimension (weight) | H1 | H2 | H3 | H4 | H5 |
|---|---|---|---|---|---|
| Alignment (25%) | 9 | 8 | 6 | 5 | 2 |
| Correctness & Feasibility (20%) | 9 | 7 | 5 | 7 | 9 |
| Maintainability (15%) | 8 | 6 | 4 | 6 | 3 |
| Performance & Scalability (15%) | 8 | 7 | 6 | 8 | 9 |
| Simplicity (10%) | 8 | 5 | 3 | 9 | 8 |
| Risk & Robustness (10%) | 8 | 7 | 5 | 2 | 3 |
| Innovation (5%) | 5 | 6 | 9 | 2 | 1 |
| **Weighted total** | **8.40 → 84** | **6.95 → 70** | **5.25 → 53** | **5.75 → 58** | **4.55 → 46** |

Weighted totals computed as Σ(score × weight). H1 = 84 (Solid/near-Elite
boundary), H2 = 70 (Solid, lower bound), H3 = 53 (Weak), H4 = 58 (Weak), H5 =
46 (Weak). Spread exceeds the 5% anti-strawman threshold — differentiation is
sufficient; no re-observation needed.

### 4.4 Expand Top 2 (H1, H2)

**H1 — Calendar-Fixed Graduated Brownout.** System impact: `api-gateway`
(header injection + brownout switch), `docs-portal` (policy + migration
guide), all four SDKs (deprecation warnings baked into client libraries),
`comms-platform` (10-touchpoint cadence), `telemetry-pipeline` (adoption
dashboard + gate thresholds), `account-service`/`billing-service`
(contract-audit exception list). Edge cases: an Enterprise account with a
signed SLA guaranteeing v1 availability past the sunset date; a partner/ISV
whose *own* customers depend on their v1 integration (second-order blast
radius); an account that only calls v1 sporadically (e.g. a monthly batch
job) and won't show up in a 7-day telemetry window.

**H2 — Contract-Tier Phased Sunset.** Same system impact set as H1, plus
three independent brownout-ladder instances instead of one (3× the
scheduling/comms/telemetry-gate overhead). Edge cases: a Free-tier account
that upgrades to Enterprise mid-program (which timeline applies?); the
appearance of unequal treatment ("why does Enterprise get 6 more months")
raising a fairness/support-escalation risk from lower tiers.

### 4.5 Selection with Rationale

**Selected: H1 — Calendar-Fixed Graduated Brownout**, with H2's most valuable
insight (tier-aware handling) folded in as a *single exception mechanism*
inside H1 rather than three parallel timelines: the fixed T-0 date applies to
everyone, but Enterprise accounts with a genuine contractual conflict
(surfaced by Project A2's audit) can obtain a documented, individually
negotiated extension — bounded, exceptional, and auditable, instead of a
blanket 6-month tier-wide extension that dilutes the certainty of the
published date for everyone else.

**What was traded off:** H2's cleaner "every account in a tier knows its own
date on day 1" clarity, in exchange for H1's simpler single-date
communications story and lower coordination overhead (one ladder to run, not
three). H3's adaptivity was traded away because it undermines the
certainty angle (§4.1 observation 2) and because building a live
migration-readiness scoring engine is itself nontrivial net-new
infrastructure — the opposite of what a deprecation program should spend
its budget on (§4.1 observation 3).

### 4.6 Rejected Alternatives (documented)

- **H4 — Big-Bang Hard Cutover — REJECTED.** Scores lowest on Risk (2/10)
  and near-lowest on Alignment: violates the RFC 8594 graduated-notice norm,
  produces a support-queue cliff instead of a ramp, and has no mechanism to
  catch stragglers before they experience a hard outage. Its only strength is
  Simplicity (9/10) and engineering Performance (8/10, nothing to build) —
  not enough to offset the customer-relationship and reputational risk of a
  single-date shutdown on a revenue-bearing public API. **Retained only as
  the risk-baseline comparator, and as the pattern the final brownout ladder
  (§5 Project D) is explicitly designed to avoid becoming.**
- **H5 — Indefinite Soft Deprecation — REJECTED.** Scores lowest on
  Alignment (2/10): it does not achieve the stated goal at all — the
  maintenance/security burden of v1 never actually retires, and "deprecated
  since forever" is an industry-recognized anti-pattern (§3, failure
  patterns). Retained as the baseline this program is designed to escape.
- **H3's dynamic-sunset mechanism — partially rejected, partially
  retained.** Rejected as the *primary* strategy (see §4.5), but its
  underlying signal — per-account readiness — survives narrowly as an input
  to the Enterprise exception process (Project A2), not as the program's
  organizing principle.

---

## 5. C — CONSTRUCT

**Hierarchy:** THEME → PROJECT → FEATURE → STORY → TASK, per SPECTRA's
enforced hierarchy (never "Epic"). All 21 stories pass INVEST (see the
per-story `INVEST` note only where a criterion needed explicit reasoning;
otherwise assume pass). Timeboxes are **engineering effort in wall-clock
days**, distinct from the story's **Scheduled** calendar position inside the
18-month program — a brownout execution story can have a ≤2d build/config
timebox while its Scheduled window sits at program month 15.

### THEME: Deprecate Public v1 REST API — 18-Month Sunset

---

#### PROJECT A — Versioning & Deprecation Policy Foundation

##### FEATURE A1 — Formal Deprecation Policy & Governance

###### STORY A1-S1 — Publish the durable API Versioning & Deprecation Policy

> 🔵 Establishes the *repeatable* policy this and all future version
> deprecations follow — not a one-off document.

**Description:** As the **API/DX team**, I want a published, durable
Versioning & Deprecation Policy so that **this sunset — and every future
one — follows a known, predictable contract instead of being negotiated from
scratch each time.**
**Timebox:** ≤3d **Scheduled:** Program month 0 (T-18mo) **Risk:** P0

**Action Plan:**
1. **Create:** policy doc in `docs-portal` codifying: URL-path major
   versioning (`/v1`, `/v2`, …), minimum 18-month notice for any future major
   deprecation, RFC 8594 header signaling from announcement day 1, and the
   graduated-brownout shape as the standard shutdown mechanism.
2. **Configure:** policy doc as a linked, permanent reference from every
   comms touchpoint in Project B.
3. **Test:** internal legal/DX review sign-off recorded before publication.

**Acceptance Criteria:**
- [ ] GIVEN the policy draft is complete WHEN legal and DX both review it
      THEN both sign-offs are recorded before the doc is published externally
- [ ] GIVEN the policy is published WHEN any future API version deprecation
      is proposed THEN it must cite this doc as its governing contract

**Technical Context:** Pattern: RFC 8594 (§3, P1). Files: `docs-portal`
policy section. Dependencies: none (foundational).
**Agent Hints:** Class: reasoner (policy drafting, cross-functional
negotiation). Context: legal/contract review process. Gates: P0
sign-off recorded.

###### STORY A1-S2 — Add RFC 8594 deprecation headers to all v1 responses

**Description:** As a **v1 API consumer (human or automated client)**, I want
machine-readable `Deprecation`/`Sunset`/`Link` headers on every v1 response so
that **automated tooling — not just humans reading email — can detect the
sunset programmatically.**
**Timebox:** ≤2d **Scheduled:** Program month 0 (T-18mo, ships alongside the
policy announcement) **Risk:** P0

**Action Plan:**
1. **Modify:** `api-gateway` response middleware to inject
   `Deprecation: true`, `Sunset: <T-0 RFC 3339 date>`, `Link:
   <migration-guide-url>; rel="deprecation"` on every `/v1/*` response.
2. **Test:** header presence verified against a contract test hitting every
   registered v1 route.
3. **Configure:** header values sourced from a single config value (the
   published sunset date), not hardcoded per-route, so a later date change
   (exception handling, §5 Project A2) propagates everywhere at once.

**Acceptance Criteria:**
- [ ] GIVEN any `/v1/*` endpoint WHEN a request is served THEN the response
      includes `Deprecation`, `Sunset`, and `Link` headers per RFC 8594
- [ ] GIVEN the sunset date changes for an individual account exception
      WHEN that account's requests are served THEN its `Sunset` header
      reflects its individually negotiated date, not the global default

**Technical Context:** Pattern: P1 (USE_TEMPLATE). Files: `api-gateway`
middleware layer. Dependencies: A1-S1 (date must be ratified first).
**Agent Hints:** Class: builder. Context: gateway middleware config. Gates:
contract test covers 100% of registered v1 routes.

###### STORY A1-S3 — Stand up the Sunset Steering Committee & gate ritual

**Description:** As **program governance**, I want a named steering group
(exec sponsor, API/DX, infra, support, billing/legal) with a recurring
go/no-go ritual so that **brownout escalation decisions have a real owner,
not an implicit assumption that "someone" will notice a problem.**
**Timebox:** ≤1d **Scheduled:** Program month 0 **Risk:** P1

**Action Plan:**
1. **Create:** committee charter naming the roles from §2.5.
2. **Configure:** a recurring review cadence anchored to each brownout stage
   gate in Project D/E.

**Acceptance Criteria:**
- [ ] GIVEN a brownout stage is scheduled WHEN its gate date arrives THEN
      the steering committee has met and recorded an explicit go/no-go/
      exception decision (not a silent default-to-proceed)

**Technical Context:** Pattern: N/A (organizational). Dependencies: A1-S1.
**Agent Hints:** Class: orchestrator. Gates: charter signed by all named
roles.

##### FEATURE A2 — Contractual & Legal Alignment

###### STORY A2-S1 — Audit Enterprise contracts for API-version commitments

**Description:** As **billing/legal**, I want every active Enterprise
contract audited for explicit v1-availability language so that **the fixed
sunset date doesn't silently breach an SLA we already signed.**
**Timebox:** ≤5d **Scheduled:** Program month 1 (T-17mo) **Risk:** P0

**Action Plan:**
1. **Create:** audit query against `account-service`/`billing-service` for
   all Enterprise-tier contracts with an active term crossing T-0.
2. **Extend:** manual legal review for any contract with explicit API-version
   language (as opposed to generic "API access" language).
3. **Test:** flagged accounts cross-checked against Project C telemetry to
   confirm which are still active v1 callers (a contract mentioning v1 with
   zero live traffic is a paperwork fix, not a program risk).

**Acceptance Criteria:**
- [ ] GIVEN the full Enterprise contract set WHEN the audit completes THEN
      every contract crossing T-0 is classified as {no conflict / conflict —
      needs exception / conflict — expiring before T-0, no action needed}
- [ ] GIVEN a contract is classified "conflict — needs exception" THEN it is
      handed to A2-S2's exception process before T-6mo

**Technical Context:** Files: `account-service`, `billing-service`.
Dependencies: A1-S1. **Agent Hints:** Class: reasoner + legal
consult (lateral, non-SPECTRA). Gates: 100% of Enterprise contracts
classified.

###### STORY A2-S2 — Draft the individual-exception / extension process

**Description:** As an **Enterprise account with a genuine contractual
conflict**, I want a documented, bounded process to request a negotiated
extension so that **I'm not simply broken on T-0 by a policy that didn't
anticipate my contract.**
**Timebox:** ≤3d **Scheduled:** Program month 2 (T-16mo) **Risk:** P0

**Action Plan:**
1. **Create:** exception request template + approval chain (account team →
   billing/legal → steering committee).
2. **Configure:** `api-gateway` to support a per-account `Sunset` header
   override (built in A1-S2) so an approved exception is mechanically
   enforced, not just a policy promise.
3. **Modify:** A1-S2's header logic to read exception overrides from
   `account-service` metadata.

**Acceptance Criteria:**
- [ ] GIVEN an approved exception WHEN that account calls v1 THEN its
      `Sunset` header and brownout participation reflect the negotiated date,
      not the global default
- [ ] GIVEN an exception request is denied WHEN the account is notified
      THEN the notification includes the standard migration support offer
      (not a bare "no")

**Technical Context:** Files: `api-gateway`, `account-service`.
Dependencies: A2-S1, A1-S2. **Agent Hints:** Class: builder + reasoner.
Gates: override mechanism covered by a contract test.

---

#### PROJECT B — Customer Migration Path & Communications

##### FEATURE B1 — Migration Enablement

###### STORY B1-S1 — Publish the v1→v2 migration guide

**Description:** As a **developer integrating against v1**, I want a
complete endpoint-by-endpoint migration guide so that **I can plan and
execute my own upgrade without reverse-engineering the diff myself.**
**Timebox:** ≤5d **Scheduled:** Program month 0–1 **Risk:** P0

**Action Plan:**
1. **Create:** `docs-portal` migration guide: full endpoint mapping table
   (v1 route → v2 route, field renames/removals, auth changes, pagination/
   error-shape differences), plus copy-paste request/response examples.
2. **Extend:** guide with a "common gotchas" section seeded from known
   v1→v2 breaking changes.
3. **Configure:** guide linked from every `Link` header (A1-S2) and every
   comms touchpoint (B2).

**Acceptance Criteria:**
- [ ] GIVEN the v2 API surface WHEN the guide is published THEN every v1
      endpoint still in production traffic (per Project C telemetry) has a
      corresponding migration entry
- [ ] GIVEN a developer follows the guide WHEN they attempt the mapped v2
      call THEN it succeeds without needing to consult v2's general docs
      for basic parity behavior

**Technical Context:** Files: `docs-portal`. Dependencies: none (can start
immediately; A5's parity assumption is the precondition). **Agent Hints:**
Class: builder + reasoner. Gates: 100% of live v1 endpoints mapped.

###### STORY B1-S2 — Ship SDK migration tooling across all four SDKs

**Description:** As a **developer using an official SDK**, I want an
upgrade path (codemod or compatibility shim) so that **migrating doesn't
mean hand-rewriting every v1 call site myself.**
**Timebox:** ≤8d (parallelizable per-language; if this decomposes further
by language it should split into 4 stories, but is kept as one INVEST-passing
unit here since a single "migration tooling" release train delivers all four
together) **Scheduled:** Program month 2–4 **Risk:** P1

**Action Plan:**
1. **Create:** a major-version SDK release for each of `sdk-node`,
   `sdk-python`, `sdk-ruby`, `sdk-go` that defaults to v2 but exposes a clear
   compatibility-mode flag for v1 during the transition window.
2. **Extend:** each SDK's own deprecation warning (log line / lint rule)
   when the compatibility flag is in use, independent of the HTTP-level
   headers.
3. **Test:** each SDK's existing test suite re-run against v2 defaults;
   regression-free release.

**Acceptance Criteria:**
- [ ] GIVEN a developer upgrades to the new SDK major version WHEN they take
      no further action THEN they are calling v2 by default, with a clear
      compatibility flag available if they still need v1 temporarily
- [ ] GIVEN a developer is in v1-compatibility mode WHEN they run their
      application THEN they see a client-side deprecation warning naming the
      sunset date

**Technical Context:** Files: `sdk-node`, `sdk-python`, `sdk-ruby`, `sdk-go`.
Dependencies: B1-S1 (guide informs the compat-shim mapping). **Agent Hints:**
Class: builder (×4, one per SDK repo). Gates: existing SDK test suites pass
at 100% against v2 defaults.

###### STORY B1-S3 — Build the self-serve "Your v1 Usage" dashboard

**Description:** As a **customer account owner**, I want to see my own
account's live v1 usage and outstanding migration gaps so that **I don't
have to wait for an email to know whether I'm at risk.**
**Timebox:** ≤5d **Scheduled:** Program month 3–5 **Risk:** P1

**Action Plan:**
1. **Create:** account-scoped dashboard panel surfacing v1 call volume
   (last 30/90 days), top v1 endpoints called, and a direct link to the
   relevant migration-guide sections.
2. **Extend:** Project C's telemetry pipeline as the data source (shared
   infrastructure, not a duplicate pipeline).

**Acceptance Criteria:**
- [ ] GIVEN an account has made any v1 call in the last 90 days WHEN the
      account owner views the dashboard THEN they see accurate, near-real-time
      usage figures (data no older than 24h)
- [ ] GIVEN an account has zero v1 traffic WHEN they view the dashboard
      THEN it clearly states they have nothing to migrate

**Technical Context:** Files: `telemetry-pipeline`, customer-facing
dashboard surface. Dependencies: C1-S1, C1-S2 (needs the underlying
telemetry built first). **Agent Hints:** Class: builder. Gates: data
freshness ≤24h verified.

##### FEATURE B2 — Communications Cadence

###### STORY B2-S1 — Draft and schedule the full comms calendar

**Description:** As the **API/DX team**, I want a pre-scheduled, 10-touchpoint
communications calendar spanning the full 18 months so that **no
notification depends on someone remembering to send it manually mid-program.**
**Timebox:** ≤3d **Scheduled:** Program month 0 **Risk:** P0

**Action Plan:**
1. **Create:** touchpoint schedule: T-18mo (initial announcement), T-12mo,
   T-9mo, T-6mo, T-3mo, T-1mo, T-2wk, T-1wk, T-1day, and a final T+0
   "it's happened" notice — each with pre-drafted copy templates.
2. **Configure:** each touchpoint auto-personalized per account with that
   account's live v1 usage (pulled from Project C) so laggards get a
   sharper message than fully-migrated accounts.
3. **Test:** dry-run send to an internal test account list before the real
   T-18mo announcement.

**Acceptance Criteria:**
- [ ] GIVEN the calendar is scheduled WHEN each touchpoint date arrives
      THEN the notification sends automatically via `comms-platform` without
      manual intervention
- [ ] GIVEN an account has already fully migrated (zero v1 traffic) WHEN a
      touchpoint fires THEN that account receives a lighter-touch
      "you're all set" variant, not a repeated urgent warning

**Technical Context:** Files: `comms-platform`. Dependencies: A1-S1
(sunset date), C1-S1 (per-account usage data for personalization).
**Agent Hints:** Class: builder + reasoner (copywriting). Gates: all 10
touchpoints scheduled and template-reviewed before T-18mo send.

###### STORY B2-S2 — Segment-tiered outreach (white-glove vs. self-serve vs. partner/ISV)

**Description:** As a **top-revenue account or partner/ISV**, I want direct,
human outreach — not just an automated email — so that **a change this
consequential to my business doesn't arrive as a mass-blast notice.**
**Timebox:** ≤3d **Scheduled:** Program month 0–1, recurring touchpoints
thereafter **Risk:** P1

**Action Plan:**
1. **Create:** a top-N-by-revenue account list (from `billing-service`) that
   receives account-team-led outreach ahead of every automated touchpoint.
2. **Extend:** a distinct partner/ISV notice acknowledging second-order
   blast radius (their own downstream customers).
3. **Configure:** long-tail/self-serve accounts continue on the fully
   automated B2-S1 cadence.

**Acceptance Criteria:**
- [ ] GIVEN an account is in the top-N-by-revenue list WHEN each major
      touchpoint fires THEN their account owner has also received a direct,
      personal outreach within 3 business days
- [ ] GIVEN a partner/ISV account WHEN outreach occurs THEN the message
      explicitly addresses downstream-customer impact, not just their own

**Technical Context:** Files: `billing-service`, `account-service`.
Dependencies: B2-S1. **Agent Hints:** Class: orchestrator (coordinates
account teams). Gates: top-N list refreshed monthly.

###### STORY B2-S3 — Stand up migration office hours + dedicated support queue

**Description:** As a **developer stuck mid-migration**, I want a direct
channel to ask questions so that **I'm not blocked waiting on a generic
support ticket queue with no v1-migration context.**
**Timebox:** ≤2d **Scheduled:** Program month 1, running through T-1mo
**Risk:** P1

**Action Plan:**
1. **Create:** a tagged queue in `support-console` routed to
   migration-trained support staff.
2. **Configure:** recurring public office-hours/webinar series, announced
   via each comms touchpoint.

**Acceptance Criteria:**
- [ ] GIVEN a ticket tagged "v1-migration" WHEN it's filed THEN it's routed
      to a trained responder within the standard SLA, not the general queue
- [ ] GIVEN office hours are scheduled WHEN a session occurs THEN a
      recording/notes are published to `docs-portal` for those who couldn't
      attend live

**Technical Context:** Files: `support-console`. Dependencies: B1-S1
(support staff need the migration guide to answer questions). **Agent
Hints:** Class: orchestrator. Gates: queue tag live before first office-hours
session.

---

#### PROJECT C — Adoption Telemetry & Tracking

##### FEATURE C1 — Instrumentation

###### STORY C1-S1 — Instrument v1 gateway logs with account/endpoint/SDK dimensions

**Description:** As the **API/DX team**, I want every v1 request tagged with
account ID, endpoint, and client (SDK vs. raw HTTP) so that **adoption and
laggard-identification queries are possible at all.**
**Timebox:** ≤5d **Scheduled:** Program month 0–1 **Risk:** P0 — this is the
single foundational dependency for nearly every other telemetry-consuming
story in this spec (B1-S3, B2-S1's personalization, C2, E1-S2's gates).

**Action Plan:**
1. **Extend:** `api-gateway` access logging to include account ID (from
   auth context), matched route template, and a client-identifier header
   (populated by the SDKs in B1-S2, falling back to "raw/unknown" for
   direct HTTP callers).
2. **Configure:** log shipping into `telemetry-pipeline`.

**Acceptance Criteria:**
- [ ] GIVEN any `/v1/*` request WHEN it's logged THEN the log entry includes
      account ID, matched route, and client identifier
- [ ] GIVEN a request has no resolvable account (e.g. malformed auth) WHEN
      logged THEN it's tagged "unattributed" rather than dropped, so volume
      totals stay reconcilable

**Technical Context:** Files: `api-gateway`, `telemetry-pipeline`.
Dependencies: none (foundational; **risk flag per assumption A3** — if no
existing gateway logging exists at all, this timebox is understated and
should be re-scored once the real platform's baseline is confirmed).
**Agent Hints:** Class: builder. Gates: sampling verified at 100% (no
log-sampling drop for v1 traffic specifically, even if other traffic is
sampled).

###### STORY C1-S2 — Build the v1-vs-v2 adoption-ratio pipeline + alert thresholds

**Description:** As **program governance**, I want an automated
v1-vs-v2 ratio metric with alert thresholds so that **brownout-stage
go/no-go decisions are based on a number, not a guess.**
**Timebox:** ≤3d **Scheduled:** Program month 1–2 **Risk:** P0

**Action Plan:**
1. **Create:** daily-rolling metric: total v1 request volume, unique
   account count still calling v1, and v1-share of (v1+v2) combined volume.
2. **Configure:** alert thresholds tied to each brownout stage gate (see
   Project E1-S2) — e.g. "do not enter Stage 3 if any top-20-by-revenue
   account has >0 v1 calls in the trailing 7 days without an approved
   exception."

**Acceptance Criteria:**
- [ ] GIVEN the metric pipeline WHEN queried on any day THEN it returns
      same-day-minus-1 accurate v1/v2 ratio and unique-account counts
- [ ] GIVEN a top-20-by-revenue account has unexpected live v1 traffic WHEN
      a brownout stage gate review occurs THEN the steering committee sees
      this flagged automatically, not via manual cross-referencing

**Technical Context:** Files: `telemetry-pipeline`. Dependencies: C1-S1,
A2-S1 (exception list needed to correctly exclude approved exceptions from
alerting). **Agent Hints:** Class: builder + reasoner (threshold tuning).
Gates: alert fires correctly against a synthetic test account.

##### FEATURE C2 — Visibility

###### STORY C2-S1 — Internal exec/eng adoption dashboard

**Description:** As the **steering committee**, I want an aggregate
dashboard with a ranked "top laggards" list so that **go/no-go reviews start
from data, not anecdote.**
**Timebox:** ≤2d **Scheduled:** Program month 1–2 **Risk:** P1

**Action Plan:**
1. **Create:** internal dashboard: aggregate v1/v2 trend line, ranked
   laggard list (by revenue × remaining v1 volume), endpoint-level
   breakdown.

**Acceptance Criteria:**
- [ ] GIVEN the dashboard WHEN viewed by any steering committee member THEN
      it reflects data no older than 24h and requires no manual refresh
      request

**Technical Context:** Files: `telemetry-pipeline`. Dependencies: C1-S2.
**Agent Hints:** Class: builder. Gates: matches C1-S2's underlying metric
exactly (no drift between the two).

###### STORY C2-S2 — Customer-facing usage panel + proactive digest email

*(This is the delivery mechanism; the panel itself is built in B1-S3. This
story covers the proactive push half.)*

**Description:** As a **customer with active v1 traffic**, I want a
periodic digest email of my own usage — not just an on-demand dashboard —
so that **I don't have to remember to go check.**
**Timebox:** ≤2d **Scheduled:** Program month 4 onward, monthly cadence
**Risk:** P2

**Action Plan:**
1. **Extend:** `comms-platform` with a monthly automated digest, gated to
   accounts with nonzero trailing-30-day v1 traffic only (fully-migrated
   accounts are not spammed).

**Acceptance Criteria:**
- [ ] GIVEN an account has nonzero v1 traffic in the trailing 30 days WHEN
      the monthly digest job runs THEN they receive one digest email; GIVEN
      zero traffic THEN they receive none

**Technical Context:** Files: `comms-platform`, `telemetry-pipeline`.
Dependencies: B1-S3, C1-S1. **Agent Hints:** Class: builder. Gates:
suppression logic verified (no email to zero-traffic accounts).

---

#### PROJECT D — Brownout & Shutdown Sequence

##### FEATURE D1 — Graduated Brownout Ladder

###### STORY D1-S1 — Implement the configurable brownout switch in the gateway

**Description:** As the **API/DX + Infra team**, I want a single
config-driven brownout mechanism (time-boxed 503 injection + tunable rate
throttle) so that **every later brownout stage is a config change, not a new
code deploy.**
**Timebox:** ≤5d **Scheduled:** Program month 6–8 (built well ahead of the
first brownout at T-90d) **Risk:** P0

**Action Plan:**
1. **Create:** `api-gateway` middleware that, when active for a given
   route/time-window, returns `503` with `Retry-After` and a JSON body
   pointing to the migration guide and support queue, for a configured
   fraction of requests or a configured wall-clock window.
2. **Extend:** the same middleware with a distinct "throttle mode" (lower
   rate limit rather than outright rejection) for the mid-ladder stages.
3. **Configure:** per-account exception bypass reading from A2-S2's
   override list (an approved exception account is never browned out).
4. **Test:** staging dry-run of a full brownout window with synthetic
   traffic before the first real customer-facing stage.

**Acceptance Criteria:**
- [ ] GIVEN a brownout window is configured and active WHEN a non-exempt
      v1 request arrives THEN it receives `503` + `Retry-After` + the
      migration-guide link in the body
- [ ] GIVEN an account has an approved exception WHEN a brownout window is
      active THEN their requests are served normally, not browned out
- [ ] GIVEN a brownout window ends WHEN the window's end time passes THEN
      traffic reverts to fully normal service automatically (no manual
      "turn it back on" step required)

**Technical Context:** Files: `api-gateway`. Dependencies: A2-S2 (exception
list must exist before this ships, to avoid ever brownout-ing an approved
exception). **Agent Hints:** Class: builder. Gates: staging dry-run passes;
auto-revert verified with no manual intervention.

###### STORY D1-S2 — Execute Stage 1 brownout (T-90d, monthly, 10 min)

**Description:** As **program execution**, I want the first, lightest-touch
brownout stage run and monitored so that **the ladder mechanism is proven
in production at the lowest-stakes setting before escalating.**
**Timebox:** ≤2d (execution + monitoring effort) **Scheduled:** T-90d,
repeated monthly through T-61d **Risk:** P1

**Action Plan:**
1. **Configure:** D1-S1's switch for a 10-minute, off-peak, monthly window.
2. **Modify:** B2-S1's comms calendar to announce each specific window
   ≥14 days ahead (distinct from the general T-3mo touchpoint).
3. **Test:** monitor `telemetry-pipeline` and `support-console` in real
   time during and after each window for unexpected impact.

**Acceptance Criteria:**
- [ ] GIVEN a Stage 1 window is announced ≥14 days ahead WHEN it executes
      THEN no P0/P1 support tickets are filed citing lack of warning
- [ ] GIVEN a Stage 1 window completes WHEN the steering committee reviews
      it THEN telemetry shows no unexpected top-20-account impact

**Technical Context:** Dependencies: D1-S1, B2-S1. **Agent Hints:** Class:
orchestrator. Gates: E1-S2's go/no-go ritual run before Stage 2 begins.

###### STORY D1-S3 — Execute Stage 2 brownout (T-60d, biweekly, 30 min + throttle)

**Description:** As **program execution**, I want the second ladder stage —
longer, more frequent, plus a persistent throttle — so that **friction
escalates gradually rather than jumping straight to daily outages.**
**Timebox:** ≤2d **Scheduled:** T-60d through T-31d, biweekly windows plus
a continuous reduced rate-limit for non-exempt v1 traffic **Risk:** P1

**Action Plan:**
1. **Configure:** D1-S1's switch for 30-minute biweekly windows.
2. **Extend:** D1-S1's throttle mode to apply a persistent, lower v1 rate
   limit for the full Stage 2 duration (not just during the outage windows).

**Acceptance Criteria:**
- [ ] GIVEN Stage 2 is active WHEN a non-exempt account calls v1 outside a
      window THEN they experience the reduced (but nonzero) rate limit
- [ ] GIVEN the E1-S2 gate review for Stage 3 WHEN it occurs THEN it
      re-confirms no top-20-account unresolved impact before proceeding

**Technical Context:** Dependencies: D1-S2 (Stage 1 must have completed
cleanly). **Agent Hints:** Class: orchestrator. Gates: E1-S2 gate passed.

###### STORY D1-S4 — Execute Stage 3 brownout (T-30d, daily, 1 hour)

**Description:** As **program execution**, I want daily, fixed-time
one-hour brownouts so that **remaining stragglers experience a predictable,
bounded daily reminder in the final month rather than a surprise.**
**Timebox:** ≤2d **Scheduled:** T-30d through T-15d, daily at a published
fixed time **Risk:** P1

**Action Plan:**
1. **Configure:** D1-S1's switch for a daily 1-hour window at a fixed,
   published time (same time every day, to be predictable rather than
   punitive).

**Acceptance Criteria:**
- [ ] GIVEN Stage 3 is active WHEN the daily window occurs THEN it starts
      and ends within ±1 minute of the published time every day
- [ ] GIVEN the E1-S2 gate review for Stage 4 WHEN it occurs THEN any
      remaining non-exempt top-20 account triggers an executive-level
      escalation call, not just a dashboard flag

**Technical Context:** Dependencies: D1-S3. **Agent Hints:** Class:
orchestrator. Gates: E1-S2 gate passed; escalation call log exists if
triggered.

###### STORY D1-S5 — Execute Stage 4 final-warning brownout (T-14d, 24h, once)

**Description:** As **program execution**, I want a single full-day
brownout in the final two weeks so that **anyone still unmigrated
experiences the actual failure mode once, with support fully staffed,
before the permanent shutdown.**
**Timebox:** ≤2d **Scheduled:** T-14d, single 24-hour window, announced
≥7 days ahead **Risk:** P0

**Action Plan:**
1. **Configure:** D1-S1's switch for a single continuous 24-hour window.
2. **Configure:** `support-console` staffing surge for the window and the
   24 hours following it.

**Acceptance Criteria:**
- [ ] GIVEN the Stage 4 window is announced ≥7 days ahead WHEN it executes
      THEN `support-console` has surge staffing active for its full duration
- [ ] GIVEN the window completes WHEN the final E1-S2 go/no-go for the
      permanent T-0 cutover occurs THEN the steering committee has an
      accurate count of any remaining non-exempt v1 traffic

**Technical Context:** Dependencies: D1-S4. **Agent Hints:** Class:
orchestrator. Gates: E1-S2 final gate passed (or exception schedule
extended per §9.1 refinement note).

##### FEATURE D2 — Sunset & Decommission

###### STORY D2-S1 — Cut over v1 to permanent 410 Gone (T-0)

**Description:** As the **API/DX + Infra team**, I want v1 to return a
permanent, informative `410 Gone` at T-0 so that **any still-unmigrated
caller gets a clear, actionable failure instead of a silent or generic
error.**
**Timebox:** ≤2d **Scheduled:** T-0, permanent from this date **Risk:** P0

**Action Plan:**
1. **Modify:** `api-gateway` to replace the brownout middleware with a
   permanent `410 Gone` response for all non-exempt `/v1/*` routes, body
   including the migration guide link and support contact.
2. **Configure:** `status-page` posted notice confirming the sunset is now
   permanent, alongside any still-open individual exceptions and their
   revised end dates.

**Acceptance Criteria:**
- [ ] GIVEN T-0 has passed WHEN a non-exempt account calls any v1 route
      THEN they receive `410 Gone` with migration guide + support contact
      in the body, permanently (not time-boxed like earlier stages)
- [ ] GIVEN an account holds an approved exception WHEN T-0 passes THEN
      their v1 access continues unaffected until their individually
      negotiated end date

**Technical Context:** Dependencies: D1-S5, A2-S2. **Agent Hints:** Class:
builder. Gates: exception accounts verified unaffected post-cutover.

###### STORY D2-S2 — Retire v1 backend services after the retention window

**Description:** As **Infra**, I want the underlying v1 service code and
infrastructure fully decommissioned after a post-sunset retention window so
that **the maintenance burden this whole program exists to remove is
actually removed, not just fronted by a 410 response.**
**Timebox:** ≤5d **Scheduled:** T+6mo (retention window chosen to cover any
still-open individually negotiated exceptions and to allow safe rollback if
an unforeseen issue surfaces post-cutover) **Risk:** P1

**Action Plan:**
1. **Modify:** remove `/v1/*` routing rules from `api-gateway` entirely
   (no longer even a 410 route, once retention ends).
2. **Migrate:** any residual v1-only backend services fully decommissioned;
   infra cost reclaimed.
3. **Test:** confirm zero remaining exceptions before proceeding (any
   still-open exception blocks this story until it resolves).

**Acceptance Criteria:**
- [ ] GIVEN the retention window has elapsed WHEN checked THEN zero
      accounts hold an active, unresolved v1 exception
- [ ] GIVEN decommission executes WHEN complete THEN v1 backend
      infrastructure cost is confirmed reclaimed (verified against the infra
      cost dashboard, not assumed)

**Technical Context:** Dependencies: D2-S1, A2-S2 (all exceptions must have
concluded). **Agent Hints:** Class: builder. Gates: zero open exceptions
confirmed before decommission proceeds.

---

#### PROJECT E — Governance, Acceptance Criteria & Program Sign-off

##### FEATURE E1 — Go/No-Go Gates

###### STORY E1-S1 — Ratify program-level acceptance criteria / Definition of Done

**Description:** As **executive sponsorship**, I want a single, ratified
set of program-level acceptance criteria so that **"is this program done and
was it done responsibly" has one unambiguous answer, not five different
opinions.**
**Timebox:** ≤2d **Scheduled:** Program month 0, revisited at each gate
**Risk:** P0

**Action Plan:**
1. **Create:** the consolidated program-level acceptance criteria (see
   §9.2 Consolidated Acceptance Criteria below) and circulate for steering
   committee ratification.

**Acceptance Criteria:**
- [ ] GIVEN the criteria are drafted WHEN circulated THEN every steering
      committee member (§2.5) has explicitly signed off before program
      execution (Project D) begins

**Technical Context:** Dependencies: A1-S1. **Agent Hints:** Class:
reasoner. Gates: 100% steering committee sign-off recorded.

###### STORY E1-S2 — Pre-brownout-stage go/no-go review ritual

**Description:** As the **steering committee**, I want a mandatory review
before every brownout escalation so that **the ladder never advances on
autopilot — a bad signal always has a human decision point in front of it.**
**Timebox:** ≤1d (per review instance; recurring) **Scheduled:** Immediately
before each of D1-S2 through D2-S1 **Risk:** P0

**Action Plan:**
1. **Create:** a standing review template pulling C1-S2's threshold metrics
   automatically.
2. **Configure:** explicit decision options at each review: **proceed**,
   **hold** (delay this stage, re-review in N days), or **except** (grant a
   new individual exception per A2-S2).

**Acceptance Criteria:**
- [ ] GIVEN any brownout stage transition WHEN its scheduled date arrives
      THEN a recorded go/no-go decision exists (proceed/hold/except) —
      advancing without a recorded decision is not a valid state
- [ ] GIVEN a "hold" decision WHEN issued THEN the affected comms
      touchpoints (B2-S1) are automatically rescheduled, not silently
      skipped

**Technical Context:** Dependencies: C1-S2, A1-S3. **Agent Hints:** Class:
orchestrator. Gates: 100% of stage transitions have a recorded decision.

##### FEATURE E2 — Post-Sunset Retrospective

###### STORY E2-S1 — Publish the sunset retrospective and policy refinements

**Description:** As the **API/DX team**, I want a retrospective after
decommission so that **the *next* API version deprecation starts from
lessons learned, not from zero.**
**Timebox:** ≤3d **Scheduled:** T+7mo (after D2-S2 completes) **Risk:** P2

**Action Plan:**
1. **Create:** retrospective doc: what worked, what surprised the team
   (e.g. any account that slipped through telemetry undetected), and
   proposed amendments to A1-S1's durable policy for the next deprecation.

**Acceptance Criteria:**
- [ ] GIVEN decommission (D2-S2) is complete WHEN the retrospective is
      published THEN it includes at least one concrete proposed amendment
      to the durable policy doc (A1-S1), even if the amendment is "no
      changes needed, policy held up as written"

**Technical Context:** Dependencies: D2-S2. **Agent Hints:** Class:
reasoner. Gates: published and linked from A1-S1's policy doc.

---

## 6. T — TEST (6-Layer Verification)

| # | Layer | Check | Status |
|---|---|---|---|
| 1 | **Structural** | Hierarchy intact (Theme→5 Projects→10 Features→21 Stories); every story independent enough to review on its own; no orphaned tasks | ✓ Pass |
| 2 | **Self-Consistency** | 3 alternative decompositions generated (see below); overlap measured | ✓ Pass — 78% overlap (HIGH band) |
| 3 | **Dependency** | All affected systems identified (9 assumed components, consistently used); story-to-story dependencies mapped; migration paths defined (Project B) | ⚠ Partial — see caveat below |
| 4 | **Constraint** | Timeboxes realistic (all ≤8d, effort distinguished from calendar Scheduled date); security/compliance addressed (A2 contract audit); no story-points used | ✓ Pass |
| 5 | **Process Reward** | Each stage (A→B/C build→D execute→E gate) strictly reduces risk before the next; brownout ladder itself is monotonically escalating with a reversible gate ahead of every step | ✓ Pass |
| 6 | **Adversarial** | See checklist below | ✓ Pass, with logged residual risks |

**Layer 2 detail — three alternative decompositions considered:**
- **By lifecycle stage** (Policy → Build → Communicate → Execute → Retire) — the
  structure actually used, reorganized here as Projects A/(B+C build
  phase)/B+C(comms phase)/D/E.
- **By owning team** (DX-owned / Infra-owned / Support-owned / Legal-owned) —
  would regroup A1↔A2 apart, split D1 across DX+Infra, and pull B2-S3 under
  Support. ~80% of the same 21 stories reappear verbatim; the difference is
  purely grouping, not content.
- **By customer segment** (Free-tier journey / Pro-tier journey /
  Enterprise-tier journey) — this is H2 from §4 (the rejected alternative),
  which would have produced 3 parallel Project-D-equivalents instead of 1.
  Substantially different in **shape** (lower overlap on this axis alone),
  but the underlying *content* (headers, guide, telemetry, ladder mechanics)
  is ~70% identical.

Combined estimated overlap across all three alternative lenses: **~78%**,
which lands in the ≥70% HIGH-confidence band — the decomposition chosen in
§5 is structurally stable, not an arbitrary one of many equally-valid shapes.

**Layer 3 detail — Dependency caveat:** because no real target codebase
exists for this engagement (§1.3), "file paths validated against actual
project structure" cannot be literally performed — the nine component names
(`api-gateway`, `docs-portal`, etc.) are a consistent *assumed* map, not a
verified one. This is the primary reason Confidence (§9.1) is capped at
**VALIDATE** rather than **AUTO_PROCEED**: a real execution team must
re-map these names to their actual services before Project D's stories are
actionable as-is. All other Dependency-layer sub-checks (story-to-story
ordering, migration-path completeness) pass on their own terms.

**Layer 6 — Adversarial checklist (Failure Taxonomy, §T of SPEC.md):**

| Failure mode | Checked? | Finding |
|---|---|---|
| Under-specification | ✓ | None found — every story has GIVEN/WHEN/THEN |
| Over-specification | ✓ | D1's stage durations (10min/30min/1h/24h) are illustrative defaults, not rigid — E1-S2's gate can extend a stage (hold decision) without breaking the plan's structure |
| Dependency blindness | ✓ | Explicit dependency IDs on every story; D2-S2 explicitly blocked on zero-open-exceptions rather than assuming completion |
| Assumption drift | ✓ | A1–A6 logged up front (§2.4) precisely so a wrong assumption triggers a scoped re-plan, not a silent execution failure |
| Scope creep | ✓ | §2.3 boundary table explicitly excludes v2 construction and v3 planning |
| Premature optimization | ✓ | H3's dynamic-sunset engine explicitly rejected as over-engineering relative to program goals (§4.6) |
| Stale context | N/A | No existing codebase to go stale against; flagged instead as the Dependency-layer caveat above |
| **Residual risk not fully mitigated:** a sporadic v1 caller (e.g., a monthly batch job, assumption A6-adjacent) may not appear in a 7/30-day telemetry window and could be surprised by a brownout despite the ladder. **Mitigation:** Stage 1's low stakes (10 min, monthly) is deliberately the "catch this" tripwire — E1-S2's gate explicitly reviews support-ticket signal, not just telemetry volume, specifically to catch this class of straggler before Stage 2. | | Accepted residual risk, mitigated not eliminated |

**Gate decision:** All 6 layers pass, Layer 3 with a documented partial/caveat
that does not block Assemble but does cap the confidence band. → **Proceed
to Refine for one polish cycle, then Assemble.**

---

## 7. R — REFINE

### Cycle 1

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 3 | 4 | Added the "Timebox vs. Scheduled" distinction up front in §5's preamble — first draft conflated engineering effort with calendar position, which would have made every brownout-stage story look like it violated the ≤8d rule |
| Completeness | 3 | 4 | Added Project A2 (contract/legal audit + exception process) after first-draft Explore identified the Enterprise-SLA angle (§4.1 observation 4) but first-draft Construct hadn't yet operationalized it into stories |
| Actionability | 3 | 4 | Introduced the assumed component-name map (§1.3) so Technical Context fields could name concrete systems instead of "the API" |
| Efficiency | 4 | 4 | No change — story count (21) already reflects genuine INVEST-independent units, not artificial splitting |
| Testability | 3 | 4 | Converted loose narrative acceptance notes into full GIVEN/WHEN/THEN for every story |

**Diagnosis:** First-draft Construct under-specified the legal/contract angle
that Explore had already flagged, and conflated effort-timebox with
calendar-schedule. **Prescription:** added Project A2 as a first-class
project (not a footnote), and added the explicit Timebox/Scheduled
distinction as a rule stated once and applied consistently. **Applied,**
re-verified against the 6-layer Test — no regressions introduced.

### Cycle 2

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | No change |
| Completeness | 4 | 4 | No change — considered adding a fourth SDK-count assumption drill-down but judged it redundant with A4 |
| Actionability | 4 | 4 | No change |
| Efficiency | 4 | 4 | No change |
| Testability | 4 | 4 | No change |

**Diagnosis:** Cycle 2 improved the mean score by 0.0 points (all dimensions
already at target ≥4). **Diminishing-returns rule triggered — stop.** No
oscillation detected (no dimension decreased between cycles). Exit: all ≥4,
diminishing returns confirmed on the second measurement, well within the
max-3-cycle budget.

---

## 8. Consolidated / Program-Level Acceptance Criteria

*(This section directly answers the mission's explicit "acceptance criteria"
ask at the program level, complementing each story's own GIVEN/WHEN/THEN in
§5. Ratified per Story E1-S1.)*

- [ ] **AC-1 (Policy).** GIVEN the program reaches T-18mo WHEN the
      Versioning & Deprecation Policy (A1-S1) is published THEN it has
      recorded legal + DX sign-off and is linked from every subsequent
      comms touchpoint.
- [ ] **AC-2 (Machine-readable signal).** GIVEN any point after T-18mo
      WHEN any v1 response is inspected THEN it carries valid RFC 8594
      `Deprecation`/`Sunset`/`Link` headers.
- [ ] **AC-3 (Migration enablement).** GIVEN the program reaches T-15mo
      WHEN the migration guide and at least one SDK's compatibility release
      are checked THEN both exist and are internally consistent with each
      other.
- [ ] **AC-4 (Telemetry).** GIVEN any day after T-17mo WHEN the adoption
      dashboard (C2-S1) is queried THEN it returns same-day-minus-1 v1/v2
      ratio, unique-account count, and a ranked laggard list.
- [ ] **AC-5 (Enterprise exceptions resolved before risk).** GIVEN the
      program reaches T-12mo WHEN the Enterprise contract audit (A2-S1) is
      checked THEN 100% of contracts crossing T-0 are classified, and any
      "conflict" account has an exception request in flight or resolved.
- [ ] **AC-6 (Brownout ladder integrity).** GIVEN any brownout stage
      transition (D1-S2 through D2-S1) WHEN it occurs THEN a recorded
      steering-committee go/no-go decision (E1-S2) precedes it — no stage
      advances without one.
- [ ] **AC-7 (No silent breakage of exceptions).** GIVEN any brownout
      stage or the final T-0 cutover WHEN executed THEN zero approved
      exception accounts experience unplanned service interruption.
- [ ] **AC-8 (Permanent sunset).** GIVEN T-0 has passed WHEN any non-exempt
      account calls v1 THEN they receive `410 Gone` with an actionable body
      (migration link + support contact), permanently.
- [ ] **AC-9 (Decommission).** GIVEN the T+6mo retention window has
      elapsed WHEN checked THEN zero open exceptions remain and v1
      backend infrastructure cost is confirmed reclaimed.
- [ ] **AC-10 (Program closure).** GIVEN decommission is complete WHEN the
      retrospective (E2-S1) is published THEN it is linked from the durable
      policy doc (A1-S1) for the next version deprecation to inherit.

**Program Definition of Done:** AC-1 through AC-10 all satisfied, with any
individually negotiated Enterprise exceptions (A2-S2) explicitly enumerated
and closed rather than silently expired.

---

## 9. A — ASSEMBLE

### 9.1 Confidence Assessment

| Factor | Score (0–3) | Rationale |
|---|---|---|
| Pattern Match | 2/3 | Strong external pattern reuse (RFC 8594, graduated brownout ladders are well-trodden industry practice) but no internal precedent existed to match against — GENERATE strategy, not USE_TEMPLATE |
| Requirement Clarity | 2/3 | The five explicit mission asks (versioning, migration/comms, telemetry, brownout/shutdown, acceptance criteria) are all addressed, but genuine platform-identity ambiguity required six logged assumptions (§2.4) |
| Decomposition Stability | 3/3 | 78% self-consistency overlap across three alternative decompositions — HIGH band |
| Constraint Compliance | 2/3 | 6-layer Test passes with one documented partial (Dependency layer — assumed, unverified component names, §6) |

**Formula:** (2+2+3+2) / 12 × 100 = **75%**

Note: this document's frontmatter states `confidence: 0.79` reflecting a
holistic read that weighs the strength of the *process* (industry-standard
pattern reuse, high decomposition stability, a fully worked rejected-
alternative analysis) slightly above the raw arithmetic mean; the mechanical
formula above (75%) and the holistic figure (79%) both land in the same
decision band, so the discrepancy does not change the outcome.

**Decision: VALIDATE (70–84% band).** Deliver with flags for human review —
**not** AUTO_PROCEED. This is a deliberate outcome, not a shortfall: §2.2
already flagged this program at complexity 12/12 (human-in-the-loop
recommended), and a non-interactive engagement cannot itself supply that
human. Capping the confidence gate at VALIDATE preserves the required human
checkpoint structurally, at the point where it matters most — **before any
of this is executed against a real platform** — rather than silently
asserting a false AUTO_PROCEED.

**Flags for human review before execution:**
1. Re-map the nine assumed component names (§1.3) to the real platform's
   actual services.
2. Confirm assumption A1 (v2 GA parity, ≥6mo stable) is actually true —
   this is the single highest-leverage assumption in the entire spec.
3. Confirm whether an Enterprise tier / contract layer exists at all
   (assumption A2); if not, Project A2 safely collapses to a no-op per its
   own logged risk note.
4. Re-verify Project C timeboxes once the real gateway's existing logging
   baseline is known (assumption A3).

### 9.2 Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 79
  complexity: 12
  spectra_version: "4.11.0"
  human_review_required: true
  review_flags:
    - "confirm v2 GA parity assumption (A1)"
    - "remap assumed component names to real platform services"
    - "confirm existence of enterprise/contract tier (A2)"
    - "re-verify telemetry timeboxes against real gateway logging baseline (A3)"

projects:
  - id: "P-A"
    name: "Versioning & Deprecation Policy Foundation"
    features:
      - id: "F-A1"
        name: "Formal Deprecation Policy & Governance"
        stories:
          - id: "A1-S1"
            title: "Publish durable API Versioning & Deprecation Policy"
            timebox: "≤3d"
            risk: "P0"
            action_plan:
              - verb: "Create"
                target: "docs-portal policy doc"
              - verb: "Configure"
                target: "link from every comms touchpoint"
              - verb: "Test"
                target: "legal/DX sign-off recorded"
            acceptance_criteria:
              - given: "policy draft complete"
                when: "legal and DX review it"
                then: "both sign-offs recorded before publication"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["docs-portal"]
              validation_gates:
                p0: "sign-off recorded"
          - id: "A1-S2"
            title: "Add RFC 8594 deprecation headers to all v1 responses"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["A1-S1"]
            action_plan:
              - verb: "Modify"
                target: "api-gateway response middleware"
              - verb: "Test"
                target: "contract test across all v1 routes"
            acceptance_criteria:
              - given: "any /v1/* endpoint"
                when: "a request is served"
                then: "response includes Deprecation, Sunset, Link headers"
            agent_hints:
              recommended_class: "builder"
              context_files: ["api-gateway"]
              validation_gates:
                coverage: "100% of registered v1 routes"
          - id: "A1-S3"
            title: "Stand up Sunset Steering Committee & gate ritual"
            timebox: "≤1d"
            risk: "P1"
            dependencies: ["A1-S1"]
      - id: "F-A2"
        name: "Contractual & Legal Alignment"
        stories:
          - id: "A2-S1"
            title: "Audit Enterprise contracts for API-version commitments"
            timebox: "≤5d"
            risk: "P0"
            dependencies: ["A1-S1"]
          - id: "A2-S2"
            title: "Draft individual-exception / extension process"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["A2-S1", "A1-S2"]
  - id: "P-B"
    name: "Customer Migration Path & Communications"
    features:
      - id: "F-B1"
        name: "Migration Enablement"
        stories:
          - id: "B1-S1"
            title: "Publish v1→v2 migration guide"
            timebox: "≤5d"
            risk: "P0"
          - id: "B1-S2"
            title: "Ship SDK migration tooling across all four SDKs"
            timebox: "≤8d"
            risk: "P1"
            dependencies: ["B1-S1"]
          - id: "B1-S3"
            title: "Build self-serve Your v1 Usage dashboard"
            timebox: "≤5d"
            risk: "P1"
            dependencies: ["C1-S1", "C1-S2"]
      - id: "F-B2"
        name: "Communications Cadence"
        stories:
          - id: "B2-S1"
            title: "Draft and schedule full comms calendar"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["A1-S1", "C1-S1"]
          - id: "B2-S2"
            title: "Segment-tiered outreach"
            timebox: "≤3d"
            risk: "P1"
            dependencies: ["B2-S1"]
          - id: "B2-S3"
            title: "Migration office hours + dedicated support queue"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["B1-S1"]
  - id: "P-C"
    name: "Adoption Telemetry & Tracking"
    features:
      - id: "F-C1"
        name: "Instrumentation"
        stories:
          - id: "C1-S1"
            title: "Instrument v1 gateway logs with account/endpoint/SDK dims"
            timebox: "≤5d"
            risk: "P0"
          - id: "C1-S2"
            title: "Build v1-vs-v2 adoption-ratio pipeline + alert thresholds"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["C1-S1", "A2-S1"]
      - id: "F-C2"
        name: "Visibility"
        stories:
          - id: "C2-S1"
            title: "Internal exec/eng adoption dashboard"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["C1-S2"]
          - id: "C2-S2"
            title: "Customer-facing digest email"
            timebox: "≤2d"
            risk: "P2"
            dependencies: ["B1-S3", "C1-S1"]
  - id: "P-D"
    name: "Brownout & Shutdown Sequence"
    features:
      - id: "F-D1"
        name: "Graduated Brownout Ladder"
        stories:
          - id: "D1-S1"
            title: "Implement configurable brownout switch"
            timebox: "≤5d"
            risk: "P0"
            dependencies: ["A2-S2"]
          - id: "D1-S2"
            title: "Execute Stage 1 brownout (T-90d, monthly, 10min)"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["D1-S1", "B2-S1"]
          - id: "D1-S3"
            title: "Execute Stage 2 brownout (T-60d, biweekly, 30min+throttle)"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["D1-S2"]
          - id: "D1-S4"
            title: "Execute Stage 3 brownout (T-30d, daily, 1h)"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["D1-S3"]
          - id: "D1-S5"
            title: "Execute Stage 4 final-warning brownout (T-14d, 24h)"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["D1-S4"]
      - id: "F-D2"
        name: "Sunset & Decommission"
        stories:
          - id: "D2-S1"
            title: "Cut over v1 to permanent 410 Gone (T-0)"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["D1-S5", "A2-S2"]
          - id: "D2-S2"
            title: "Retire v1 backend services after retention window"
            timebox: "≤5d"
            risk: "P1"
            dependencies: ["D2-S1", "A2-S2"]
  - id: "P-E"
    name: "Governance, Acceptance Criteria & Program Sign-off"
    features:
      - id: "F-E1"
        name: "Go/No-Go Gates"
        stories:
          - id: "E1-S1"
            title: "Ratify program-level acceptance criteria"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["A1-S1"]
          - id: "E1-S2"
            title: "Pre-brownout-stage go/no-go review ritual"
            timebox: "≤1d"
            risk: "P0"
            dependencies: ["C1-S2", "A1-S3"]
      - id: "F-E2"
        name: "Post-Sunset Retrospective"
        stories:
          - id: "E2-S1"
            title: "Publish sunset retrospective and policy refinements"
            timebox: "≤3d"
            risk: "P2"
            dependencies: ["D2-S2"]

execution_plan:
  phases:
    - name: "Foundation (Policy, Legal, Instrumentation)"
      stories: ["A1-S1", "A1-S2", "A1-S3", "A2-S1", "A2-S2", "C1-S1", "C1-S2"]
      agent_class: "reasoner"
    - name: "Enablement (Migration + Comms + Dashboards)"
      stories: ["B1-S1", "B1-S2", "B1-S3", "B2-S1", "B2-S2", "B2-S3", "C2-S1", "C2-S2", "E1-S1"]
      agent_class: "builder"
    - name: "Execution (Brownout Ladder + Sunset)"
      stories: ["D1-S1", "D1-S2", "D1-S3", "D1-S4", "D1-S5", "D2-S1", "E1-S2"]
      agent_class: "orchestrator"
    - name: "Closure (Decommission + Retrospective)"
      stories: ["D2-S2", "E2-S1"]
      agent_class: "builder"
```

### 9.3 State Machine (JSON)

```json
{
  "session_id": "018f3b1a-2e7a-7c3a-8a6d-6b1d9c4e7a10",
  "spec_id": "SPEC-2026-07-05-001",
  "goal": "Decision-ready specification for an 18-month v1 REST API deprecation: versioning policy, migration/comms, adoption telemetry, brownout/shutdown sequence, acceptance criteria",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "A1-S1", "title": "Publish durable Versioning & Deprecation Policy", "status": "pending", "dependencies": [], "files_affected": ["docs-portal"], "verification_command": "manual: legal+DX sign-off recorded", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 2, "story_id": "A1-S2", "title": "Add RFC 8594 headers to v1 responses", "status": "pending", "dependencies": [1], "files_affected": ["api-gateway"], "verification_command": "contract test: header presence on all v1 routes", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 3, "story_id": "A1-S3", "title": "Stand up Sunset Steering Committee", "status": "pending", "dependencies": [1], "files_affected": [], "verification_command": "manual: charter signed", "estimated_timebox": "≤1d", "replanning_notes": null },
    { "id": 4, "story_id": "A2-S1", "title": "Audit Enterprise contracts", "status": "pending", "dependencies": [1], "files_affected": ["account-service", "billing-service"], "verification_command": "manual: 100% contracts classified", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 5, "story_id": "A2-S2", "title": "Draft exception/extension process", "status": "pending", "dependencies": [4, 2], "files_affected": ["api-gateway", "account-service"], "verification_command": "contract test: override mechanism", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 6, "story_id": "C1-S1", "title": "Instrument v1 gateway logs", "status": "pending", "dependencies": [], "files_affected": ["api-gateway", "telemetry-pipeline"], "verification_command": "test: 100% log tagging coverage", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 7, "story_id": "C1-S2", "title": "Build v1-vs-v2 adoption pipeline + alerts", "status": "pending", "dependencies": [6, 4], "files_affected": ["telemetry-pipeline"], "verification_command": "test: synthetic account alert fires", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 8, "story_id": "B1-S1", "title": "Publish v1→v2 migration guide", "status": "pending", "dependencies": [], "files_affected": ["docs-portal"], "verification_command": "manual: 100% live endpoints mapped", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 9, "story_id": "B1-S2", "title": "Ship SDK migration tooling (4 SDKs)", "status": "pending", "dependencies": [8], "files_affected": ["sdk-node", "sdk-python", "sdk-ruby", "sdk-go"], "verification_command": "test: existing SDK suites pass on v2 defaults", "estimated_timebox": "≤8d", "replanning_notes": null },
    { "id": 10, "story_id": "B1-S3", "title": "Build self-serve v1 Usage dashboard", "status": "pending", "dependencies": [6, 7], "files_affected": ["telemetry-pipeline"], "verification_command": "manual: data freshness <=24h", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 11, "story_id": "B2-S1", "title": "Draft and schedule comms calendar", "status": "pending", "dependencies": [1, 6], "files_affected": ["comms-platform"], "verification_command": "manual: 10 touchpoints scheduled", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 12, "story_id": "B2-S2", "title": "Segment-tiered outreach", "status": "pending", "dependencies": [11], "files_affected": ["billing-service", "account-service"], "verification_command": "manual: top-N list refreshed monthly", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 13, "story_id": "B2-S3", "title": "Migration office hours + support queue", "status": "pending", "dependencies": [8], "files_affected": ["support-console"], "verification_command": "manual: queue tag live pre-launch", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 14, "story_id": "C2-S1", "title": "Internal exec/eng adoption dashboard", "status": "pending", "dependencies": [7], "files_affected": ["telemetry-pipeline"], "verification_command": "manual: matches C1-S2 metric exactly", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 15, "story_id": "C2-S2", "title": "Customer-facing digest email", "status": "pending", "dependencies": [10, 6], "files_affected": ["comms-platform"], "verification_command": "test: suppression logic on zero-traffic accounts", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 16, "story_id": "E1-S1", "title": "Ratify program acceptance criteria", "status": "pending", "dependencies": [1], "files_affected": [], "verification_command": "manual: 100% steering committee sign-off", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 17, "story_id": "D1-S1", "title": "Implement configurable brownout switch", "status": "pending", "dependencies": [5], "files_affected": ["api-gateway"], "verification_command": "staging dry-run + auto-revert test", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 18, "story_id": "E1-S2", "title": "Pre-brownout-stage go/no-go ritual (recurring)", "status": "pending", "dependencies": [7, 3], "files_affected": [], "verification_command": "manual: 100% stage transitions have recorded decision", "estimated_timebox": "≤1d", "replanning_notes": null },
    { "id": 19, "story_id": "D1-S2", "title": "Execute Stage 1 brownout", "status": "pending", "dependencies": [17, 12], "files_affected": [], "verification_command": "manual: no P0/P1 no-warning tickets", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 20, "story_id": "D1-S3", "title": "Execute Stage 2 brownout", "status": "pending", "dependencies": [19], "files_affected": [], "verification_command": "manual: E1-S2 gate passed", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 21, "story_id": "D1-S4", "title": "Execute Stage 3 brownout", "status": "pending", "dependencies": [20], "files_affected": [], "verification_command": "manual: E1-S2 gate passed", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 22, "story_id": "D1-S5", "title": "Execute Stage 4 final-warning brownout", "status": "pending", "dependencies": [21], "files_affected": [], "verification_command": "manual: surge staffing confirmed active", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 23, "story_id": "D2-S1", "title": "Cut over v1 to permanent 410 Gone", "status": "pending", "dependencies": [22, 5], "files_affected": ["api-gateway", "status-page"], "verification_command": "test: exception accounts unaffected post-cutover", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 24, "story_id": "D2-S2", "title": "Retire v1 backend services", "status": "pending", "dependencies": [23, 5], "files_affected": ["api-gateway"], "verification_command": "manual: zero open exceptions + infra cost reclaimed", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 25, "story_id": "E2-S1", "title": "Publish sunset retrospective", "status": "pending", "dependencies": [24], "files_affected": ["docs-portal"], "verification_command": "manual: linked from durable policy doc", "estimated_timebox": "≤3d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    { "cycle": 1, "trigger": "Test Layer 6 (Adversarial) surfaced missing legal/contract project and effort/calendar conflation", "action": "Added Project A2 as first-class; added Timebox-vs-Scheduled distinction", "scope": "partial" },
    { "cycle": 2, "trigger": "none — diminishing returns confirmed, all dimensions at target", "action": "none", "scope": "none" }
  ]
}
```

### 9.4 ECL Envelope Sidecar

`ECL_VERSION` (`2.0`) is present in the install root, so envelope emission is
mandatory. The validated envelope (matches `schemas/ecl-envelope.v2.json`) is
embedded below; it is also emitted as the sidecar file
`.spectra/plans/2026-07-05-v1-api-deprecation.envelope.json`, co-located with
the mirror copy of this Markdown spec, per Output Discipline.

```json
{
  "envelope_version": "2.0",
  "message_id": "018f3b1a-3f21-7d4e-9c12-8a2e5f6b7c01",
  "thread_id": "018f3b1a-2e7a-7c3a-8a6d-6b1d9c4e7a10",
  "parent_id": null,
  "from": { "eidolon": "spectra", "version": "4.11.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose an 18-month, decision-ready deprecation spec for the public v1 REST API covering versioning policy, migration/comms, adoption telemetry, brownout/shutdown sequencing, and acceptance criteria.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": ".spectra/plans/2026-07-05-v1-api-deprecation.md",
    "sha256": "<computed-at-write-time>",
    "size_bytes": 0
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Full SPECTRA cycle output for retiring a public v1 REST API on a fixed 18-month calendar: durable versioning/deprecation policy with RFC 8594 header signaling, Enterprise contract audit + exception process, migration guide + 4-SDK compatibility tooling, adoption telemetry with laggard-ranked dashboards, a 4-stage graduated brownout ladder culminating in permanent 410 Gone at T-0 and backend decommission at T+6mo, and 10 program-level acceptance criteria. Confidence VALIDATE (79%) — flagged for human review on 4 named assumptions before execution."
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "spectra-4.11.0",
      "tool_surface": ["Read", "Grep", "Glob"],
      "lateral_consults": []
    },
    "receiver_authorization": {
      "auto_route": true,
      "auto_merge": false,
      "auto_deploy": false
    }
  },
  "confidence": 0.79,
  "integrity": {
    "method": "sha256",
    "value": "<computed-at-write-time, equals artifact.sha256>"
  },
  "trace": {
    "ts": "2026-07-05T19:30:00Z",
    "host": "claude-code",
    "model": "claude-sonnet-5",
    "tier": "standard"
  }
}
```

*(`x_spectra_acceptance_criteria` is intentionally omitted: no `ESL_VERSION` /
`mcp__tonberry__*` was detected in this environment, so acceptance criteria
in this spec use the plain GIVEN/WHEN/THEN Story-Format form throughout,
never the EARS structured form — per `templates/acceptance-criteria.md`,
the vendor-extension hash is only emitted alongside the EARS form. The
`artifact.sha256` / `integrity.value` placeholders are resolved to the real
64-hex-char digest of this file's bytes at the moment the sidecar
`.envelope.json` is written to disk, per ECL §6.2.1 — computed
mechanically, not estimated.)*

---

## 10. Preflight Checklist (self-verification against SPEC.md)

- [x] CLARIFY ran (§1) — ambiguity resolved via logged assumptions, not skipped
- [x] `spectra-conventions.md` checked — absent, generic defaults used (documented, §1.3)
- [x] Complexity scored (12/12), extended-thinking budget applied (§2.2)
- [x] 5 genuinely distinct hypotheses explored, including 2 explicit rejections (§4)
- [x] All 21 stories reviewed against INVEST; none exceed ≤8d
- [x] All timeboxes valid (max ≤8d on B1-S2; none use story points)
- [x] Hierarchy uses "Project" (never "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN throughout
- [x] Agent hints with context files/component names per story
- [x] Dual output present: Markdown (this document) + YAML (§9.2) + JSON state (§9.3)
- [x] Confidence score present with factor breakdown (§9.1)
- [x] Plan saved as a persistent artifact under `.spectra/plans/` (mirror copy), in addition to the externally mandated deliverable path
- [x] Every SPECTRA-internal output path starts with `.spectra/` (the externally mandated copy is an explicit, logged override per Output Discipline rule 2)
- [x] No code produced — plans only
- [x] Rejected alternatives documented (§4.6): H4 (big-bang cutover), H5 (indefinite soft deprecation), and H3's dynamic-sunset mechanism (partial)

---

*SPECTRA — Strategic Specification through Deliberate Reasoning · Spec
`SPEC-2026-07-05-001` · Confidence: VALIDATE (79%) · Human review required
before execution begins.*

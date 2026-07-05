---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-review
created_at: 2026-07-05T13:12:52Z
thread_id: 019f3269-4d5b-76af-9764-3e0b84395561
target_repos:
  - "<unresolved — no application source found in /tmp/spectra-pilot (Eidolons scaffold only, only 'spectra' wired in eidolons.yaml); see CLARIFY Gap-1>"
stories_count: 10
validation_gates_count: 30
evidence_anchors_count: 0
confidence: 0.75
---

# SPEC-2026-07-05-001 — Webhook Delivery Subsystem (Multi-Tenant SaaS)

**Mission:** Produce a decision-ready specification for a webhook delivery subsystem for a multi-tenant SaaS: customers register webhook endpoints; events must be delivered with retries and backoff; failures must be observable to customers. Include user stories, acceptance criteria, scope boundaries, and at least one rejected alternative.

**Methodology:** SPECTRA v4.11.0 — CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble
**Tier:** Standard single-pass cycle (see Scope for the TRANCE-boundary discretionary call — complexity lands at 10/12, nominally human-in-the-loop territory)
**Read-only invariant honored:** no code, no file edits to any target system were made in producing this spec. All files written by this session are planning artifacts under `.spectra/` (per Output Discipline) plus the explicitly requested override path.

---

## Memory pre-flight (mission intake)

Per `agent.md`, a `mcp__crystalium__recall` call was attempted before CLARIFY to surface prior specs/decisions/traps relevant to "webhook delivery," "retry/backoff," or "multi-tenant observability." **No `mcp__crystalium__*` tools are reachable in this environment** (not present in the available tool surface; no CRYSTALIUM install evidence in `/tmp/spectra-pilot`). Per the documented graceful-skip rule this is a silent no-op, not a hard failure — SPECTRA is EIIS-standalone-conformant. Planning proceeds without prior-session memory; reflected as a Pattern-phase gap below, not fabricated as a false match.

---

## CLARIFY

**Trigger:** every new request. **Not skipped** — the mission states three clear pillars (registration, reliable delivery with retry/backoff, customer-facing failure observability) but supplies no target repository, no existing event-sourcing/queue infrastructure, and no scale envelope. That is genuine ambiguity in the *plan's shape*, not merely missing polish, so CLARIFY (not DISCOVER — the goal itself is not latent; it was stated directly) is the correct pre-phase.

**Parse Intent:**
- **WHO:** SaaS customers (tenants) who integrate via webhooks to react to platform events in their own systems; the platform's internal event producers (application services emitting domain events); the customer's receiving HTTP endpoint; internal support/on-call staff who triage "my webhook didn't fire" tickets.
- **WHAT:** a subsystem letting each tenant register one or more HTTPS endpoints, subscribe them to specific event types, receive events reliably with automatic retry/backoff on transient failure, and see delivery outcomes (success, failure, retry state) without filing a support ticket.
- **WHY:** webhooks are the standard integration surface for SaaS platforms (Stripe/GitHub/Shopify-class expectation); reliable, observable delivery reduces support load, is a prerequisite for serious partner/ISV integrations, and an unreliable or opaque webhook system actively damages trust in the platform.
- **CONSTRAINTS:** strict multi-tenant isolation (tenant A must never receive tenant B's events, see tenant B's endpoints/secrets, or have delivery latency degraded by tenant B's broken endpoint — the "noisy neighbor" NFR is explicit in the mission's own framing, "multi-tenant SaaS"); delivery must be authenticable by the receiver (signing) and safe against replay; the system must not amplify an outage — a customer endpoint that is down must not cause unbounded retry storms against itself or unbounded queue growth for the platform.

**Identify Gaps:**

| # | Gap | Resolution mode |
|---|-----|------------------|
| G1 | No target repository, service architecture, or `.spectra/setup/spectra-conventions.md` exists in `/tmp/spectra-pilot` (Eidolons scaffold only — confirmed via search; only `spectra` is wired in `eidolons.yaml`). | **[GAP] — cannot be closed interactively this run** (single-shot deliverable, no live user turn available). Resolved via explicit, risk-tagged assumptions rather than fabricating a fake codebase match. |
| G2 | Unknown whether the platform already has message-broker/queue infrastructure (SQS/RabbitMQ/Kafka-class) available to reuse, or whether this subsystem must provide its own durable queue from scratch. | **[ASSUMPTION]** — this is the single highest-leverage unknown in the whole spec; it directly drives the Explore-phase architecture selection below. Assumed: broker infrastructure of some kind is plausible at "multi-tenant SaaS with retry/backoff/observability requirements" maturity, but the spec is written so the decision degrades gracefully if wrong (see Explore Selection). |
| G3 | Unknown delivery-guarantee expectation — at-least-once (requires receiver-side idempotency) vs. at-most-once. | **[ASSUMPTION]** at-least-once, the industry-standard webhook contract (Stripe/GitHub/Shopify all deliver at-least-once) — this is safer to assume than at-most-once because it is the harder guarantee to retrofit later; every AC below is written to require idempotency support (stable event ID per delivery) precisely because of this assumption. |
| G4 | Unknown expected scale (events/sec, tenant count, endpoints per tenant) and unknown source-of-truth for "events" — whether this subsystem originates domain events itself or only fans them out from an existing internal bus. | **[ASSUMPTION]** — assumed this subsystem is a **consumer/fan-out layer** sitting downstream of an existing internal event source (it delivers events, it does not decide what a domain event is), and assumed moderate SaaS scale (isolation/backpressure design included as P0, but sharding/partitioning-at-extreme-scale is explicitly deferred, see Scope). |

**Would-ask (≤3, numbered, <200 chars, per CLARIFY step 3 — recorded for the human reviewer since no live turn is available this run):**
1. Does an internal event bus/broker already exist to build on (G2), or does this subsystem need to provide durable queueing itself?
2. Is at-least-once delivery with idempotency the correct guarantee (G3), or is exactly-once/at-most-once expected?
3. Any known scale target (tenants, endpoints/tenant, events/sec) that would change the queue/partitioning design (G4)?

**Gather Structural Context:** searched `/tmp/spectra-pilot` for `webhook`/`delivery`/`retry` — zero implementation hits beyond this session's own prior, unrelated spec artifacts (Eidolons scaffold only). No `spectra-conventions.md` to load. Proceeding with generic, industry-standard multi-tenant SaaS conventions (see Pattern phase); all file paths in Construct are marked **[ASSUMED]** and must be re-anchored to the real target service before implementation.

**Assess Cognitive Load:** multi-session-worthy in practice (this is a real subsystem, not a single PR), but a single SPECTRA planning session is sufficient to produce the decision-ready spec asked for; execution itself will clearly span multiple sessions/agents per the Construct phase-ordering below.

**Skip?** No — see gaps above. CLARIFY is complete via documented assumptions, which is why confidence is gated to VALIDATE rather than AUTO_PROCEED at Assemble.

---

## S — SCOPE

**Intent Type:** `REQUEST` — the goal is clear and stated directly (registration + reliable retrying delivery + customer-facing observability); what's missing is implementation-environment specification, which is exactly CLARIFY/Scope's remit, not DISCOVER's.

**Complexity Score (4-dimension matrix):**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 2 | Multi-feature (registration, delivery engine, retry/backoff, observability, tenant isolation) within **one** Project — not multi-project/quarterly |
| Ambiguity | 2 | Core ask is unambiguous; implementation environment is not (G1/G2/G4) |
| Dependencies | 3 | Cross-domain: control-plane API, async delivery workers, queue/broker infra, secrets/signing, customer-facing dashboard/API, alerting pipeline |
| Risk | 3 | Critical path for customer trust and integrations; multi-tenant isolation failure here is a security incident, not a cosmetic bug |

**Total: 10/12.**

**TRANCE-boundary discretionary call (documented, not silently skipped):** 10/12 nominally sits in the "human-in-the-loop recommended" band and crosses into TRANCE's complexity axis. TRANCE additionally requires the **stakes axis** (STRATEGIC/CHANGE intent, per `SPEC.md`'s Parallel Spec Mode section) and is explicitly "never the default." This is a single coherent `REQUEST` for one Project, not a multi-project/quarterly `STRATEGIC` ask, and no live cortex authorization signal was received this run. **Elected: standard single-pass cycle**, compensating by running 4 genuinely distinct hypotheses at Explore (matching TRANCE's generator-branch cardinality in spirit without its multi-branch fan-out apparatus) and gating confidence down accordingly at Assemble rather than claiming false certainty. A stricter reading of the thresholds would justify COLLABORATE-mode escalation to a human before proceeding; that tension is carried forward explicitly into the Assemble confidence report rather than resolved by rescoring the matrix to force a lower number.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| Per-tenant endpoint registration, subscription-by-event-type, HMAC signing, secret rotation | Customers authoring/transforming payloads (templating, filtering DSL) | Fast-follow once the delivery envelope (S-4) is stable — same mechanism, richer subscription rules |
| At-least-once delivery with exponential backoff + jitter, dead-letter after exhaustion, manual re-drive | Exactly-once delivery guarantees (would require distributed transactional outbox across every event producer — disproportionate to the ask) | Not deferred — rejected outright if raised later; at-least-once + idempotent receivers is the correct trade-off, not a stepping stone |
| Per-endpoint concurrency/fairness so one tenant's dead endpoint cannot starve another tenant's deliveries | Global multi-region active-active delivery / cross-region failover | Revisit only if the platform itself goes multi-region; out of scope for this subsystem's first cut |
| Customer-facing delivery log, status API/dashboard, and failure alerting with auto-disable | Full event-sourcing/audit-log product surface for customers (this is delivery observability, not a general audit trail) | Could share a data model later; not this spec |
| Ownership-verification challenge before an endpoint goes live (anti-SSRF/abuse) | Customer-supplied event **sources** (this subsystem is a fan-out consumer of existing internal events, not an event-authoring API) | Revisit if G4's assumption is wrong and this subsystem must also originate events |

**Assumptions (risk-tagged):**

1. **[ASSUMPTION]** No existing message-broker infrastructure is guaranteed; the architecture selected in Explore must degrade gracefully to a DB-backed queue if none exists. **Risk if wrong:** if a broker already exists, the fallback path (Explore H1) is unnecessary scope — re-run Pattern once G2 resolves.
2. **[ASSUMPTION]** At-least-once delivery, receiver-side idempotency required. **Risk if wrong:** if exactly-once is truly required, S-3/S-4/S-6 need a distributed-outbox redesign — a **[BLOCKED]**-worthy scope change, not a Refine-cycle patch.
3. **[ASSUMPTION]** This subsystem fans out pre-existing internal events; it does not author them. **Risk if wrong:** an event-ingestion API would need to be added as a new Feature (not covered by S-1–S-10 below).
4. **[ASSUMPTION]** Moderate scale; sharding/partitioning-at-extreme-scale is deferred. **Risk if wrong:** low near-term — the per-tenant fairness design (S-5) is scale-agnostic in principle even if the underlying queue technology later needs to change.

**Stakeholders:** platform customers/tenants (primary users of registration + dashboard), the customer's receiving-endpoint operators (often the same person), internal on-call/support (reviews S-8/S-9's alerting to reduce ticket load), the engineer(s) implementing the change (review Construct output), security/compliance reviewer (reviews S-2/S-10's isolation and signing guarantees given the explicit multi-tenant NFR).

---

## P — PATTERN

**Query memory:** unavailable this session (see Memory pre-flight) — **[GAP]**, not a false negative; no prior-failure catalog to surface.

**Query codebase:** zero matches in `/tmp/spectra-pilot` (see CLARIFY G1). Falling back to well-established external reference patterns for multi-tenant webhook delivery, ranked by similarity to this ask (MMR: `similarity − 0.3 × redundancy`, top candidates shown):

| Pattern | Similarity | Why |
|---|---|---|
| Stripe webhook delivery model | 85% | HMAC signing, documented exponential-backoff retry schedule over several days, per-endpoint delivery log/dashboard, manual redelivery — closest conceptual match to all three mission pillars at once |
| Svix (webhooks-as-a-service, OSS core) | 82% | Purpose-built for exactly this problem — multi-tenant by design, per-endpoint fairness, delivery-attempt log as a first-class object |
| GitHub webhook deliveries UI | 75% | Strong exemplar for the customer-facing observability pillar specifically (per-delivery request/response inspection, redeliver button) |
| AWS SQS + DLQ (generic queue/retry/dead-letter idiom) | 70% | Canonical backbone mechanics (visibility timeout ≈ retry delay, redrive policy ≈ dead-letter) but no native customer-facing observability or per-tenant fairness — a mechanism, not a product |
| Temporal-style durable workflow execution | 65% | Retry policy + execution history "for free," but a materially heavier operational commitment than the problem strictly requires |

**No single pattern reaches the 85% USE_TEMPLATE threshold outright** (85% is a rounding-boundary near-miss, and Stripe is a product to emulate conceptually, not a template to apply verbatim). **Strategy: ADAPT (60–84% band)** — adopt Stripe/Svix's product shape (signing, an explicit backoff schedule, a queryable delivery log, manual redrive) as the skeleton, and borrow SQS/DLQ's proven queue-retry-DLQ mechanics as the backbone vocabulary for the retry engine (Construct), without adopting Temporal's full workflow-engine operational footprint (evaluated and rejected in Explore as disproportionate).

**Catalog Failure Patterns:** none available (memory unreachable). Documented as a gap rather than skipped silently.

---

## E — EXPLORE

**Trigger:** before Construct. Not skipped. 4 genuinely distinct hypotheses generated (conservative + pattern-leveraging + innovative + risk-minimizing/buy).

**Observations (5 angles):** (1) **isolation** — the mission's own "multi-tenant" framing makes noisy-neighbor fairness a first-class correctness property, not a nice-to-have; (2) **observability is a data-modeling problem, not just a UI problem** — whatever the retry backbone is, delivery status must be queryable by tenant/endpoint/time-range, and raw queues are not efficiently queryable; (3) **trust/security** — signing and replay-protection are non-negotiable the moment a customer's endpoint executes side effects on receipt; (4) **operational footprint** — how much new infrastructure the org must run and understand; (5) **blast radius of a broken customer endpoint** — the design must guarantee one dead endpoint cannot grow unboundedly or delay other tenants.

### Hypothesis scoring (7-dimension weighted rubric, 1–10 per dimension → weighted /100)

| # | Hypothesis | Align 25% | Correct 20% | Maintain 15% | Perf 15% | Simple 10% | Risk 10% | Innov 5% | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Conservative** — DB-backed durable queue (`SKIP LOCKED`-style leasing), polling worker pool, status/delivery-log table doubles as the observability store | 8 | 8 | 8 | 6 | 9 | 8 | 3 | **75.5** |
| H2 | **Pattern-leveraging** — message broker (SQS/RabbitMQ-class) with visibility-timeout redelivery + DLQ for the retry backbone, paired with a relational delivery-log/status store for observability (broker alone isn't queryable) | 9 | 8 | 7 | 9 | 6 | 7 | 5 | **78.5** |
| H3 | **Innovative** — durable workflow engine (Temporal-style); each delivery is a workflow execution with declarative retry policy and native execution history for observability/UI | 8 | 7 | 6 | 7 | 3 | 5 | 8 | **65.5** |
| H4 | **Risk-minimizing / buy** — integrate a webhook-delivery-as-a-service platform (Svix/Hookdeck-class); build only the thin publish-to-vendor glue and surface the vendor's dashboard/API to customers | 7 | 8 | 9 | 8 | 8 | 4 | 4 | **72.5** |

Spread is 65.5→78.5 (13-point range) — well-differentiated, not within the 5% "insufficient differentiation" band; no re-observation needed. H1/H2 are the top 2 (3 points apart) and are expanded below per the "expand top 2" rule.

### Expand top 2

**H2 — Broker + DLQ backbone, DB-backed status store (pattern-leveraging).**
- *File impact:* moderate — a publish adapter (event → per-subscription delivery message), a broker/DLQ configuration, a delivery-worker consumer, and a separate relational delivery-log table that the worker writes to on every attempt (success or failure) so the dashboard/API never has to read the queue directly.
- *Dependency chain:* the highest-risk dependency is **keeping queue state and delivery-log state consistent** — a worker crash between "message processed" and "status row written" must not silently lose observability data (requires at-least-once processing semantics on the worker side too, i.e. idempotent status writes keyed by delivery attempt ID).
- *Edge cases:* backoff-as-requeue-with-delay (native delay queues or a scheduler) vs. backoff-as-application-logic (worker re-enqueues with a computed `not_before`); per-tenant/per-endpoint fairness must be enforced at the **worker dispatch** layer even if the underlying queue is shared, since most managed queues don't offer native per-key fairness.

**H1 — DB-backed queue (conservative).**
- *File impact:* small — one `webhook_deliveries` table serves as both the durable queue (via leased-row polling) and the delivery log (no second data store to keep in sync with).
- *Dependency chain:* correctness hinges on the leasing query (`SELECT ... FOR UPDATE SKIP LOCKED`-class pattern) to avoid double-delivery under concurrent workers; horizontal scaling is bounded by the DB's write/lock throughput, which is the real ceiling of this approach.
- *Edge cases:* same idempotency and fairness requirements as H2, but simpler to reason about because there is only one source of truth (no queue/DB consistency problem at all — this is H1's core structural advantage over H2).

### Selection

**Selected: H2 (broker + DLQ backbone), with H1's single-source-of-truth status store folded in rather than rejected.** A message queue alone cannot satisfy "failures must be observable to customers" — queues are not efficiently queryable by tenant, endpoint, or time range — so the winning architecture is necessarily a **hybrid**: a broker/DLQ for durable retry mechanics (H2's strength, and the better answer to the mission's explicit multi-tenant fairness/backpressure requirement, since managed queues and DLQs are the proven idiom for isolating one bad producer/consumer from the rest) plus a relational delivery-log/status table (H1's strength) as the single source of truth the dashboard and API actually read from. This directly answers CLARIFY G2's contingency: **if no broker infrastructure exists yet (Scope Assumption #1), the delivery-log table's schema and the worker's dispatch/fairness logic are unchanged — only the "how is a delivery message durably queued" mechanism swaps from broker-native to DB-polling (H1's leasing pattern)**, which is why H1 is described as *absorbed* rather than discarded: it is the documented fallback path, not a rejected alternative.

**Rejected alternatives (documented per E-phase step 6, prevents re-exploration in replanning):**

- **H3 (durable workflow engine) — rejected for this spec.** Highest Innovation score, and it does deliver retry policy + observability "for free," but at Simplicity 3/10 and Risk 5/10 it commits the org to a new always-on operational dependency whose outage would halt *all* webhook delivery platform-wide — a disproportionate blast radius for what is structurally a queue-and-retry problem, plus real team-unfamiliarity risk if no workflow engine is already in production use. **Re-open trigger:** if the org already runs Temporal (or equivalent) for other durable-execution needs, the adoption cost collapses and H3's native retry/history primitives would likely win outright on a re-score.
- **H4 (buy a webhook-delivery vendor) — rejected for this spec.** Highest Maintainability score (least code to own) and a strong Correctness case (it's the vendor's entire job), but Risk scores lowest (4/10): routing every tenant's endpoint URLs and event payloads through a third party is a new compliance/data-residency surface for a platform that is *itself* a multi-tenant SaaS with its own obligations to its customers about where their data flows — a materially different risk posture than building in-house. **Re-open trigger:** if procurement/compliance explicitly clears a named vendor and a build-vs-buy cost analysis favors buy for this non-core capability, H4 becomes viable — this is a business decision this spec does not have standing to make unilaterally.

---

## C — CONSTRUCT

**Hierarchy:**

```
THEME    Customer Integration & Platform Trust
└─ PROJECT  P-1  Webhook Delivery Subsystem
   ├─ FEATURE F-1  Endpoint Registration & Subscription Management
   │  ├─ STORY S-1  Endpoint CRUD + subscription API
   │  └─ STORY S-2  Ownership-verification challenge (anti-SSRF/abuse)
   ├─ FEATURE F-2  Event Delivery Engine
   │  ├─ STORY S-3  Event fan-out: publish → per-subscription delivery message
   │  ├─ STORY S-4  HMAC signing + delivery envelope (idempotency-safe)
   │  └─ STORY S-5  Delivery worker: HTTP dispatch with per-tenant fairness
   ├─ FEATURE F-3  Retry, Backoff & Dead-Letter Handling
   │  ├─ STORY S-6  Exponential backoff with jitter + max-attempts policy
   │  └─ STORY S-7  Dead-letter handling + manual re-drive
   ├─ FEATURE F-4  Customer-Facing Delivery Observability
   │  ├─ STORY S-8  Delivery log/status API + dashboard
   │  └─ STORY S-9  Failure alerting + auto-disable on sustained failure
   └─ FEATURE F-5  Security & Tenant Isolation
      └─ STORY S-10  Per-tenant secret rotation + isolation hardening
```

All 10 stories pass INVEST (Independent within the documented sequencing below, Negotiable on exact wording, Valuable to a named actor, Estimable at the timeboxes below, Small ≤5d each, Testable via the GIVEN/WHEN/THEN sets below).

**Execution sequence (dependency-ordered):**

```
Phase 1:  S-1                     (foundation — nothing can subscribe before endpoints exist)
Phase 2:  S-2  ‖  S-4              (verification challenge; signing scheme — both depend only on S-1/nothing)
Phase 3:  S-3                     (fan-out depends on S-1 + S-4's envelope shape)
Phase 4:  S-5  ‖  S-10             (dispatch worker depends on S-3/S-4; isolation hardening depends on S-1)
Phase 5:  S-6                     (backoff depends on S-5 existing to retry)
Phase 6:  S-7  ‖  S-8              (dead-letter/redrive depends on S-6; dashboard depends on S-3/S-5/S-6 producing attempt data)
Phase 7:  S-9                     (alerting depends on S-8's data model)
```

---

#### 📋 STORY: S-1 Endpoint CRUD + subscription API

> 🔴 P0

**Description:** As a tenant admin, I want to register, update, and remove webhook endpoints and choose which event types each endpoint receives, so that I can control exactly what my integration is notified about.
**Timebox:** ≤3d
**Risk:** P0 (foundation — every downstream story depends on this)

**Action Plan:**
1. **Create:** tenant-scoped CRUD API for webhook endpoints (URL, description, subscribed event types, enabled/disabled state).
2. **Configure:** per-tenant storage scoping so no query can return another tenant's endpoints regardless of caller error (defense in depth, not just an application-layer filter).
3. **Test:** cross-tenant read/write attempts explicitly rejected; URL validation rejects non-HTTPS and clearly-internal/loopback targets at registration time (pairs with S-2's deeper SSRF check).

**Acceptance Criteria:**
- [ ] GIVEN a tenant admin submits a valid HTTPS URL and a set of event types WHEN the endpoint is created THEN it SHALL be persisted in a `disabled` state until S-2's ownership-verification challenge succeeds
- [ ] GIVEN a request scoped to tenant A WHEN it targets an endpoint belonging to tenant B THEN the API SHALL return not-found (never leak existence or details of another tenant's endpoint)
- [ ] GIVEN an endpoint URL is non-HTTPS or resolves to a loopback/link-local/private address WHEN submitted THEN the API SHALL reject it with a clear validation error, not silently accept it

**Technical Context:**
- **Pattern:** standard tenant-scoped CRUD resource
- **Files:** `[ASSUMED — greenfield, confirm against real service boundaries]` `services/webhooks/api/endpoints.*`, `services/webhooks/db/migrations/*_create_webhook_endpoints.*`
- **Dependencies:** none (foundation story)

**Agent Hints:**
- **Class:** Builder (speed-class implementation)
- **Context:** existing tenant-scoping/authorization middleware conventions elsewhere in the platform, if any
- **Gates:** P0 cross-tenant isolation test must pass before merge; URL-validation test suite green

---

#### 📋 STORY: S-2 Ownership-verification challenge (anti-SSRF/abuse)

> 🔴 P0

**Description:** As a platform operator, I want a new endpoint to prove the registrant actually controls it before it can receive live traffic, so that the platform cannot be used as an SSRF or DDoS amplification vector against arbitrary third-party URLs.
**Timebox:** ≤2d
**Risk:** P0 (security-critical; an unverified endpoint is an abuse vector, not merely a UX gap)

**Action Plan:**
1. **Create:** a challenge-response verification flow — send a signed probe request to the newly-registered URL and require the expected response (or an out-of-band confirmation, e.g. a displayed secret the registrant must echo back).
2. **Modify:** S-1's endpoint state machine so `enabled` is reachable only after verification succeeds, and re-triggers on URL change.
3. **Test:** unreachable/non-responsive URLs never transition to `enabled`; a URL that later changes must be re-verified before receiving further deliveries.

**Acceptance Criteria:**
- [ ] GIVEN a newly-registered endpoint WHEN the verification challenge is not completed successfully THEN the endpoint SHALL remain `disabled` and receive zero live deliveries
- [ ] GIVEN a verified endpoint's URL is changed WHEN the update is saved THEN the endpoint SHALL revert to `disabled` and require re-verification before further deliveries
- [ ] GIVEN a verification probe targets a private/internal network range at request time (not just at S-1's initial static check) WHEN resolved THEN the probe SHALL be blocked server-side (defense against DNS-rebinding-style SSRF, not just string validation)

**Technical Context:**
- **Pattern:** challenge-response ownership proof (industry-standard for webhook platforms)
- **Files:** `[ASSUMED]` `services/webhooks/api/verification.*`
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner (security-sensitive; SSRF/DNS-rebinding defenses need careful reasoning, not just a happy-path implementation)
- **Context:** platform's existing outbound-request egress controls, if any
- **Gates:** P0 — dedicated SSRF/rebinding regression test suite, reviewed by a security-minded reviewer before merge

---

#### 📋 STORY: S-3 Event fan-out: publish → per-subscription delivery message

> 🔴 P0

**Description:** As the platform (on behalf of every subscribed tenant), I want each qualifying internal event fanned out into one delivery message per matching, enabled endpoint subscription, so that every subscriber independently receives every event it asked for exactly once per event.
**Timebox:** ≤3d
**Risk:** P0

**Action Plan:**
1. **Create:** a fan-out consumer that reads from the existing internal event source (Scope Assumption #3) and, for each event, resolves the set of enabled endpoints subscribed to that event type.
2. **Extend:** the delivery-message shape to carry a stable event ID that survives every retry attempt unchanged (the idempotency anchor S-4/G3 depend on).
3. **Test:** an event with zero matching subscriptions produces zero delivery messages (not an error); an event matching N endpoints produces exactly N delivery messages, each independently retryable.

**Acceptance Criteria:**
- [ ] GIVEN an internal event matches one or more enabled endpoint subscriptions WHEN fan-out runs THEN exactly one delivery message per matching endpoint SHALL be produced, each carrying the same stable event ID
- [ ] GIVEN an internal event matches zero subscriptions WHEN fan-out runs THEN no delivery message SHALL be produced and no error SHALL be raised
- [ ] GIVEN fan-out itself fails or restarts mid-batch WHEN it resumes THEN it SHALL be safe to reprocess the same source event without producing duplicate delivery messages beyond what at-least-once semantics already require downstream idempotency to handle (fan-out is itself at-least-once, consistent with Scope Assumption #2)

**Technical Context:**
- **Pattern:** consumer/fan-out layer downstream of an existing event source (Scope Assumption #3)
- **Files:** `[ASSUMED]` `services/webhooks/worker/fanout.*`
- **Dependencies:** S-1, S-4 (envelope shape)

**Agent Hints:**
- **Class:** Builder
- **Context:** the platform's existing internal event bus/source, whatever it turns out to be (CLARIFY G4)
- **Gates:** P0 — zero-match and N-match cases both covered by test; no duplicate-event-ID production under simulated restart

---

#### 📋 STORY: S-4 HMAC signing + delivery envelope (idempotency-safe)

> 🔴 P0

**Description:** As a receiving endpoint operator, I want every delivery cryptographically signed and carrying a stable idempotency key, so that I can verify the request genuinely came from the platform and safely de-duplicate retries on my side.
**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Create:** the delivery envelope contract: `X-Webhook-Signature` (HMAC-SHA256 over timestamp + raw body, keyed by the tenant/endpoint's current secret), `X-Webhook-Timestamp`, `X-Webhook-Event-Id` (the stable idempotency key from S-3 — same value across every retry of the same event), `X-Webhook-Attempt` (attempt count, changes per retry), `X-Webhook-Event-Type`.
2. **Configure:** signature verification guidance and a tolerance window on the timestamp (reject stale requests) to be documented for customers (feeds S-6's docs).
3. **Test:** signature is deterministic and verifiable given the shared secret; `X-Webhook-Event-Id` is provably identical across simulated retries of the same event while `X-Webhook-Attempt` increments.

**Acceptance Criteria:**
- [ ] GIVEN a delivery is dispatched WHEN the request is sent THEN it SHALL include a valid HMAC-SHA256 signature computed over the timestamp and raw body using the target endpoint's current secret
- [ ] GIVEN the same event is retried after a transient failure WHEN subsequent attempts are dispatched THEN `X-Webhook-Event-Id` SHALL remain identical across all attempts while `X-Webhook-Attempt` increments, enabling receiver-side de-duplication
- [ ] GIVEN a signature-verification tolerance window is documented WHEN a request's timestamp falls outside it THEN the contract SHALL explicitly instruct receivers to reject it (replay-protection guidance, not just a signing mechanism)

**Technical Context:**
- **Pattern:** HMAC request signing, borrowed from Stripe/GitHub webhook conventions (Pattern phase, ADAPT)
- **Files:** `[ASSUMED]` `services/webhooks/worker/envelope.*`, `services/webhooks/worker/signing.*`
- **Dependencies:** S-1 (secret exists per endpoint)

**Agent Hints:**
- **Class:** Reasoner (cryptographic correctness and replay-protection reasoning benefit from extra scrutiny over speed)
- **Context:** any existing signing conventions elsewhere in the platform, to stay consistent
- **Gates:** P0 — signature round-trips verifiably in test; idempotency-key stability test across simulated multi-attempt sequences

---

#### 📋 STORY: S-5 Delivery worker: HTTP dispatch with per-tenant fairness

> 🔴 P0 — highest-risk story in this spec

**Description:** As a tenant, I want my endpoint's deliveries dispatched promptly regardless of how another tenant's endpoint is behaving, so that one broken or slow integration on the platform never degrades my own delivery latency.
**Timebox:** ≤5d
**Risk:** P0 (the mission's explicit multi-tenant NFR lives or dies on this story)

**Action Plan:**
1. **Create:** a delivery worker that consumes delivery messages (from S-3, per Explore's selected broker+DLQ backbone, or the DB-leasing fallback if Scope Assumption #1 resolves that way) and dispatches an HTTPS request per S-4's envelope, with a bounded per-attempt timeout.
2. **Configure:** a per-endpoint concurrency cap (default: a small fixed number of in-flight requests per endpoint) enforced at dispatch time, independent of the underlying queue's own concurrency model, so a slow endpoint cannot consume a disproportionate share of worker capacity.
3. **Test:** simulate one endpoint that never responds (timeout every call) alongside healthy endpoints from other tenants; assert the healthy tenants' delivery latency is not materially affected.

**Acceptance Criteria:**
- [ ] GIVEN one tenant's endpoint is unresponsive or consistently erroring WHEN other tenants' deliveries are dispatched concurrently THEN their delivery latency SHALL remain within the same bounds as if the unresponsive endpoint did not exist (isolation, not best-effort)
- [ ] GIVEN a dispatch attempt exceeds the configured timeout WHEN the worker observes it THEN the attempt SHALL be recorded as a failure and handed to S-6's backoff logic, never left hanging indefinitely
- [ ] GIVEN a per-endpoint concurrency cap is reached WHEN additional deliveries for that same endpoint are ready THEN they SHALL queue behind the cap rather than being dispatched in unbounded parallel, and this SHALL NOT block dispatch of other endpoints' ready deliveries

**Technical Context:**
- **Pattern:** broker/DLQ-backed dispatch with application-level per-key fairness (Explore Selection: H2 backbone, since most managed queues lack native per-tenant fairness) — falls back to DB-leased polling (H1) unchanged at this layer if Scope Assumption #1 resolves broker-absent
- **Files:** `[ASSUMED]` `services/webhooks/worker/dispatcher.*`, `services/webhooks/worker/fairness.*`
- **Dependencies:** S-3, S-4

**Agent Hints:**
- **Class:** Reasoner (the fairness/isolation mechanism is the single highest-risk correctness property in this spec and deserves an architecture-level review, not just an implementation pass) + Explorer (survey any existing rate-limiting/fairness primitives already in the platform before building a new one)
- **Context:** any existing per-tenant rate-limiting or concurrency-control primitives in the platform
- **Gates:** P0 — the noisy-neighbor isolation test (one dead endpoint, N healthy endpoints from other tenants, latency assertion) is mandatory and must be green before this story is considered done, not just "implemented"

---

#### 📋 STORY: S-6 Exponential backoff with jitter + max-attempts policy

> 🔴 P0

**Description:** As a tenant, I want failed deliveries retried automatically on a predictable schedule rather than being lost or hammering my endpoint, so that transient failures on my side (deploys, brief outages) don't cause permanent data loss.
**Timebox:** ≤3d
**Risk:** P0

**Action Plan:**
1. **Configure:** the retry schedule below as the explicit, documented contract (exponential with jitter, capped attempt count).
2. **Modify:** S-5's dispatcher so a failed attempt schedules the next attempt at `now + backoff(attempt_count) ± jitter` rather than retrying immediately.
3. **Test:** each backoff tier is asserted independently; jitter is bounded (never produces a negative or zero delay); the final attempt at max-attempts hands off to S-7 rather than retrying forever.

**Retry schedule (explicit contract, documented per Refine cycle below):**

| Attempt | Delay before this attempt | Cumulative elapsed |
|---|---|---|
| 1 (initial) | 0 | 0 |
| 2 | ~1 min ± jitter | ~1 min |
| 3 | ~5 min ± jitter | ~6 min |
| 4 | ~30 min ± jitter | ~36 min |
| 5 | ~2 hr ± jitter | ~2.6 hr |
| 6 | ~6 hr ± jitter | ~8.6 hr |
| 7 | ~24 hr ± jitter | ~32.6 hr |
| 8 (final) | ~48 hr ± jitter | ~80.6 hr (~3.4 days) |

**Acceptance Criteria:**
- [ ] GIVEN a delivery attempt fails with a retryable error (timeout, 5xx, connection error) WHEN the next attempt is scheduled THEN its delay SHALL follow the exponential schedule above with bounded jitter, never a fixed or unbounded interval
- [ ] GIVEN a delivery attempt fails with a non-retryable error (e.g. a 4xx indicating the receiver explicitly rejected the payload) WHEN the worker observes it THEN it MAY be routed to S-7's dead-letter path immediately rather than consuming the full retry schedule, and this distinction SHALL be explicit and documented, not implicit
- [ ] GIVEN attempt 8 (the final scheduled attempt) also fails WHEN the schedule is exhausted THEN the delivery SHALL transition to S-7's dead-letter handling rather than being silently dropped or retried indefinitely

**Technical Context:**
- **Pattern:** exponential backoff with jitter, borrowed from Stripe/AWS SDK retry conventions (Pattern phase, ADAPT)
- **Files:** `[ASSUMED]` `services/webhooks/worker/backoff.*`
- **Dependencies:** S-5

**Agent Hints:**
- **Class:** Builder
- **Context:** S-5's dispatcher failure classification (retryable vs. non-retryable)
- **Gates:** P0 — each schedule tier covered by a deterministic (seeded-jitter) unit test; max-attempts hand-off to S-7 covered by an integration test

---

#### 📋 STORY: S-7 Dead-letter handling + manual re-drive

> 🟡 P1

**Description:** As a tenant, I want to know when a delivery has exhausted retries and be able to manually re-trigger it once I've fixed my endpoint, so that a permanent failure doesn't mean permanent, irrecoverable data loss.
**Timebox:** ≤3d
**Risk:** P1 (degrades recoverability if wrong; does not itself risk data leakage or over-delivery)

**Action Plan:**
1. **Create:** a dead-letter state for deliveries that exhaust S-6's schedule (or hit a non-retryable error), retaining the full delivery envelope so it can be re-dispatched later without reconstructing it from scratch.
2. **Extend:** the customer-facing API/dashboard (S-8) with a "redeliver" action on any dead-lettered (or even successfully-delivered, for debugging) delivery.
3. **Test:** a manual redrive re-uses S-4's stable event ID (so receiver-side idempotency still applies) but resets the attempt/backoff state as a fresh attempt sequence.

**Acceptance Criteria:**
- [ ] GIVEN a delivery exhausts its retry schedule WHEN the final attempt fails THEN it SHALL transition to a dead-lettered state visible to the tenant, never silently disappear
- [ ] GIVEN a tenant triggers manual redrive on a dead-lettered delivery WHEN redrive is requested THEN the platform SHALL dispatch a fresh attempt using the original stable event ID, and the tenant SHALL see the new attempt reflected in the delivery log (S-8)
- [ ] GIVEN a delivery is dead-lettered WHEN 30 days elapse without manual redrive THEN the platform's retention policy SHALL apply (explicit retention window — see Refine cycle below — rather than unbounded storage growth)

**Technical Context:**
- **Pattern:** dead-letter-queue idiom (SQS/RabbitMQ DLQ convention, Pattern phase)
- **Files:** `[ASSUMED]` `services/webhooks/worker/deadletter.*`, `services/webhooks/api/redrive.*`
- **Dependencies:** S-6

**Agent Hints:**
- **Class:** Builder
- **Context:** S-6's failure classification and S-4's envelope shape
- **Gates:** P1 — redrive round-trip test (dead-letter → manual redrive → success) green; retention-window deletion covered by a scheduled-job test

---

#### 📋 STORY: S-8 Delivery log/status API + dashboard

> 🔴 P0 — directly satisfies the mission's explicit "failures must be observable to customers" requirement

**Description:** As a tenant, I want to see every delivery attempt for my endpoints — timestamp, event type, response code, and current retry/dead-letter state — so that I can diagnose integration problems myself without opening a support ticket.
**Timebox:** ≤5d
**Risk:** P0 (this is not a nice-to-have polish story; it is one of the three pillars named directly in the mission)

**Action Plan:**
1. **Create:** a tenant-scoped API and dashboard view listing delivery attempts, filterable by endpoint/event type/status/time range, backed by the delivery-log store selected in Explore (H2's relational status table, populated by every worker attempt regardless of outcome).
2. **Extend:** each delivery-attempt record with enough detail (request headers sent, response status/body — redacted per the rule below, latency) to actually diagnose a failure, matching the observability bar set by the Pattern-phase exemplars (GitHub's per-delivery inspector).
3. **Test:** a tenant can never see another tenant's delivery records under any filter combination (same isolation bar as S-1); a failed delivery's diagnostic detail is sufficient to distinguish "your endpoint returned 500" from "your endpoint never responded" from "your endpoint returned 4xx and rejected the payload."

**Acceptance Criteria:**
- [ ] GIVEN a tenant queries their delivery log WHEN attempts exist for their endpoints THEN each attempt SHALL show timestamp, event type, target endpoint, response status (or timeout/connection-error classification), attempt number, and current state (pending-retry / succeeded / dead-lettered)
- [ ] GIVEN a delivery attempt's response body is stored for diagnostics WHEN displayed to the tenant THEN any platform-internal secrets (e.g. signing keys, internal request headers not part of the documented envelope) SHALL be redacted before storage or display — customer-controlled response content from their own endpoint is not redacted, only platform-internal data is
- [ ] GIVEN a tenant filters their delivery log by endpoint, event type, status, or time range WHEN the filter is applied THEN results SHALL be scoped strictly to that tenant regardless of filter combination (cross-tenant leakage test, same bar as S-1)

**Technical Context:**
- **Pattern:** queryable delivery-log store (Explore Selection: H1's status-store design, absorbed into H2's hybrid architecture), rendering vocabulary borrowed from GitHub's delivery-inspector UI (Pattern phase)
- **Files:** `[ASSUMED]` `services/webhooks/api/deliveries.*`, `services/webhooks/db/migrations/*_create_delivery_log.*`, `[ASSUMED]` dashboard frontend component
- **Dependencies:** S-3, S-5, S-6

**Agent Hints:**
- **Class:** Builder (API/dashboard) + Reasoner (redaction-boundary correctness — getting the "what's platform-internal vs. customer's own data" line wrong is a security-relevant mistake, not just a UX one)
- **Context:** S-4's envelope field list (to know exactly what's platform-internal vs. customer-visible-by-design)
- **Gates:** P0 — cross-tenant isolation test (same suite family as S-1); redaction test asserting no platform secret ever appears in a tenant-visible payload

---

#### 📋 STORY: S-9 Failure alerting + auto-disable on sustained failure

> 🟡 P1 — independently deferrable

**Description:** As a tenant, I want to be proactively notified when my endpoint is persistently failing, rather than discovering it only by noticing missing data days later, so that I can fix my integration before it causes downstream problems for me.
**Timebox:** ≤2d
**Risk:** P1 (degrades experience/trust if missing; does not itself risk over-delivery or data leakage)

**Action Plan:**
1. **Create:** a sustained-failure threshold (e.g. N consecutive dead-lettered deliveries, or a high failure rate over a rolling window) computed from S-8's delivery-log data.
2. **Configure:** an alert (email/in-app notification) to the tenant when the threshold is crossed, and an explicit auto-disable of the specific endpoint (not the whole tenant) once failures are severe/sustained enough that continuing to attempt delivery is pure waste — surfaced clearly as "why this endpoint is disabled" in the dashboard, with a one-action re-enable once the tenant believes it's fixed.
3. **Test:** the threshold computation is deterministic given a fixture failure history; auto-disable affects only the specific failing endpoint, never sibling endpoints on the same tenant.

**Acceptance Criteria:**
- [ ] GIVEN an endpoint crosses the sustained-failure threshold WHEN detected THEN the tenant SHALL receive an alert identifying the specific endpoint and a summary of recent failures (pulled from S-8's log, not a separate ad-hoc data path)
- [ ] GIVEN an endpoint is auto-disabled after sustained failure THEN it SHALL stop consuming retry/dispatch capacity entirely, and the dashboard SHALL clearly state why it was disabled and how to re-enable it
- [ ] GIVEN a tenant has multiple endpoints and only one crosses the failure threshold WHEN auto-disable triggers THEN only that specific endpoint SHALL be affected — sibling endpoints on the same tenant SHALL continue receiving deliveries normally

**Technical Context:**
- **Pattern:** threshold-based alerting + circuit-breaker-style auto-disable, scoped per-endpoint (extends S-5's fairness philosophy — a chronically dead endpoint shouldn't keep consuming capacity, this time by its own choice rather than by imposition)
- **Files:** `[ASSUMED]` `services/webhooks/worker/health.*`, notification integration (existing platform notification system, if any)
- **Dependencies:** S-8

**Agent Hints:**
- **Class:** Builder
- **Context:** S-8's delivery-log schema; any existing platform notification/alerting integration
- **Gates:** P1 — per-endpoint (not per-tenant) blast-radius test for auto-disable is mandatory

---

#### 📋 STORY: S-10 Per-tenant secret rotation + isolation hardening

> 🔴 P0

**Description:** As a security-conscious tenant admin, I want to rotate my endpoint's signing secret on demand (e.g. after a suspected leak) without downtime, and I want assurance that no cross-tenant data path exists anywhere in this subsystem, so that a compromise of one tenant's secret or a bug in the system cannot expose or spoof another tenant's data.
**Timebox:** ≤3d
**Risk:** P0 (the mission's multi-tenant NFR is explicit; this story is the dedicated hardening pass across every other story's isolation claims)

**Action Plan:**
1. **Create:** secret-rotation flow supporting a dual-secret grace period (old + new secret both valid for a bounded overlap window) so in-flight/retrying deliveries signed under the old secret don't suddenly fail verification mid-rotation.
2. **Audit:** every story S-1–S-9's data-access paths (endpoint CRUD, fan-out, dispatch, delivery log, alerting) for a cross-tenant leak vector — this story's Action Plan is explicitly a hardening/audit pass across the whole feature, not a standalone piece of new functionality.
3. **Test:** rotation-during-in-flight-retry scenario (a delivery queued before rotation, dispatched after) verifies correctly against whichever secret was valid at signing time within the grace window.

**Acceptance Criteria:**
- [ ] GIVEN a tenant rotates an endpoint's secret WHEN the rotation completes THEN both the old and new secret SHALL verify successfully for a documented grace window, after which only the new secret SHALL be valid
- [ ] GIVEN a delivery was signed before rotation and is retried after rotation but within the grace window WHEN the receiver verifies it THEN verification SHALL succeed against the secret that was current at signing time
- [ ] GIVEN the cross-tenant isolation audit runs across S-1 (endpoints), S-3 (fan-out), S-5 (dispatch), S-8 (delivery log), and S-9 (alerting) WHEN each is checked THEN no code path SHALL be found capable of returning, dispatching, or alerting on another tenant's data — any finding SHALL be filed as a P0 fix, not deferred

**Technical Context:**
- **Pattern:** dual-secret rotation window (industry-standard for webhook/API-key rotation without downtime)
- **Files:** `[ASSUMED]` `services/webhooks/api/secrets.*`; audit touches files from S-1, S-3, S-5, S-8, S-9
- **Dependencies:** S-1 (secrets exist), and conceptually all of S-1–S-9 (audit scope)

**Agent Hints:**
- **Class:** Reasoner + Reviewer (this is fundamentally a cross-cutting security audit; a reviewer-class pass across every other story's isolation claims is the actual deliverable, not new isolated code)
- **Context:** full delivery pipeline from S-1 through S-9
- **Gates:** P0 — dual-secret grace-window test green; audit findings tracked to zero open P0s before this story is considered done

---

## T — TEST (6-layer verification)

| # | Layer | Result |
|---|---|---|
| 1 | **Structural** | ✓ Hierarchy intact (Theme→Project→5 Features→10 Stories), no orphaned tasks, stories independent modulo the documented Construct sequencing |
| 2 | **Self-Consistency** | ✓ See below — 3 alternative decompositions, ~75% overlap → HIGH confidence, stable |
| 3 | **Dependency** | ⚠ Partial — real file paths, existing broker availability (G2), and the true internal event source (G4) cannot be enumerated against a real codebase; flagged, not silently assumed complete. Migration path: additive new subsystem, no destructive migration, but S-10's dual-secret rotation must be designed before any secret ever ships (cannot be retrofitted painlessly) |
| 4 | **Constraint** | ✓ Timeboxes realistic (all ≤5d); the mission's core NFR (multi-tenant fairness) has a dedicated P0 story (S-5) plus a dedicated hardening/audit story (S-10), not just an implicit assumption; security implications (SSRF, signing, replay, secret rotation) each have an explicit story rather than being folded silently into a "build the feature" story |
| 5 | **Process Reward** | ✓ Ordering (register → verify → sign/fan-out → dispatch-with-fairness → backoff → dead-letter/observe → alert) monotonically reduces risk: the highest-risk property (no cross-tenant leakage, no unbounded blast radius from one bad endpoint) is proven in Phases 1–4, before observability/alerting polish is layered on top |
| 6 | **Adversarial** | ✓ See checklist below |

**Self-Consistency check (3 alternative decompositions):**

- **Decomposition A (this spec):** registration/verification / delivery-engine / retry-and-DLQ / observability / security-hardening — 5 features, grouped by feature slice.
- **Decomposition B:** "control plane" (merges S-1+S-2+S-10's secret-rotation half) / "delivery pipeline" (merges S-3+S-4+S-5+S-6+S-7) / "customer-facing surface" (merges S-8+S-9) — 3 bundles, same conceptual chunks regrouped by delivery-boundary.
- **Decomposition C:** grouped by execution layer instead of feature — "API/control-plane layer" / "worker/dispatch layer" / "data/observability layer" / "cross-cutting security" — same coverage, different axis (mirrors S-10's own cross-cutting nature).

All three surface the same underlying concepts (registration+verification, signing+fan-out+dispatch, backoff+DLQ, tenant-facing observability, security hardening) — estimated **~75% story-content overlap** → **HIGH confidence, decomposition is stable.** Decomposition A was kept because P0/P1 risk tags and the fairness/isolation NFR map more cleanly onto feature slices (each with its own dedicated story) than onto delivery bundles or execution layers, which matters directly for the Confidence factors below.

**Adversarial checklist (Failure Taxonomy, `scoring.md`):**

| Failure mode | Checked | Finding |
|---|---|---|
| Under-specification | ✓ | S-5's fairness mechanism and S-8's redaction boundary were both under-specified in the first pass — fixed in Refine below |
| Over-specification | ✓ | No rigid constraint blocks a valid implementation; file paths marked `[ASSUMED]`, broker-vs-DB-queue choice explicitly left open pending G2 |
| Dependency blindness | ⚠ | True broker availability (G2) and internal event source (G4) are unknown — mitigated by designing S-5's fairness layer to be broker-agnostic (application-level, not relying on queue-native fairness) rather than pretending the infra is known |
| Assumption drift | — | No earlier-phase discovery yet invalidates a later step; re-open triggers documented for H3/H4 if their preconditions (G2-adjacent org context) resolve differently |
| Scope creep | ✓ | Boundary table enforced; payload templating/filtering, exactly-once delivery, multi-region failover, and customer-authored event sources explicitly kept out |
| Premature optimization | ✓ | Complexity 10/12 was handled by adding rigor (4 hypotheses, explicit TRANCE-boundary discussion), not by over-architecting the delivery mechanism itself; H3 (the most "sophisticated" option) was rejected precisely for disproportionate operational weight |
| Stale context | n/a | No prior file reads to go stale; this is a fresh cycle |

**Gate:** Minor gaps only (Dependency layer ⚠, one adversarial ⚠, same root cause: unknown target infra/event source) → **Refine (1 cycle).**

---

## R — REFINE

**Cycle 1 diagnosis:** Test surfaced two related under-specification gaps: (a) S-5's per-tenant fairness mechanism originally said "cap concurrency per endpoint" without naming *where* that cap is enforced, which matters because most managed message queues don't offer native per-key fairness — an implementer could wire S-5 against a queue's native concurrency controls and silently reintroduce the noisy-neighbor problem the story exists to prevent; (b) S-8's redaction requirement originally said "redact sensitive data" without drawing the actual line between platform-internal secrets and the customer's own response content, which is exactly the kind of ambiguous boundary a security reviewer would challenge.

**Root cause:** both gaps trace back to naming a *property* ("fairness," "redaction") without naming the *mechanism boundary* that makes the property mechanically checkable — the same root cause pattern, applied twice.

**Prescription (applied):** S-5's Action Plan and Technical Context now explicitly require the fairness cap to be enforced at the **worker dispatch layer**, independent of the underlying queue's own concurrency model — this is already reflected in the Construct section above. S-8's AC #2 now explicitly draws the line ("platform-internal secrets... redacted... customer-controlled response content... not redacted") and S-6's retry schedule and S-7's 30-day retention window were made explicit tables/numbers rather than left as "a reasonable schedule" during this same pass, closing the same class of gap before a reviewer had to ask.

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | unchanged — no clarity issue found |
| Completeness | 3 | 4 | fairness-enforcement layer now explicit in S-5; redaction boundary now explicit in S-8; retry schedule and retention window now tabular/numeric in S-6/S-7 |
| Actionability | 3 | 4 | an implementing agent no longer has to infer where fairness is enforced, where the redaction line falls, or what the backoff numbers actually are |
| Efficiency | 4 | 4 | unchanged |
| Testability | 3 | 4 | all three fixes are independently unit/integration-testable assertions (dispatch-layer concurrency test; redaction-boundary test; seeded-jitter schedule test) |

**Mean:** 3.4 → 4.0 (**+0.6**, above the 0.3 diminishing-returns floor — this cycle earned its keep). **No dimension decreased** — no oscillation. **Cycle 1 target (all ≥3) met and exceeded (all ≥4); stopping at 1 cycle** rather than continuing to a cycle whose marginal gain would likely fall under the diminishing-returns threshold.

**Re-verify:** re-ran the Structural/Constraint/Adversarial layers against the updated S-5/S-6/S-7/S-8 — no new gaps introduced, no prior pass invalidated.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (/3) | Basis |
|---|---|---|
| Pattern Match | 2 | Strong external pattern family (Stripe/Svix/SQS+DLQ) and a clear ADAPT strategy, but no in-repo template exists to apply directly (G1) |
| Requirement Clarity | 2 | The mission's three pillars (registration, retry/backoff, observability) are unambiguous; the implementation environment (broker availability, event source, scale) is not (CLARIFY G2/G4) |
| Decomposition Stability | 3 | ~75% self-consistency overlap across 3 alternative decompositions — HIGH |
| Constraint Compliance | 2 | 6-layer Test passed with 2 flagged-but-mitigated gaps, both traced to the same root cause (unknown target infra/event source), not to spec quality; both closed a level further in Refine |

**Weighted Confidence:** (2+2+3+2)/12 × 100 = **75%**

**Decision: VALIDATE (70–84% band) — deliver with flags, human reviews.**

**Explicit tension carried forward from Scope:** the raw complexity score (10/12) nominally recommends human-in-the-loop *before* proceeding, while this Confidence factor set lands at 75%/VALIDATE (deliver-then-review). Both are honored rather than one overriding the other silently: this spec is delivered as complete and decision-ready, but the punch list below is the human-in-the-loop step the complexity score called for, deliberately sequenced *after* delivery rather than *before* it, since no live human turn was available mid-session.

**What a human reviewer should specifically validate before this becomes AUTO_PROCEED-worthy:**
1. Confirm whether broker infrastructure already exists (CLARIFY G2) — this decides whether S-5 is built against a real broker+DLQ or the DB-leasing fallback, though the fairness/observability contracts are unchanged either way.
2. Confirm the delivery-guarantee assumption (at-least-once, G3) and the event-source assumption (fan-out consumer, not originator, G4) — either resolving differently is a scope change, not a Refine-cycle patch.
3. Re-anchor every `[ASSUMED]` file path in Construct against the real target service, and have security/compliance specifically review S-2 (SSRF), S-4 (signing/replay), and S-10 (rotation/isolation audit) given how explicitly the mission named multi-tenant isolation as a requirement.
4. Confirm the retry schedule (S-6) and dead-letter retention window (S-7) against any existing platform-wide conventions for similar async-retry systems, if one already exists.

### Deliverables produced (dual-format contract + ECL sidecar)

| Artifact | Path |
|---|---|
| Plan artifact (this file) | `/tmp/ramza-s2/ac003/AB-T1-spectra-r2.out.md` (requested output path — explicit override, honored) |
| Authoritative mirror (Output Discipline rule 2) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.md` |
| Agent handoff (YAML) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.yaml` |
| State machine (JSON) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.state.json` |
| ECL v2.0 envelope sidecar | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.envelope.json` (emitted because `ECL_VERSION=2.0` is present at `/tmp/spectra-pilot/.eidolons/spectra/ECL_VERSION`) |

Per Output Discipline rule 2: since the mission explicitly named a path outside `.spectra/`, that path was honored as the primary deliverable, and the authoritative copy was mirrored under `.spectra/plans/` regardless, together with the full Assemble deliverable set (YAML handoff, state JSON, ECL envelope) that a SPECTRA Assemble phase produces per `SPEC.md` and `skills/planning.md`.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 75
  complexity: 10
  spectra_version: "4.11.0"
  thread_id: "019f3269-4d5b-76af-9764-3e0b84395561"

projects:
  - id: "P-1"
    name: "Webhook Delivery Subsystem"
    features:
      - id: "F-1"
        name: "Endpoint Registration & Subscription Management"
        stories:
          - id: "S-1"
            title: "Endpoint CRUD + subscription API"
            timebox: "<=3d"
            risk: "P0"
            action_plan:
              - verb: "Create"
                target: "tenant-scoped CRUD API for webhook endpoints + event-type subscriptions"
              - verb: "Configure"
                target: "per-tenant storage scoping, defense-in-depth against cross-tenant reads"
              - verb: "Test"
                target: "cross-tenant isolation + URL validation (HTTPS-only, no loopback/private targets)"
            acceptance_criteria:
              - given: "a tenant admin submits a valid HTTPS URL and event types"
                when: "the endpoint is created"
                then: "it is persisted disabled until ownership verification (S-2) succeeds"
              - given: "a request scoped to tenant A"
                when: "it targets an endpoint belonging to tenant B"
                then: "the API returns not-found, never leaking existence"
              - given: "an endpoint URL is non-HTTPS or resolves to a private/loopback address"
                when: "submitted"
                then: "the API rejects it with a clear validation error"
            agent_hints:
              recommended_class: "builder"
              context_files: ["services/webhooks/api/endpoints.* [ASSUMED]"]
              validation_gates:
                p0: "cross-tenant isolation test green"
          - id: "S-2"
            title: "Ownership-verification challenge (anti-SSRF/abuse)"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "challenge-response verification flow for newly-registered endpoints"
              - verb: "Modify"
                target: "endpoint state machine: enabled only after verification, re-verify on URL change"
              - verb: "Test"
                target: "unreachable URLs never reach enabled; DNS-rebinding defense at request time"
            acceptance_criteria:
              - given: "a newly-registered endpoint"
                when: "the verification challenge is not completed"
                then: "the endpoint remains disabled, zero live deliveries"
              - given: "a verified endpoint's URL is changed"
                when: "the update is saved"
                then: "it reverts to disabled and requires re-verification"
              - given: "a verification probe targets a private/internal range at request time"
                when: "resolved"
                then: "the probe is blocked server-side"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["services/webhooks/api/verification.* [ASSUMED]"]
              validation_gates:
                p0: "dedicated SSRF/rebinding regression suite, security-reviewed"
      - id: "F-2"
        name: "Event Delivery Engine"
        stories:
          - id: "S-3"
            title: "Event fan-out: publish -> per-subscription delivery message"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-1", "S-4"]
            action_plan:
              - verb: "Create"
                target: "fan-out consumer resolving enabled subscriptions per event"
              - verb: "Extend"
                target: "delivery-message shape carrying a stable event ID across retries"
              - verb: "Test"
                target: "zero-match produces zero messages; N-match produces exactly N messages"
            acceptance_criteria:
              - given: "an event matches one or more enabled subscriptions"
                when: "fan-out runs"
                then: "exactly one delivery message per matching endpoint is produced, same event ID"
              - given: "an event matches zero subscriptions"
                when: "fan-out runs"
                then: "no delivery message is produced and no error is raised"
              - given: "fan-out fails or restarts mid-batch"
                when: "it resumes"
                then: "reprocessing does not produce duplicate delivery messages beyond documented at-least-once semantics"
            agent_hints:
              recommended_class: "builder"
              context_files: ["services/webhooks/worker/fanout.* [ASSUMED]"]
              validation_gates:
                p0: "zero-match and N-match cases covered; no duplicate event IDs under simulated restart"
          - id: "S-4"
            title: "HMAC signing + delivery envelope (idempotency-safe)"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "delivery envelope contract: signature, timestamp, stable event id, attempt count, event type headers"
              - verb: "Configure"
                target: "signature verification guidance + timestamp tolerance window for replay protection"
              - verb: "Test"
                target: "deterministic signature verification; event-id stability across simulated retries"
            acceptance_criteria:
              - given: "a delivery is dispatched"
                when: "the request is sent"
                then: "it includes a valid HMAC-SHA256 signature over timestamp + raw body"
              - given: "the same event is retried after transient failure"
                when: "subsequent attempts are dispatched"
                then: "the event id stays identical while attempt count increments"
              - given: "a documented timestamp tolerance window"
                when: "a request falls outside it"
                then: "receivers are instructed to reject it (replay protection)"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["services/webhooks/worker/envelope.* [ASSUMED]", "services/webhooks/worker/signing.* [ASSUMED]"]
              validation_gates:
                p0: "signature round-trip test; idempotency-key stability test"
          - id: "S-5"
            title: "Delivery worker: HTTP dispatch with per-tenant fairness"
            timebox: "<=5d"
            risk: "P0"
            dependencies: ["S-3", "S-4"]
            action_plan:
              - verb: "Create"
                target: "delivery worker dispatching HTTPS requests per envelope, bounded per-attempt timeout"
              - verb: "Configure"
                target: "per-endpoint concurrency cap enforced at dispatch layer, independent of queue's own model"
              - verb: "Test"
                target: "one dead endpoint alongside healthy endpoints from other tenants; assert no latency degradation"
            acceptance_criteria:
              - given: "one tenant's endpoint is unresponsive or erroring"
                when: "other tenants' deliveries are dispatched concurrently"
                then: "their latency remains unaffected (isolation, not best-effort)"
              - given: "a dispatch attempt exceeds the timeout"
                when: "the worker observes it"
                then: "it is recorded as a failure and handed to backoff logic, never left hanging"
              - given: "a per-endpoint concurrency cap is reached"
                when: "more deliveries for that endpoint are ready"
                then: "they queue behind the cap without blocking other endpoints"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["services/webhooks/worker/dispatcher.* [ASSUMED]", "services/webhooks/worker/fairness.* [ASSUMED]"]
              validation_gates:
                p0: "noisy-neighbor isolation test (mandatory, not optional) green"
      - id: "F-3"
        name: "Retry, Backoff & Dead-Letter Handling"
        stories:
          - id: "S-6"
            title: "Exponential backoff with jitter + max-attempts policy"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-5"]
            action_plan:
              - verb: "Configure"
                target: "8-tier exponential backoff schedule with jitter, ~3.4 day total retry window"
              - verb: "Modify"
                target: "dispatcher to schedule next attempt at now + backoff(n) +/- jitter"
              - verb: "Test"
                target: "each tier asserted independently; jitter bounded; max-attempts hands off to dead-letter"
            acceptance_criteria:
              - given: "a delivery attempt fails with a retryable error"
                when: "the next attempt is scheduled"
                then: "its delay follows the documented exponential+jitter schedule"
              - given: "a delivery attempt fails with a non-retryable error"
                when: "the worker observes it"
                then: "it may route to dead-letter immediately, explicitly and documented"
              - given: "the final scheduled attempt also fails"
                when: "the schedule is exhausted"
                then: "the delivery transitions to dead-letter handling, never dropped or retried forever"
            agent_hints:
              recommended_class: "builder"
              context_files: ["services/webhooks/worker/backoff.* [ASSUMED]"]
              validation_gates:
                p0: "seeded-jitter unit tests per tier; max-attempts hand-off integration test"
          - id: "S-7"
            title: "Dead-letter handling + manual re-drive"
            timebox: "<=3d"
            risk: "P1"
            dependencies: ["S-6"]
            action_plan:
              - verb: "Create"
                target: "dead-letter state retaining full delivery envelope for later redrive"
              - verb: "Extend"
                target: "dashboard/API with a redeliver action"
              - verb: "Test"
                target: "manual redrive reuses stable event id, resets attempt/backoff state"
            acceptance_criteria:
              - given: "a delivery exhausts its retry schedule"
                when: "the final attempt fails"
                then: "it transitions to a visible dead-lettered state, never silently disappears"
              - given: "a tenant triggers manual redrive"
                when: "redrive is requested"
                then: "a fresh attempt dispatches using the original event id, visible in the delivery log"
              - given: "a delivery is dead-lettered"
                when: "30 days elapse without redrive"
                then: "the documented retention policy applies"
            agent_hints:
              recommended_class: "builder"
              context_files: ["services/webhooks/worker/deadletter.* [ASSUMED]", "services/webhooks/api/redrive.* [ASSUMED]"]
              validation_gates:
                p1: "redrive round-trip test; retention-window deletion job test"
      - id: "F-4"
        name: "Customer-Facing Delivery Observability"
        stories:
          - id: "S-8"
            title: "Delivery log/status API + dashboard"
            timebox: "<=5d"
            risk: "P0"
            dependencies: ["S-3", "S-5", "S-6"]
            action_plan:
              - verb: "Create"
                target: "tenant-scoped delivery-attempt API/dashboard, filterable by endpoint/type/status/time"
              - verb: "Extend"
                target: "each attempt record with request/response diagnostic detail, redacted per boundary rule"
              - verb: "Test"
                target: "cross-tenant isolation under any filter combination; failure-cause distinguishability"
            acceptance_criteria:
              - given: "a tenant queries their delivery log"
                when: "attempts exist for their endpoints"
                then: "each shows timestamp, event type, endpoint, response status/classification, attempt number, state"
              - given: "a delivery attempt's response body is stored"
                when: "displayed to the tenant"
                then: "platform-internal secrets are redacted; the customer's own response content is not"
              - given: "a tenant filters by endpoint/type/status/time"
                when: "the filter is applied"
                then: "results are scoped strictly to that tenant regardless of filter combination"
            agent_hints:
              recommended_class: "builder"
              context_files: ["services/webhooks/api/deliveries.* [ASSUMED]", "services/webhooks/db/migrations/*_create_delivery_log.* [ASSUMED]"]
              validation_gates:
                p0: "cross-tenant isolation test; redaction-boundary test"
          - id: "S-9"
            title: "Failure alerting + auto-disable on sustained failure"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-8"]
            action_plan:
              - verb: "Create"
                target: "sustained-failure threshold computed from delivery-log data"
              - verb: "Configure"
                target: "tenant alert + per-endpoint auto-disable with clear dashboard reason and re-enable action"
              - verb: "Test"
                target: "deterministic threshold computation; auto-disable scoped to the specific endpoint only"
            acceptance_criteria:
              - given: "an endpoint crosses the sustained-failure threshold"
                when: "detected"
                then: "the tenant receives an alert identifying the endpoint and a failure summary"
              - given: "an endpoint is auto-disabled after sustained failure"
                then: "it stops consuming dispatch capacity and the dashboard states why + how to re-enable"
              - given: "only one of a tenant's multiple endpoints crosses the threshold"
                when: "auto-disable triggers"
                then: "only that endpoint is affected, siblings continue normally"
            agent_hints:
              recommended_class: "builder"
              context_files: ["services/webhooks/worker/health.* [ASSUMED]"]
              validation_gates:
                p1: "per-endpoint (not per-tenant) blast-radius test"
      - id: "F-5"
        name: "Security & Tenant Isolation"
        stories:
          - id: "S-10"
            title: "Per-tenant secret rotation + isolation hardening"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "dual-secret rotation flow with bounded grace-period overlap"
              - verb: "Modify"
                target: "audit S-1/S-3/S-5/S-8/S-9 data-access paths for cross-tenant leak vectors"
              - verb: "Test"
                target: "rotation-during-in-flight-retry scenario verifies against secret valid at signing time"
            acceptance_criteria:
              - given: "a tenant rotates an endpoint's secret"
                when: "rotation completes"
                then: "both old and new secret verify during the documented grace window, then only new"
              - given: "a delivery signed before rotation is retried after rotation, within the grace window"
                when: "the receiver verifies it"
                then: "verification succeeds against the secret current at signing time"
              - given: "the cross-tenant isolation audit runs across S-1/S-3/S-5/S-8/S-9"
                when: "each is checked"
                then: "no path returns/dispatches/alerts on another tenant's data; findings filed as P0, not deferred"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["services/webhooks/api/secrets.* [ASSUMED]"]
              validation_gates:
                p0: "dual-secret grace-window test; zero open P0 audit findings"

execution_plan:
  phases:
    - name: "Phase 1 -- Foundation"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Phase 2 -- Verification & signing (parallel)"
      stories: ["S-2", "S-4"]
      agent_class: "reasoner"
    - name: "Phase 3 -- Fan-out"
      stories: ["S-3"]
      agent_class: "builder"
    - name: "Phase 4 -- Dispatch & isolation hardening (parallel)"
      stories: ["S-5", "S-10"]
      agent_class: "reasoner"
    - name: "Phase 5 -- Backoff"
      stories: ["S-6"]
      agent_class: "builder"
    - name: "Phase 6 -- Dead-letter & observability (parallel)"
      stories: ["S-7", "S-8"]
      agent_class: "builder"
    - name: "Phase 7 -- Alerting"
      stories: ["S-9"]
      agent_class: "builder"
```

### State Machine (JSON)

```json
{
  "session_id": "019f3269-4d65-7b44-88a8-129599c37019",
  "spec_id": "SPEC-2026-07-05-001",
  "goal": "Design a multi-tenant webhook delivery subsystem: endpoint registration, reliable delivery with retry/backoff, and customer-facing failure observability.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Endpoint CRUD + subscription API", "status": "pending", "dependencies": [], "files_affected": ["services/webhooks/api/endpoints.* [ASSUMED]"], "verification_command": "test: cross-tenant isolation + URL validation", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Ownership-verification challenge", "status": "pending", "dependencies": [1], "files_affected": ["services/webhooks/api/verification.* [ASSUMED]"], "verification_command": "test: SSRF/rebinding regression suite", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Event fan-out to delivery messages", "status": "pending", "dependencies": [1, 4], "files_affected": ["services/webhooks/worker/fanout.* [ASSUMED]"], "verification_command": "test: zero-match/N-match + no-duplicate-id under restart", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "HMAC signing + delivery envelope", "status": "pending", "dependencies": [1], "files_affected": ["services/webhooks/worker/envelope.* [ASSUMED]", "services/webhooks/worker/signing.* [ASSUMED]"], "verification_command": "test: signature round-trip + idempotency-key stability", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Delivery worker with per-tenant fairness", "status": "pending", "dependencies": [3, 4], "files_affected": ["services/webhooks/worker/dispatcher.* [ASSUMED]", "services/webhooks/worker/fairness.* [ASSUMED]"], "verification_command": "test: noisy-neighbor isolation (mandatory)", "estimated_timebox": "<=5d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Exponential backoff + max-attempts", "status": "pending", "dependencies": [5], "files_affected": ["services/webhooks/worker/backoff.* [ASSUMED]"], "verification_command": "test: seeded-jitter per-tier + max-attempts hand-off", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Dead-letter handling + manual re-drive", "status": "pending", "dependencies": [6], "files_affected": ["services/webhooks/worker/deadletter.* [ASSUMED]", "services/webhooks/api/redrive.* [ASSUMED]"], "verification_command": "test: redrive round-trip + retention-window deletion", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 8, "story_id": "S-8", "title": "Delivery log/status API + dashboard", "status": "pending", "dependencies": [3, 5, 6], "files_affected": ["services/webhooks/api/deliveries.* [ASSUMED]"], "verification_command": "test: cross-tenant isolation + redaction boundary", "estimated_timebox": "<=5d", "replanning_notes": null },
    { "id": 9, "story_id": "S-9", "title": "Failure alerting + auto-disable", "status": "pending", "dependencies": [8], "files_affected": ["services/webhooks/worker/health.* [ASSUMED]"], "verification_command": "test: per-endpoint blast-radius", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 10, "story_id": "S-10", "title": "Secret rotation + isolation hardening", "status": "pending", "dependencies": [1], "files_affected": ["services/webhooks/api/secrets.* [ASSUMED]"], "verification_command": "test: dual-secret grace window + cross-tenant audit", "estimated_timebox": "<=3d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "phase": "Refine",
      "diagnosis": "S-5's fairness-enforcement layer and S-8's redaction boundary were named as properties without a mechanically checkable mechanism boundary; S-6/S-7 lacked explicit numeric schedules",
      "fix_applied": "pinned fairness enforcement to the worker dispatch layer (S-5); drew the explicit platform-internal-vs-customer-content redaction line (S-8); made the 8-tier backoff schedule and 30-day retention window explicit tables (S-6/S-7)",
      "mean_score_before": 3.4,
      "mean_score_after": 4.0,
      "oscillation_detected": false
    }
  ]
}
```

### CRYSTALIUM persistence

`mcp__crystalium__ingest` and `mcp__crystalium__session_end` were **not called** — no `mcp__crystalium__*` tools are reachable in this environment (see Memory pre-flight). Per `agent.md`/`skills/planning.md`, this is a documented graceful no-op, not a silent omission.

### Preflight Checklist

- [x] CLARIFY ran (not skipped — genuine ambiguity, resolved via risk-tagged assumptions, no live user turn available this run)
- [x] `spectra-conventions.md` checked — absent, generic defaults used and documented
- [x] Complexity scored (10/12); TRANCE-boundary discretionary call documented rather than silently resolved either way
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing/buy)
- [x] All 10 stories pass INVEST
- [x] All timeboxes valid (≤2d/≤3d/≤5d only, no story points, none >8d)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN (30 total — 3 per story)
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this file) + structured YAML/JSON (embedded above + mirrored as separate files)
- [x] Confidence score present with factor breakdown (75%, VALIDATE)
- [x] Plan saved as artifact at the requested path + mirrored under `.spectra/plans/`
- [x] Every mirrored/derived output path starts with `.spectra/`
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H3 workflow-engine, H4 buy-vendor — both with explicit re-open triggers; H1 explicitly noted as absorbed rather than rejected)

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*

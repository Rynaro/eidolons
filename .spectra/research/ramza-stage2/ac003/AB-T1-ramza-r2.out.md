---
eidolon: ramza
kind: spec
version: 0.1.0
created_at: 2026-07-05T13:11:39Z
plan: ac003-t1-r2
tier: full
status: ready-for-apivr
---

# Webhook Delivery Subsystem for a Multi-Tenant SaaS

## Scope

Intent class: REQUEST

In: A subsystem letting each tenant (customer) register one or more HTTPS
webhook endpoints, subscribe them to specific internal event types, receive
at-least-once delivery of those events with automatic retries and exponential
backoff, verify payload authenticity via signed requests, and observe
delivery health (per-event status and per-attempt history) without contacting
support. Covers: endpoint registration/management, secret issuance and
rotation, the delivery/retry/backoff engine, dead-letter handling with
customer notification, manual redelivery of a dead-lettered event, a
customer-facing delivery-status read API, and tenant-isolation/anti-SSRF
controls on customer-supplied URLs.

Out:
- Delivery transports other than HTTPS POST (no WebSocket push, no gRPC
  callbacks, no email/SMS fallback channel).
- Per-tenant configurable retry policy (attempt count, backoff curve) —
  platform sets one policy for all tenants in this iteration.
- Payload transformation/templating or event-type filtering rules beyond a
  static event-type subscription list.
- A webhook testing/simulation tool, request-replay UI, or local dev proxy
  beyond the single manual-redelivery action (AC-016).
- Multi-region/active-active delivery infrastructure.
- Billing or metering of webhook volume.
- Delivery to endpoints without a public IP (no relay/tunnel mechanism for
  customer-private networks).

Deferred:
- Per-tenant configurable retry/backoff policy — postponed until real usage
  data shows the platform default under- or over-retries for a meaningful
  segment of tenants.
- Automatic circuit-breaking of a chronically failing endpoint beyond the
  fixed backoff/dead-letter path — postponed pending signal on how often
  endpoints fail persistently enough to warrant it (see Risks).
- Payload encryption at rest beyond standard database-level encryption —
  deferred to a platform-wide encryption initiative if one exists, rather
  than being solved uniquely for this subsystem.

Assumptions:
- A durable, at-least-once job-queue technology is either already present in
  the platform or is introduced net-new for this subsystem (the `--new-dep`
  right-sizing flag was set on this basis). Risk if wrong: if a suitable
  durable queue already exists, Approach step 1 shrinks from "introduce" to
  "integrate," which would lower the files-est input and could move the tier
  down from full at re-right-sizing.
- Internal domain events (e.g., `invoice.paid`, `user.created`) are already
  emitted somewhere in the platform, and this subsystem only needs to
  subscribe to and enqueue on them. Risk if wrong: if no internal eventing
  exists yet, this spec would need to also define the emit side, which is a
  materially larger and distinct piece of work and would trigger a fresh
  right-sizing pass.
- "Customers" register endpoints through an authenticated tenant-admin
  role in an existing dashboard/API, with no further sub-user permission
  tiers required for this iteration. Risk if wrong: if webhook management
  must be split across finer-grained roles (e.g., a "developer" role
  distinct from "admin"), an RBAC dimension gets added to Story 1.
- The platform already has a notification channel (email or in-app) that
  Story 5 can reuse. Risk if wrong: if no such channel exists, dead-letter
  notification would need its own delivery mechanism, which is a new
  dependency in its own right and should be scoped separately rather than
  folded silently into this subsystem.
- No repo-local precedent exists to validate any of the above against: this
  consumer project ships no application code today (Pattern (P) search
  found no existing delivery/queue/webhook implementation), so this plan
  leans on documented, widely-used industry patterns (Stripe/GitHub-style
  webhook delivery) rather than an in-repo pattern match — reflected
  honestly in the Confidence score below (`pattern_match` scored low for
  exactly this reason).

Complexity (`ramza-score --rubric complexity`): 11/12 → **human_loop**
(scope 3, ambiguity 2, dependencies 3, risk 3 — recorded in
`.spectra/plans/ac003-t1-r2.state.json` gates[], label
`webhook-delivery-scope-complexity`). This routing is honest, not
decorative: the subsystem spans customer-facing security surface
(signing, SSRF-safe URL handling), multi-tenant fairness (rate limiting),
and a new durable-delivery dependency — a human should review this plan
before an executor starts (see Confidence).

## Approach

Selected: **Hyp A — durable job queue + worker pool with exponential
backoff, HMAC-signed payloads, and a customer-facing delivery-status API**
(`ramza-score --rubric explore` total 81/100, verdict `solid` — highest of
four scored hypotheses; see Rejected Alternatives).

1. Introduce (or integrate with, per the Assumptions risk above) a durable,
   at-least-once job queue. Every subscribed domain event enqueues exactly
   one delivery job per active, subscribed endpoint (AC-007), persisted
   before the triggering event is acknowledged (AC-010) — a worker crash
   must never silently drop a pending delivery.
2. A worker pool dequeues jobs and performs the outbound HTTPS POST. Every
   attempt — success or failure — is written to a delivery-attempt log
   (AC-013) with timestamp, HTTP status/error class, latency, and resulting
   state.
3. On a non-2xx response or timeout, compute the next retry delay via
   exponential backoff with jitter (to avoid thundering-herd retries against
   a recovering customer endpoint) and re-enqueue; never dispatch before
   that computed delay elapses (AC-008).
4. After the configured maximum retry count is exhausted, mark the event
   dead-lettered for that endpoint (AC-009) and notify the tenant admin
   through the platform's existing notification channel (AC-015). A tenant
   admin may manually trigger exactly one fresh delivery attempt on a
   dead-lettered event, resetting its attempt count (AC-016).
5. Sign every outbound payload: HMAC-SHA256 over the raw request body,
   with the exact delivery timestamp bound into the signature so a
   customer's own verification logic can enforce a replay-tolerance window
   (AC-011, AC-012). Support secret rotation with a grace window during
   which either the old or new secret verifies (AC-005, AC-006).
6. Validate every customer-supplied URL at registration time (reject
   non-HTTPS schemes and URLs resolving to private/loopback/link-local
   ranges — AC-002, AC-003) and **again at delivery time**, immediately
   before dispatch, to guard against DNS rebinding between registration and
   send (AC-018).
7. Scope every endpoint, event, delivery attempt, and log record to exactly
   one tenant at the data-access layer, never at the query-filter layer
   alone (AC-004). Enforce a per-tenant delivery-rate cap in the worker pool
   so one tenant's volume or one endpoint's misbehavior cannot delay another
   tenant's deliveries (AC-017). A signing secret is returned in the API
   response exactly once, at issuance or rotation, and never again on a
   subsequent read (AC-019). Deactivating an endpoint discards any of its
   still-pending queued jobs rather than dispatching them (AC-020).
8. Expose a tenant-scoped, read-only delivery-status API returning an
   event's current state (pending/delivered/retrying/dead-lettered) and its
   full attempt history (AC-014) — this is the customer-facing
   "observability" requirement; no dashboard UI is prescribed here, only the
   API contract an executor implements a UI against.

This is the industry-standard shape for reliable webhook delivery (the
pattern used by Stripe, GitHub, and similar platforms) rather than a novel
design — deliberately: proven failure modes (retry storms, replay attacks,
SSRF via user-supplied URLs, noisy-neighbor tenants) already have known
mitigations, and this subsystem's job is to apply them correctly, not
reinvent them (reflected in Hyp A's low `innovation` sub-score, which is a
feature here, not a weakness).

## Stories

### Story 1: Register and manage webhook endpoints

As a customer administrator, I want to register, update, and deactivate
webhook endpoints for my tenant, so that I control which URLs receive my
account's events without affecting other tenants.

Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier (Sonnet-class) — file-level action plan, named
pattern (tenant-scoped CRUD resource + secret issuance on create), no
step-scripting beyond the URL-validation guard in AC-002/AC-003. Two
security-adjacent details an independent critique flagged and this story
must also cover: the secret is write-once-readable (AC-019), and
deactivating an endpoint must stop its already-queued jobs from firing
(AC-020) — both are easy to miss in a straightforward CRUD implementation.

### Story 2: Reliable event delivery with retries and backoff

As a platform operator, I want every subscribed event delivered to a
customer's endpoint with automatic retries using exponential backoff, so
that a transient customer-side outage doesn't cause permanent event loss.

Timebox: 5d.
Risk tag: P0.
Executor hint: mid tier — action plan: enqueue-on-domain-event (AC-007) →
worker pool consumes the queue, records the attempt (AC-013), computes the
next backoff delay on failure (AC-008) → re-enqueue until the max-attempt
cap, then dead-letter (AC-009). Durability (AC-010) is the story's
highest-stakes property; test it with an actual process-kill, not a mock.

### Story 3: Verify webhook authenticity via signed payloads

As a customer engineer integrating against this platform, I want each
webhook payload to carry a verifiable signature, so that I can confirm a
request to my endpoint genuinely originated from the platform and was not
tampered with or replayed.

Timebox: 2d.
Risk tag: P0 (security).
Executor hint: mid tier — HMAC-SHA256 over the raw body with a bound
timestamp (Stripe-style signature header), secret issuance and rotation
with a grace window (AC-005, AC-006, AC-011, AC-012).

### Story 4: Observe delivery health and history

As a customer administrator, I want to see the delivery status and attempt
history for my events, so that I can diagnose a failure myself before
opening a support ticket.

Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — a tenant-scoped read API over the delivery-attempt
log (AC-013, AC-014); no dashboard UI prescribed, only the API contract.

### Story 5: Be notified when an event is permanently undeliverable

As a customer administrator, I want to be notified when an event exhausts
all retries, so that I learn about a broken endpoint from the platform
itself, not from a customer of mine reporting a missed event.

Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier — dead-letter transition (AC-009) triggers a
notification (AC-015) via the platform's existing channel (Assumptions);
manual redelivery (AC-016) is this story's recovery action.

### Story 6: Protect the platform and other tenants from a misconfigured or malicious endpoint URL

As a platform operator, I want every customer-supplied webhook URL
validated against internal/private address ranges — at both registration
and delivery time — and rate-limited per tenant, so that one tenant's
misconfiguration or malicious input cannot be used to probe internal
infrastructure (SSRF) or degrade delivery for other tenants.

Timebox: 3d.
Risk tag: P0 (security).
Executor hint: mid tier — DNS resolution + IP-range denylist check at
registration (AC-002, AC-003) **and again immediately before dispatch**
(AC-018) to close the DNS-rebinding gap; per-tenant concurrency/rate caps
in the worker pool (AC-017).

## Acceptance Criteria

*(Identical to `.spectra/plans/ac003-t1-r2.acceptance.md`, the frozen
criteria file — `ramza-ears-lint` reports `ok: 20 criteria pass EARS lint`
against that file. AC-019/AC-020 were added in Refine cycle 1, closing two
gaps an independent critique pass raised — see the critique note appended
after Risks.)*

### AC-001 (event-driven)
GIVEN an authenticated tenant administrator submits a webhook registration with a valid HTTPS URL and at least one subscribed event type
WHEN  the registration request is submitted
THEN  the system SHALL create an endpoint scoped to the requesting tenant and return a signing secret exactly once in the response
VERIFY: test: spec/webhooks/registration_spec#creates_tenant_scoped_endpoint_with_secret

### AC-002 (unwanted-behavior)
GIVEN a submitted webhook URL resolves to a private, loopback, or link-local IP address
WHEN  the registration or update request is validated
THEN  the system SHALL reject the request with a 4xx error, never persisting the endpoint
VERIFY: test: spec/webhooks/registration_spec#rejects_private_ip_targets

### AC-003 (unwanted-behavior)
GIVEN a submitted webhook URL uses a scheme other than https
WHEN  the registration or update request is validated
THEN  the system SHALL reject the request with a 4xx error, never persisting a non-HTTPS endpoint
VERIFY: test: spec/webhooks/registration_spec#rejects_non_https_scheme

### AC-004 (ubiquitous)
THEN the system SHALL never return, in any endpoint list, detail, or delivery-log response, a record belonging to a tenant other than the authenticated caller's own tenant
VERIFY: test: spec/webhooks/tenant_isolation_spec#no_cross_tenant_leakage

### AC-005 (optional-feature)
GIVEN the signing-secret-rotation feature is invoked by a tenant administrator for one of their endpoints
THEN the system SHALL issue a newly generated signing secret for that endpoint
VERIFY: test: spec/webhooks/secret_rotation_spec#issues_new_secret_on_rotation

### AC-006 (state-driven)
GIVEN an endpoint is within its configured secret-rotation grace window
THEN the system SHALL accept a payload signature produced by either the previous or the newly rotated secret
VERIFY: test: spec/webhooks/secret_rotation_spec#accepts_either_secret_during_grace_window

### AC-007 (event-driven)
GIVEN an endpoint is active and subscribed to an event type
WHEN  an event of that type is emitted for the endpoint's tenant
THEN  the system SHALL enqueue exactly one delivery job for that endpoint and event
VERIFY: test: spec/webhooks/delivery_spec#enqueues_one_job_per_subscribed_endpoint

### AC-008 (event-driven)
GIVEN a delivery attempt receives a non-2xx response or times out
WHEN  the worker evaluates the attempt outcome
THEN  the system SHALL schedule the next retry using exponential backoff with jitter, never before the computed delay has elapsed
VERIFY: test: spec/webhooks/backoff_spec#schedules_retry_after_computed_delay

### AC-009 (unwanted-behavior)
GIVEN an event has already reached the configured maximum retry count for an endpoint
WHEN  that final delivery attempt still fails
THEN  the system SHALL mark the event dead-lettered for that endpoint, never scheduling a further retry
VERIFY: test: spec/webhooks/deadletter_spec#stops_retrying_after_max_attempts

### AC-010 (ubiquitous)
THEN the system SHALL durably persist every enqueued delivery job before acknowledging the triggering event, so a worker-process crash never silently drops a pending delivery
VERIFY: test: spec/webhooks/delivery_spec#survives_worker_crash_without_job_loss

### AC-011 (event-driven)
GIVEN an endpoint has an active signing secret
WHEN  the system delivers a payload to that endpoint
THEN  the outbound request SHALL include a signature header computed as HMAC-SHA256 over the raw request body
VERIFY: test: spec/webhooks/signing_spec#includes_valid_hmac_signature_header

### AC-012 (ubiquitous)
THEN the system SHALL bind the exact delivery timestamp into every computed signature, never omitting it, so downstream verification can enforce a replay-tolerance window
VERIFY: test: spec/webhooks/signing_spec#signature_binds_current_timestamp

### AC-013 (ubiquitous)
THEN the system SHALL record a delivery-attempt entry (timestamp, HTTP status code or error class, latency, and resulting attempt state) for every outbound delivery try, whether it succeeds or fails
VERIFY: test: spec/webhooks/observability_spec#records_attempt_for_every_try

### AC-014 (event-driven)
GIVEN a tenant administrator is authenticated for their own tenant
WHEN  they request the delivery status for one of their events
THEN  the system SHALL return the event's current state (pending, delivered, retrying, or dead-lettered) with its full attempt history
VERIFY: test: spec/webhooks/observability_spec#returns_current_state_and_attempt_history

### AC-015 (event-driven)
GIVEN an event has just transitioned to dead-lettered for an endpoint
WHEN  that transition is recorded
THEN  the system SHALL notify the endpoint's tenant administrator through the platform's existing notification channel within a documented delay bound
VERIFY: test: spec/webhooks/notification_spec#notifies_tenant_on_dead_letter

### AC-016 (optional-feature)
GIVEN the manual-redelivery feature is invoked by a tenant administrator on one of their dead-lettered events
THEN the system SHALL enqueue exactly one fresh delivery attempt for that event and endpoint, resetting its attempt count
VERIFY: test: spec/webhooks/redelivery_spec#enqueues_fresh_attempt_on_manual_redelivery

### AC-017 (unwanted-behavior)
GIVEN a tenant's aggregate outbound delivery rate exceeds its configured per-tenant cap
WHEN  additional delivery jobs for that tenant would be dispatched
THEN  the worker pool SHALL defer those jobs rather than dispatch them, never delaying another tenant's deliveries beyond the documented isolation bound
VERIFY: test: spec/webhooks/ratelimit_spec#defers_excess_jobs_without_cross_tenant_delay

### AC-018 (unwanted-behavior)
GIVEN an endpoint's URL re-resolves to a private or internal IP address at delivery time even though it passed validation at registration
WHEN  the worker is about to dispatch the outbound request
THEN  the system SHALL abort that delivery attempt and mark it failed, never sending the request to the re-resolved address
VERIFY: test: spec/webhooks/ssrf_spec#aborts_delivery_on_dns_rebind_at_send_time

### AC-019 (ubiquitous)
THEN the system SHALL expose an endpoint's signing secret in an API response only in the create or rotate response body, never in any subsequent list, detail, or log response
VERIFY: test: spec/webhooks/secret_exposure_spec#never_returns_secret_outside_issuance_response

### AC-020 (unwanted-behavior)
GIVEN a tenant administrator deactivates a webhook endpoint while a delivery job for that endpoint is still pending in the queue
WHEN  the worker pool would otherwise dispatch that pending job
THEN  the worker pool SHALL discard the pending job rather than dispatch it to the deactivated endpoint
VERIFY: test: spec/webhooks/deactivation_spec#discards_pending_jobs_on_deactivation

## Confidence

`ramza-score --rubric confidence`: 71.25% → **VALIDATE** (human reviews) —
dims: pattern_match 45, requirement_clarity 80, decomposition_stability 72,
constraint_compliance 88 (recorded in state, label
`ac003-t1-r2-assemble-confidence`). Scored VALIDATE rather than
AUTO_PROCEED specifically because `pattern_match` is honestly low: this
consumer project has no existing application code (no queue, no delivery
code, no tenant model) to confirm the assumed architecture against — every
Assumption in Scope is an inference from the mission statement, not a
repo-verified fact. Combined with the complexity gate's `human_loop`
verdict, a human should confirm the Assumptions (especially the eventing
and job-queue prerequisites) before an executor starts Story 2.

## Rejected Alternatives

- **Hyp B — synchronous/in-process delivery with limited immediate retries
  and a background sweeper, no durable queue** — `ramza-score --rubric
  explore` total 55.5 (`weak`; dims: alignment 5, correctness 5,
  maintainability 7, performance 6, simplicity 8, risk 4, innovation 3).
  Simpler to build (fewer moving parts, no new queue dependency), but a
  worker-process crash silently drops any retry that was only tracked
  in-memory — a direct violation of the "failures must be observable" and
  implicit "no data loss" requirements. Rejected outright, not deferred:
  the durability gap is a correctness defect for a paying multi-tenant
  customer base, not a scope trade-off.
- **Hyp C — delegate delivery entirely to a third-party webhook-delivery
  vendor (e.g., Svix, Hookdeck)** — total 65.5 (`weak`; dims: alignment 6,
  correctness 7, maintainability 8, performance 7, simplicity 8, risk 4,
  innovation 4). Would minimize in-house engineering effort and inherits a
  battle-tested retry/backoff implementation, but routes every tenant's
  customer payloads through a second external processor — a materially
  different data-residency and compliance posture for a multi-tenant SaaS
  than an in-house system, plus vendor lock-in and a cost curve that scales
  with delivery volume rather than infrastructure. Worth revisiting only if
  a future compliance or cost analysis explicitly favors it; not rejected
  for technical weakness, but for a risk/control trade-off this spec is not
  positioned to make unilaterally.
- **Hyp D — route all delivery through a shared message broker (e.g.
  Kafka/Kinesis) with per-tenant consumer groups** — total 54.5 (`weak`;
  dims: alignment 5, correctness 7, maintainability 4, performance 8,
  simplicity 3, risk 4, innovation 6). Best raw throughput/scale of the four
  hypotheses, but disproportionate operational overhead for what is
  fundamentally a queue-plus-retry problem: introduces a broker cluster,
  per-tenant topic/partition isolation, and a second piece of
  multi-tenant-security surface to lock down, none of which changes how the
  actual outbound-HTTP-call-with-backoff problem gets solved. Rejected as
  over-engineered for this scope; would only become attractive if delivery
  volume grows by an order of magnitude beyond what a durable queue +
  worker pool can handle.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Assumed prerequisites (existing internal eventing, existing notification channel) don't actually exist in the target platform | P1 | Confidence scored VALIDATE, not AUTO_PROCEED, specifically for this reason; a human confirms both prerequisites before Story 2/Story 5 start; re-run `ramza-drift` once real integration points are known. |
| Customer-supplied URL is used for SSRF against internal infrastructure (validated at registration, then re-resolves to a private IP via DNS rebinding before send) | P0 | AC-002/AC-003 (registration-time validation) plus AC-018 (mandatory re-validation immediately before dispatch) — this is a two-point control, not a single check, by design. |
| A single tenant's endpoint volume or a single mass-retrying failing endpoint starves delivery capacity for other tenants (noisy neighbor) | P0 | AC-017's per-tenant rate cap in the worker pool; exponential backoff (AC-008) also naturally reduces retry volume against a persistently failing endpoint over time. |
| Exponential backoff without jitter causes synchronized retry storms across many endpoints failing at once (e.g., a shared upstream outage) | P1 | Approach step 3 mandates jitter, not bare exponential backoff; AC-008 explicitly requires the "computed delay" language rather than a fixed table, letting the implementation vary it per attempt. |
| Signing-secret rotation without a grace window breaks a customer's verification the instant they haven't yet deployed the new secret | P1 | AC-006 requires both old and new secrets to verify during a configured grace window — rotation is not a hard cutover. |
| Automatic circuit-breaking of a chronically failing endpoint was deferred; a persistently broken endpoint could still consume retry capacity up to its cap before dead-lettering | P2 | Documented in Deferred; AC-009's max-attempt cap plus AC-017's per-tenant rate limit bound the damage even without circuit-breaking; revisit if telemetry shows this is a frequent pattern. |

## Critique (T — maker≠checker)

`ramza-lint`: clean (all full-tier sections present). `ramza-ears-lint`:
clean (18/18, then 20/20 after Refine). Refine rubric (cycle 1, author ≠
checker per `ramza-gate critic`): total 4.4/5, verdict **pass** — dims
clarity 5, completeness 4, actionability 4, efficiency 4, testability 5.

**Findings:** completeness (4/5) — the pre-refine draft covered
registration, delivery, signing, observability, notification, and
SSRF/rate-limiting, but was silent on two security-adjacent edges: (1)
whether a signing secret is ever re-exposed after initial issuance, and (2)
what happens to a job already queued for an endpoint that gets deactivated
mid-flight. Neither is exotic — both are the kind of gap that ships quietly
in a straightforward CRUD implementation and surfaces later as an incident.

**Prescriptions applied in Refine (cycle 1/3):** added AC-019 (secret is
write-once-readable — issuance/rotation response only) and AC-020
(deactivation discards, rather than dispatches, an endpoint's pending
queued jobs); Story 1 and Approach step 7 updated to reference both.

## Plan Audit Trail

RAMZA full-tier cycle (RS → S → P → E → C → T → R → T → A → DONE), plan
slug `ac003-t1-r2`, all gates run through `bin/ramza-*` (never
role-played):

- **RS:** `ramza-rightsize --files-est 10 --new-dep --public-api --migration --security --stakes high` → tier **full** (score 8/12).
- **S:** `ramza-score --rubric complexity` → 11/12, **human_loop**.
- **P:** no in-repo delivery/queue/webhook precedent found in this consumer project; leaned on documented industry patterns (see Scope → Assumptions).
- **E:** 4 hypotheses scored via `ramza-score --rubric explore` — Hyp A 81 (`solid`, selected), Hyp B 55.5 (`weak`), Hyp C 65.5 (`weak`), Hyp D 54.5 (`weak`).
- **C:** 6 stories, 20 EARS-form acceptance criteria (`ramza-ears-lint`: clean).
- **T:** `ramza-lint` clean; independent critic recorded (`ramza-gate critic --author ramza-author-session --checker ramza-independent-critic`, maker≠checker enforced); refine rubric cycle 1 pass (4.4/5) → 1 refine cycle applied (AC-019, AC-020 added) → cycle 2 confirmation pass (4.8/5).
- **A:** `ramza-score --rubric confidence` → 71.25%, **VALIDATE**; scope declared (`ramza-drift --declare`, 5 globs); criteria frozen (`ramza-freeze`, sha256 `c1ea3f3ed453f7422c5ee4ea95c3f39d1d60d099df330b72b49e088af01386a8`); emission verified (`ramza-verify-emit`, exit 0) with an ECL v2.0 envelope sidecar.
- **Adherence** (`ramza-adherence`): plan_phase 1.0, plan_order 1.0 (1 refine cycle, well under the cap of 3, no penalty), composite 1.0.

Audit artifacts: `.spectra/plans/ac003-t1-r2.state.json` (state machine +
gate history), `.spectra/plans/ac003-t1-r2.acceptance.md` (frozen
criteria), `.spectra/plans/ac003-t1-r2.envelope.json` (ECL v2.0 sidecar).
Refine cap: 1 of 3 cycles used. Escalation was **not** triggered (confidence
71.25% is above the <50 ESCALATE threshold); the human-review recommendation
is carried as **VALIDATE**, not a blocking escalation.

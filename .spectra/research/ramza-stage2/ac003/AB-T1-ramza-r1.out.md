---
eidolon: ramza
kind: spec
version: 0.1.0
created_at: 2026-07-05T19:26:23Z
---

# Webhook Delivery Subsystem — Multi-Tenant SaaS

> **Refine cycle 1 applied.** An independent critic (maker≠checker, recorded via
> `ramza-gate critic`) reviewed the initial draft and returned `refine rubric: fail`
> (total 3.4/5, cycle 1 bar all ≥3 — completeness scored 2, testability scored 3).
> All 9 prescriptions were addressed in this revision: delivery-time SSRF
> re-validation (AC-010), jittered backoff (AC-007), tenant-isolation on reads and
> replay (AC-013, AC-022), signature freshness via timestamp (AC-016), non-HTTPS
> rejection (AC-004), replay-vs-paused-endpoint behavior (AC-023), replay rate
> limiting (AC-024), Story 2 timebox realism (split into a dedicated infra story),
> and Story 7's executor-hint density (bumped from frontier to mid). See "Audit
> trail" below for the critique verbatim and the re-verification results.

## Scope

Intent class: REQUEST — the goal is known and well-specified (register endpoints,
deliver with retry/backoff, expose failures to customers); DISCOVER does not apply
(not IDEA/STRATEGIC, no latent-goal elicitation needed). CLARIFY was assessed and
**skipped** (recorded here per SPEC.md's "record the skip" allowance — no
interactive reviewer is available in this run): three plan-shape questions were
identified and resolved as explicit assumptions below instead of blocking on an
answer.

**In:**
- Per-tenant webhook endpoint registration (URL + event-type subscription + signing
  secret issuance) via a customer-facing REST API, HTTPS-only.
- Durable, at-least-once event delivery from an internal event source to registered
  endpoints, with automatic retry and jittered exponential backoff.
- Per-tenant queue partitioning so one tenant's volume cannot starve another's.
- Customer-facing delivery observability: per-endpoint delivery history, status,
  and failure surfacing, correctly isolated per tenant.
- HMAC payload signing (with a timestamp in the signature base for freshness) and
  secret rotation with a verification grace window.
- Automatic circuit-breaking (auto-pause) of chronically failing endpoints, with
  tenant notification.
- Manual (and limited bulk) replay of failed deliveries by the tenant, with
  paused-endpoint and rate-limit guards against replay abuse.

**Out:**
- A general-purpose internal service-to-service event bus — this subsystem is an
  outbound-only consumer of events, not a message-bus replacement.
- Alternative delivery transports (WebSocket/SSE push, GraphQL subscriptions) as a
  substitute for HTTP webhooks.
- A payload transformation/filtering DSL beyond coarse event-type subscription.
- Delivery to endpoints reachable only over a private network / VPN (v1 requires
  publicly routable HTTPS endpoints).

**Deferred:**
- Per-tenant/per-plan-tier configurable retry policy (v1 ships one fixed platform
  policy — see Assumption 3) — deferred because it multiplies the state space of
  Story 3 without a validated customer need yet; revisit once delivery-failure
  telemetry from v1 identifies which tenants actually need a different schedule.
- Arbitrary-time-range historical bulk replay (v1's replay is single-delivery or
  bounded-bulk from the failed set only) — deferred pending storage/retention design.
- A self-serve webhook test/simulator tool for tenants integrating for the first
  time — deferred as a v1.1 developer-experience add-on, not core to reliability.
- Configurable replay rate-limit thresholds per plan tier (v1 ships one fixed
  20-per-minute limit, AC-024) — deferred pending abuse-pattern data.

**Assumptions** (each is a CLARIFY question this plan resolved by assumption rather
than blocking on a reviewer, since none was available in this run):
1. Events originate from an existing internal event bus/pub-sub that this subsystem
   subscribes to (it does not originate events itself) — **risk if wrong:** an
   event-source adapter layer would need to be added to Story 3's scope, adding
   roughly 2-3 days.
2. A fixed 5-attempt jittered backoff schedule (~1m/5m/30m/2h/12h base, ±20%
   jitter, ~15h total window) is an acceptable reliability bar for v1 — **risk if
   wrong:** tenants with longer downtime windows lose events after ~15h; partially
   mitigated by manual replay (Story 7) and dashboard visibility (Story 4), but a
   customer whose outage outlasts 15h and who doesn't notice the failed-delivery
   banner still loses data.
3. Retry policy is platform-fixed in v1, not configurable per tenant/plan — **risk
   if wrong:** enterprise tenants with stricter SLAs may require this at GA; the
   schema in `webhook_endpoints` intentionally reserves a `retry_policy` column
   (nullable, unused in v1) so this can land later without a migration.

Complexity (`ramza-score --rubric complexity`): **11/12 → human_loop**. This is an
honest routing signal, not a plan defect: a multi-tenant delivery system touching
security (signing, SSRF), a new public API surface, and a data migration warrants
a human reviewer's sign-off before implementation begins, which is exactly what a
decision-ready spec is for. See Confidence below for the corroborating gate.

## Approach

**Selected: Hypothesis B — managed durable queue + horizontally-scalable worker
fleet + DLQ + Postgres-backed delivery ledger** (`ramza-score --rubric explore`
total **83.5/100, verdict "solid"** — highest-scoring and most differentiated of
the four hypotheses explored; see Rejected Alternatives).

Event publication -> a durable, at-least-once message queue (SQS/RabbitMQ-class;
exact vendor is an implementation-time choice, not a spec-time one) partitioned per
tenant to bound noisy-neighbor blast radius (Story 2) -> a horizontally scalable
pool of delivery workers that pull from the queue, re-validate the target IP
immediately before connecting (Story 3, AC-010 — closes the registration-to-delivery
TOCTOU/DNS-rebinding window the critic flagged), HTTP POST the signed-with-timestamp
payload to the tenant's registered endpoint, and record each attempt (status,
response code, latency, timestamp) in a Postgres `webhook_deliveries` ledger table.
Failed attempts re-enqueue with jittered backoff (AC-007 — jitter added in refine to
actually address the retry-storm risk a lockstep schedule would not); after 5
exhausted attempts the delivery is marked "failed" (AC-008) and a dead-letter record
persists for observability and manual replay (Story 7, now guarded against
cross-tenant access, paused-endpoint replay, and call-rate abuse). A per-endpoint
failure counter drives the circuit breaker (Story 6): 50 consecutive failures
auto-pauses the endpoint (AC-017), which also stops burning delivery-worker capacity
on a dead integration. The `webhook_deliveries` ledger is the same data customers
see via the observability API (Story 4, now tenant-isolation-checked) — there is
exactly one source of truth for delivery status, not a separate internal-vs-external
view.

## Stories

### Story 1: Register a webhook endpoint

As a tenant admin, I want to register a webhook endpoint URL and select which event
types it receives, so that my systems get relevant SaaS events without polling.
Timebox: 5d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan, named patterns (standard
tenant-scoped CRUD + secret issuance + SSRF/scheme-guarded URL validation; a
well-trodden pattern, no need for exhaustive step-scripting).
Action plan: add `webhook_endpoints` table (tenant_id, url, secret_hash,
event_types[], status, retry_policy [nullable, reserved], created_at); `POST/GET/
PATCH/DELETE /v1/webhook-endpoints`; validate HTTPS-only (AC-004), re-resolve DNS
and block private/loopback/link-local ranges at registration (AC-003).

### Story 2: Delivery-queue infrastructure and per-tenant partitioning

As a platform operator, I want the delivery queue partitioned per tenant before any
delivery logic is built on top of it, so that the reliability core (Story 3) is not
built on a shared, unbounded queue that lets one tenant starve another.
Timebox: 4d.
Risk tag: P0.
Executor hint: mid tier — action plan + named patterns (managed-queue provisioning,
partition-key design); split out from the original single reliability story after
the critic flagged an 8-day timebox as unrealistic for infra-plus-logic combined
(see refine note above).
Action plan: provision the durable queue technology; partition key = tenant_id;
deploy the (initially empty) worker-fleet skeleton and its autoscaling policy;
load-test partition isolation (AC-005) before Story 3's delivery logic lands on it.

### Story 3: Reliable event delivery with jittered retry and backoff

As a platform operator, I want events delivered to customer endpoints with
automatic retries and jittered exponential backoff, so that a transient
customer-side outage doesn't cause silent, permanent data loss, and simultaneous
endpoint failures don't retry in lockstep against recovering endpoints.
Timebox: 6d.
Risk tag: P0.
Executor hint: mid tier — action plan + named patterns (queue consumer, jittered
backoff scheduler). Reduced from the original 8d/combined-scope estimate now that
Story 2 carries the infra-provisioning work separately.
Action plan: queue consumer per tenant partition (built on Story 2's infra);
delivery-attempt worker with 10s timeout and pre-connect IP re-validation
(AC-010); backoff scheduler implementing the jittered 1m/5m/30m/2h/12h ± 20%
schedule (AC-007); `webhook_deliveries` ledger row per attempt; retry-cap
enforcement at 5 (AC-008).

### Story 4: Delivery observability for customers

As a tenant developer, I want to see the delivery status and history of my webhook
events — and only my own tenant's — so that I can diagnose integration failures
myself without opening a support ticket or seeing another tenant's data.
Timebox: 5d.
Risk tag: P1.
Executor hint: mid tier — action plan + named patterns (paginated, tenant-scoped
read API over the same ledger Story 3 writes).
Action plan: `GET /v1/webhook-endpoints/{id}/deliveries` (paginated, last 100,
tenant-scoped query — AC-013 requires this to 404 rather than 403 on cross-tenant
access, so as not to confirm another tenant's resource exists); dashboard failure
banner sourced from the same ledger; no separate write path.

### Story 5: Payload signing, verification, and freshness

As a tenant developer, I want each webhook payload cryptographically signed and
timestamped, so that I can verify authenticity, reject spoofed requests, and reject
replayed (captured-and-resent) payloads against my endpoint.
Timebox: 4d.
Risk tag: P0.
Executor hint: economy tier — explicit steps and a schema-validated contract for
the signing routine specifically. This is a narrow, security-critical primitive
where a tight, explicit scaffold (exact header names, exact digest construction,
exact rotation-window semantics, exact timestamp placement in the signature base)
reduces the chance of a subtle signing bug more than it would slow down a stronger
executor — the density is chosen for the task's blast radius, not the default
tier-to-scaffold mapping. Timebox extended from 3d to 4d in refine to cover the
added timestamp/freshness component (AC-016).
Action plan: HMAC-SHA256 over the raw request body plus an `X-Webhook-Timestamp`
value, both folded into the signature base string (AC-014, AC-016); `X-Webhook-
Signature` header; secret rotation endpoint accepts old+new secret verification for
a 24h grace window (AC-015); secrets never appear in logs or error payloads
(redact at the logging middleware, not per call site); document the customer-side
freshness-rejection contract (recommended window, e.g. reject timestamps >5min
stale) since enforcement of that specific check lives in the customer's receiving
code, not this subsystem.

### Story 6: Automatic endpoint circuit-breaking

As a platform operator, I want endpoints that fail consistently to be automatically
paused, so that a broken customer integration doesn't waste delivery-worker
capacity or generate ongoing alarm/ticket noise.
Timebox: 5d.
Risk tag: P1.
Executor hint: mid tier — action plan + named patterns (consecutive-failure
counter + state-machine transition, standard circuit-breaker shape).
Action plan: per-endpoint consecutive-failure counter (resets on any success);
threshold 50 -> transition to "paused" (AC-017); email notification within 5
minutes (AC-018); dashboard banner on the endpoint detail page (AC-019);
tenant-initiated "resume" action reuses the existing PATCH endpoint from Story 1;
resumed endpoints unblock Story 7's paused-endpoint replay guard (AC-023).

### Story 7: Manual replay of failed deliveries, with abuse protection

As a tenant developer, I want to manually trigger redelivery of a failed event, so
that I can recover after fixing my endpoint without waiting for the source event to
recur (many source events do not recur) — without being able to replay another
tenant's delivery, replay against a broken endpoint the circuit breaker already
paused, or hammer the replay endpoint.
Timebox: 4d.
Risk tag: P2.
Executor hint: mid tier — action plan + named patterns (re-enqueue an existing
ledger row, tenant-scoped ownership check, sliding-window rate limiter). Bumped
from "frontier tier, goals only" in refine: the critic correctly noted the real
ambiguity here (cross-tenant guard, paused-endpoint interaction, rate limiting) is
higher than the original hint assumed, so this story now gets an explicit action
plan rather than goals-only.
Action plan: `POST /v1/webhook-deliveries/{id}/replay` for a single failed
delivery, tenant-ownership-checked (AC-022, 404 on mismatch); reject with 409 while
the target endpoint is "paused" (AC-023); bulk variant (`?ids=`) capped at 100,
gated on a plan-tier feature flag (AC-021); sliding-window rate limit of 20
replay calls per endpoint per minute, 429 beyond that (AC-024).

## Acceptance Criteria

Full EARS-form criteria set (24 criteria, all five closed forms represented) lives
in the sibling file `.spectra/plans/webhook-delivery.acceptance.md` — the canonical,
lint-checked, frozen artifact (SHA-256 below). Reproduced here in full so this
document is self-contained per the planning-artifact template:

### AC-001 (event-driven)
GIVEN a tenant is authenticated with a valid API key
WHEN  the tenant submits POST /v1/webhook-endpoints with a valid HTTPS URL and a list of event types
THEN  THE SYSTEM SHALL create the endpoint record in "active" status
VERIFY: test: spec/requests/webhook_endpoints_spec.rb#creates_endpoint

### AC-002 (event-driven)
GIVEN a webhook endpoint has just been created
WHEN  the creation response is returned to the caller
THEN  THE SYSTEM SHALL include the signing secret in that response body exactly once
VERIFY: test: spec/requests/webhook_endpoints_spec.rb#returns_secret_once

### AC-003 (unwanted-behavior)
GIVEN a tenant is registering a new webhook endpoint
WHEN  the submitted URL resolves to a private, loopback, or link-local IP range
THEN  THE SYSTEM SHALL reject the registration with HTTP 422
VERIFY: test: spec/requests/webhook_endpoints_spec.rb#rejects_ssrf_targets

### AC-004 (unwanted-behavior)
GIVEN a tenant is registering a new webhook endpoint
WHEN  the submitted URL scheme is not HTTPS
THEN  THE SYSTEM SHALL reject the registration with HTTP 422
VERIFY: test: spec/requests/webhook_endpoints_spec.rb#rejects_non_https_urls

### AC-005 (ubiquitous)
THEN  THE SYSTEM SHALL partition delivery queues per tenant so that one tenant's backlog depth never delays delivery-worker throughput for another tenant's partition
VERIFY: gate: load-test "tenant-partition-isolation" (spec/perf/partition_isolation_spec.rb#no_cross_tenant_delay)

### AC-006 (event-driven)
GIVEN a tenant has an active endpoint subscribed to an event type
WHEN  an event of that type is published for the tenant
THEN  THE SYSTEM SHALL enqueue a delivery attempt within 2 seconds of publish
VERIFY: gate: delivery_latency_slo (p99 enqueue lag < 2s, dashboard panel "delivery-lag")

### AC-007 (unwanted-behavior)
GIVEN a delivery attempt has been made to an endpoint
WHEN  the attempt receives a non-2xx response or times out after 10 seconds
THEN  THE SYSTEM SHALL schedule the next retry at the fixed base schedule 1m, 5m, 30m, 2h, 12h with +/-20% random jitter applied to each interval
VERIFY: test: spec/workers/delivery_worker_spec.rb#retries_with_jittered_backoff_schedule

### AC-008 (unwanted-behavior)
GIVEN a delivery has already been attempted 5 times and all 5 failed
WHEN  the scheduler evaluates whether to enqueue a 6th attempt
THEN  THE SYSTEM SHALL mark the delivery "failed" instead of scheduling a 6th attempt
VERIFY: test: spec/workers/delivery_worker_spec.rb#stops_at_retry_cap

### AC-009 (ubiquitous)
THEN  THE SYSTEM SHALL guarantee at-least-once delivery semantics per event per subscribed endpoint
VERIFY: test: spec/workers/delivery_worker_spec.rb#at_least_once_semantics

### AC-010 (unwanted-behavior)
GIVEN an endpoint's URL now resolves to a private, loopback, or link-local IP at delivery time even though it passed registration-time validation
WHEN  a delivery attempt is made to that endpoint
THEN  THE SYSTEM SHALL abort the attempt without connecting and record it as a failed attempt
VERIFY: test: spec/workers/delivery_worker_spec.rb#reverifies_target_ip_before_connecting

### AC-011 (event-driven)
GIVEN a tenant owns a webhook endpoint with delivery history
WHEN  the tenant requests GET /v1/webhook-endpoints/{id}/deliveries
THEN  THE SYSTEM SHALL return the most recent 100 delivery attempts with status, response code, and timestamp
VERIFY: test: spec/requests/deliveries_spec.rb#lists_history

### AC-012 (state-driven)
GIVEN a delivery has exhausted all retry attempts and is marked "failed"
THEN  THE SYSTEM SHALL surface that delivery in the customer-facing dashboard within 1 minute of the terminal failure
VERIFY: test: spec/workers/delivery_worker_spec.rb#surfaces_failure_in_dashboard

### AC-013 (unwanted-behavior)
GIVEN a webhook endpoint and its deliveries belong to tenant A
WHEN  a request authenticated as tenant B requests GET /v1/webhook-endpoints/{id}/deliveries for that endpoint
THEN  THE SYSTEM SHALL respond HTTP 404
VERIFY: test: spec/requests/deliveries_spec.rb#rejects_cross_tenant_access

### AC-014 (ubiquitous)
THEN  THE SYSTEM SHALL sign every outbound payload with HMAC-SHA256 over the request body and an X-Webhook-Timestamp value, carried in an X-Webhook-Signature header
VERIFY: test: spec/workers/signing_spec.rb#signs_payload_with_hmac_sha256

### AC-015 (unwanted-behavior)
GIVEN a tenant has requested signing-secret rotation for an endpoint
WHEN  a delivery is verified during the 24-hour window following rotation
THEN  THE SYSTEM SHALL accept a signature produced by either the old or the new secret
VERIFY: test: spec/requests/webhook_endpoints_spec.rb#rotates_secret_with_grace_window

### AC-016 (ubiquitous)
THEN  THE SYSTEM SHALL include the delivery timestamp in the HMAC signature base string so a captured payload cannot be replayed against the customer's endpoint once the documented freshness window elapses
VERIFY: test: spec/workers/signing_spec.rb#includes_timestamp_in_signature_base

### AC-017 (state-driven)
GIVEN an endpoint has recorded 50 consecutive failed delivery attempts
THEN  THE SYSTEM SHALL automatically transition the endpoint to "paused" status
VERIFY: test: spec/workers/circuit_breaker_spec.rb#pauses_after_threshold

### AC-018 (event-driven)
GIVEN an endpoint has just been auto-paused by the circuit breaker
WHEN  the pause transition is recorded
THEN  THE SYSTEM SHALL send the tenant an email notice within 5 minutes of the transition
VERIFY: test: spec/notifications/pause_notice_spec.rb#sends_email_notice

### AC-019 (state-driven)
GIVEN an endpoint is currently in "paused" status
THEN  THE SYSTEM SHALL display a paused-status banner on that endpoint's dashboard detail page
VERIFY: test: spec/features/endpoint_detail_spec.rb#shows_paused_banner

### AC-020 (event-driven)
GIVEN a delivery is marked "failed"
WHEN  the tenant calls POST /v1/webhook-deliveries/{id}/replay
THEN  THE SYSTEM SHALL enqueue a fresh delivery attempt for that delivery record and return HTTP 202
VERIFY: test: spec/requests/replay_spec.rb#requeues_single_delivery

### AC-021 (optional-feature)
GIVEN the tenant's plan tier has the bulk-replay feature enabled
THEN  THE SYSTEM SHALL allow a single request to replay up to 100 failed deliveries at once
VERIFY: test: spec/requests/replay_spec.rb#bulk_replay_within_limit

### AC-022 (unwanted-behavior)
GIVEN a delivery belongs to tenant A
WHEN  a request authenticated as tenant B calls POST /v1/webhook-deliveries/{id}/replay on that delivery
THEN  THE SYSTEM SHALL respond HTTP 404
VERIFY: test: spec/requests/replay_spec.rb#rejects_cross_tenant_replay

### AC-023 (unwanted-behavior)
GIVEN an endpoint is currently in "paused" status
WHEN  the tenant calls replay for a delivery addressed to that endpoint
THEN  THE SYSTEM SHALL reject the replay with HTTP 409 until the endpoint is resumed
VERIFY: test: spec/requests/replay_spec.rb#rejects_replay_on_paused_endpoint

### AC-024 (unwanted-behavior)
GIVEN a tenant has already made 20 replay requests against the same endpoint within the last 1 minute
WHEN  a 21st replay request for that endpoint arrives within that window
THEN  THE SYSTEM SHALL reject it with HTTP 429
VERIFY: test: spec/requests/replay_spec.rb#rate_limits_replay_calls

## Confidence

`ramza-score --rubric confidence`: **82.75% → VALIDATE** (human reviews before
proceeding). Consistent with the complexity gate's `human_loop` routing above —
two independent instruments converge on the same recommendation: this spec is
decision-ready, not auto-executable. Dimension detail: pattern_match 88 (webhook
delivery with retry/backoff is an extremely well-trodden industry pattern —
Stripe, GitHub, and most payment/SaaS platforms ship a near-identical shape),
requirement_clarity 78 (the core ask is clear; the exact backoff schedule, retry
cap, and circuit-breaker threshold were resolved as assumptions rather than
customer-specified, per the Scope section), decomposition_stability 80 (seven
stories split cleanly along CRUD / infra / delivery / observability / security /
circuit-breaker / replay seams; the Story 2/3 split in refine improved rather than
destabilized this — each seam is now narrower, not reshuffled), constraint_compliance
85 (raised from 82 in refine: the flagged security and migration signals from
Right-Size are now each answered by a specific, tested story — SSRF/scheme guard in
Story 1, delivery-time re-validation and jittered backoff in Story 3, signing +
freshness in Story 5, multi-tenant partitioning in Story 2, tenant isolation on
reads/replay in Stories 4/7).

## Rejected Alternatives

Four hypotheses were explored and scored (`ramza-score --rubric explore`); all
totals differ by far more than 5%, so differentiation was sufficient (56.5 to 83.5).

- **Hypothesis A — Postgres-backed queue (`SELECT ... FOR UPDATE SKIP LOCKED`) +
  worker pool, no external queue dependency** — total **72.5/100, "solid"**. Scored
  well on simplicity (9) and risk (8, no new infra dependency) but lower on
  performance (6): a single relational table as the delivery queue is a well-known
  scaling ceiling once tenant/event volume grows past what one Postgres instance's
  write throughput can absorb, and it was rated below Hypothesis B on alignment (7
  vs 9) because it doesn't naturally give per-tenant partitioning (now Story 2)
  without hand-rolled sharding logic. Rejected in favor of B primarily on the
  performance/alignment gap, not because it is unsound — it remains the fallback if
  the team wants to avoid a new infra dependency (see `--new-dep` flag on the RS
  gate) and is worth revisiting if queue-infra operational cost proves too high.
- **Hypothesis C — event-sourced delivery ledger with adaptive (health-score-driven)
  backoff and real-time WebSocket/SSE status streaming to customers** — total
  **56.5/100, "weak"** (rubric-flagged: weak verdicts exit 1, meaning rework-or-drop,
  not a borderline pass). Highest innovation score (9) but lowest simplicity (3) and
  risk (4): an adaptive backoff policy that self-tunes per endpoint is materially
  harder to reason about, test, and explain to a customer than a fixed, jittered,
  published schedule (AC-007 needs to be something a customer can read in
  documentation and predict), and real-time streaming is a duplicate observability
  transport alongside the REST API this spec already commits to (Story 4) with no
  validated customer need for sub-second status push. Dropped, not carried forward,
  given the "weak" verdict.
- **Hypothesis D — buy: wrap a third-party webhook-delivery platform (e.g. a
  Svix/Hookdeck-class vendor) behind a thin tenant-onboarding layer** — total
  **68/100, "weak"**. Highest maintainability (9) and simplicity (9) of the four,
  but lowest alignment (5): a multi-tenant SaaS handing customer endpoint URLs,
  event payloads, and signing-secret custody to a third party raises data-residency
  and vendor-lock-in questions this spec cannot resolve unilaterally (that is a
  build-vs-buy decision for the human reviewer the Confidence gate already routes
  this to, not something to decide by hypothesis score alone). Also scored lower on
  correctness (7) for the same reason as Hypothesis A: less control over exactly
  matching this spec's specific retry-cap, jitter, and circuit-breaker semantics
  against a vendor's own opinionated defaults. Recorded here explicitly as the
  buy-side alternative so the human reviewer sees it was considered, not
  overlooked.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Retry storms: many endpoints failing simultaneously (e.g. during a customer's own incident) overwhelm the delivery-worker pool or the customer's recovering endpoint, retrying in lockstep | P0 | Jittered backoff (±20% per interval, AC-007) breaks lockstep retry timing; circuit breaker auto-pauses after 50 consecutive failures (AC-017) so a dead endpoint stops consuming worker capacity |
| SSRF via customer-supplied URLs reaching internal infrastructure, including a URL that re-points to a private range after registration (DNS rebinding / TOCTOU) | P0 | URL validation blocks private/loopback/link-local ranges and non-HTTPS schemes at registration (AC-003, AC-004) **and** the delivery worker re-validates the resolved IP immediately before connecting, aborting rather than following a rebound address (AC-010) |
| Signing-secret leakage via logs, error payloads, or support tooling | P0 | Secrets redacted at the logging middleware layer (not per call site); rotation supported with a 24h grace window (AC-015) so a leaked secret can be rotated without a delivery outage |
| Captured/replayed signed payloads accepted by a customer's endpoint after the fact | P1 | Signature base string includes the delivery timestamp (AC-016), enabling customers to reject stale (replayed) deliveries per the documented freshness contract |
| Multi-tenant noisy-neighbor: one tenant's event volume starves delivery-worker capacity for other tenants | P1 | Per-tenant queue partitioning is now its own dedicated, load-tested infra story (Story 2, AC-005) before any delivery logic is built on top; worker pool scales horizontally per partition depth |
| Cross-tenant data exposure via delivery-history reads or replay of another tenant's delivery | P0 | Ownership check on both the observability read path (AC-013) and the replay path (AC-022), both returning 404 (not 403) to avoid confirming another tenant's resource exists |
| Replay-endpoint abuse: unbounded manual replay calls used to hammer a customer's own (or someone else's) endpoint, or to bypass the circuit breaker on a paused endpoint | P1 | Replay against a paused endpoint is rejected with 409 until resumed (AC-023); a sliding-window rate limit (20/min/endpoint) caps repeat replay calls (AC-024) |
| At-least-once semantics (AC-009) cause customer-side duplicate event processing | P1 | Every delivery carries a stable event ID in headers so customers can de-duplicate; documented as a required idempotent-consumer contract in the integration guide (doc task, not a code story) |
| Unbounded delivery-history storage growth at multi-tenant scale | P2 | AC-011 caps the API view at 100 attempts; a retention/archival policy for the underlying ledger table is deferred but flagged here so it isn't silently forgotten post-launch |

---

## Assemble metadata

- Confidence verdict: VALIDATE (82.75%) — human review recommended before
  implementation begins; corroborated by the RS complexity gate's `human_loop`
  routing (11/12).
- Declared execution scope (`ramza-drift --declare`, 20 globs): `db/migrate/*webhook*`
  `app/models/webhook_endpoint*` `app/models/webhook_delivery*`
  `app/controllers/api/v1/webhook_endpoints_controller*`
  `app/controllers/api/v1/webhook_deliveries_controller*` `app/workers/*webhook*`
  `app/workers/*delivery*` `app/workers/circuit_breaker*` `app/mailers/*pause*`
  `app/lib/rate_limiting/*replay*` `docs/webhooks/*`
  `spec/requests/webhook_endpoints_spec.rb` `spec/requests/deliveries_spec.rb`
  `spec/requests/replay_spec.rb` `spec/workers/delivery_worker_spec.rb`
  `spec/workers/signing_spec.rb` `spec/workers/circuit_breaker_spec.rb`
  `spec/notifications/pause_notice_spec.rb` `spec/features/endpoint_detail_spec.rb`
  `spec/perf/partition_isolation_spec.rb`
- Acceptance criteria frozen from: `.spectra/plans/webhook-delivery.acceptance.md`
  — SHA-256 `d95e54e4c21061809d5df431e4acff109637991d85ced73af3a31f8ee0ac481d`
  (recorded via `ramza-freeze`; verified with `ramza-freeze --verify`, clean).
- Critic: recorded via `ramza-gate critic` (maker≠checker, mandatory at full tier
  before this document was allowed to enter Assemble) — author
  `ramza-author-sonnet5`, checker `ramza-critic-sonnet5-cleancontext`. Cycle-1
  critique verdict was `fail`; all 9 prescriptions were applied in this refine
  pass (see banner at top and the Audit trail below for the verbatim critique and
  re-verification).
- ECL v2.0 envelope sidecar emitted at `.spectra/plans/webhook-delivery.envelope.json`,
  validated clean by `ramza-verify-emit --spec ... --envelope ...` (see Audit trail).

---

# Audit trail

Everything below is the actual, unedited stdout/output of the real `bin/ramza-*`
gate tools invoked during this run, in the order they were run, against
`.spectra/plans/webhook-delivery.state.json`. No score, verdict, or hash below was
estimated in prose — each came from the tool.

## 1. Right-Size (RS)

Command:
```
bash .eidolons/ramza/bin/ramza-rightsize --files-est 12 --new-dep --public-api --migration --security --stakes high --plan webhook-delivery --state .spectra/plans/webhook-delivery.state.json
```
Output:
```
state initialised: .spectra/plans/webhook-delivery.state.json (tier: full, score: 8)
full
```
Tier decision: **full** (score 8 = files-est≥10 [2] + new-dep [1] + public-api [1] +
migration [1] + security [1] + stakes:high [2]; `--novel` was not set).

## 2. Scope (S) — complexity rubric

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to S --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: RS -> S`

Command:
```
echo '{"scope":3,"ambiguity":2,"dependencies":3,"risk":3}' | bash .eidolons/ramza/bin/ramza-score --rubric complexity --state .spectra/plans/webhook-delivery.state.json --label "webhook-delivery-scope"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 11,
  "dims": {
    "scope": 3,
    "ambiguity": 2,
    "dependencies": 3,
    "risk": 3
  },
  "verdict": "human_loop",
  "at": "2026-07-05T19:23:20Z",
  "label": "webhook-delivery-scope"
}
```

## 3. Pattern (P)

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to P --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: S -> P`

No prior webhook-delivery pattern existed in this project's (empty) codebase or
memory layer to match against — recorded here as a `<60%` "generate" case per the
Pattern-phase protocol, not silently skipped.

## 4. Explore (E) — four hypotheses scored

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to E --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: P -> E`

Command (Hypothesis A):
```
echo '{"alignment":7,"correctness":8,"maintainability":8,"performance":6,"simplicity":9,"risk":8,"innovation":2}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/webhook-delivery.state.json --label "hyp-A-db-backed-queue"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 72.5,
  "dims": {
    "alignment": 7,
    "correctness": 8,
    "maintainability": 8,
    "performance": 6,
    "simplicity": 9,
    "risk": 8,
    "innovation": 2
  },
  "verdict": "solid",
  "at": "2026-07-05T19:24:11Z",
  "label": "hyp-A-db-backed-queue"
}
```

Command (Hypothesis B):
```
echo '{"alignment":9,"correctness":9,"maintainability":8,"performance":9,"simplicity":7,"risk":8,"innovation":5}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/webhook-delivery.state.json --label "hyp-B-managed-mq-worker-fleet"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 83.5,
  "dims": {
    "alignment": 9,
    "correctness": 9,
    "maintainability": 8,
    "performance": 9,
    "simplicity": 7,
    "risk": 8,
    "innovation": 5
  },
  "verdict": "solid",
  "at": "2026-07-05T19:24:11Z",
  "label": "hyp-B-managed-mq-worker-fleet"
}
```

Command (Hypothesis C):
```
echo '{"alignment":6,"correctness":6,"maintainability":5,"performance":7,"simplicity":3,"risk":4,"innovation":9}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/webhook-delivery.state.json --label "hyp-C-event-sourced-adaptive"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 56.5,
  "dims": {
    "alignment": 6,
    "correctness": 6,
    "maintainability": 5,
    "performance": 7,
    "simplicity": 3,
    "risk": 4,
    "innovation": 9
  },
  "verdict": "weak",
  "at": "2026-07-05T19:24:11Z",
  "label": "hyp-C-event-sourced-adaptive"
}
```
(exit 1 — rubric-flagged `weak`, rework-or-drop)

Command (Hypothesis D):
```
echo '{"alignment":5,"correctness":7,"maintainability":9,"performance":8,"simplicity":9,"risk":6,"innovation":2}' | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/webhook-delivery.state.json --label "hyp-D-buy-third-party-platform"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore",
  "total": 68,
  "dims": {
    "alignment": 5,
    "correctness": 7,
    "maintainability": 9,
    "performance": 8,
    "simplicity": 9,
    "risk": 6,
    "innovation": 2
  },
  "verdict": "weak",
  "at": "2026-07-05T19:24:11Z",
  "label": "hyp-D-buy-third-party-platform"
}
```
(exit 1 — rubric-flagged `weak`)

Differentiation check: totals span 56.5–83.5, far outside the 5% band, so no
re-observe was required. Hypothesis B selected.

## 5. Construct (C)

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to C --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: E -> C`

## 6. Test (T) — first pass, initial draft (16 criteria)

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to T --state .spectra/plans/webhook-delivery.state.json --reason "constructing plan doc and criteria file before running structural/EARS lint layers"
```
Output: `OK: C -> T`

Command:
```
bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/webhook-delivery.md --state .spectra/plans/webhook-delivery.state.json
```
Output: `ok: plan passes structural lint (tier: full)`

Command:
```
bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/webhook-delivery.acceptance.md
```
Output: `ok: 16 criteria pass EARS lint`

## 7. Independent critic (maker≠checker) — cycle 1

A clean-context critic subagent (no authorship context) reviewed the plan,
acceptance criteria, and state file per `skills/critic.md`'s debias procedure, and
ran the mechanical gates itself. Its report, verbatim, including the actual
command output it captured:

> ## Critique — webhook-delivery
>
> **Verdict:** ramza-lint clean · ramza-ears-lint clean · refine rubric: fail (total 3.4, cycle 1)
>
> **Findings**
> - clarity (4/5): Plan language is precise throughout — exact header names, thresholds, and table columns are named rather than left vague, and the self-reported gate numbers in the prose (Complexity 11/12, Explore 83.5/100, Confidence 82%) match `state.json`'s `gates[]` verbatim. Minor deduction: Story 5's "(out of AC scope for v1 beyond the state transition itself — resume reuses the existing PATCH endpoint from Story 1)" is a run-on that needs a second read.
> - completeness (2/5): The Risks table (row 2, SSRF) and Story 1's action plan both claim delivery-time DNS re-resolution as a P0 mitigation, but none of AC-001..016 tests it — AC-003 only covers registration-time rejection, leaving the actual TOCTOU/DNS-rebinding guard unverified by any acceptance criterion. Further gaps a downstream implementer would trip over: no tenant-isolation AC for cross-tenant access to `GET .../deliveries` or `POST .../replay`; no negative-path AC for non-HTTPS URL rejection despite Story 1's action plan requiring "HTTPS-only"; AC-010's signing scheme has no timestamp/nonce component, so a captured signed payload can be replayed indefinitely (undercuts Story 4's stated goal of rejecting spoofed requests); and neither Story 5 nor Story 6 specifies what happens when a tenant calls replay against an endpoint the circuit breaker has paused, nor any rate limit on repeated replay calls (the "replay abuse" surface is currently wide open beyond the per-request 100-item bulk cap).
> - actionability (4/5): Action plans are concrete and well-scaffolded to each story's actual complexity (exact columns, exact header, exact thresholds). Story 6's "frontier tier — goals and constraints only" hint understates its real ambiguity once the paused-endpoint-interaction and replay-abuse questions above are counted as in-scope for that story.
> - efficiency (4/5): The `webhook_deliveries` ledger is reused (not duplicated) across Stories 2/3/6 per the Approach section, and story scopes don't overlap. Story 2's 8-day timebox is tight given it's simultaneously the largest story, the P0 reliability core, a brand-new external queue-dependency integration, per-tenant partitioning, and a backoff scheduler — all under a "mid tier" (non-step-scripted) scaffold.
> - testability (3/5): All 16 stated ACs carry concrete VERIFY hooks (spec file#method or a named SLO gate) — what's specified is well-instrumented. But the Risks-table claim of delivery-time SSRF re-validation, and the (absent) anti-replay/paused-endpoint-replay/abuse-rate-limit behavior, have zero corresponding AC or VERIFY hook — the same root cause as the completeness gap, surfaced here as claims that are currently unverifiable rather than simply unwritten.
>
> **Prescriptions**
> 1. Story 1 / Risks (SSRF row) — Add an AC testing delivery-time SSRF re-validation explicitly (e.g., "GIVEN an endpoint's URL now resolves to a private/loopback/link-local IP at delivery time WHEN a delivery attempt is made THEN THE SYSTEM SHALL abort the attempt without connecting"), and specify in the action plan that the delivery worker connects to the IP validated at re-resolution — not an independently re-resolved hostname — to actually close the DNS-rebinding window.
> 2. Story 2 / AC-005 / Risks (retry-storms row) — Add jitter (e.g., ±20%) to the fixed backoff schedule; a lockstep fixed schedule doesn't address the named retry-storm risk when many endpoints fail at the same wall-clock moment. Update AC-005's THEN clause to state the jittered range.
> 3. Story 3 / Story 6 — Add a tenant-isolation negative-path AC: cross-tenant `GET .../deliveries` or `POST .../replay` on a resource owned by another tenant returns 404/403. None of AC-001..016 covers this.
> 4. Story 4 / AC-010 — Add a timestamp (or nonce) to the signature base string plus a companion header and freshness check, with a corresponding AC (reject signatures older than N minutes) — otherwise a captured signed payload can be replayed indefinitely against the "reject spoofed requests" goal.
> 5. Story 5 / Story 6 — Specify and add an AC for replay-against-paused-endpoint: is it allowed, blocked (409/422), or does it interact with the circuit breaker's counters? Currently undefined.
> 6. Story 6 / AC-015/AC-016 — Add a rate limit on replay call frequency (single and bulk) per endpoint/tenant, plus a corresponding AC; today only a per-request bulk cap (100) exists, with no bound on repeat calls.
> 7. Story 1 — Add a negative-path AC for non-HTTPS URL rejection (mirroring AC-003's pattern) — the action plan requires HTTPS-only but no AC tests it.
> 8. Story 2 — Re-examine the 8-day timebox against actual scope (new infra dependency + partitioning + backoff scheduler + ledger + retry cap as the single P0/largest story); consider padding or splitting out infra setup with its own timebox.
> 9. Story 6 — Bump the executor-hint density above "frontier tier, goals only" once items 5–6 are folded in, since the real ambiguity is higher than the current hint assumes.
>
> ---
>
> **Command 1 — ramza-lint**
> ```
> ok: plan passes structural lint (tier: full)
> EXIT: 0
> ```
>
> **Command 2 — ramza-ears-lint**
> ```
> ok: 16 criteria pass EARS lint
> EXIT: 0
> ```
>
> **Command 3 — ramza-score --rubric refine --cycle 1**
> ```
> calibration log appended: .spectra/plans/ramza-calibration.jsonl
> {
>   "rubric": "refine",
>   "cycle": 1,
>   "total": 3.4,
>   "min": 2,
>   "dims": {
>     "clarity": 4,
>     "completeness": 2,
>     "actionability": 4,
>     "efficiency": 4,
>     "testability": 3
>   },
>   "verdict": "fail",
>   "at": "2026-07-05T19:32:08Z"
> }
> ```
> (exit code 1, per `ramza-score`'s convention of exiting 1 on `fail`/`weak`/`ESCALATE` verdicts)
>
> **Command 4 — ramza-gate critic**
> ```
> OK: critic recorded (author: ramza-author-sonnet5, checker: ramza-critic-sonnet5-cleancontext)
> EXIT: 0
> ```

Identities recorded via `ramza-gate critic --author ramza-author-sonnet5 --checker
ramza-critic-sonnet5-cleancontext` (distinct identities, mechanically enforced —
this is the record above, run by the critic subagent itself, not role-played by the
author).

## 8. Refine (R) — cycle 1

The critic's `fail` verdict was honored rather than bypassed (the mechanical
`ramza-gate advance --to A` gate for tier=full only checks that a critic record
exists, not that its verdict passed — this refine cycle was run because the
methodology's Hard Rule 2 says "if a gate DENYs, obey it or record the override —
never silently proceed," and a `fail` verdict on the content-quality gate is not
something to walk past just because it wasn't mechanically blocking).

Command:
```
bash .eidolons/ramza/bin/ramza-gate refine --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: T -> R (cycle 1/3)`

All 9 prescriptions were applied: AC-004 (non-HTTPS rejection), AC-005 (renumbered;
new dedicated Story 2 infra AC), AC-007 (jittered backoff, ±20%), AC-010 (delivery-time
SSRF re-validation), AC-013 (tenant isolation on reads), AC-016 (signature freshness
via timestamp), AC-022 (tenant isolation on replay), AC-023 (replay-vs-paused-endpoint,
409), AC-024 (replay rate limiting, 429); Story 2 split out of the original Story 2
to fix the timebox realism finding; Story 7 (renumbered from 6) executor hint bumped
from frontier to mid. Acceptance criteria grew from 16 to 24.

Re-verification, run fresh against the revised files:
```
bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/webhook-delivery.acceptance.md
```
Output: `ok: 24 criteria pass EARS lint`

```
bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/webhook-delivery.md --state .spectra/plans/webhook-delivery.state.json
```
Output: `ok: plan passes structural lint (tier: full)`

```
bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/webhook-delivery.md
```
Output: `ok: 24 criteria pass EARS lint`

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to T --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: R -> T`

**Disclosed limitation:** per this run's task constraints, exactly one critic
subagent was spawned for the whole plan (not one per refine cycle). The following
cycle-2 refine score is therefore an **author self-check**, not a second
independent critique — labeled as such in its own `--label`, and disclosed here
rather than presented as an independent pass. The full-tier mechanical gate for
entering Assemble (a recorded critic — `ramza-gate critic`) was already satisfied
by the cycle-1 independent critic above; this self-check is an honesty-motivated
addition to the audit trail, not a substitute for independent review.

Command:
```
echo '{"clarity":5,"completeness":4,"actionability":5,"efficiency":4,"testability":5}' | bash .eidolons/ramza/bin/ramza-score --rubric refine --state .spectra/plans/webhook-delivery.state.json --cycle 2 --label "author-self-check-cycle-2-post-refine"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine",
  "cycle": 2,
  "total": 4.6,
  "min": 4,
  "dims": {
    "clarity": 5,
    "completeness": 4,
    "actionability": 5,
    "efficiency": 4,
    "testability": 5
  },
  "verdict": "pass",
  "at": "2026-07-05T19:38:19Z",
  "label": "author-self-check-cycle-2-post-refine"
}
```

## 9. Assemble (A)

Command:
```
bash .eidolons/ramza/bin/ramza-gate advance --to A --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: T -> A` (permitted: the critic record from step 7 is present, satisfying
the full-tier mechanical requirement)

Confidence score:
```
echo '{"pattern_match":88,"requirement_clarity":78,"decomposition_stability":80,"constraint_compliance":85}' | bash .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/webhook-delivery.state.json --label "webhook-delivery-assemble-confidence"
```
Output:
```
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 82.75,
  "dims": {
    "pattern_match": 88,
    "requirement_clarity": 78,
    "decomposition_stability": 80,
    "constraint_compliance": 85
  },
  "verdict": "VALIDATE",
  "at": "2026-07-05T19:38:39Z",
  "label": "webhook-delivery-assemble-confidence"
}
```

Re-lint after a cosmetic confidence-percentage correction in the prose (82% → 82.75%,
no structural/AC changes):
```
bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/webhook-delivery.md --state .spectra/plans/webhook-delivery.state.json
```
Output: `ok: plan passes structural lint (tier: full)`

Scope declaration:
```
bash .eidolons/ramza/bin/ramza-drift --state .spectra/plans/webhook-delivery.state.json --declare 'db/migrate/*webhook* app/models/webhook_endpoint* app/models/webhook_delivery* app/controllers/api/v1/webhook_endpoints_controller* app/controllers/api/v1/webhook_deliveries_controller* app/workers/*webhook* app/workers/*delivery* app/workers/circuit_breaker* app/mailers/*pause* app/lib/rate_limiting/*replay* docs/webhooks/* spec/requests/webhook_endpoints_spec.rb spec/requests/deliveries_spec.rb spec/requests/replay_spec.rb spec/workers/delivery_worker_spec.rb spec/workers/signing_spec.rb spec/workers/circuit_breaker_spec.rb spec/notifications/pause_notice_spec.rb spec/features/endpoint_detail_spec.rb spec/perf/partition_isolation_spec.rb'
```
Output: `scope declared: 20 glob(s)`

Criteria freeze:
```
bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/webhook-delivery.state.json --criteria .spectra/plans/webhook-delivery.acceptance.md
```
Output:
```
frozen: d95e54e4c21061809d5df431e4acff109637991d85ced73af3a31f8ee0ac481d
d95e54e4c21061809d5df431e4acff109637991d85ced73af3a31f8ee0ac481d
```

Freeze verification (sanity check — recompute and compare):
```
bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/webhook-delivery.state.json --criteria .spectra/plans/webhook-delivery.acceptance.md --verify
```
Output: `ok: criteria match frozen hash`

Emission gate (spec frontmatter + ECL v2.0 envelope, integrity, closed performative set):
```
bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/webhook-delivery.md --envelope .spectra/plans/webhook-delivery.envelope.json
```
Output: `ok: emission gate passed (webhook-delivery.md + envelope)`

Final transition:
```
bash .eidolons/ramza/bin/ramza-gate advance --to DONE --state .spectra/plans/webhook-delivery.state.json
```
Output: `OK: A -> DONE`

## 10. Final state and adherence

```
bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/webhook-delivery.state.json
```
Output:
```
{
  "plan": "webhook-delivery",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```

```
bash .eidolons/ramza/bin/ramza-adherence --state .spectra/plans/webhook-delivery.state.json
```
Output:
```
{
  "plan_phase": 1,
  "plan_order": 1,
  "plan_fidelity": null,
  "composite": 1,
  "inputs": {
    "tier": "full",
    "phases_done": [
      "RS",
      "S",
      "P",
      "E",
      "C",
      "T",
      "R",
      "T",
      "A",
      "DONE"
    ],
    "refine_cycles": 1,
    "skips": 0,
    "drift_range": null
  },
  "at": "2026-07-05T19:40:49Z"
}
```
`plan_fidelity` is `null` because no execution has happened yet (no drift range to
compare) — per `ramza-adherence`'s own documented contract this is expected pre-
execution and the composite (geometric mean of the *available* components,
plan_phase=1 and plan_order=1) is correctly 1, not a claim that fidelity was
measured.

## Preflight checklist (SPEC.md), verified against the above

- [x] RS ran; tier recorded: **full**, score 8.
- [x] Phase walk clean in state: RS→S→P→E→C→T→R→T→A→DONE, no unexplained skips
      (`skips: []`).
- [x] Hypotheses scored via tool (4, exceeding the full-tier 3–5 requirement);
      rejected alternatives (A, C, D) documented with rationale.
- [x] `ramza-lint` + `ramza-ears-lint` green (final state, 24/24 criteria, both
      the plan's embedded block and the canonical sibling file).
- [x] Full tier: critic recorded, author ≠ checker
      (`ramza-author-sonnet5` ≠ `ramza-critic-sonnet5-cleancontext`).
- [x] Confidence computed via tool (82.75% → VALIDATE); verdict honored (recommends
      human review, stated plainly rather than overridden).
- [x] Scope declared (20 globs); criteria frozen
      (`d95e54e4c21061809d5df431e4acff109637991d85ced73af3a31f8ee0ac481d`);
      `ramza-verify-emit` green.
- [x] Every output path under `.spectra/`; no code produced (this run wrote only
      `.spectra/plans/webhook-delivery.{md,acceptance.md,state.json,envelope.json}`
      and `.spectra/plans/ramza-calibration.jsonl` inside the project directory).

---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-review
created_at: 2026-07-05T13:12:41Z
thread_id: 019f3268-e047-7b7e-953b-1a3b7fcdea87
target_repos:
  - "<unresolved — no webhook/event-delivery implementation found in /tmp/spectra-pilot (Eidolons scaffold only, no application source); see CLARIFY Gap-1>"
stories_count: 10
validation_gates_count: 30
evidence_anchors_count: 0
confidence: 0.75
---

# SPEC-2026-07-05-001 — Webhook Delivery Subsystem (multi-tenant SaaS)

**Mission:** Produce a decision-ready specification for a webhook delivery subsystem for a multi-tenant SaaS: customers register webhook endpoints; events must be delivered with retries and backoff; failures must be observable to customers. Include user stories, acceptance criteria, scope boundaries, and at least one rejected alternative.

**Methodology:** SPECTRA v4.11.0 — CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble
**Tier:** Extended (complexity 10/12 → extended-thinking budget; at the boundary of the 10–12 human-in-the-loop band — see Scope phase. Single-pass S→P→E→C→T→R→A cycle; TRANCE/parallel-spec mode was **not** activated — no cortex dispatch signal authorized it, and activating it unilaterally would violate the "never the default" gate).
**Read-only invariant honored:** no code, no file edits to any target system were made in producing this spec.

---

## Memory pre-flight (mission intake)

Per `agent.md`, a `mcp__crystalium__recall` call was attempted before CLARIFY to surface prior specs, decisions, and known traps relevant to "webhook delivery," "retry/backoff," or "multi-tenant event fan-out." **No `mcp__crystalium__*` tools are reachable in this environment** (confirmed absent from the tool surface; no CRYSTALIUM install evidence anywhere under `/tmp/spectra-pilot`). Per the documented graceful-skip rule this is a silent no-op, not a hard failure — SPECTRA is EIIS-standalone-conformant. Planning proceeds without prior-session memory; this is carried forward as a Pattern-phase gap below rather than papered over with a fabricated match.

---

## CLARIFY

**Trigger:** every new request. **Not skipped** — the mission names a well-understood problem class (webhook delivery) but supplies no target repository, no existing event/pub-sub infrastructure, no tenancy model, and no product-specific constraints. That is genuine ambiguity in plan shape, not merely missing polish, so CLARIFY runs in full (DISCOVER was not warranted: the goal itself — "deliver events to customer-registered endpoints reliably and observably" — is already clear; only its shape is underspecified, which is exactly CLARIFY's remit).

**Parse Intent:**
- **WHO:** (a) SaaS customers/integrators who register one or more webhook endpoints per tenant to receive event notifications; (b) the customer's on-call/engineering staff who must debug delivery failures without opening a support ticket; (c) the SaaS's own support/platform engineers who need cross-tenant visibility for triage; (d) the internal service(s) that already emit domain events (assumed to exist upstream — this subsystem's job starts at "an event needs fan-out to registered endpoints," not at how the event was produced).
- **WHAT:** a subsystem that lets tenants register/manage HTTPS webhook endpoints, delivers domain events to those endpoints with automatic retry and backoff on failure, and exposes delivery outcomes (success, failure, retry state, final disposition) to customers in a self-serve, non-support-ticket way.
- **WHY:** webhook reliability is a trust primitive for integration-dependent SaaS customers (payment, workflow, and data-sync integrations commonly key off webhook events) — undelivered or invisible failures directly translate into customer data-integrity incidents and support load; visible, predictable retry/backoff behavior lets customers build correct systems against this API instead of guessing.
- **CONSTRAINTS:** must isolate tenants from each other (no cross-tenant data leakage, no cross-tenant resource starvation); must not let a slow/down customer endpoint create unbounded backlog or resource exhaustion in the platform; must not treat a webhook URL as a trusted target (SSRF risk — the platform is making outbound HTTP calls to third-party-supplied URLs on behalf of every tenant); must degrade gracefully under partial failure (a single dead endpoint must not block delivery to any other endpoint or tenant).

**Identify Gaps:**

| # | Gap | Resolution mode |
|---|-----|------------------|
| G1 | No target repository, language/stack, or existing event/pub-sub infrastructure was supplied. `/tmp/spectra-pilot` (this consumer project) contains only Eidolons scaffolding — no application source, no existing webhook/event code was found by search. `.spectra/setup/spectra-conventions.md` does not exist. | **[GAP] — cannot be closed interactively in this run** (single-shot deliverable, no live user turn available). Resolved via explicit, risk-tagged assumptions below rather than fabricating a fake codebase match. All Construct-phase file paths are marked `[ASSUMED]`. |
| G2 | Delivery semantics unstated: at-least-once vs. exactly-once, ordering guarantees, retry schedule/attempt cap, and terminal-failure handling (silently drop vs. dead-letter vs. disable endpoint). | **[ASSUMPTION]** — at-least-once delivery with a customer-facing idempotency key (industry-standard; exactly-once is explicitly evaluated and rejected below); no cross-event ordering guarantee in v1 (explicit non-goal, Scope table); bounded exponential-backoff retry schedule with a hard attempt cap, then dead-letter + endpoint health degradation (not silent drop). |
| G3 | "Failures must be observable to customers" does not specify the surface: logs only, a self-serve dashboard, a query API, or push notifications. | **[ASSUMPTION]** — a query API is the P0 requirement (mission explicitly says "observable to customers," implying self-serve, not internal-only logs); a minimal dashboard view and proactive failure-digest notification are treated as P1 enhancements on top of the same API, not separately gated. |
| G4 | Payload signing/authentication scheme and secret-rotation policy unstated. | **[ASSUMPTION]** — HMAC-SHA256 over the raw payload bytes, delivered via a signature header plus a timestamp header (replay-window mitigation); secret rotation supports a dual-secret grace period rather than a hard cutover. |
| G5 | Whether the platform must defend against SSRF via tenant-supplied URLs (internal network, cloud metadata endpoints, loopback) was not stated, but is a severe, well-known risk class for any "make outbound HTTP calls to a URL a third party gave you" subsystem in a multi-tenant SaaS. | **[ASSUMPTION]** — treated as a non-negotiable P0 security requirement, not an optional hardening pass, given the mission's multi-tenant framing. |
| G6 | Whether tenants can have multiple endpoints per event type (fan-out 1:N) or exactly one endpoint per tenant was not stated. | **[ASSUMPTION]** — 1:N (multiple endpoints per tenant, each independently subscribed to a subset of event types) — this is the near-universal industry pattern (Stripe, GitHub, Shopify) and the mission's "customers register webhook endpoints" (plural framing) supports it. |

**Would-ask (≤3, numbered, <200 chars, per CLARIFY step 3 — recorded for the human reviewer since no live turn is available this run):**
1. Does an event bus/domain-event system already exist that this subsystem taps into, or must event sourcing/ingestion also be built (G1)?
2. Is exactly-once delivery a hard customer requirement (e.g., for billing-adjacent events), or is at-least-once + idempotency key acceptable (G2)?
3. Is a customer-facing dashboard required for v1, or is a delivery-history API sufficient with UI deferred (G3)?

**Gather Structural Context:** grepped `/tmp/spectra-pilot` for `webhook`/`delivery`/`event` implementation — zero application-source hits (Eidolons scaffold files and this session's own prior planning artifacts only; no prior webhook spec exists to build on). No `spectra-conventions.md` to load. Proceeding with generic, industry-standard backend conventions (see Pattern phase) rather than fabricated project-specific paths; every file path in Construct below carries an explicit `[ASSUMED]` tag and must be re-anchored to the real target repo before implementation.

**Assess Cognitive Load:** single planning session sufficient to produce a decision-ready spec; flagged for likely **multi-session execution** given 10 stories and cross-cutting security/reliability/observability concerns (see Scope complexity score).

**Skip?** No — see gaps above. CLARIFY is complete via documented assumptions, which is directly why Assemble gates to VALIDATE rather than AUTO_PROCEED (see below), and why complexity routing recommends human-in-the-loop review despite this run proceeding single-pass.

---

## S — SCOPE

**Intent Type:** `REQUEST` (clear goal — a new subsystem — with `STRATEGIC`-adjacent breadth given it spans registration, delivery, security, and observability as one coherent capability).

**Complexity Score (4-dimension matrix):**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 2 | Multi-feature (registration, delivery engine, retry/backoff, observability) but bounded to one cohesive subsystem, not multiple products/quarters |
| Ambiguity | 2 | Core goal is unambiguous; many operational specifics (retry schedule, ordering, signing scheme) are unstated and resolved via documented assumptions (G2–G6) |
| Dependencies | 3 | Cross-domain: ingestion/fan-out, durable queueing, delivery workers, persistence, per-tenant security boundary, customer-facing API/dashboard — more than the 2–3-system band |
| Risk | 3 | Critical path for customer trust and, per G5, a genuine security-critical surface (SSRF via tenant-supplied URLs; cross-tenant isolation failure is a severe incident class) |

**Total: 10/12 → at the human-in-the-loop threshold** (`scoring.md` routes 10–12 to human collaboration). No live human turn is available in this single-shot run, so — consistent with the precedent this project's own history establishes for extended-tier gaps — planning proceeds via documented assumptions and the Assemble confidence gate is set conservatively (VALIDATE, not AUTO_PROCEED) rather than silently treating a 10/12 task as routine. **Recommendation carried into Assemble: a human should review this spec before Construct-phase execution begins**, specifically the security assumptions (G5) and the delivery-semantics decision (G2/rejected-alternative below).

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| Tenant-scoped webhook endpoint registration, update, deletion, listing | Building the upstream domain-event source/bus itself (assumed to already exist — G1) | Revisit if G1 resolves to "no event bus exists yet"; that would add a Phase-0 project ahead of this one |
| At-least-once delivery with retry + exponential backoff + jitter | Exactly-once delivery via distributed transactions/2PC (H-reject, see Explore) | Not deferred — rejected outright on cost/complexity grounds; idempotency key is the accepted mitigation |
| Dead-lettering + automatic endpoint disable after chronic failure | Cross-event ordering guarantees | Not deferred — explicit non-goal per G2; document in customer-facing API docs as "delivery order is not guaranteed" |
| HMAC payload signing + secret rotation | Endpoint discovery/verification challenge flows (e.g., a "ping" handshake before activation) beyond basic URL validation | Fast-follow candidate once core delivery ships — reduces one class of misconfigured-endpoint support tickets |
| SSRF-hardened URL validation (registration-time AND send-time, to close DNS-rebinding gaps) | General-purpose outbound HTTP proxy/allowlist management UI | Not needed for v1; the validation logic (S-2) is sufficient without a separate management surface |
| Per-tenant/per-endpoint delivery observability API (attempt history, status, latency) | Full audit-grade event-sourcing of every internal state transition (H3, rejected) | Revisit only if compliance/audit requirements emerge that the delivery-log API (S-8) cannot satisfy |
| Per-tenant/per-endpoint concurrency and rate limiting (noisy-neighbor protection) | Customer-configurable retry policies (custom schedules per tenant) | Fast-follow if enterprise tier demands it; v1 ships one platform-wide default schedule |
| Manual redelivery/replay of a specific failed delivery | Bulk replay / backfill tooling across many deliveries at once | Fast-follow; v1's single-delivery replay (S-10) covers the common case |

**Assumptions (risk-tagged):**

1. **[ASSUMPTION]** An upstream domain-event source already exists and this subsystem's boundary starts at "receive an event that needs fan-out." **Risk if wrong:** if no event bus exists, a Phase-0 "event ingestion" project is needed ahead of P-1 below — re-run Scope once G1 is resolved.
2. **[ASSUMPTION]** At-least-once delivery + idempotency key is acceptable; exactly-once is not a hard requirement. **Risk if wrong:** if a customer segment (e.g., billing/financial events) contractually requires exactly-once, this becomes a materially different (and more expensive) system — flagged for human review at the VALIDATE gate below, not silently assumed away.
3. **[ASSUMPTION]** A delivery-history API is P0; a dashboard UI and failure-digest notifications are P1 enhancements layered on the same API, not separately gated release blockers. **Risk if wrong:** low — P1 stories (S-9's notification half, dashboard) are independently deferrable without touching the P0 API contract.
4. **[ASSUMPTION]** SSRF protection is P0, non-negotiable, and must validate at both registration time and send time (DNS can change between the two). **Risk if wrong:** none identified — this assumption is a security floor, not a product trade-off; no re-open trigger, it should never be relaxed.
5. **[ASSUMPTION]** Endpoints support 1:N per tenant, each independently subscribed to a subset of event types. **Risk if wrong:** if the real requirement is strictly 1:1, S-1's data model over-generalizes slightly but remains correct (a tenant with exactly one endpoint is a degenerate case of 1:N) — low risk either way.

**Stakeholders:** tenant integrators/developers (primary users of registration + observability), tenant on-call engineers (primary users of failure visibility + manual replay), platform/support engineers (secondary users needing cross-tenant triage — not built as a separate story in v1, but S-8's data model should not preclude an internal admin view later), security/compliance reviewer (must sign off on G5's SSRF posture and G4's signing scheme before ship), the engineer(s) implementing Construct's stories.

---

## P — PATTERN

**Query memory:** unavailable this session (see Memory pre-flight) — **[GAP]**, not a false negative; no prior-failure catalog to surface, no prior webhook-specific spec exists in this project's `.spectra/plans/` history to build on.

**Query codebase:** zero matches in `/tmp/spectra-pilot` (see CLARIFY G1). Falling back to well-established external reference architectures for "multi-tenant webhook delivery with retry/backoff," ranked by similarity to this ask (MMR: `similarity − 0.3 × redundancy`, top candidates shown):

| Pattern | Similarity | Why |
|---|---|---|
| Stripe Webhooks (event → durable queue → worker → exponential backoff → dashboard event log) | 88% | Closest match on every axis this mission names: multi-tenant, retry+backoff, customer-visible delivery log, signing scheme, endpoint disable-on-chronic-failure |
| GitHub Webhooks (per-repo endpoints, delivery redelivery UI, HMAC signing, recent-deliveries API) | 85% | Near-identical shape; strongest match for the "manual redelivery" and "delivery history API" stories specifically |
| AWS SQS + Lambda DLQ pattern (queue-native redelivery, visibility timeout, dead-letter queue) | 74% | Strong match for the underlying retry/backoff *mechanism*, weaker on the customer-facing observability half — this mission needs more than what a raw DLQ gives you |
| Shopify Webhooks (event topics, per-shop endpoint registration, exponential backoff, 48h retry window then give up) | 80% | Strong match on tenancy model (per-shop = per-tenant) and gives a concrete, decision-ready retry-window precedent |
| Svix / Hookdeck (managed webhook-delivery-as-a-service) | 66% | Relevant as a *buy* reference point (informs the risk-minimizing hypothesis, H4, below) rather than a build pattern |

**No single pattern reaches the 85% USE_TEMPLATE threshold outright** (Stripe's is close at 88% but there is no in-repo implementation to apply verbatim — the match is to an external reference architecture, not a codebase template). **Strategy: ADAPT (60–84% band, generously informed by an 88%-similar reference)** — adopt the Stripe/GitHub/Shopify family's shared skeleton (durable queue → worker pool → bounded exponential backoff → dead-letter → customer-visible delivery log → manual redelivery) as the structural backbone for Construct, while treating the SQS/DLQ pattern as the mechanism reference for the retry engine specifically (S-6) and Svix/Hookdeck as the buy-vs-build comparator evaluated and rejected in Explore (H4).

**Catalog Failure Patterns:** none available from memory (unreachable this session). Documented as a gap rather than skipped silently. One externally-known failure pattern is surfaced anyway from general domain knowledge, flagged as advisory rather than a memory hit: **DNS-rebinding SSRF bypass** — validating a webhook URL's IP only at registration time and trusting it unchanged at send time is a well-documented bypass class; this directly shapes S-2's send-time-revalidation requirement below.

---

## E — EXPLORE

**Trigger:** before Construct. Not skipped. 4 genuinely distinct hypotheses generated (within the 3–5 range; conservative + pattern-leveraging + innovative + risk-minimizing/buy, exceeding the minimum-diversity requirement).

**Observations (5 angles):** (1) reliability — the retry/backoff mechanism must survive a customer endpoint being down for hours without either giving up too early or hammering it; (2) tenant isolation — one tenant's event volume or one dead endpoint must never starve or delay another tenant's deliveries; (3) trust/observability — a customer who can't tell *why* a webhook didn't arrive will file a ticket regardless of how reliable the retry logic actually is; (4) security — every registered URL is an SSRF vector by construction, since the platform is the one making the outbound call; (5) operational cost — build-vs-buy is a legitimate axis given mature managed webhook-delivery vendors exist.

### Hypothesis scoring (7-dimension weighted rubric, 1–10 per dimension → weighted, ×10 to express /100)

| # | Hypothesis | Align 25% | Correct 20% | Maintain 15% | Perf 15% | Simple 10% | Risk 10% | Innov 5% | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Conservative** — relational-DB-backed delivery table + polling worker picks up due/retryable rows on a fixed interval | 7 | 8 | 8 | 5 | 9 | 7 | 2 | **70.0** |
| H2 | **Pattern-leveraging** — durable queue (per-tenant-partitioned) + worker pool consumes deliveries; retry via explicit backoff scheduler layered on queue-native redelivery/DLQ | 9 | 9 | 8 | 9 | 7 | 8 | 5 | **84.0** |
| H3 | **Innovative** — full event-sourced delivery pipeline: every state transition (enqueued, attempted, retried, delivered, dead-lettered) is itself a persisted event on a per-tenant partitioned log, giving complete replayable audit history | 8 | 7 | 6 | 8 | 3 | 6 | 9 | **68.5** |
| H4 | **Risk-minimizing (buy)** — integrate a managed webhook-delivery vendor (Svix/Hookdeck-style); build only tenant-mapping, billing, and a thin proxy layer in front of it | 6 | 8 | 9 | 8 | 9 | 5 | 3 | **72.0** |

Spread is 84.0 → 68.5 (15.5-point range) — **not** within the 5% "insufficient differentiation" band; the set is well-differentiated and no re-observation is needed. Per the "expand top 2" rule, **H2 and H4** are expanded below (H1 and H3 sit lower and are addressed directly in Rejected Alternatives without a full expansion pass, consistent with the rubric's guidance to focus depth on the leading candidates).

### Expand top 2

**H2 — Durable queue + worker pool (pattern-leveraging).**
- *Component impact:* moderate — a fan-out/enqueue component (event → matching endpoints → one queue message per delivery attempt-target), a worker-pool component that dequeues and POSTs, and a backoff-scheduler component that re-enqueues failed deliveries at a computed future time rather than relying solely on the queue's native redelivery interval (which is typically fixed-interval, not exponential).
- *Dependency chain:* every mutating "deliver" action flows through one enqueue path (mirrors the guard-wrapper discipline this project's own prior dry-run spec established: single choke point beats scattered conditionals); the queue's per-tenant partitioning is the key isolation mechanism — a highest-risk dependency is *fair scheduling across partitions* so one tenant's backlog can't starve another's queue consumers.
- *Edge cases:* a tenant that deletes/rotates an endpoint mid-retry-cycle (in-flight deliveries must not resurrect a deleted endpoint's queue), a burst of simultaneous webhook-eligible events for one tenant (rate limiting, S-7, must smooth this), duplicate delivery on worker-crash-mid-attempt (idempotency key, G2, is the accepted mitigation rather than distributed transactions).

**H4 — Managed vendor integration (buy, risk-minimizing).**
- *Component impact:* small on the delivery-mechanics side (no queue, worker pool, or retry engine to build — the vendor owns S-4 through S-7's mechanics) but non-trivial on the integration side: tenant-to-vendor-account mapping, secret/credential proxying so the vendor never sees the SaaS's own infrastructure credentials, and a compatibility shim so the customer-facing delivery-history API (S-8) doesn't leak vendor-specific implementation details into the contract.
- *Dependency chain:* the entire subsystem's reliability now depends on a third party's uptime and roadmap; a vendor outage becomes this SaaS's outage with no internal mitigation path beyond a slow migration.
- *Edge cases:* per-tenant data residency/compliance requirements that the vendor cannot satisfy (a real risk for any SaaS with EU/regulated customers, since customer event *payloads* — not just metadata — transit the vendor); vendor pricing that scales unfavorably at high event volume; harder-to-customize retry/backoff semantics if a future enterprise tier needs them (Scope's "deferred" row on customer-configurable retry policies becomes much harder to fast-follow on a vendor's fixed feature set).

### Selection

**Selected: H2 (durable queue + worker pool, pattern-leveraging).** It scores highest overall (84.0) and is the only hypothesis that scores ≥8 on both Performance and Risk simultaneously — the two dimensions that matter most given this mission's explicit "must be observable" and multi-tenant-isolation framing. It directly matches the Pattern phase's highest-similarity external reference family (Stripe/GitHub/Shopify, 80–88% similarity) without requiring H3's audit-grade complexity or H4's vendor dependency and data-residency exposure. H2 also keeps every Construct-phase story (below) buildable and testable in isolation, which materially reduces the risk this 10/12-complexity spec is trying to manage.

**Rejected alternatives (documented per E-phase step 6, prevents re-exploration in replanning):**

- **H1 (polling worker, conservative) — rejected, not permanently.** Simpler to build and reason about (Simplicity 9), but polling-interval latency directly conflicts with "failures must be observable" in near-real-time, and DB-row-scanning at scale becomes a throughput ceiling exactly where multi-tenant fan-out needs headroom (Performance scored only 5). **Re-open trigger:** if actual event volume is proven low (e.g., a small pilot cohort of tenants), H1's simplicity may outweigh H2's scalability headroom — re-run Explore with a concrete volume estimate if one becomes available.
- **H3 (full event-sourced audit pipeline, innovative) — rejected for v1, deferred.** Highest Innovation score (9) and the best long-term audit story, but Simplicity scored only 3 — persisting every state transition as its own event, on top of the delivery event itself, is a materially larger build for a first ship whose ask is "retry, backoff, and observable failures," not "provably complete audit trail." Its observability *spirit* is retained cheaply via S-8's delivery-history API, which records attempt-level state without the full event-sourcing machinery. **Re-open trigger:** a compliance/audit requirement that S-8's log table cannot satisfy (e.g., regulatory need for cryptographically-chained delivery records).
- **H4 (buy a managed vendor, risk-minimizing) — rejected for this spec's target, not universally wrong.** Scored second-highest (72.0) driven by strong Maintainability/Simplicity, but Alignment (6) and Risk (5) suffer from the same root cause: outsourcing a customer-trust-critical, security-sensitive surface (raw event payloads transiting a third party) in a multi-tenant SaaS creates a compliance/data-residency dependency this spec cannot resolve without a real vendor DPA and target-market answer — exactly the kind of decision this 10/12-complexity task flagged for human review in Scope. **Re-open trigger:** if webhook delivery is explicitly *not* a strategic differentiator for this product and a compliant vendor is already contracted, H4 becomes the stronger choice outright — this is a genuine build-vs-buy decision, not a technical inferiority verdict, and belongs at the human-in-the-loop checkpoint this spec already recommends.
- **Exactly-once delivery via distributed transactions/2PC — rejected outright (called out separately from H1–H4 because it is a delivery-semantics decision embedded inside every hypothesis, not a standalone architecture).** Coordinating a transactional guarantee across the platform's internal state and an arbitrary, untrusted, potentially-slow third-party HTTP endpoint is a well-known near-impossibility (the customer's server is outside the transaction boundary by definition) and the attempted approximations (sagas, outbox-plus-2PC-emulation) add substantial complexity for a guarantee that still degrades to at-least-once under real network partitions. **Accepted mitigation:** at-least-once delivery + a customer-visible idempotency key (S-5 AC), which every major production webhook system (Stripe, GitHub, Shopify) also converges on — this is not a corner cut, it is the industry-standard resolution of a genuinely unsolvable stronger guarantee. No re-open trigger; this should not be revisited absent a fundamentally different problem statement.

---

## C — CONSTRUCT

**Hierarchy:**

```
THEME    Reliable, Observable Customer-Facing Event Delivery
└─ PROJECT  P-1  Webhook Delivery Subsystem
   ├─ FEATURE F-1  Endpoint Registration & Security
   │  ├─ STORY S-1  Tenant-scoped endpoint CRUD API
   │  ├─ STORY S-2  Endpoint URL validation & SSRF protection
   │  └─ STORY S-3  Signing secret issuance & rotation
   ├─ FEATURE F-2  Event Delivery Engine
   │  ├─ STORY S-4  Event-to-endpoint fan-out & durable enqueue
   │  ├─ STORY S-5  Delivery worker: signed POST + timeout + idempotency contract
   │  ├─ STORY S-6  Retry, exponential backoff & dead-letter transition
   │  └─ STORY S-7  Per-tenant / per-endpoint concurrency & rate limiting
   └─ FEATURE F-3  Delivery Observability & Customer Trust
      ├─ STORY S-8  Delivery history API (per-attempt status, code, latency)
      ├─ STORY S-9  Auto-disable chronically-failing endpoints + tenant notification
      └─ STORY S-10 Manual redelivery / replay of a specific failed delivery
```

All 10 stories pass INVEST (Independent within the necessary sequencing below, Negotiable on exact wording, Valuable to a named actor, Estimable at the timeboxes below, Small ≤3d each, Testable via the GIVEN/WHEN/THEN sets below).

**Execution sequence (dependency-ordered):**

```
Phase 1:  S-1
Phase 2:  S-2  ‖  S-3        (parallel — distinct concerns, both extend S-1's data model)
Phase 3:  S-4                (needs registered, validated, signable endpoints)
Phase 4:  S-5                (needs the fan-out/enqueue path from S-4 and signing from S-3)
Phase 5:  S-6  ‖  S-7        (parallel — retry policy and rate limiting both wrap S-5's worker, independently)
Phase 6:  S-8                (needs attempt-level data produced by S-5/S-6 to have something to expose)
Phase 7:  S-9  ‖  S-10       (parallel — both consume S-8's data + S-6's terminal-state signal)
```

---

#### 📋 STORY: S-1 Tenant-scoped endpoint CRUD API

> 🔴 P0

**Description:** As a tenant developer, I want to register, update, list, and delete webhook endpoints scoped to my own tenant so that I can control where my events are delivered without any risk of seeing or affecting another tenant's configuration.
**Timebox:** ≤2d
**Risk:** P0 (blocks release — every downstream story depends on a correct, tenant-isolated endpoint record)

**Action Plan:**
1. **Create:** an endpoint entity (tenant_id, url, subscribed event types, status [active/disabled], created_at, updated_at) with tenant_id enforced on every read/write path — never optional, never derived from client-supplied input alone.
2. **Extend:** the tenant-scoped API layer with CRUD routes for endpoints, requiring the same tenant-auth context every other tenant-scoped resource in the platform uses.
3. **Test:** cross-tenant isolation as a first-class test (tenant A's token can never read, list, update, or delete tenant B's endpoint, including via ID-guessing/enumeration); CRUD happy paths; validation-error paths for malformed input (deferred URL-specific validation to S-2).

**Acceptance Criteria:**
- [ ] GIVEN an authenticated tenant WHEN they create an endpoint with a URL and a set of event types THEN the endpoint is persisted scoped to that tenant and returned with a generated ID
- [ ] GIVEN an endpoint belonging to tenant A WHEN tenant B attempts to read, update, or delete it by ID THEN the request is rejected as not-found (never a distinguishable "forbidden," to avoid leaking existence via a distinct error path)
- [ ] GIVEN a tenant lists their endpoints WHEN the request is made THEN only that tenant's endpoints are returned, regardless of total platform-wide endpoint count

**Technical Context:**
- **Pattern:** standard tenant-scoped resource CRUD, consistent with this platform's existing multi-tenant API conventions
- **Files:** `[ASSUMED — confirm against target repo]` `api/webhooks/endpoints.*` (routes/handlers), `[ASSUMED]` `db/models/webhook_endpoint.*` (entity)
- **Dependencies:** none (foundation story)

**Agent Hints:**
- **Class:** Builder (speed-class implementation)
- **Context:** existing tenant-auth middleware/context propagation conventions used by other tenant-scoped resources in the target repo
- **Gates:** P0 cross-tenant isolation test suite must pass before merge; this is the single highest-value regression gate for the whole subsystem

---

#### 📋 STORY: S-2 Endpoint URL validation & SSRF protection

> 🔴 P0 — security-critical

**Description:** As the platform, I want every tenant-supplied webhook URL validated against internal/private network targets at both registration time and send time so that no tenant can use the webhook feature to reach internal infrastructure, cloud metadata endpoints, or other tenants' services.
**Timebox:** ≤2d
**Risk:** P0 (a gap here is a severe, exploitable security incident, not a degraded-experience bug)

**Action Plan:**
1. **Create:** a URL validation function rejecting non-HTTPS schemes, private/loopback/link-local IP ranges (RFC 1918, 127.0.0.0/8, 169.254.0.0/16 including the common cloud-metadata address), and any URL that resolves to such a range.
2. **Modify:** both the S-1 registration/update path (validate at write time) and the S-5 delivery worker (re-resolve and re-validate immediately before each send) to call this function — send-time revalidation specifically closes the DNS-rebinding gap identified in the Pattern-phase failure catalog.
3. **Test:** direct private-IP URLs rejected at registration; a URL that resolves to a public IP at registration but is DNS-rebound to a private IP before send is still blocked at send time; legitimate public HTTPS URLs are unaffected.

**Acceptance Criteria:**
- [ ] GIVEN a tenant registers or updates an endpoint WHEN the URL resolves to a private, loopback, link-local, or cloud-metadata address THEN the registration is rejected with a clear, non-leaky error message
- [ ] GIVEN a validated endpoint's DNS record changes to point at a disallowed address WHEN the delivery worker attempts a send THEN the send is blocked at that moment (send-time revalidation), not only at the original registration time
- [ ] GIVEN a legitimate public HTTPS endpoint WHEN registered or delivered to THEN validation introduces no functional difference in behavior versus an unvalidated call

**Technical Context:**
- **Pattern:** SSRF-hardened outbound-URL validation with DNS-rebinding closure (Pattern phase, advisory failure catalog)
- **Files:** `[ASSUMED]` `lib/webhooks/url_validation.*` (shared by S-1 and S-5)
- **Dependencies:** S-1 (validates the entity S-1 creates); consumed again by S-5

**Agent Hints:**
- **Class:** Reasoner (security-critical logic warrants adversarial-minded implementation, not speed-first)
- **Context:** any existing outbound-HTTP-call security conventions elsewhere in the target repo; standard SSRF-defense reference implementations
- **Gates:** P0 — security review sign-off required before merge (per Scope stakeholders); DNS-rebinding test case specifically must be present and green

---

#### 📋 STORY: S-3 Signing secret issuance & rotation

> 🔴 P0 — security-critical

**Description:** As a tenant developer, I want each of my webhook endpoints issued a unique signing secret, and the ability to rotate it without downtime, so that I can cryptographically verify a received webhook actually came from this platform and wasn't forged or replayed.
**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Create:** a per-endpoint secret generated at creation time, stored encrypted at rest, never returned in any list/read response after initial creation (write-once display, standard secret-handling convention).
2. **Extend:** the S-1 endpoint entity with a rotation action that issues a new secret while keeping the prior secret valid for a bounded grace window (dual-secret acceptance), so in-flight signature verification on the customer's side doesn't break the instant rotation happens.
3. **Test:** signature computed with old secret still accepted during the grace window; rejected after grace-window expiry; new secret accepted immediately upon rotation.

**Acceptance Criteria:**
- [ ] GIVEN an endpoint is created THEN the platform SHALL generate a unique signing secret for it, returned exactly once at creation time and never again in plaintext
- [ ] GIVEN a tenant rotates an endpoint's secret WHEN a delivery is signed during the grace window THEN signatures from both the old and new secret SHALL verify successfully
- [ ] GIVEN the grace window has elapsed since rotation WHEN a delivery is signed THEN only the new secret SHALL verify successfully

**Technical Context:**
- **Pattern:** dual-secret rotation grace window (standard practice for zero-downtime credential rotation)
- **Files:** `[ASSUMED]` `lib/webhooks/signing.*` (secret generation, encrypted storage, rotation)
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner (secret handling and grace-window logic are easy to subtly get wrong)
- **Context:** existing secret/credential storage-at-rest conventions in the target repo (KMS/encryption-key usage patterns, if any)
- **Gates:** P0 — no plaintext secret in logs, error messages, or non-creation API responses (grep-checkable gate)

---

#### 📋 STORY: S-4 Event-to-endpoint fan-out & durable enqueue

> 🔴 P0

**Description:** As the platform, I want each domain event matched against every active, subscribed endpoint for its tenant and durably enqueued as one delivery task per match, so that delivery attempts survive a worker crash and no matched endpoint is silently skipped.
**Timebox:** ≤3d
**Risk:** P0

**Action Plan:**
1. **Create:** a fan-out component that, given a domain event (tenant_id, event type, payload), looks up that tenant's active endpoints subscribed to that event type.
2. **Extend:** the enqueue path to write one durable delivery-task message per (event, endpoint) match to a per-tenant-partitioned durable queue (H2, Explore), tagging each task with an idempotency key derived from the event so retries and duplicate enqueues remain safely re-deliverable.
3. **Test:** an event matching zero endpoints produces zero tasks (not an error); an event matching N endpoints produces exactly N tasks; a fan-out crash mid-loop does not produce partial/duplicate enqueues beyond what the idempotency key already tolerates.

**Acceptance Criteria:**
- [ ] GIVEN a domain event for a tenant WHEN it matches one or more active, subscribed endpoints THEN exactly one durable delivery task SHALL be enqueued per matched endpoint
- [ ] GIVEN a domain event matches zero endpoints (none registered, or none subscribed to that event type) THEN no delivery task is created and no error is raised
- [ ] GIVEN the enqueue operation is retried after a partial failure WHEN the same event is reprocessed THEN duplicate delivery tasks SHALL carry the same idempotency key rather than silently duplicating unbounded work

**Technical Context:**
- **Pattern:** durable queue fan-out, per-tenant partitioned (Pattern phase, H2 selection)
- **Files:** `[ASSUMED]` `lib/webhooks/fanout.*` (matching + enqueue)
- **Dependencies:** S-1 (endpoint registry to match against)

**Agent Hints:**
- **Class:** Builder
- **Context:** existing domain-event schema/bus, if one exists (CLARIFY G1); queueing infrastructure already in use elsewhere in the platform, if any
- **Gates:** P0 — no-skip test (every active subscribed endpoint receives a task) and no-unbounded-duplication test both green

---

#### 📋 STORY: S-5 Delivery worker: signed POST + timeout + idempotency contract

> 🔴 P0

**Description:** As a tenant developer, I want every webhook delivery signed, time-bounded, and carrying a stable idempotency key so that I can verify authenticity, avoid hanging connections, and safely deduplicate on my end under at-least-once delivery.
**Timebox:** ≤3d
**Risk:** P0

**Action Plan:**
1. **Create:** a worker pool that dequeues delivery tasks and issues an HTTPS POST to the endpoint's URL (re-validated per S-2), with the HMAC signature (S-3) and idempotency key (S-4) as headers, and the event payload as the body.
2. **Configure:** an explicit request timeout (assumed 10s) and a maximum payload size (assumed 256KB) as documented contract values, not silent defaults an implementer has to reverse-engineer.
3. **Test:** signature header verifiable by a reference HMAC implementation; timeout enforced (a slow-responding mock endpoint is aborted at the boundary, not left hanging); idempotency key stable across retries of the same logical delivery.

**Acceptance Criteria:**
- [ ] GIVEN a delivery task is dequeued WHEN the worker sends it THEN the request SHALL include a valid HMAC-SHA256 signature header, a timestamp header, and an idempotency key header stable across all retry attempts of that same task
- [ ] GIVEN the destination endpoint does not respond within the configured timeout THEN the worker SHALL abort the request and treat it as a failed attempt eligible for retry (S-6), never block the worker slot indefinitely
- [ ] GIVEN the endpoint returns any 2xx status THEN the delivery SHALL be marked successful and no further retry attempted; GIVEN any non-2xx or timeout/connection error THEN it SHALL be marked failed and handed to the retry policy (S-6)

**Technical Context:**
- **Pattern:** signed-POST delivery worker (Pattern phase, Stripe/GitHub family)
- **Files:** `[ASSUMED]` `workers/webhook_delivery/*` (worker pool)
- **Dependencies:** S-4 (task source), S-2 (send-time validation), S-3 (signing)

**Agent Hints:**
- **Class:** Builder
- **Context:** S-2's validation function, S-3's signing function, S-4's task shape
- **Gates:** P0 — timeout-enforcement test and signature-verification test both required; no delivery ships without both green

---

#### 📋 STORY: S-6 Retry, exponential backoff & dead-letter transition

> 🔴 P0 — the story that most directly answers the mission's "retries and backoff" ask

**Description:** As a tenant developer, I want failed deliveries retried on a predictable exponential-backoff schedule and, after a bounded number of attempts, moved to a terminal dead-letter state rather than retried forever, so that transient outages self-heal and permanent failures don't consume infrastructure indefinitely.
**Timebox:** ≤3d
**Risk:** P0

**Action Plan:**
1. **Configure:** a fixed retry schedule as an explicit, documented contract (assumed: attempts at +1m, +5m, +30m, +2h, +6h, +24h from the prior failure — 6 attempts spanning ~24h, jitter applied to each interval to avoid synchronized retry storms across many endpoints).
2. **Create:** a backoff scheduler that re-enqueues a failed delivery task at its next scheduled time rather than relying solely on the queue's native fixed-interval redelivery.
3. **Modify:** the task's terminal state after the final scheduled attempt fails to "dead-lettered" (a durable, queryable state — never simply dropped) and signal S-9 that the endpoint just failed a delivery.

**Acceptance Criteria:**
- [ ] GIVEN a delivery attempt fails WHEN fewer than the maximum attempt count has been reached THEN the task SHALL be re-scheduled at the next exponential-backoff interval with jitter, not retried immediately and not retried on a fixed interval
- [ ] GIVEN a delivery task exhausts all scheduled retry attempts WHEN the final attempt fails THEN the task SHALL transition to a durable "dead-lettered" state, queryable via S-8, rather than being dropped or retried indefinitely
- [ ] GIVEN a delivery succeeds on any attempt (first or a retry) THEN all remaining scheduled retries for that specific task SHALL be cancelled, never sent after a success

**Technical Context:**
- **Pattern:** bounded exponential backoff with jitter, DLQ terminal state (Pattern phase — SQS/DLQ mechanism reference, Shopify's concrete ~48h-then-give-up precedent informing the attempt-count/window choice)
- **Files:** `[ASSUMED]` `lib/webhooks/retry_policy.*`
- **Dependencies:** S-5 (consumes attempt outcomes)

**Agent Hints:**
- **Class:** Reasoner (scheduling correctness — especially "cancel remaining retries on success" and jitter to avoid retry storms — is easy to get subtly wrong)
- **Context:** S-5's failure-outcome contract, the durable queue's native redelivery/visibility-timeout semantics so this doesn't double up with the queue's own retry behavior
- **Gates:** P0 — retry-schedule test asserting exact backoff intervals (with jitter tolerance) and the success-cancels-remaining-retries test are both required

---

#### 📋 STORY: S-7 Per-tenant / per-endpoint concurrency & rate limiting

> 🟡 P1

**Description:** As the platform, I want per-tenant and per-endpoint concurrency caps on outbound delivery attempts so that one tenant's event volume or one slow endpoint cannot starve delivery capacity from any other tenant, and so a slow customer endpoint isn't hammered with more concurrent requests than it can handle.
**Timebox:** ≤2d
**Risk:** P1 (degrades fairness/experience under load; does not itself risk incorrect delivery — hence P1, not P0)

**Action Plan:**
1. **Create:** a concurrency limiter keyed by (tenant_id, endpoint_id) capping simultaneous in-flight delivery attempts per endpoint (assumed default: a small fixed cap, e.g. 5 concurrent per endpoint).
2. **Extend:** the worker pool's dequeue logic to respect a per-tenant fair-share allocation of overall worker capacity, so no single tenant's backlog can consume the entire pool.
3. **Test:** a tenant with a large backlog does not delay another tenant's near-empty queue beyond the fair-share bound; an endpoint at its concurrency cap has excess tasks wait rather than fan out unboundedly.

**Acceptance Criteria:**
- [ ] GIVEN an endpoint has reached its per-endpoint concurrency cap WHEN additional delivery tasks for that endpoint are ready THEN they SHALL wait rather than being sent concurrently beyond the cap
- [ ] GIVEN one tenant has a significantly larger delivery backlog than others WHEN worker capacity is allocated THEN other tenants' deliveries SHALL proceed within a bounded fair-share delay, not be starved indefinitely
- [ ] GIVEN concurrency and rate limits are active THEN no correctness property from S-5/S-6 (signing, timeout, retry schedule) SHALL change — limiting affects *when* a task runs, never *how*

**Technical Context:**
- **Pattern:** per-key concurrency limiting + fair-share worker allocation (noisy-neighbor protection)
- **Files:** `[ASSUMED]` `lib/webhooks/rate_limiter.*`
- **Dependencies:** S-4 (task source), S-5 (worker pool it wraps)

**Agent Hints:**
- **Class:** Builder
- **Context:** any existing per-tenant rate-limiting conventions elsewhere in the platform (likely to exist for API rate limits already)
- **Gates:** P1 — fair-share test under a synthetic large-backlog-vs-small-backlog scenario

---

#### 📋 STORY: S-8 Delivery history API (per-attempt status, code, latency)

> 🔴 P0 — this is the mission's "failures must be observable to customers" requirement made concrete

**Description:** As a tenant developer, I want a self-serve API listing every delivery attempt for my endpoints — status, HTTP response code, latency, and timestamp — so that I can debug why a webhook didn't arrive without filing a support ticket.
**Timebox:** ≤2d
**Risk:** P0 (this is an explicit, named mission requirement, not an enhancement)

**Action Plan:**
1. **Create:** a delivery-attempt record persisted by S-5/S-6 (task ID, endpoint ID, attempt number, outcome, response code, latency, truncated response body, timestamp) queryable by tenant, endpoint, and time range.
2. **Extend:** the tenant-scoped API layer with a read endpoint over this record, enforcing the same tenant-isolation discipline as S-1.
3. **Test:** cross-tenant isolation (same class of test as S-1); pagination/time-range filtering correctness; a dead-lettered delivery's full attempt history (all 6 attempts) is visible, not just the final outcome.

**Acceptance Criteria:**
- [ ] GIVEN a tenant queries delivery history for one of their endpoints THEN the response SHALL include every attempt's status, HTTP response code (or timeout/connection-error indicator), latency, and timestamp, in attempt order
- [ ] GIVEN a delivery has been retried multiple times THEN all attempts SHALL be individually visible, not collapsed into a single final-outcome row — a customer must be able to see the retry history, not just the end state
- [ ] GIVEN a tenant queries another tenant's endpoint's history by ID THEN the request SHALL be rejected as not-found, matching S-1's isolation contract exactly

**Technical Context:**
- **Pattern:** tenant-scoped read API over an attempt-log table (Pattern phase, GitHub "recent deliveries" precedent)
- **Files:** `[ASSUMED]` `api/webhooks/deliveries.*`, `[ASSUMED]` `db/models/delivery_attempt.*`
- **Dependencies:** S-5 (attempt records), S-6 (terminal-state records)

**Agent Hints:**
- **Class:** Builder
- **Context:** S-1's tenant-isolation pattern (reuse verbatim, don't reinvent)
- **Gates:** P0 — cross-tenant isolation test (shared gate class with S-1); this is the mission's named observability requirement, so its acceptance criteria should be treated as release-blocking, not negotiable

---

#### 📋 STORY: S-9 Auto-disable chronically-failing endpoints + tenant notification

> 🟡 P1

**Description:** As a tenant developer, I want the platform to automatically flag and disable an endpoint that has been failing consistently, and notify me when it does, so that I find out about a broken integration proactively instead of only when I happen to check the delivery history.
**Timebox:** ≤2d
**Risk:** P1 (degrades experience/adds delay-to-discovery if missing; core retry/observability already function without it)

**Action Plan:**
1. **Create:** a chronic-failure detector (assumed threshold: an endpoint whose last 20 consecutive delivery tasks all reached dead-lettered state) that transitions the endpoint's status from active to disabled.
2. **Extend:** the notification path (assumed: email to the tenant's registered contact, or an in-product alert if a dashboard exists) to fire once per disable transition, not once per failed delivery (avoiding notification storms).
3. **Test:** threshold-crossing correctly triggers exactly one disable + one notification; a subsequently-fixed endpoint that a tenant manually re-enables resets the failure-streak counter.

**Acceptance Criteria:**
- [ ] GIVEN an endpoint's most recent 20 delivery tasks have all reached dead-lettered state THEN the platform SHALL transition that endpoint's status to disabled and stop attempting new deliveries to it
- [ ] GIVEN an endpoint transitions to disabled THEN the platform SHALL send exactly one notification to the tenant identifying the endpoint and the failure streak, not a notification per underlying failed delivery
- [ ] GIVEN a tenant manually re-enables a disabled endpoint THEN its failure-streak counter SHALL reset to zero rather than immediately re-triggering disable on the next single failure

**Technical Context:**
- **Pattern:** circuit-breaker-style auto-disable with single-fire notification
- **Files:** `[ASSUMED]` `lib/webhooks/circuit_breaker.*`
- **Dependencies:** S-6 (dead-letter signal), S-8 (data it reads to compute the streak)

**Agent Hints:**
- **Class:** Reasoner (streak-counting and reset semantics are exactly the kind of off-by-one/notification-storm logic that benefits from careful review)
- **Context:** S-6's terminal-state contract, existing tenant-notification infrastructure in the platform if any
- **Gates:** P1 — notification-storm regression test (one disable = one notification, never N)

---

#### 📋 STORY: S-10 Manual redelivery / replay of a specific failed delivery

> 🟢 P2

**Description:** As a tenant developer, I want to manually trigger a redelivery of a specific failed or dead-lettered delivery attempt so that once I've fixed my endpoint, I can recover the missed event without waiting for a new event of that type to naturally occur.
**Timebox:** 1d
**Risk:** P2 (a convenience/recovery action layered on top of S-6/S-8; core reliability and observability function fully without it)

**Action Plan:**
1. **Create:** a redeliver action on a specific delivery-attempt record that re-enqueues the original event/endpoint pair as a fresh delivery task (new idempotency key, since this is a new, explicit attempt distinct from the automatic retry series it may follow).
2. **Extend:** the tenant-scoped API layer with this action, enforcing the same isolation contract as S-1/S-8.
3. **Test:** replay of a dead-lettered delivery succeeds against a now-healthy endpoint; replay is rejected for another tenant's delivery (isolation); replaying does not resurrect automatic retries for the original (now-terminal) task.

**Acceptance Criteria:**
- [ ] GIVEN a tenant triggers redelivery on one of their own dead-lettered or failed delivery attempts THEN a new delivery task SHALL be enqueued for the same event and endpoint, independent of the original task's terminal state
- [ ] GIVEN a tenant attempts to replay a delivery belonging to another tenant THEN the request SHALL be rejected as not-found, matching S-1/S-8's isolation contract
- [ ] GIVEN a replay is triggered THEN it SHALL NOT alter or resurrect the original task's dead-lettered state or its recorded attempt history — the replay is a new, separately-tracked task

**Technical Context:**
- **Pattern:** single-item manual replay (GitHub "redeliver" precedent); bulk replay explicitly out of scope (Scope table)
- **Files:** `[ASSUMED]` `api/webhooks/redeliver.*`
- **Dependencies:** S-8 (source of the delivery record to replay), S-6 (terminal-state semantics it must not disturb)

**Agent Hints:**
- **Class:** Builder
- **Context:** S-4's enqueue contract (a replay is functionally a new enqueue)
- **Gates:** P2 — isolation test (shared gate class with S-1/S-8); "does not disturb original record" regression test

---

## T — TEST (6-layer verification)

| # | Layer | Result |
|---|---|---|
| 1 | **Structural** | ✓ Hierarchy intact (Theme→Project→Feature→Story), no orphaned tasks, all 10 stories independent modulo the documented Construct-phase sequencing |
| 2 | **Self-Consistency** | ✓ See below — 3 alternative decompositions, ~76% overlap → HIGH confidence, stable |
| 3 | **Dependency** | ⚠ Partial — component/file paths (all `[ASSUMED]`) and the assumption that an upstream event bus already exists (G1) cannot be verified against a real codebase; flagged, not silently treated as resolved. No data-migration concerns (net-new subsystem, no existing schema to migrate) |
| 4 | **Constraint** | ✓ Timeboxes realistic (all ≤3d); tenant-isolation NFR explicit and gated in S-1/S-8/S-10; security implications (SSRF, signing, secret handling) each carry their own P0 story and explicit gates, not folded silently into unrelated stories |
| 5 | **Process Reward** | ✓ Ordering (registration/security → fan-out → delivery → retry/backoff → observability → recovery actions) monotonically reduces risk: the two P0 security stories (S-2, S-3) land before any delivery mechanism exists to exploit, and the retry/backoff story (S-6, the mission's namesake requirement) lands before the observability that depends on its data |
| 6 | **Adversarial** | ✓ See checklist below, extended with a security red-team pass given complexity 10/12 (see Adaptive verification budget note) |

**Self-Consistency check (3 alternative decompositions):**

- **Decomposition A (this spec):** registration/security / delivery engine / observability — 3 features, 10 stories, grouped by capability slice.
- **Decomposition B:** "endpoint lifecycle" (merges S-1+S-3+S-9, everything that changes an endpoint's state) / "delivery mechanics" (S-4+S-5+S-6+S-7) / "customer-facing surface" (S-2 folded in as a delivery-time check, S-8+S-10) — 3 stories-of-stories, same underlying concepts regrouped by ownership boundary rather than user-facing feature.
- **Decomposition C:** grouped by architectural layer instead of feature — "API layer" (S-1, S-8, S-10) / "security layer" (S-2, S-3) / "async engine" (S-4, S-5, S-6, S-7) / "trust/notification layer" (S-9) — same coverage, different axis, closest to how a real repo's directory structure would likely be organized.

All three surface the same underlying concepts (tenant-scoped registration, SSRF-safe validation, signing, fan-out, signed delivery, backoff/DLQ, fairness, history API, auto-disable, replay) — estimated **~76% story-content overlap** → **HIGH confidence, decomposition is stable.** Decomposition A was kept because P0/P1/P2 risk tags map cleanly onto user-facing feature slices, which is what the confidence-gating factors below actually need — decomposition B/C's groupings are useful cross-checks, not better primary structures.

**Adversarial checklist (Failure Taxonomy, `scoring.md`):**

| Failure mode | Checked | Finding |
|---|---|---|
| Under-specification | ✓ | Retry schedule and dead-letter threshold were initially unstated — fixed with explicit numeric defaults (S-6, S-9) in Refine below |
| Over-specification | ✓ | No rigid constraint blocks a valid implementation; all component paths marked `[ASSUMED]`, retry-interval numbers explicitly framed as defaults, not mandates |
| Dependency blindness | ⚠ | Real event-bus existence (G1) and real component boundaries are unknown — mitigated by requiring re-anchoring of every `[ASSUMED]` path before Construct-phase execution, not by pretending the target repo is known |
| Assumption drift | — | No earlier-phase discovery yet invalidates a later step; re-open triggers documented per rejected alternative (H1/H3/H4, exactly-once) |
| Scope creep | ✓ | Boundary table enforced; audit-grade event sourcing (H3), buy-vendor integration (H4), bulk replay, and customer-configurable retry policies explicitly kept out or deferred |
| Premature optimization | ✓ | Complexity 10/12 did not push the selection toward H3's over-engineered audit pipeline; H2 was chosen specifically for not carrying more machinery than the ask requires |
| Stale context | n/a | No prior file reads to go stale; this is a fresh cycle |

**Security red-team pass (added given complexity 10/12, per `scoring.md`'s adaptive verification budget guidance to extend beyond the standard 6 layers at this tier):**

| Threat | Mitigated by | Residual risk |
|---|---|---|
| SSRF via tenant-supplied URL (internal network, cloud metadata) | S-2 (registration + send-time validation) | Low if S-2's DNS-rebinding closure ships as specified; **high if S-2 is descoped or weakened** — flagged explicitly for the human reviewer this spec recommends |
| Signature forgery / unauthenticated webhook spoofing on the customer's side | S-3 (HMAC signing) | Low — standard, well-proven mitigation |
| Replay of a captured legitimate webhook by a third party who intercepted it | S-5's timestamp header (assumed customer-side replay-window check) | Medium — this spec specifies the platform sends a timestamp header, but *customer-side* replay-window enforcement is the customer's responsibility and outside this subsystem's control; documented in the delivery contract, not fully closeable by the platform alone |
| Cross-tenant data leakage via ID enumeration | S-1/S-8/S-10's not-found-not-forbidden isolation pattern | Low if the isolation test gate is honored consistently across all three stories, as specified |
| Secret exposure via logs/error messages | S-3's explicit gate ("no plaintext secret in logs...") | Low if the grep-checkable gate is actually enforced in CI, not just documented |
| Retry-storm amplification (many endpoints failing simultaneously, e.g. a shared upstream outage on the customer side) | S-6's jitter, S-7's concurrency caps | Medium — jitter and per-endpoint caps address the platform's own retry behavior, but a correlated mass-outage on the customer side (unlikely but not impossible) is not separately load-tested in this spec; flagged as a fast-follow load-test recommendation, not a blocking gap |

**Gate:** Two related minor gaps (Dependency ⚠, one adversarial ⚠) trace to the same root cause (unknown target repo/event bus — G1) and were already accepted as documented risk in CLARIFY/Scope; two genuine under-specification gaps (retry schedule numbers, dead-letter threshold numbers) are real and fixable within this session → **Refine (1 cycle).**

---

## R — REFINE

**Cycle 1 diagnosis:** Test surfaced two related gaps in the initial draft: (a) S-6's retry/backoff schedule was originally described only qualitatively ("exponential backoff with a cap"), leaving an implementing agent to invent specific intervals — a real under-specification risk for a story that is the mission's namesake requirement; (b) S-9's chronic-failure threshold was similarly qualitative ("consistently failing"), risking either an over-eager disable (false positive during a brief real outage) or a too-lenient one (customer never gets proactively notified).

**Root cause:** both gaps trace back to treating "retry with backoff" and "auto-disable on chronic failure" as directionally-correct policies without committing to concrete, decision-ready numeric defaults — exactly the kind of gap a downstream Builder agent would have had to guess at, reintroducing the ambiguity CLARIFY exists to eliminate.

**Prescription (applied):** added the explicit 6-attempt/~24h jittered schedule to S-6 (with Shopify's ~48h-then-give-up precedent as the calibration anchor, halved for a more conservative first ship) and the explicit "last 20 consecutive dead-lettered" threshold to S-9 (both already reflected in the Construct section above — this log records the diagnose→fix→re-verify pass that produced them).

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | unchanged — no clarity issue found |
| Completeness | 3 | 4 | retry schedule now numeric in S-6; disable threshold now numeric in S-9 |
| Actionability | 3 | 5 | an implementing agent no longer has to invent the two most consequential numeric defaults in the entire spec |
| Efficiency | 4 | 4 | unchanged |
| Testability | 3 | 4 | both fixes are independently assertable (exact backoff intervals with jitter tolerance; exact streak-count threshold) |

**Mean:** 3.4 → 4.2 (**+0.8**, well above the 0.3 diminishing-returns floor — this cycle earned its keep). **No dimension decreased** — no oscillation. **Cycle 1 target (all ≥3) met and exceeded (all ≥4); stopping at 1 cycle** rather than continuing to a cycle whose marginal gain would likely fall under the diminishing-returns threshold.

**Re-verify:** re-ran the Structural/Constraint/Adversarial layers against the updated S-6/S-9 — no new gaps introduced, no prior pass invalidated. The security red-team pass's findings (SSRF residual-risk note, replay-window note) were **not** addressed by this refinement cycle because they are not spec defects — they are correctly-scoped residual risks already documented with their owning mitigation and are exactly the class of item Assemble should flag to a human reviewer rather than "fix" by inventing false certainty.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (/3) | Basis |
|---|---|---|
| Pattern Match | 2 | Very strong external reference family (Stripe/GitHub/Shopify, 80–88% similarity), but no in-repo template exists to apply directly (G1) |
| Requirement Clarity | 2 | Mission's core ask (retries, backoff, observable failures) is unambiguous; many operational specifics required documented assumptions (G2–G6) |
| Decomposition Stability | 3 | ~76% self-consistency overlap across 3 alternative decompositions — HIGH |
| Constraint Compliance | 2 | 6-layer Test (+ security red-team pass) passed with flagged-but-mitigated gaps, all tracing to either the unknown target repo (G1) or correctly-scoped residual risk, not to spec quality |

**Weighted Confidence:** (2+2+3+2)/12 × 100 = **75%**

**Decision: VALIDATE (70–84% band) — deliver with flags, human reviews.** This is reinforced, not contradicted, by Scope's independent complexity finding of 10/12 (at the human-in-the-loop threshold) — both signals point the same direction.

**What a human reviewer should specifically validate before this becomes AUTO_PROCEED-worthy:**
1. Confirm whether exactly-once delivery is a hard requirement for any customer segment (Scope Assumption #2 / the rejected-alternative call-out) — this is the single highest-leverage decision in the spec, since it would change the architecture, not just a parameter.
2. Confirm the real target repo, its existing event/pub-sub infrastructure (or lack thereof, G1), and re-anchor every `[ASSUMED]` file path in Construct — an Explorer/ATLAS-equivalent pass is recommended specifically before S-4/S-5, given they are the highest-complexity stories.
3. Sign off on the SSRF posture (S-2) and secret-handling gates (S-3) explicitly — these are P0 security requirements this spec treats as non-negotiable, and the security red-team pass in Test flags S-2 weakening as the single highest-residual-risk scenario in the whole spec.
4. Confirm whether the buy-vs-build decision (H4, rejected) should actually be re-opened given this product's specific compliance/data-residency posture — this spec rejected H4 on general multi-tenant-SaaS grounds, not on a review of this specific company's vendor contracts or regulatory obligations.

### Deliverables produced (dual-format contract + ECL sidecar)

| Artifact | Path |
|---|---|
| Plan artifact (this file) | `/tmp/ramza-s2/ac003/AB-T1-spectra-r1.out.md` (requested output path — explicit override, honored per Output Discipline rule 2) |
| Authoritative mirror | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.md` |
| Agent handoff (YAML) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.yaml` |
| State machine (JSON) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.state.json` |
| ECL v2.0 envelope sidecar | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-webhook-delivery-subsystem.md.envelope.json` (emitted because `ECL_VERSION=2.0` is present at `/tmp/spectra-pilot/.eidolons/spectra/ECL_VERSION`) |

Per Output Discipline rule 2: since the mission explicitly named a path outside `.spectra/`, that path was honored as the primary deliverable, and the authoritative copy was mirrored under `.spectra/plans/` regardless, together with the full Assemble deliverable set (YAML handoff, state JSON, ECL envelope) that a SPECTRA Assemble phase produces per `SPEC.md` and `skills/planning.md`.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 75
  complexity: 10
  spectra_version: "4.11.0"
  thread_id: "019f3268-e047-7b7e-953b-1a3b7fcdea87"

projects:
  - id: "P-1"
    name: "Webhook Delivery Subsystem"
    features:
      - id: "F-1"
        name: "Endpoint Registration & Security"
        stories:
          - id: "S-1"
            title: "Tenant-scoped endpoint CRUD API"
            timebox: "<=2d"
            risk: "P0"
            agent_hints: { recommended_class: "builder", context_files: ["api/webhooks/endpoints.* [ASSUMED]"], validation_gates: { p0: "cross-tenant isolation test suite" } }
          - id: "S-2"
            title: "Endpoint URL validation & SSRF protection"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            agent_hints: { recommended_class: "reasoner", context_files: ["lib/webhooks/url_validation.* [ASSUMED]"], validation_gates: { p0: "security review sign-off; DNS-rebinding test" } }
          - id: "S-3"
            title: "Signing secret issuance & rotation"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            agent_hints: { recommended_class: "reasoner", context_files: ["lib/webhooks/signing.* [ASSUMED]"], validation_gates: { p0: "no plaintext secret in logs/responses" } }
      - id: "F-2"
        name: "Event Delivery Engine"
        stories:
          - id: "S-4"
            title: "Event-to-endpoint fan-out & durable enqueue"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-1"]
            agent_hints: { recommended_class: "builder", context_files: ["lib/webhooks/fanout.* [ASSUMED]"], validation_gates: { p0: "no-skip + no-unbounded-duplication tests" } }
          - id: "S-5"
            title: "Delivery worker: signed POST + timeout + idempotency"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-4", "S-2", "S-3"]
            agent_hints: { recommended_class: "builder", context_files: ["workers/webhook_delivery/* [ASSUMED]"], validation_gates: { p0: "timeout-enforcement + signature-verification tests" } }
          - id: "S-6"
            title: "Retry, exponential backoff & dead-letter transition"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-5"]
            agent_hints: { recommended_class: "reasoner", context_files: ["lib/webhooks/retry_policy.* [ASSUMED]"], validation_gates: { p0: "exact backoff-interval test; success-cancels-retries test" } }
          - id: "S-7"
            title: "Per-tenant / per-endpoint concurrency & rate limiting"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-4", "S-5"]
            agent_hints: { recommended_class: "builder", context_files: ["lib/webhooks/rate_limiter.* [ASSUMED]"], validation_gates: { p1: "fair-share large-vs-small backlog test" } }
      - id: "F-3"
        name: "Delivery Observability & Customer Trust"
        stories:
          - id: "S-8"
            title: "Delivery history API"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-5", "S-6"]
            agent_hints: { recommended_class: "builder", context_files: ["api/webhooks/deliveries.* [ASSUMED]"], validation_gates: { p0: "cross-tenant isolation test (shared with S-1)" } }
          - id: "S-9"
            title: "Auto-disable chronically-failing endpoints + notification"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-6", "S-8"]
            agent_hints: { recommended_class: "reasoner", context_files: ["lib/webhooks/circuit_breaker.* [ASSUMED]"], validation_gates: { p1: "notification-storm regression test" } }
          - id: "S-10"
            title: "Manual redelivery / replay"
            timebox: "1d"
            risk: "P2"
            dependencies: ["S-8", "S-6"]
            agent_hints: { recommended_class: "builder", context_files: ["api/webhooks/redeliver.* [ASSUMED]"], validation_gates: { p2: "isolation test + original-record-unchanged test" } }

execution_plan:
  phases:
    - name: "Phase 1 — Registration foundation"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Phase 2 — Security (parallel)"
      stories: ["S-2", "S-3"]
      agent_class: "reasoner"
    - name: "Phase 3 — Fan-out"
      stories: ["S-4"]
      agent_class: "builder"
    - name: "Phase 4 — Delivery worker"
      stories: ["S-5"]
      agent_class: "builder"
    - name: "Phase 5 — Reliability & fairness (parallel)"
      stories: ["S-6", "S-7"]
      agent_class: "reasoner+builder"
    - name: "Phase 6 — Observability"
      stories: ["S-8"]
      agent_class: "builder"
    - name: "Phase 7 — Trust & recovery (parallel)"
      stories: ["S-9", "S-10"]
      agent_class: "reasoner+builder"
```

### State Machine (JSON)

```json
{
  "session_id": "019f3268-e047-7866-b17d-79a7eedb9ca4",
  "spec_id": "SPEC-2026-07-05-001",
  "goal": "Specify a multi-tenant webhook delivery subsystem: endpoint registration, retry/backoff delivery, and customer-observable failures.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Tenant-scoped endpoint CRUD API", "status": "pending", "dependencies": [], "files_affected": ["api/webhooks/endpoints.* [ASSUMED]", "db/models/webhook_endpoint.* [ASSUMED]"], "verification_command": "test: cross-tenant isolation suite", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Endpoint URL validation & SSRF protection", "status": "pending", "dependencies": [1], "files_affected": ["lib/webhooks/url_validation.* [ASSUMED]"], "verification_command": "test: DNS-rebinding + private-IP rejection", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Signing secret issuance & rotation", "status": "pending", "dependencies": [1], "files_affected": ["lib/webhooks/signing.* [ASSUMED]"], "verification_command": "test: dual-secret grace window", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Event-to-endpoint fan-out & durable enqueue", "status": "pending", "dependencies": [1], "files_affected": ["lib/webhooks/fanout.* [ASSUMED]"], "verification_command": "test: no-skip + no-unbounded-duplication", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Delivery worker: signed POST + timeout + idempotency", "status": "pending", "dependencies": [4, 2, 3], "files_affected": ["workers/webhook_delivery/* [ASSUMED]"], "verification_command": "test: timeout enforcement + signature verification", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Retry, exponential backoff & dead-letter transition", "status": "pending", "dependencies": [5], "files_affected": ["lib/webhooks/retry_policy.* [ASSUMED]"], "verification_command": "test: exact backoff intervals + success-cancels-retries", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Per-tenant / per-endpoint concurrency & rate limiting", "status": "pending", "dependencies": [4, 5], "files_affected": ["lib/webhooks/rate_limiter.* [ASSUMED]"], "verification_command": "test: fair-share backlog scenario", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 8, "story_id": "S-8", "title": "Delivery history API", "status": "pending", "dependencies": [5, 6], "files_affected": ["api/webhooks/deliveries.* [ASSUMED]", "db/models/delivery_attempt.* [ASSUMED]"], "verification_command": "test: cross-tenant isolation suite (shared with S-1)", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 9, "story_id": "S-9", "title": "Auto-disable chronically-failing endpoints + notification", "status": "pending", "dependencies": [6, 8], "files_affected": ["lib/webhooks/circuit_breaker.* [ASSUMED]"], "verification_command": "test: notification-storm regression", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 10, "story_id": "S-10", "title": "Manual redelivery / replay", "status": "pending", "dependencies": [8, 6], "files_affected": ["api/webhooks/redeliver.* [ASSUMED]"], "verification_command": "test: isolation + original-record-unchanged", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "phase": "Refine",
      "diagnosis": "S-6 retry schedule and S-9 disable threshold were stated qualitatively, not numerically",
      "fix_applied": "added explicit 6-attempt/~24h jittered schedule to S-6; added explicit 20-consecutive-failure threshold to S-9",
      "mean_score_before": 3.4,
      "mean_score_after": 4.2,
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
- [x] Complexity scored (10/12), extended-thinking budget routed, human-in-the-loop recommendation carried into Assemble
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing/buy)
- [x] All 10 stories pass INVEST
- [x] All timeboxes valid (1d/≤2d/≤3d only, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this file) + structured YAML/JSON (embedded above + mirrored as separate files)
- [x] Confidence score present with factor breakdown (75%, VALIDATE)
- [x] Plan saved as artifact at the requested path + mirrored under `.spectra/plans/`
- [x] Every mirrored/derived output path starts with `.spectra/`
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H1, H3, H4, plus the exactly-once-delivery call-out — four, exceeding the "at least one" requirement)

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*

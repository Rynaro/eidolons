---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-review
created_at: 2026-07-05T13:12:41Z
thread_id: c1584458-65b3-4fba-8819-3875f52c0c48
target_repos:
  - "<unresolved — no payment/charge/retry implementation found in /tmp/spectra-pilot (Eidolons scaffold only, no application source); see CLARIFY Gap-1>"
stories_count: 7
validation_gates_count: 24
evidence_anchors_count: 0
confidence: 0.75
---

# SPEC-2026-07-05-002 — Fix: intermittent double-charge on payment retry / delayed-confirmation race

**Mission:** Customers are intermittently double-charged when a payment retry races the original attempt's delayed confirmation. Produce a decision-ready FIX specification: root-cause hypothesis, fix approach, regression scope, acceptance criteria proving the double-charge cannot recur, and at least one rejected alternative.

**Methodology:** SPECTRA v4.11.0 — CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble
**Intent type:** `BUG_SPEC` — root cause → fix spec (Scope routing table)
**Tier:** Standard single-pass cycle, **extended thinking** (complexity 10/12 — see Scope). TRANCE parallel-spec considered and explicitly **not** invoked (rationale in Scope, "TRANCE gating decision").
**Read-only invariant honored:** no code, no file edits, no mutations were made in producing this spec.

---

## Memory pre-flight (mission intake)

Per `agent.md`, a `mcp__crystalium__recall` call was attempted before CLARIFY (query: "payment retry double charge idempotency delayed confirmation race", scope `{project: spectra-pilot, agent_class_visibility: spectra}`, k=5, layers=[semantic, episodic, procedural]). **No `mcp__crystalium__*` tools are reachable in this environment** (absent from the available tool surface; no CRYSTALIUM install evidence anywhere under `/tmp/spectra-pilot`). Per the documented graceful-skip rule this is a silent no-op, not a hard failure — SPECTRA is EIIS-standalone-conformant. Planning proceeds without prior-session memory; the absence is carried forward as a Pattern-phase gap, not fabricated as a false match.

---

## CLARIFY

**Trigger:** every new request. **Not skipped.** The mission names a precise failure *symptom* (double charge, retry vs. delayed confirmation) but supplies no target repository, payment gateway, retry framework, or confirmation channel — genuine structural ambiguity, distinct from the causal mechanism itself, which is a well-known distributed-systems failure class.

**Parse Intent:**
- **WHO:** end customers who are charged twice for one purchase; support/finance teams who absorb the refund and chargeback load; the engineer who will implement the fix; whoever owns payment-gateway integration and on-call for the payments service.
- **WHAT:** a fix that makes it structurally impossible for a retried charge attempt to produce a second successful charge for the same logical purchase, regardless of how long the original attempt's confirmation is delayed.
- **WHY:** double-charging is a direct financial-integrity and trust failure — it produces support burden, refund/chargeback cost, potential compliance exposure (payment-processor and card-network dispute rules), and erodes customer trust in a way single outages don't.
- **CONSTRAINTS:** the fix must not weaken legitimate retry behavior (a truly failed charge must still be retryable); it must not silently swallow a second, *genuinely distinct* purchase as a duplicate; it must hold under concurrent/distributed execution (multiple app instances/workers), not just within a single process.

**Identify Gaps:**

| # | Gap | Resolution mode |
|---|-----|------------------|
| G1 | No target repository, payment gateway (Stripe/Adyen/Braintree/in-house processor), or retry framework was supplied. `/tmp/spectra-pilot` (this consumer project) contains only Eidolons scaffolding — grep for `payment`/`charge` returns zero implementation hits. `.spectra/setup/spectra-conventions.md` does not exist. | **[GAP] — cannot be closed interactively in this single-shot run.** Resolved via explicit, risk-tagged assumptions below rather than fabricating a fake codebase match; every file path in Construct is marked `[ASSUMED]`. |
| G2 | Unknown whether "retry" means a client-initiated retry (customer double-clicks / resubmits after a spinner timeout), a server-side automatic retry (job/queue retry on timeout or 5xx), or both. | **[ASSUMPTION]** — treat as **server-side automatic retry on ambiguous timeout**, since the mission explicitly frames it as racing "the original attempt's delayed confirmation," which is a server/orchestration-layer phenomenon, not a UI click. Client-side double-submit is a related but distinct failure mode and is named out-of-scope below, not silently merged in. |
| G3 | Unknown whether the payment gateway already supports server-side idempotency keys (most modern processors do) or is a legacy/in-house processor without that primitive. | **[ASSUMPTION]** — design the fix to hold **even if the gateway has no native idempotency support** (defense-in-depth: local guard + gateway-level key when available), so the spec is correct under the weaker assumption and strictly better under the stronger one. |
| G4 | Unknown current confirmation channel: synchronous response, async webhook/callback, or polling. | **[ASSUMPTION]** — treat confirmation as **asynchronous and independently delayable** (webhook/callback or delayed polling), since that is the only shape under which "a retry races the original attempt's delayed confirmation" is even possible — a purely synchronous confirmation cannot produce this exact race. |

**Would-ask (≤3, numbered, <200 chars — recorded for the human reviewer since no live turn is available this run):**
1. Does the current gateway integration send an idempotency key today, and if so, is a *new* key generated per retry or is the original reused?
2. Is the retry triggered by a queue/job framework (e.g., Sidekiq/Celery-style retry-on-exception) or bespoke orchestration code?
3. Are duplicate charges currently caught by any process (manual finance review, chargeback only), or is this the first systematic detection?

**Gather Structural Context:** grepped `/tmp/spectra-pilot` for `payment`/`charge`/`retry`/`webhook` — zero implementation hits (Eidolons scaffold files only, consistent with the prior `2026-07-04-deploy-dry-run` spec's finding for this same project). No `spectra-conventions.md` to load. Proceeding on well-established, cross-industry payment-integration conventions (Pattern phase) rather than fabricated project-specific paths.

**Assess Cognitive Load:** single planning session sufficient for the spec itself; flagged in Scope that *implementation* of the highest-risk story (S-2, the pending-attempt lock) should get a dedicated human design review before coding starts, given the complexity score below.

**Skip?** No — see G1–G4. CLARIFY is complete via documented, risk-tagged assumptions, which is why Assemble gates this spec to VALIDATE-with-mandatory-escalations rather than AUTO_PROCEED.

---

## S — SCOPE

**Intent Type:** `BUG_SPEC` — root cause diagnosed first, fix spec follows.

### Root-Cause Hypothesis

**Primary hypothesis:** the double charge is produced by a **check-then-act (TOCTOU) race between the retry decision and the original attempt's asynchronous confirmation, compounded by the absence of a idempotency key shared across attempts and the absence of any exclusive lock on "an attempt for this order is already outstanding."**

Causal chain:
1. Attempt #1 is submitted to the gateway. The gateway accepts and will eventually settle it, but the settlement/confirmation is delivered asynchronously (webhook, callback, or delayed poll) rather than in the same synchronous round-trip.
2. The calling system's synchronous wait for attempt #1 times out (network latency, gateway processing delay, webhook queueing delay) **before** the confirmation is durably recorded. At this instant, the system's local state for the order is still "unconfirmed" — indistinguishable, from the retry logic's point of view, from "actually failed."
3. Retry logic reads that "unconfirmed" state, treats it as "safe to retry," and submits attempt #2 — **as an entirely independent request**, because no idempotency key is carried over from attempt #1 (or a *new* key is generated per attempt), and no row/record-level lock prevents a second attempt from being created while attempt #1 is still outstanding.
4. The gateway has no way to recognize attempts #1 and #2 as the same logical purchase (they arrive as unrelated requests), so it authorizes and settles **both**. The delayed confirmation for attempt #1 then lands after attempt #2 has already gone out — by which point the race has already been lost.

This is the textbook shape of the failure (the same class documented by every major processor's idempotency-key guidance — Stripe, Adyen, Braintree — as the reason idempotency keys exist at all): **duplicate submission is possible whenever a caller cannot distinguish "the previous attempt is still in flight" from "the previous attempt failed," and the receiver cannot recognize two requests as one logical operation.**

**Differential diagnosis — alternative causes considered and ruled out (or scoped out) as the *dominant* cause:**

| Alternative cause | Verdict | Reasoning |
|---|---|---|
| Gateway-side dedup failure (gateway itself double-settles one idempotency key) | **Ruled out as primary** | Assumed reliable per the gateway's own published idempotency contract (G3); if this were the actual cause, no application-level fix could close it — would require an escalation to the processor, out of scope here. |
| Client-side double-submit (customer double-clicks "Pay") | **Related, but scoped out (G2)** | Produces a superficially similar symptom but a different mechanism (no "delayed confirmation" is involved) and a different fix (client-side submit-disable + form-token). Named explicitly as a non-goal below so it isn't silently conflated with this bug. |
| Two genuinely separate purchases for the same order (e.g., cart re-submitted after edit) | **Ruled out** | Mission specifies "retry," not a new purchase; the fix must be careful not to conflate this case going the *other* direction (see Regression Scope). |

**Complexity Score (4-dimension matrix):**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 2 | Touches multiple subsystems (charge submission, retry policy, confirmation/webhook handling, reconciliation) under one bounded capability — not multi-project |
| Ambiguity | 2 | The causal mechanism is well-understood industry pattern; target repo/gateway/retry-framework specifics are unknown (G1) |
| Dependencies | 3 | Cross-domain: external payment gateway, internal payments datastore, async confirmation channel, retry/queue orchestration — four distinct systems |
| Risk | 3 | Critical path: direct financial harm to customers, chargeback/compliance exposure, trust erosion |

**Total: 10/12 → crosses into the "human-in-the-loop recommended" band** (Scope routing table: 10–12).

**TRANCE gating decision:** Parallel Spec Mode (TRANCE, G3 evaluator-optimizer) was explicitly considered given the complexity score crosses the 10–12 threshold named in its trigger examples. **Not invoked.** TRANCE requires *both* the complexity flag *and* the stakes flag named by the cortex — its worked trigger examples are "complexity 10–12 STRATEGIC/CHANGE, multi-service architecture, high-rework-risk **system design**." This mission is a `BUG_SPEC` against one bounded capability (charge-submission integrity for one order at a time), not a STRATEGIC/multi-project effort or a from-scratch multi-service architecture build — and no cortex/orchestrator authorization signal is present in this single-shot delegation. Practical effect of the 10/12 score is instead applied where the routing table actually intends it: extended-thinking budget (already applied), and an elevated, **mandatory** (not merely recommended) human design review gate on the highest-risk story (S-2) before implementation — reflected in the Assemble confidence-band override below.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| Preventing two successful gateway charges for one retry-chain of one logical purchase attempt | Client-side double-submit-click guard (different mechanism, G2) | Fast-follow once S-2's lock primitive exists — same mechanism, reusable for the double-click case |
| Idempotency-key reuse across retries of the same attempt | Reconciliation/refund-after-the-fact as the *primary* control (rejected, see Explore H3) | Retained only as an operational safety net (S-5), not the prevention mechanism |
| A local exclusive "attempt in flight" guard, independent of gateway idempotency support | Redesigning the payment gateway integration or switching processors | Not deferred — unrelated surface |
| Reconciling delayed confirmations against the single guarded attempt record | Refund/partial-capture/void flow redesign | Regression-tested (must keep working), not redesigned |
| A backstop duplicate-charge detector + alert for defense-in-depth | Disabling retries outright (rejected, see Explore H4) | Not deferred — rejected outright |

**Assumptions (risk-tagged):**

1. **[ASSUMPTION]** Confirmation is asynchronous and independently delayable (G4). **Risk if wrong:** if confirmation is actually synchronous, the race as described cannot occur and the real root cause is elsewhere (e.g., naive retry-on-any-exception with no confirmation step at all) — re-open CLARIFY G4 with the real repo before implementation.
2. **[ASSUMPTION]** The system runs on ≥1 horizontally-scaled instance/worker, so any guard must be a distributed lock (DB row lock, unique constraint, or distributed cache lock), never an in-process mutex. **Risk if wrong:** if truly single-instance, an in-process lock would suffice and would be far cheaper — but assuming the stronger (distributed) requirement is the safe default; it degrades gracefully to the single-instance case.
3. **[ASSUMPTION]** The gateway's own idempotency-key TTL (commonly ~24h for major processors) is longer than any plausible retry-storm duration. **Risk if wrong:** an unusually long-delayed retry could arrive after the gateway has forgotten the key and would treat it as a fresh charge — this exact edge case is explicitly covered by S-4 rather than assumed away.

**Stakeholders:** customers (harmed party, primary), finance/support teams (absorb chargeback and refund load today), payments/platform engineering (implements and owns S-2's lock design — **mandatory reviewer** per the complexity override above), compliance/risk (reviews for card-network dispute-rule exposure), on-call/SRE (owns S-5's alert).

---

## P — PATTERN

**Query memory:** unavailable this session (see Memory pre-flight) — **[GAP]**, not a false negative; no prior-failure catalog to surface.

**Query codebase:** zero matches in `/tmp/spectra-pilot` (CLARIFY G1). Falling back to established external reference patterns for "prevent duplicate mutating requests under retry," ranked by similarity (MMR: `similarity − 0.3 × redundancy`):

| Pattern | Similarity | Why |
|---|---|---|
| Stripe/Adyen/Braintree **idempotency-key** contract (same key ⇒ same result, replayed safely) | 88% | Direct, industry-canonical answer to exactly this failure class; explicitly designed for "client retried, don't know if the first attempt landed" |
| **Saga / outbox pattern** with a persisted "attempt" record as the single source of truth before any external call | 79% | Matches the need for a durable, lockable local record that exists *before* the gateway call, so retries have something authoritative to check instead of racing on absence-of-confirmation |
| **Distributed advisory lock / unique constraint** keyed on `(order_id, attempt_group)` | 76% | Standard mechanism for "only one in-flight mutation per key" across horizontally-scaled workers |
| **Compare-and-swap state machine** (`pending → confirmed / failed`) | 74% | Names the exact bug precisely: today's implicit two-state model (confirmed / not-yet-confirmed) conflates "in flight" with "failed"; a third explicit `pending` state with CAS transitions closes that gap |
| **Reconciliation job** (detect gateway-vs-ledger mismatches, refund duplicates) | 55% | Valuable as a safety net, not as the primary control — evaluated and demoted to defense-in-depth in Explore (H3) |

**No single pattern reaches the 85% USE_TEMPLATE threshold** without a specific in-repo integration to apply it to (G1). **Strategy: ADAPT (60–84% band)** — combine the idempotency-key contract (external boundary) with the CAS state-machine + distributed-lock pair (internal boundary) into one defense-in-depth fix, borrowing the outbox pattern's core insight ("write the intent record before the external call, treat it as the source of truth") without adopting a full saga/outbox message-bus rebuild, which would be disproportionate to a bug fix.

**Catalog Failure Patterns:** none available from memory (unreachable this session). Documented as a gap, not silently skipped — this is exactly the kind of prior-incident catalog a real CRYSTALIUM-backed session would surface (e.g., "this class of race previously bit the refund path too").

---

## E — EXPLORE

**Trigger:** before Construct. Not skipped. 4 genuinely distinct hypotheses (conservative, pattern-leveraging, innovative, risk-minimizing — exceeds the 3-minimum, within the 3–5 range).

**Observations (5 angles):** (1) *boundary of control* — the fix can act at the gateway boundary (idempotency key), the local boundary (lock/state machine), or after the fact (reconciliation); each has a different failure mode if the *other* boundary is absent; (2) *distributed correctness* — any local guard must survive multiple app instances/workers, not just one process; (3) *false-positive cost* — over-guarding must not block a customer's *genuinely new* purchase; (4) *TTL/edge-case honesty* — a fix that works "almost always" but silently reverts to unguarded behavior past some TTL is not a real fix; (5) *provability* — the mission explicitly demands proof the bug "cannot recur," which rules out any hypothesis whose guarantee is probabilistic or after-the-fact only.

### Hypothesis scoring (7-dimension weighted rubric, 1–10 per dimension → weighted /100)

| # | Hypothesis | Align 25% | Correct 20% | Maintain 15% | Perf 15% | Simple 10% | Risk 10% | Innov 5% | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Conservative** — idempotency key only: generate one key per logical attempt, reuse it verbatim on every retry, rely on the gateway's own dedup | 8 | 7 | 9 | 9 | 9 | 6 | 2 | **77.6** |
| H2 | **Pattern-leveraging (selected)** — idempotency key reuse **+** local CAS `pending` state machine with a distributed lock keyed on `(order_id, attempt_group)`, blocking any second attempt while one is outstanding | 10 | 9 | 8 | 8 | 6 | 9 | 6 | **86.7** |
| H3 | **Innovative** — allow duplicates to occur; detect via a near-real-time reconciliation job diffing gateway transactions against orders, auto-refund within seconds | 6 | 5 | 6 | 7 | 5 | 4 | 8 | **58.0** |
| H4 | **Risk-minimizing (overcorrection)** — remove ambiguous-timeout retries entirely; only retry on a gateway-confirmed hard failure, never on timeout/ambiguity | 7 | 8 | 7 | 6 | 8 | 8 | 3 | **72.4** |

Spread is 86.7 → 58.0 (28.7-point range) — **not** within the 5% "insufficient differentiation" band; well-differentiated, no re-observation needed. H2 and H1 are the closest pair (9.1 points apart) — both expanded below per the "expand top 2" rule.

### Expand top 2

**H2 — Idempotency key + local pending-lock state machine (selected).**
- *File impact:* moderate — a new `payment_attempt` durable record (or equivalent column set) with an explicit `pending/confirmed/failed` state, a distributed lock/unique-constraint acquisition at submission time, the confirmation handler updated to transition the record instead of writing a bare "confirmed" flag, and the retry path updated to check the lock before ever calling the gateway.
- *Dependency chain:* the local guard must be correct **independently** of whether the gateway supports idempotency keys (G3) — it is the layer that actually stops a second gateway call from being attempted at all, which the key-only approach (H1) cannot do since a key-only fix still lets two requests race to the gateway and only relies on the gateway to dedup them. Highest-risk dependency: correctness of the lock's release/expiry semantics (a lock that never releases on true failure would make legitimate retries impossible; see S-4).
- *Edge cases:* worker crash while holding the lock (needs a lock TTL / heartbeat, not just an unbounded hold); the gateway-key-TTL-exceeded case (S-4); confirmation arriving for an attempt whose lock already expired (must reconcile against the correct attempt record, not silently create a new one).

**H1 — Idempotency key only (conservative).**
- *File impact:* small — generate-and-store one key per attempt, pass it on every retry to the gateway.
- *Dependency chain:* entirely dependent on the gateway's own idempotency implementation (G3) being correct and available; if the gateway is legacy/in-house without this primitive, H1 provides **zero** protection — a single point of failure with no local backstop.
- *Edge cases:* same TTL edge case as H2, but with no local lock to fall back on if the TTL is exceeded or the gateway silently doesn't honor the key — H1 alone cannot *prove* non-recurrence, only make it less likely when the gateway cooperates.

### Selection

**Selected: H2 (idempotency key + local pending-lock state machine).** It scores highest overall (86.7, "Elite" band per `scoring.md`) and is the only hypothesis whose guarantee holds **independently of gateway behavior** — which is exactly what "prove the double-charge cannot recur" requires: a claim that depends on a third party (the gateway) correctly implementing its side of a contract is a weaker proof than a claim enforced locally, with the gateway-side key as a second, redundant layer rather than the only layer. H2 subsumes H1's idempotency-key mechanism (the fix carries it forward as the outer boundary) while adding the inner boundary H1 lacks.

**Rejected alternatives (documented per E-phase step 6, prevents re-exploration in replanning):**

- **H1 (idempotency key only) — rejected as insufficient, not wrong.** It is correct and valuable *as a component* (retained inside H2, S-1) but insufficient as the whole fix: it cannot prevent two requests from racing to the gateway in the first place, and provides zero protection if the gateway lacks native idempotency support (G3) or if the key TTL is exceeded with no local fallback. **Re-open trigger:** none — H1 is folded into the selected approach, not shelved.
- **H3 (reconciliation/detect-and-refund) — rejected as the primary control, retained as a safety net.** Scored 58.0 ("Weak" band) primarily on Alignment and Risk: it does not prevent the double charge, it shortens the window of harm after the fact, which does not satisfy the mission's explicit "prove it cannot recur" bar — a customer is still charged twice, however briefly, and refund timing/tax/statement-cycle edge cases make "briefly double-charged, then refunded" a real support and trust cost, not a non-event. Retained at reduced scope as **S-5** (operational tripwire / defense-in-depth), never as the thing doing the preventing.
- **H4 (remove ambiguous-timeout retries entirely) — rejected as overcorrection.** Technically eliminates this specific race (Correctness 8, Risk 8) but at the cost of converting every transient network/gateway hiccup into a hard-failed checkout that the customer must manually re-initiate — a direct conversion-rate and support-load cost for a problem that H2 solves without sacrificing retry-ability. **Re-open trigger:** if H2's lock mechanism is found to be infeasible in the real target stack (e.g., no viable distributed-lock primitive available), H4 becomes the fallback worth revisiting.

---

## C — CONSTRUCT

**Hierarchy:**

```
THEME    Payment Integrity & Duplicate-Charge Prevention
└─ PROJECT  P-1  Charge Retry / Delayed-Confirmation Race Elimination
   └─ FEATURE F-1  Idempotent, lock-guarded charge submission with confirmation reconciliation
      ├─ STORY S-1  Idempotency-key generation & reuse across retries
      ├─ STORY S-2  Local pending-attempt lock (CAS state machine, order-scoped)
      ├─ STORY S-3  Confirmation reconciliation against the single guarded attempt record
      ├─ STORY S-4  TTL/ambiguous-timeout fallback — query-before-charge
      ├─ STORY S-5  Duplicate-charge detection safety net + alerting
      ├─ STORY S-6  Concurrency/race regression suite + historical-duplicate audit
      └─ STORY S-7  Docs, runbook, support-tooling updates
```

All 7 stories pass INVEST (Independent within the documented sequencing, Negotiable on exact wording, Valuable to a named actor, Estimable at the timeboxes below, Small ≤2d each, Testable via the GIVEN/WHEN/THEN sets below).

**Execution sequence (dependency-ordered):**

```
Phase 1:  S-1
Phase 2:  S-2                       (depends on S-1)
Phase 3:  S-3  ‖  S-4               (parallel — both consume S-2's lock/state machine)
Phase 4:  S-5  ‖  S-6               (parallel — both consume S-2 + S-3)
Phase 5:  S-7
```

---

#### 📋 STORY: S-1 Idempotency-key generation & reuse across retries

> 🔴 P0

**Description:** As a payments engineer, I want one idempotency key generated per logical charge attempt and reused verbatim on every retry of that attempt, so that the gateway itself can recognize and dedup a raced retry even if the local guard (S-2) is ever bypassed.

**Timebox:** 1d
**Risk:** P0 (outer boundary of the defense-in-depth fix; every downstream story assumes this key exists)

**Action Plan:**
1. **Create:** a deterministic idempotency-key derivation (or a stored key) tied to the logical attempt — not the individual HTTP request — so a retry looks up and reuses the same key rather than generating a new one.
2. **Modify:** every charge-submission call site to pass this key to the gateway.
3. **Test:** retry of the same attempt sends byte-identical key; two genuinely distinct attempts (e.g., a new checkout after a real decline) receive distinct keys.

**Acceptance Criteria:**
- [ ] GIVEN a charge attempt is retried WHEN the retry submits to the gateway THEN it SHALL carry the exact same idempotency key as the original attempt
- [ ] GIVEN two genuinely distinct purchases (different logical attempts) WHEN each is submitted THEN each SHALL receive a distinct idempotency key (no cross-order key collision)
- [ ] GIVEN the gateway is queried directly with a previously-used key WHEN a duplicate request with that key arrives THEN the gateway's own response SHALL be the original charge result, not a new charge (verified against the gateway's documented idempotency contract in an integration test)

**Technical Context:**
- **Pattern:** gateway idempotency-key contract (Pattern phase, external boundary)
- **Files:** `[ASSUMED — confirm against target repo]` `lib/payments/gateway_client.*` (submission call sites)
- **Dependencies:** none (foundation story)

**Agent Hints:**
- **Class:** Builder
- **Context:** existing gateway client/SDK wrapper, current retry call sites
- **Gates:** P0 — key-reuse-on-retry test green before merge

---

#### 📋 STORY: S-2 Local pending-attempt lock (CAS state machine, order-scoped)

> 🔴 P0 — highest-risk story in this spec; **mandatory human design review before implementation** (Scope complexity override)

**Description:** As a platform engineer, I want an exclusive, distributed lock and an explicit `pending → confirmed | failed` state machine per logical attempt, so that no second charge attempt can be submitted for an order while a prior attempt is outstanding, regardless of how many app instances or workers are running.

**Timebox:** ≤2d
**Risk:** P0 (the inner boundary — the story that actually stops a second gateway call from ever being attempted; a bug here is the single failure mode this whole spec exists to prevent)

**Action Plan:**
1. **Create:** a durable `payment_attempt` record (or equivalent) with a compare-and-swap `state` column (`pending`, `confirmed`, `failed`) and a uniqueness constraint / distributed lock keyed on `(order_id, attempt_group)`.
2. **Modify:** the charge-submission path to atomically transition `none → pending` (lock acquisition) *before* calling the gateway, and to refuse to acquire the lock if an unexpired `pending` record already exists for the same key.
3. **Configure:** a lock TTL / heartbeat so a crashed worker's held lock expires into a well-defined "ambiguous, needs reconciliation" state rather than blocking forever or silently unblocking into an unguarded retry (feeds directly into S-4).
4. **Test:** N concurrent submission attempts for the same `(order_id, attempt_group)` → exactly one acquires the lock and reaches the gateway; the rest observe `pending` and are rejected/queued, never independently submitted.

**Acceptance Criteria:**
- [ ] GIVEN a `pending` attempt exists (unexpired) for an order WHEN any retry (automatic or manual) targets the same order THEN the retry SHALL NOT acquire a new lock or submit a new gateway charge — it SHALL observe the existing `pending` state and wait/queue instead
- [ ] GIVEN N simultaneous submission attempts race for the same `(order_id, attempt_group)` lock WHEN they execute concurrently across multiple app instances/workers THEN exactly one SHALL acquire the lock and reach the gateway, and this SHALL hold under a multi-process/multi-worker concurrency test, not just a single-process test
- [ ] GIVEN a worker crashes while holding the lock WHEN the lock TTL elapses THEN the attempt SHALL transition to an explicit "ambiguous — needs reconciliation" state, never silently back to an unguarded "safe to retry freely" state

**Technical Context:**
- **Pattern:** CAS state machine + distributed lock (Pattern phase, internal boundary)
- **Files:** `[ASSUMED]` `lib/payments/attempt_lock.*` (new), `[ASSUMED]` payments datastore migration for the `payment_attempt` table/columns
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner (lock/CAS correctness under concurrency is the risk-critical step; a design review by a human payments/platform owner is mandatory per Scope before Builder implements)
- **Context:** existing datastore's locking primitives (row-level `SELECT ... FOR UPDATE`, unique-constraint-on-insert, or distributed cache lock — whichever the real repo already uses elsewhere)
- **Gates:** P0 — concurrency test demonstrating exactly-one-lock-winner across simulated concurrent workers; human design sign-off recorded before merge

---

#### 📋 STORY: S-3 Confirmation reconciliation against the single guarded attempt record

> 🔴 P0

**Description:** As a platform engineer, I want the (possibly delayed) confirmation from the gateway to resolve the same `payment_attempt` record that S-2's lock created, so that a late-arriving confirmation never gets treated as evidence for a *new* attempt and never leaves the lock stuck in `pending` after the true outcome is known.

**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Modify:** the confirmation/webhook handler to look up the attempt by the shared idempotency key (S-1) / lock key (S-2), not create a fresh record.
2. **Modify:** the handler to perform the CAS transition `pending → confirmed` or `pending → failed`, releasing the lock as part of the same transition (never as a separate, racing step).
3. **Test:** a confirmation arriving after the lock's TTL has already expired (S-2 AC #3) still resolves the *correct* original attempt record, not a newly-created one; a confirmation for an attempt that no longer exists locally (edge case) is logged and alerts (feeds S-5), never silently dropped or misapplied to an unrelated attempt.

**Acceptance Criteria:**
- [ ] GIVEN a confirmation (webhook/callback) arrives for a `pending` attempt WHEN it is processed THEN it SHALL transition that exact attempt record's state and release its lock atomically — never create a second attempt record
- [ ] GIVEN a confirmation arrives after the attempt's lock TTL has already expired (S-2's "ambiguous" state) WHEN reconciliation runs THEN it SHALL resolve the original attempt record using the shared idempotency key, and any queued retry (S-4) SHALL observe that resolved state before considering a fresh charge
- [ ] GIVEN a confirmation references an idempotency key with no matching local attempt record WHEN processed THEN the system SHALL log and alert (S-5) rather than silently discard or misattribute it

**Technical Context:**
- **Pattern:** outbox-style "resolve the intent record, don't create a new one" (Pattern phase)
- **Files:** `[ASSUMED]` `lib/payments/webhook_handler.*`, shares the `payment_attempt` model from S-2
- **Dependencies:** S-2

**Agent Hints:**
- **Class:** Builder + Reasoner (the atomic transition-and-release is the correctness-critical piece)
- **Context:** existing webhook/callback receiver, its current signature-verification and idempotent-processing conventions
- **Gates:** P0 — late-confirmation-after-TTL-expiry test green; no-orphan-record test green

---

#### 📋 STORY: S-4 TTL/ambiguous-timeout fallback — query-before-charge

> 🔴 P0

**Description:** As a platform engineer, I want a retry that arrives after the local lock has expired (or after the gateway's own idempotency-key TTL) to first *query* the gateway/attempt record for an existing result before ever submitting a fresh charge, so that the "ambiguous" state S-2 introduces never silently degrades back into the original unguarded race.

**Timebox:** ≤2d
**Risk:** P0 (this is the story that closes the exact edge case named in Scope Assumption #3 — without it, S-2's TTL-expiry path would recreate the original bug under load)

**Action Plan:**
1. **Create:** a "reconcile-before-retry" check: on observing an `ambiguous`/expired-lock attempt, query the gateway (or wait for/poll the attempt record) for a definitive outcome before deciding to submit anything new.
2. **Modify:** the retry entrypoint so this check is mandatory and unconditional on the ambiguous path — not an optional fast-path a future call site could skip.
3. **Test:** a retry hitting the ambiguous path where the gateway confirms the original attempt *did* succeed → no new charge is ever submitted; a retry where the gateway confirms the original attempt genuinely failed → a fresh attempt (new lock, same/derived idempotency key per S-1) is permitted.

**Acceptance Criteria:**
- [ ] GIVEN an attempt's lock has expired into the "ambiguous" state WHEN a retry is triggered THEN the system SHALL query for the attempt's definitive outcome before submitting any new gateway charge
- [ ] GIVEN that query resolves to "original attempt succeeded" THEN the retry SHALL NOT submit a new charge under any circumstance, and SHALL surface the existing successful result to the caller
- [ ] GIVEN that query resolves to "original attempt genuinely failed" or "gateway has no record" THEN the retry SHALL be permitted to proceed with a fresh, properly-locked attempt (re-entering S-2)

**Technical Context:**
- **Pattern:** query-before-mutate fallback (Pattern phase — closes the gap H1-only would have left open)
- **Files:** `[ASSUMED]` `lib/payments/attempt_lock.*` (shared with S-2), `[ASSUMED]` `lib/payments/gateway_client.*` (query/lookup call)
- **Dependencies:** S-2, S-3

**Agent Hints:**
- **Class:** Reasoner
- **Context:** gateway's transaction-lookup/query API, S-2's ambiguous-state definition
- **Gates:** P0 — "ambiguous path never double-submits" is the single most important test in this spec; must run under the same concurrency harness as S-2 AC #2

---

#### 📋 STORY: S-5 Duplicate-charge detection safety net + alerting

> 🟡 P1 — defense-in-depth, not the prevention mechanism (per Explore, H3 demoted here)

**Description:** As an on-call/finance engineer, I want an independent, periodic job that compares gateway-settled charges against local order/attempt records and pages on-call the moment it ever finds two successful charges for one order, so the "cannot recur" claim has an operational tripwire even if S-1–S-4 have an undiscovered gap.

**Timebox:** ≤2d
**Risk:** P1 (does not itself prevent a double charge — it proves the prevention is working and catches the unknown-unknown)

**Action Plan:**
1. **Create:** a reconciliation job diffing gateway-settled transactions against local `payment_attempt`/order records, keyed on idempotency key and order ID.
2. **Configure:** an alert that pages on-call the moment >1 settled charge is found for one order — zero tolerance, not a threshold.
3. **Test:** job correctly reports zero findings against a clean fixture; job correctly flags an injected synthetic duplicate.

**Acceptance Criteria:**
- [ ] GIVEN the reconciliation job runs on a schedule WHEN it finds exactly one settled charge per order THEN it SHALL report clean with no alert
- [ ] GIVEN the reconciliation job ever finds two or more settled charges for the same order THEN it SHALL page on-call immediately, treating this as a P0 incident, not a batched daily report
- [ ] GIVEN a synthetic duplicate is injected into a test fixture WHEN the job runs against it THEN it SHALL detect and flag it, proving the detector itself is not silently broken

**Technical Context:**
- **Pattern:** reconciliation-as-safety-net (Explore H3, demoted from primary control to backstop)
- **Files:** `[ASSUMED]` `jobs/payments/duplicate_charge_audit.*` (new)
- **Dependencies:** S-2, S-3

**Agent Hints:**
- **Class:** Builder
- **Context:** existing scheduled-job framework, on-call paging integration
- **Gates:** P1 — synthetic-duplicate-detection test green

---

#### 📋 STORY: S-6 Concurrency/race regression suite + historical-duplicate audit

> 🔴 P0 — this is the story that proves the fix, not just describes it

**Description:** As the engineer shipping this fix, I want a dedicated concurrency test suite that actively simulates the exact race (concurrent retry + delayed confirmation) and a one-time audit of historical charges for already-occurred duplicates, so the fix is proven against the real failure mode rather than only against sequential unit tests.

**Timebox:** ≤2d
**Risk:** P0 (without this, "proves it cannot recur" is an assertion, not a demonstrated result)

**Action Plan:**
1. **Test:** build a concurrency harness that fires the original attempt, artificially delays its confirmation past the retry timeout, and fires N simulated concurrent retries — assert exactly one successful gateway charge and N−1 short-circuited/queued outcomes, across every AC in S-2/S-3/S-4.
2. **Test:** run the same harness under load (many orders, many simulated workers) to catch lock-contention or throughput regressions, not just correctness at N=1 order.
3. **Configure:** a one-time backfill query against historical settled charges to identify any already-occurred duplicates (pre-fix), feeding S-5's baseline and finance's remediation queue — explicitly a data audit, not a code change.

**Acceptance Criteria:**
- [ ] GIVEN the concurrency harness simulates a delayed confirmation racing N concurrent retries for one order WHEN the suite runs THEN it SHALL assert exactly one successful charge and zero duplicate settlements, and this test SHALL be part of the required merge-gate suite (not optional/manual)
- [ ] GIVEN the same harness runs at realistic multi-order, multi-worker load WHEN executed THEN no lock-contention deadlock or unbounded wait SHALL occur (explicit timeout/latency budget asserted)
- [ ] GIVEN the historical-duplicate backfill audit runs against pre-fix production data WHEN it completes THEN it SHALL produce a list (possibly empty) of already-occurred duplicate charges for finance remediation, establishing the pre-fix baseline S-5 will be measured against

**Technical Context:**
- **Pattern:** adversarial/concurrency test harness, directly answering the mission's "prove it cannot recur" requirement
- **Files:** `[ASSUMED]` `spec/payments/duplicate_charge_race_spec.*` (new), read-only backfill query against production charge history
- **Dependencies:** S-2, S-3, S-4

**Agent Hints:**
- **Class:** Reasoner + Builder
- **Context:** S-2/S-3/S-4's combined implementation; any existing load/concurrency test tooling in the target repo
- **Gates:** P0 — this suite is itself the acceptance gate for S-2/S-3/S-4; must be green and included in CI, not a one-off manual run

---

#### 📋 STORY: S-7 Docs, runbook, support-tooling updates

> 🟢 P2

**Description:** As a support agent or on-call engineer, I want the new `pending`/`ambiguous` attempt states documented in the runbook and visible in support tooling, so that a customer inquiry about a "stuck" charge can be resolved by checking a documented state rather than reading source code.

**Timebox:** 1d
**Risk:** P2 (discoverability/support-load — does not block core functionality)

**Action Plan:**
1. **Modify:** support/admin tooling to surface `payment_attempt.state` (pending/confirmed/failed/ambiguous) on the order detail view.
2. **Modify:** on-call runbook with the new S-5 alert's response procedure and the meaning of each state.
3. **Modify:** CHANGELOG with the fix summary and the exit criteria proven in S-6.

**Acceptance Criteria:**
- [ ] GIVEN a support agent views an order with a `payment_attempt` record WHEN the admin tool renders it THEN the current state (pending/confirmed/failed/ambiguous) SHALL be visible without a database query
- [ ] GIVEN the S-5 alert fires WHEN on-call responds THEN the runbook SHALL document the exact reconciliation steps to take
- [ ] GIVEN the fix ships WHEN the changelog is updated THEN it SHALL document the new states and reference the S-6 concurrency proof

**Technical Context:**
- **Pattern:** n/a — documentation/tooling story
- **Files:** `[ASSUMED]` admin/support tooling views, `CHANGELOG.md`, `[ASSUMED]` `docs/runbooks/payments.md`
- **Dependencies:** S-1, S-2, S-3, S-4, S-5, S-6 (documents final, proven behavior)

**Agent Hints:**
- **Class:** Scriber (IDG-equivalent, per this project's wired Eidolons roster)
- **Context:** final state-machine shape from S-2/S-3/S-4
- **Gates:** reviewed by support/runbook owner

---

## Regression Scope

Explicit call-out (mission-required deliverable), consolidating the Dependency-layer findings below into one list of everything that must be regression-tested, beyond the new stories' own acceptance criteria:

1. **Legitimate distinct new purchases must not be blocked.** S-2's lock is scoped to `(order_id, attempt_group)` — a genuinely new purchase (different order, or an intentional new attempt after a real, resolved failure) must acquire a fresh lock without interference from an unrelated order's `pending` state. Regression test: two different orders charging concurrently never contend on each other's lock.
2. **Existing refund/void/partial-capture flows.** These flows read charge state; verify they correctly interpret the new `pending`/`ambiguous` states rather than assuming only `confirmed`/`failed` exist (a refund attempted against a still-`pending` attempt must be explicitly rejected or queued, not silently no-op).
3. **Multi-gateway routing (if applicable).** If more than one payment processor is used (e.g., by region or fallback), S-1's idempotency-key semantics and S-4's query-before-charge fallback must be verified per gateway — some processors' idempotency TTLs and lookup APIs differ.
4. **Existing job/queue retry wrappers.** Framework-level retry-on-exception (e.g., Sidekiq/Celery-style) must be checked against S-2's lock: a framework retry that fires while the lock is legitimately held must observe `pending` and back off, not throw an unhandled exception that the framework itself catches and re-queues faster than the lock TTL.
5. **Idempotency-key TTL alignment.** The gateway's own key TTL (assumption #3, Scope) must be verified against real-world retry-storm durations; S-4 covers the *logic* for the TTL-exceeded case, but the actual TTL values must be confirmed against the real gateway, not assumed.
6. **Lock/datastore performance under load.** The new lock acquisition adds a write on every charge attempt; S-6's load test must confirm no meaningful latency regression on the happy path (single attempt, no contention) and no deadlock under contention.
7. **Support/admin tooling and dashboards.** Anything currently rendering charge status must be checked for silent assumptions about only two states existing (S-7).
8. **Database migration safety.** Adding the `payment_attempt` state/columns (S-2) must follow the project's standard migration discipline (backward-compatible rollout, no downtime) — flagged as a real but generic dependency-layer risk, not detailed further here since the concrete migration tooling is unknown (G1).

---

## T — TEST (6-layer verification)

| # | Layer | Result |
|---|---|---|
| 1 | **Structural** | ✓ Hierarchy intact (Theme→Project→Feature→Story), no orphaned tasks, stories independent modulo the documented Construct sequencing |
| 2 | **Self-Consistency** | ✓ 3 alternative decompositions, ~75% overlap → HIGH confidence, stable (detail below) |
| 3 | **Dependency** | ⚠ Partial — exact call sites, migration tooling, and lock primitive availability cannot be enumerated against a real codebase (G1); flagged, not silently assumed complete. Regression Scope above enumerates every adjacent flow at risk |
| 4 | **Constraint** | ✓ Timeboxes realistic (all ≤2d); NFR "legitimate retries must still work" explicit in S-4; distributed-correctness NFR explicit in S-2 AC #2; compliance/financial-risk stakes explicit in Scope |
| 5 | **Process Reward** | ✓ Ordering (key → lock → reconciliation → TTL-fallback → safety-net/proof → docs) monotonically reduces risk: the property that most matters (no second gateway call) is closed by end of Phase 3, before any safety-net or documentation polish |
| 6 | **Adversarial** | ✓ See checklist below |

**Self-Consistency check (3 alternative decompositions):**

- **Decomposition A (this spec):** key-generation / local-lock / reconciliation / TTL-fallback / safety-net / proof-suite / docs — 7 stories, grouped by defense-in-depth layer.
- **Decomposition B:** "prevention core" (merges S-1+S-2+S-3+S-4 into one large story) / "observability" (merges S-5+S-6) / docs — 3 coarser stories, same conceptual chunks regrouped by delivery milestone.
- **Decomposition C:** grouped by system boundary instead of layer — "gateway-facing" (S-1, S-4's query half) / "internal state machine" (S-2, S-3) / "operational" (S-5, S-6) / docs — same coverage, different axis.

All three surface the same underlying concepts (shared idempotency key, exclusive local guard, confirmation-must-resolve-not-create, ambiguous-timeout handling, a safety net, and a proof suite) — estimated **~75% story-content overlap** → **HIGH confidence, decomposition is stable.** Decomposition A was kept because P0/P1/P2 risk tags and the ≤2d timebox ceiling map more cleanly onto per-layer stories than onto the coarser milestone or boundary groupings, which matters directly for the parallel Phase-3/Phase-4 execution sequencing above.

**Adversarial checklist (Failure Taxonomy, `scoring.md`):**

| Failure mode | Checked | Finding |
|---|---|---|
| Under-specification | ✓ | Initial pass left the lock's crash/TTL-expiry behavior implicit — fixed in Refine below (now explicit in S-2 AC #3 and the entire S-4 story) |
| Over-specification | ✓ | No rigid constraint blocks a valid implementation; file paths marked `[ASSUMED]`, lock primitive choice left open to whatever the real datastore supports |
| Dependency blindness | ⚠ | Real call-site enumeration and migration tooling are unknown (G1) — mitigated by the explicit Regression Scope section and by requiring S-6's proof suite as a merge gate rather than trusting code review alone |
| Assumption drift | — | No earlier-phase discovery yet invalidates a later step; re-open trigger documented for H4 if S-2's lock proves infeasible in the real stack |
| Scope creep | ✓ | Boundary table enforced; reconciliation-as-primary-control (H3) and gateway migration are explicitly kept out |
| Premature optimization | ✓ | Complexity 10/12 was addressed via extended thinking + mandatory review, not via TRANCE process overhead or an over-built saga/message-bus rebuild (Pattern phase explicitly declined the full outbox rebuild) |
| Stale context | n/a | No prior file reads to go stale; this is a fresh cycle |

**Gate:** One minor gap (dependency-layer, traced to unknown target repo — same root cause as the precedent spec for this project) → **Refine (1 cycle).**

---

## R — REFINE

**Cycle 1 diagnosis:** Test surfaced that the first Construct pass described S-2's lock only in terms of the happy-path acquire/release, leaving the crash-while-holding and TTL-expiry behavior implicit — a real under-specification risk, since an implementing agent could reasonably build a lock with no TTL at all (livelock risk) or one that silently reverts to unguarded retry on expiry (recreating the original bug under exactly the load conditions this fix targets).

**Root cause:** treating "acquire a lock" as a single fact rather than naming its full lifecycle (acquire → hold → release-on-resolve → expire-into-ambiguous) explicitly enough for an implementer to build without guessing.

**Prescription (applied):** added S-2 AC #3 (crash → ambiguous, never silently unguarded) and promoted the TTL-exceeded case from an implicit assumption into its own full story, S-4, with its own AC set proving the ambiguous path never double-submits. Both are already reflected in the Construct section above — this log records the diagnose→fix→re-verify pass that produced them.

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | unchanged — no clarity issue found |
| Completeness | 3 | 4 | lock lifecycle (crash/TTL) now fully named; ambiguous-path behavior now has its own story and proof obligation |
| Actionability | 3 | 4 | an implementing agent no longer has to guess at TTL/crash semantics — S-4 states the required behavior explicitly |
| Efficiency | 4 | 4 | unchanged |
| Testability | 3 | 5 | the fix now has a dedicated proof story (S-6) with concurrency-harness ACs directly answering "prove it cannot recur," not just per-story unit-level ACs |

**Mean:** 3.4 → 4.2 (**+0.8**, above the 0.3 diminishing-returns floor — this cycle earned its keep). **No dimension decreased** — no oscillation. **Cycle 1 target (all ≥3) met and exceeded (all ≥4); stopping at 1 cycle** rather than continuing to a cycle whose marginal gain would likely fall under the diminishing-returns threshold.

**Re-verify:** re-ran the Structural/Constraint/Adversarial layers against the updated S-2/S-4/S-6 — no new gaps introduced, no prior pass invalidated.

---

## Proof of Non-Recurrence — consolidated acceptance criteria

The mission specifically requires proving the double-charge "cannot recur." The following criteria, pulled together from across S-2/S-3/S-4/S-6, are the load-bearing proof set — every other AC in this spec supports these but these are the ones a skeptical reviewer should check first:

1. **No second gateway call while an attempt is outstanding** (S-2 AC #1, #2): under concurrent load across multiple workers, exactly one lock winner reaches the gateway per `(order_id, attempt_group)` — proven, not merely asserted, by S-6's concurrency harness.
2. **No orphaned or duplicated attempt record on confirmation** (S-3 AC #1, #2): a delayed confirmation always resolves the one existing record, including after TTL expiry, never creating a second one.
3. **No silent fallback to unguarded retry on ambiguity** (S-4 AC #1, #2): the TTL/crash-expiry edge case — the exact condition under which the original bug occurred — is closed by a mandatory query-before-charge step, itself covered by the same concurrency harness (S-6 AC #1).
4. **Independent operational proof, continuously** (S-5 AC #2): even if every above control has an undiscovered gap, the safety-net job pages on-call the instant a duplicate ever settles — the claim is backed by both a design-time proof (S-6) and a run-time tripwire (S-5), not by design confidence alone.
5. **No regression into false-positive blocking** (Regression Scope #1): the proof of "cannot double-charge" is not achieved by being so conservative that legitimate distinct purchases are blocked — verified by the cross-order non-interference test.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (/3) | Basis |
|---|---|---|
| Pattern Match | 2 | Canonical, industry-wide pattern (idempotency key + local guard) with strong consensus, but no in-repo template exists to apply directly (G1) |
| Requirement Clarity | 2 | The bug and the required deliverables (root cause, fix, regression scope, proof, rejected alternative) are unambiguous; target-repo specifics are not (CLARIFY gaps) |
| Decomposition Stability | 3 | ~75% self-consistency overlap across 3 alternative decompositions — HIGH |
| Constraint Compliance | 2 | 6-layer Test passed with one flagged-but-mitigated gap (dependency layer, unknown target repo); the lock design (S-2) introduces a genuinely new operational risk class (distributed-lock correctness) that a human reviewer must sign off on, not something fully closed by this spec alone |

**Weighted Confidence:** (2+2+3+2)/12 × 100 = **75%**

**Decision: VALIDATE (70–84% band) — deliver with flags, human reviews.**

**Confidence-band override (complexity 10/12):** the numeric formula lands in VALIDATE, but Scope's complexity score (10/12) crosses into the "human-in-the-loop recommended" band on its own terms, and the financial/compliance stakes independently warrant it. This spec therefore carries an **elevated, mandatory** (not optional) human sign-off requirement specifically on S-2's lock/state-machine design — narrower than a full COLLABORATE halt (the spec itself is complete and decision-ready), but stricter than a standard VALIDATE flag-for-review.

**What a human reviewer should specifically validate before this becomes implementation-ready:**
1. Confirm the real target repo, gateway, and retry framework (CLARIFY G1–G4) — re-anchor every `[ASSUMED]` file path in Construct.
2. Sign off on S-2's distributed-lock primitive choice (DB row lock vs. unique constraint vs. distributed cache lock) against the real datastore's actual concurrency guarantees — this is the mandatory review gate named above.
3. Confirm the real gateway's idempotency-key TTL (Scope Assumption #3) so S-4's TTL-exceeded threshold is calibrated to a real number, not an assumed one.
4. Confirm whether multi-gateway routing exists (Regression Scope #3); if so, S-1/S-4 need a per-gateway pass before implementation.

### Deliverables produced (dual-format contract + ECL sidecar)

| Artifact | Path |
|---|---|
| Plan artifact (this file) | `/tmp/ramza-s2/ac003/AB-T3-spectra-r2.out.md` (requested output path — explicit override, honored) |
| Authoritative mirror (Output Discipline rule 2) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-double-charge-fix.md` |
| Agent handoff (YAML) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-double-charge-fix.yaml` |
| State machine (JSON) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-double-charge-fix.state.json` |
| ECL v2.0 envelope sidecar | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-double-charge-fix.envelope.json` (emitted because `ECL_VERSION=2.0` is present at `/tmp/spectra-pilot/.eidolons/spectra/ECL_VERSION`) |

Per Output Discipline rule 2: since the mission explicitly named a path outside `.spectra/`, that path was honored as the primary deliverable, and the authoritative copy was mirrored under `.spectra/plans/` regardless, together with the full Assemble deliverable set (YAML handoff, state JSON, ECL envelope).

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-002"
  confidence: 75
  complexity: 10
  spectra_version: "4.11.0"
  thread_id: "c1584458-65b3-4fba-8819-3875f52c0c48"

projects:
  - id: "P-1"
    name: "Charge Retry / Delayed-Confirmation Race Elimination"
    features:
      - id: "F-1"
        name: "Idempotent, lock-guarded charge submission with confirmation reconciliation"
        stories:
          - id: "S-1"
            title: "Idempotency-key generation & reuse across retries"
            timebox: "1d"
            risk: "P0"
            action_plan:
              - verb: "Create"
                target: "one idempotency key per logical attempt, reused verbatim on retry"
              - verb: "Modify"
                target: "every charge-submission call site to pass the shared key"
              - verb: "Test"
                target: "retry reuses key; distinct attempts get distinct keys"
            acceptance_criteria:
              - given: "a charge attempt is retried"
                when: "the retry submits to the gateway"
                then: "it carries the exact same idempotency key as the original attempt"
              - given: "two genuinely distinct purchases"
                when: "each is submitted"
                then: "each receives a distinct idempotency key"
              - given: "the gateway is queried with a previously-used key"
                when: "a duplicate request with that key arrives"
                then: "the gateway's response is the original charge result, not a new charge"
            agent_hints:
              recommended_class: "builder"
              context_files: ["lib/payments/gateway_client.* [ASSUMED]"]
              validation_gates:
                p0: "key-reuse-on-retry test green"
          - id: "S-2"
            title: "Local pending-attempt lock (CAS state machine, order-scoped)"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "payment_attempt record with pending/confirmed/failed CAS state + distributed lock on (order_id, attempt_group)"
              - verb: "Modify"
                target: "submission path: atomic none->pending transition before any gateway call"
              - verb: "Configure"
                target: "lock TTL/heartbeat -> well-defined ambiguous state on crash, never silent unguarded retry"
              - verb: "Test"
                target: "N concurrent submissions for one order -> exactly one lock winner"
            acceptance_criteria:
              - given: "a pending attempt exists (unexpired) for an order"
                when: "any retry targets the same order"
                then: "the retry does not acquire a new lock or submit a new charge"
              - given: "N simultaneous submission attempts race for the same lock across workers"
                when: "they execute concurrently"
                then: "exactly one acquires the lock and reaches the gateway"
              - given: "a worker crashes while holding the lock"
                when: "the lock TTL elapses"
                then: "the attempt transitions to an explicit ambiguous state, never silently unguarded"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["lib/payments/attempt_lock.* [ASSUMED]"]
              validation_gates:
                p0: "concurrency test: exactly-one-lock-winner; mandatory human design sign-off"
          - id: "S-3"
            title: "Confirmation reconciliation against the single guarded attempt record"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-2"]
            action_plan:
              - verb: "Modify"
                target: "confirmation/webhook handler to look up attempt by shared key, never create a fresh record"
              - verb: "Modify"
                target: "handler performs pending->confirmed|failed CAS + lock release atomically"
              - verb: "Test"
                target: "late confirmation after TTL expiry resolves the correct original record"
            acceptance_criteria:
              - given: "a confirmation arrives for a pending attempt"
                when: "it is processed"
                then: "it transitions that exact attempt record and releases its lock atomically"
              - given: "a confirmation arrives after the lock TTL has expired"
                when: "reconciliation runs"
                then: "it resolves the original attempt record via the shared idempotency key"
              - given: "a confirmation references a key with no matching local attempt"
                when: "processed"
                then: "the system logs and alerts rather than silently discarding it"
            agent_hints:
              recommended_class: "builder"
              context_files: ["lib/payments/webhook_handler.* [ASSUMED]"]
              validation_gates:
                p0: "late-confirmation-after-TTL test green; no-orphan-record test green"
          - id: "S-4"
            title: "TTL/ambiguous-timeout fallback — query-before-charge"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-2", "S-3"]
            action_plan:
              - verb: "Create"
                target: "reconcile-before-retry check on the ambiguous/expired-lock path"
              - verb: "Modify"
                target: "retry entrypoint: mandatory, unconditional check on the ambiguous path"
              - verb: "Test"
                target: "ambiguous-path retry never double-submits when original succeeded"
            acceptance_criteria:
              - given: "an attempt's lock has expired into the ambiguous state"
                when: "a retry is triggered"
                then: "the system queries for the definitive outcome before submitting any new charge"
              - given: "that query resolves to original attempt succeeded"
                then: "the retry never submits a new charge under any circumstance"
              - given: "that query resolves to original attempt genuinely failed"
                then: "the retry is permitted to proceed with a fresh, properly-locked attempt"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["lib/payments/attempt_lock.* [ASSUMED]", "lib/payments/gateway_client.* [ASSUMED]"]
              validation_gates:
                p0: "ambiguous-path-never-double-submits test green under the S-6 concurrency harness"
          - id: "S-5"
            title: "Duplicate-charge detection safety net + alerting"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-2", "S-3"]
            action_plan:
              - verb: "Create"
                target: "reconciliation job diffing gateway-settled charges vs local records"
              - verb: "Configure"
                target: "zero-tolerance page-on-call alert on >1 settled charge per order"
              - verb: "Test"
                target: "clean fixture reports clean; injected synthetic duplicate is detected"
            acceptance_criteria:
              - given: "the reconciliation job runs on schedule"
                when: "it finds exactly one settled charge per order"
                then: "it reports clean with no alert"
              - given: "the job ever finds two or more settled charges for one order"
                then: "it pages on-call immediately as a P0 incident"
              - given: "a synthetic duplicate is injected into a test fixture"
                when: "the job runs against it"
                then: "it detects and flags it"
            agent_hints:
              recommended_class: "builder"
              context_files: ["jobs/payments/duplicate_charge_audit.* [ASSUMED]"]
              validation_gates:
                p1: "synthetic-duplicate-detection test green"
          - id: "S-6"
            title: "Concurrency/race regression suite + historical-duplicate audit"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-2", "S-3", "S-4"]
            action_plan:
              - verb: "Test"
                target: "concurrency harness: delayed confirmation racing N concurrent retries -> exactly one charge"
              - verb: "Test"
                target: "same harness at multi-order/multi-worker load -> no deadlock/unbounded wait"
              - verb: "Configure"
                target: "one-time backfill audit of historical settled charges for pre-fix duplicates"
            acceptance_criteria:
              - given: "the concurrency harness simulates a delayed confirmation racing N concurrent retries"
                when: "the suite runs"
                then: "exactly one successful charge and zero duplicate settlements are asserted, as a required merge gate"
              - given: "the same harness runs at realistic multi-order, multi-worker load"
                when: "executed"
                then: "no lock-contention deadlock or unbounded wait occurs"
              - given: "the historical-duplicate backfill audit runs against pre-fix production data"
                when: "it completes"
                then: "it produces a list (possibly empty) of already-occurred duplicates for finance remediation"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["spec/payments/duplicate_charge_race_spec.* [ASSUMED]"]
              validation_gates:
                p0: "concurrency suite green and included in CI as a required merge gate"
          - id: "S-7"
            title: "Docs, runbook, support-tooling updates"
            timebox: "1d"
            risk: "P2"
            dependencies: ["S-1", "S-2", "S-3", "S-4", "S-5", "S-6"]
            action_plan:
              - verb: "Modify"
                target: "admin/support tooling: surface payment_attempt.state on order detail view"
              - verb: "Modify"
                target: "on-call runbook: S-5 alert response procedure + state meanings"
              - verb: "Modify"
                target: "CHANGELOG: fix summary + S-6 proof reference"
            acceptance_criteria:
              - given: "a support agent views an order with a payment_attempt record"
                when: "the admin tool renders it"
                then: "the current state is visible without a database query"
              - given: "the S-5 alert fires"
                when: "on-call responds"
                then: "the runbook documents the exact reconciliation steps"
              - given: "the fix ships"
                when: "the changelog is updated"
                then: "it documents the new states and references the S-6 concurrency proof"
            agent_hints:
              recommended_class: "scriber"
              context_files: ["CHANGELOG.md", "docs/runbooks/payments.md [ASSUMED]"]
              validation_gates:
                p2: "reviewed by support/runbook owner"

execution_plan:
  phases:
    - name: "Phase 1 — Outer boundary"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Phase 2 — Inner boundary (mandatory human design review)"
      stories: ["S-2"]
      agent_class: "reasoner"
    - name: "Phase 3 — Resolution + ambiguity handling (parallel)"
      stories: ["S-3", "S-4"]
      agent_class: "builder+reasoner"
    - name: "Phase 4 — Safety net + proof (parallel)"
      stories: ["S-5", "S-6"]
      agent_class: "builder+reasoner"
    - name: "Phase 5 — Docs"
      stories: ["S-7"]
      agent_class: "scriber"
```

### State Machine (JSON)

```json
{
  "session_id": "d56a334c-8f9c-425a-b5fc-4e564d387930",
  "spec_id": "SPEC-2026-07-05-002",
  "goal": "Make it structurally impossible for a retried charge to produce a second successful gateway charge for the same purchase, regardless of confirmation delay, and prove it under concurrency.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Idempotency-key generation & reuse across retries", "status": "pending", "dependencies": [], "files_affected": ["lib/payments/gateway_client.* [ASSUMED]"], "verification_command": "test: key-reuse-on-retry", "estimated_timebox": "1d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Local pending-attempt lock (CAS state machine)", "status": "pending", "dependencies": [1], "files_affected": ["lib/payments/attempt_lock.* [ASSUMED]"], "verification_command": "test: concurrency exactly-one-lock-winner", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Confirmation reconciliation against the guarded attempt record", "status": "pending", "dependencies": [2], "files_affected": ["lib/payments/webhook_handler.* [ASSUMED]"], "verification_command": "test: late-confirmation-after-TTL resolves correct record", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "TTL/ambiguous-timeout fallback — query-before-charge", "status": "pending", "dependencies": [2, 3], "files_affected": ["lib/payments/attempt_lock.* [ASSUMED]", "lib/payments/gateway_client.* [ASSUMED]"], "verification_command": "test: ambiguous-path never double-submits", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Duplicate-charge detection safety net + alerting", "status": "pending", "dependencies": [2, 3], "files_affected": ["jobs/payments/duplicate_charge_audit.* [ASSUMED]"], "verification_command": "test: synthetic-duplicate detection", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Concurrency/race regression suite + historical audit", "status": "pending", "dependencies": [2, 3, 4], "files_affected": ["spec/payments/duplicate_charge_race_spec.* [ASSUMED]"], "verification_command": "test: concurrency harness exactly-one-charge (required CI gate)", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Docs, runbook, support-tooling updates", "status": "pending", "dependencies": [1, 2, 3, 4, 5, 6], "files_affected": ["CHANGELOG.md", "docs/runbooks/payments.md [ASSUMED]"], "verification_command": "manual: runbook/support owner review", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "phase": "Refine",
      "diagnosis": "S-2's lock lifecycle (crash/TTL-expiry behavior) was implicit; ambiguous-path fallback was an unstated assumption rather than a story with its own proof obligation",
      "fix_applied": "added S-2 AC #3 (crash -> ambiguous, never silently unguarded); promoted the TTL-exceeded case into its own story S-4 with a full AC set",
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
- [x] Complexity scored (10/12), extended-thinking budget routed; TRANCE explicitly considered and declined with rationale
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing)
- [x] All 7 stories pass INVEST
- [x] All timeboxes valid (1d/≤2d only, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this file) + structured YAML/JSON (embedded above + mirrored as separate files)
- [x] Confidence score present with factor breakdown (75%, VALIDATE, with a documented mandatory-review override on S-2)
- [x] Plan saved as artifact at the requested path + mirrored under `.spectra/plans/`
- [x] Every mirrored/derived output path starts with `.spectra/`
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H1-alone, H3, H4 — three, exceeding the "at least one" requirement)
- [x] Root-cause hypothesis stated explicitly with differential diagnosis (Scope)
- [x] Regression scope enumerated as its own section
- [x] Consolidated "Proof of Non-Recurrence" acceptance-criteria set assembled

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*

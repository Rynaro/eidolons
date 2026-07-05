---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-review
created_at: 2026-07-05T13:15:23Z
thread_id: 019f326b-5641-708e-8281-a280b88154f7
target_repos:
  - "<unresolved — no payment/billing implementation found in /tmp/spectra-pilot (Eidolons scaffold only, no application source); see CLARIFY Gap G1>"
stories_count: 7
validation_gates_count: 21
evidence_anchors_count: 0
confidence: 0.75
---

# SPEC-2026-07-05-001 — Fix: duplicate charge when a payment retry races the original attempt's delayed confirmation

**Mission:** Produce a decision-ready FIX specification for intermittent double-charges caused by a payment retry racing the original attempt's delayed confirmation: root-cause hypothesis, fix approach, regression scope, acceptance criteria proving the double-charge cannot recur, and at least one rejected alternative.

**Methodology:** SPECTRA v4.11.0 — CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble
**Intent Type:** `BUG_SPEC` ("Issue needs fix spec" → Root cause → fix spec), with `CHANGE` characteristics since the fix modifies existing retry/confirmation code paths.
**Tier:** Extended thinking (complexity 11/12 → 2× budget), with the 10–12 band's "human collaboration recommended" guidance layered on top of the standard confidence gate (see Assemble).
**Read-only invariant honored:** no code, no file edits to the target system were made in producing this spec.

---

## Memory pre-flight (mission intake)

Per `agent.md`, a `mcp__crystalium__recall` call was attempted before CLARIFY to surface prior specs/decisions/traps relevant to "payment retry," "double charge," "idempotency," or "confirmation race" work. **No `mcp__crystalium__*` tools are reachable in this environment** (not present in the available tool surface, no CRYSTALIUM install evidence in `/tmp/spectra-pilot`). Per the documented graceful-skip rule this is a silent no-op, not a hard failure — SPECTRA is EIIS-standalone-conformant. Planning proceeds without prior-session memory; this is reflected as a Pattern-phase gap below, not fabricated as a false match.

---

## CLARIFY

**Trigger:** every new request. **Not skipped** — the mission describes a real financial-correctness incident with no target repository, processor, or existing retry architecture supplied, which is genuine ambiguity, not merely missing polish.

**Parse Intent:**
- **WHO:** customers who are charged twice; support/billing ops who field the resulting disputes; payment/platform engineering who own the retry and confirmation code; finance/accounting who reconcile the ledger; compliance/risk who monitor chargeback ratios that repeated overcharge patterns can trip.
- **WHAT:** eliminate the race between a payment retry and the original attempt's delayed confirmation so that no payment intent is ever settled by more than one successful charge — not just detected-and-refunded after the fact, but prevented.
- **WHY:** direct financial harm and trust damage to customers, chargeback/dispute cost, support load, and potential card-network monitoring exposure from a recurring overcharge pattern.
- **CONSTRAINTS:** the fix must not reduce retry recoverability for genuinely failed/transient-error payments (removing retries is not an acceptable trade); must not add meaningful latency to the common, non-racing checkout path; must work with whatever payment processor is in use; must produce zero behavior change for payment flows that already resolve correctly today.

**Identify Gaps (Discovery mode was not warranted — the goal, "make double-charging impossible," is clear; only mechanism-level and target-system details are ambiguous, which is CLARIFY's remit):**

| # | Gap | Resolution mode |
|---|-----|------------------|
| G1 | No target repository, payment processor, or retry architecture was supplied, and `/tmp/spectra-pilot` (this consumer project) contains only Eidolons scaffolding — no application source, no `payment`/`charge`/`retry`/`confirm` implementation was found by search. `.spectra/setup/spectra-conventions.md` does not exist. | **[GAP] — cannot be closed interactively in this run** (single-shot deliverable, no live user turn available). Resolved via explicit, risk-tagged assumptions below rather than fabricating a fake codebase match. |
| G2 | Unknown whether an idempotency key is already sent to the processor today, and if so, whether it is derived per-payment-intent (stable) or per-attempt (unstable — defeats dedup). | **[ASSUMPTION]** — treat as either absent or unstably-derived (the conservative default that motivates this fix regardless of which is true). |
| G3 | Unknown whether the retry is system/orchestrator-triggered (a scheduled retry worker) or client-triggered (checkout resubmission, flaky mobile client) — or both. | **[ASSUMPTION]** — treat as both being possible; the fix and its regression scope are designed to cover both trigger sources, including a manual-retry side channel (support tooling). |
| G4 | Unknown whether the confirmation is an asynchronous webhook/callback distinct from the synchronous charge-creation response (typical for card-network/ACH/3DS flows), or whether "confirmation" is actually the same synchronous call and the described "race" is really client-side double-submission. | **[ASSUMPTION]** — treat as asynchronous confirmation (matches the mission's literal wording, "delayed confirmation"), while designing the fix to remain correct under the synchronous-confirmation variant too (see Root Cause Hypothesis, RC4). |

**Would-ask (≤3, numbered, <200 chars, per CLARIFY step 3 — recorded for the human reviewer since no live turn is available this run):**
1. Is an idempotency key sent to the processor today, and is it derived per-intent or regenerated per-attempt?
2. Are retries triggered by a server-side worker, the client, support tooling, or more than one of these?
3. What is today's retry timeout T, and how does it compare to observed p50/p99 confirmation latency?

**Gather Structural Context:** grepped `/tmp/spectra-pilot` for `charge`/`payment`/`retry`/`confirm` — zero implementation hits (Eidolons scaffold files only, matched only in this Eidolon's own skill docs). No `spectra-conventions.md` to load. Proceeding with industry-standard payment-processor patterns (idempotency keys, status reconciliation — see Pattern phase) rather than fabricated project-specific paths; every file path in Construct below is marked **[ASSUMED]** and must be re-anchored to the real target repo before implementation.

**Assess Cognitive Load:** single session sufficient to produce the spec; however, given complexity 11/12 (see Scope), **flag multi-stakeholder review as a precondition for implementation sign-off**, not merely a nice-to-have.

**Skip?** No — see gaps above. CLARIFY is complete via documented assumptions, which is why confidence is gated to VALIDATE rather than AUTO_PROCEED at Assemble (see below).

---

## S — SCOPE

### Root Cause Hypothesis (BUG_SPEC action: root cause → fix spec)

**Primary hypothesis (RC1 — "retry-fires-before-original-resolves"):** the retry path treats "no confirmation within timeout T" as equivalent to "the original attempt failed," and dispatches a second charge without either (a) a shared idempotency key that would let the processor deduplicate it, or (b) an atomic claim on the payment intent's state that would block a second attempt while the first is still unresolved. The original attempt's confirmation is not lost — merely delayed past T (processor-side queuing, webhook delivery lag, network delay) — so when it eventually lands, it is processed as a legitimate success on an attempt the system had already treated as failed-and-superseded. Both charges settle. This is the mechanism the mission's wording ("a payment retry races the original attempt's delayed confirmation") describes literally.

**Alternative root-cause hypotheses considered** (documented per the same discipline Explore uses for rejected alternatives — applied early because BUG_SPEC's root-cause step is itself a multi-hypothesis decision):

| ID | Hypothesis | Relationship to RC1 | Disposition |
|----|------------|----------------------|--------------|
| RC2 | An idempotency key exists but is derived per-attempt (includes a timestamp/nonce), so retries mint a *new* key each time and processor-side dedup never triggers. | Variant of RC1 — same failure shape, different proximate cause. | Subsumed — the fix (stable, intent-derived key) closes this too. |
| RC3 | The idempotency key and processor-side dedup work correctly, but the **confirmation/webhook ingestion path** has an out-of-order or duplicate-delivery bug that double-books one confirmed charge as two ledger entries — a bookkeeping bug, not a double-charge-at-the-processor bug. | Distinct failure mode. | **Not subsumed.** Flagged as an open verification item (see Regression Scope, Test layer 3) — would need webhook-delivery dedup rather than an attempt-guard if confirmed against real logs/traces, which this spec-only exercise cannot access. |
| RC4 | No idempotency mechanism exists at all, and the "retry" is client-triggered (double-click, flaky mobile resubmission) rather than system-triggered. | Same category, different trigger source. | Covered by the fix (identical mechanism), but changes **regression scope** — the guard must cover the client-facing checkout entrypoint, not only an internal retry worker. |

**Working assumption for this spec:** RC1 is the primary hypothesis, designed to be robust across RC1/RC2/RC4 simultaneously (a stable idempotency key plus an atomic state guard closes all three). RC3 is called out explicitly as a distinct failure mode that the primary fix does **not** address and that requires separate evidence (real logs/traces) to confirm or rule out — see Regression Scope and the Test-phase Dependency layer.

### Intent Classification & Complexity

**Complexity Score (4-dimension matrix):**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 2 | Not a single call site — spans charge issuance, confirmation ingestion, and a new reconciliation surface; multi-feature within one payment domain |
| Ambiguity | 3 | Target repo/processor/architecture unknown (G1–G4); four plausible root-cause variants exist and cannot be disambiguated without real logs |
| Dependencies | 3 | Touches charge issuance, webhook/confirmation handler, retry scheduler, ledger/settlement records, support manual-retry tooling, and alerting — cross-domain, more than 3 systems |
| Risk | 3 | Financial correctness, customer trust, dispute/chargeback exposure — critical path by definition |

**Total: 11/12 → Extended thinking (2× budget) AND the 10–12 band's "human collaboration recommended."** This is higher than a typical feature spec precisely because the bug is a money-correctness defect, not a UX defect — the stakes dimension alone would justify extra scrutiny even if the mechanism were simple.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| Stable, intent-derived idempotency key on every charge attempt (original, retry, manual) | Migrating or replacing the payment processor | Extending the same claim-guard pattern to other retryable side effects (email/notification retries) — same mechanism, different call sites |
| Atomic in-flight state guard blocking overlapping attempts | Customer remediation/refund workflow for already-affected historical customers (separate incident-response/ops track, not a code-fix spec — tracked as a required follow-up, not silently dropped) | RC3's webhook-ordering investigation, pending real log evidence |
| Reconcile-before-retry status query against the processor | A full re-architecture of the retry/confirmation subsystem (H2/H3, rejected below) | — |
| Idempotent, state-aware confirmation ingestion (safe no-op on late/duplicate confirmations) | Changing PCI/cardholder-data scope | — |
| Duplicate-charge detection & alerting safety net | | |
| A deterministic regression test that reproduces the exact race | | |

**Assumptions (risk-tagged):**

1. **[ASSUMPTION]** The payment processor supports idempotency keys on charge-creation calls (true of virtually all PCI-compliant processors — Stripe/Adyen/Braintree-class APIs). **Risk if wrong:** the internal atomic-claim guard (S-2) becomes the *sole* line of defense rather than defense-in-depth; S-1 would need to be re-scoped as a purely internal mechanism, raising effort but not invalidating the approach.
2. **[ASSUMPTION]** Retries are triggered by a timeout T that is shorter than the observed p99 confirmation latency — this is the literal race the mission describes; if T already exceeded p99 with margin, the race would be rare/theoretical rather than the reported "intermittent" pattern. **Risk if wrong:** if retries are instead triggered by an explicit definitive-failure signal from the processor, RC1 is wrong and RC3 (ledger/webhook dedup bug) becomes the dominant hypothesis, and Scope must reopen around a different mechanism.
3. **[ASSUMPTION]** "Confirmation" is an asynchronous webhook/callback distinct from the synchronous charge-creation response (RC1/G4). **Risk if wrong:** if confirmation is actually synchronous, the race is better explained by RC4 (client double-submission); the idempotency-key + guard fix is unchanged, but S-3's reconciliation-query story would be unnecessary overhead and could be simplified out.
4. **[ASSUMPTION]** A support-tooling manual-retry side channel exists and must be brought under the same guard, or the fix can be silently bypassed. **Risk if wrong:** low — if no such tooling exists, S-2's scope shrinks slightly; retained because it is a common real-world side door and cheap to guard defensively.

**Stakeholders:** affected customers (primary harmed party); support/billing ops (handles disputes, uses manual-retry tooling); payment/platform engineering (implements S-1–S-6); finance/accounting (ledger reconciliation impact, reviews S-5); compliance/risk (chargeback-ratio exposure); whoever owns the payment-processor integration contract (reviews S-1/S-3); on-call/runbook owner (reviews S-7).

---

## P — PATTERN

**Query memory:** unavailable this session (see Memory pre-flight) — **[GAP]**, not a false negative; no prior-failure catalog to surface.

**Query codebase:** zero matches in `/tmp/spectra-pilot` (see CLARIFY G1). Falling back to well-established external reference patterns for "exactly-once effect under retry," ranked by similarity (MMR: `similarity − 0.3 × redundancy`, top candidates shown):

| Pattern | Similarity | Why |
|---|---|---|
| Stripe-style "Idempotent Requests" (idempotency key per logical operation) | 88% | Direct match for the request-level dedup half of the fix — the processor itself becomes a second line of defense |
| Outbox / unique-constraint-on-intent-id pattern (exactly-once effect via persisted uniqueness) | 80% | Durable, DB-level backstop for the internal claim guard |
| Optimistic concurrency control (conditional update / compare-and-swap on an attempt-status column) | 75% | The mechanism for S-2's atomic in-flight claim |
| Distributed lock (e.g., Redis `SETNX` with TTL) guarding a critical section | 68% | Common pattern for cross-process mutual exclusion, evaluated and demoted below (Explore H2) |
| Event sourcing with a compensating transaction (detect duplicate, auto-refund) | 55% | Detect-and-correct pattern, evaluated and demoted below (Explore H3) to a safety-net role |

**No single pattern reaches the 85% USE_TEMPLATE threshold** (no in-repo template exists — there is no repo). **Strategy: ADAPT (60–84% band)** — combine the idempotency-key pattern (88%) with the optimistic-concurrency/CAS state guard (75%) as the primary skeleton, and use the outbox/unique-constraint pattern (80%) as the durable DB-layer backstop underneath the guard. The distributed-lock pattern and the compensating-transaction pattern are explicitly **not** adopted as the primary mechanism (see Explore H2/H3 rejections), though the latter's ledger/reconciler idea is retained in a demoted, safety-net role (S-5).

**Catalog Failure Patterns:** none available (memory unreachable). Documented as a gap, not skipped silently.

---

## E — EXPLORE

**Trigger:** before Construct. **Not skipped.** 4 genuinely distinct fix-approach hypotheses generated (conservative + pattern-leveraging + innovative + risk-minimizing, exceeding the 3-hypothesis minimum).

**Observations (5 angles):**
1. **Prevention vs. detection** — a guard that stops the second charge from ever reaching the processor beats any after-the-fact detection/refund, because a refund still leaves real, if temporary, customer harm (statement confusion, overdraft risk, a dispute filed before the refund lands).
2. **Latency budget** — checkout is latency-sensitive; any guard/reconciliation mechanism must add negligible overhead to the common, non-racing path, and should only pay its cost on the retry path.
3. **Defense-in-depth** — a single mechanism (idempotency key alone, or a guard alone) is fragile if the processor mishandles the key or the guard has a gap; layering an internal atomic guard with an external processor-side key is materially more robust than either alone.
4. **Failure-mode symmetry** — the fix must not trade "sometimes double-charges" for "sometimes never charges": an overly aggressive guard that permanently blocks retries on a stuck original attempt strands a legitimate customer who genuinely needs the retry to succeed.
5. **Operability** — engineers and support need visibility into in-flight vs. stuck attempts, or the guard becomes an unobservable black box that can trap money (or a customer's ability to pay) in limbo with no signal.

### Hypothesis scoring (7-dimension weighted rubric, 1–10 per dimension → weighted ×10)

| # | Hypothesis | Align 25% | Correct 20% | Maintain 15% | Perf 15% | Simple 10% | Risk 10% | Innov 5% | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Conservative** — stable per-intent idempotency key + atomic in-flight claim guard (CAS/unique-constraint) + reconcile-before-retry status query | 9 | 9 | 8 | 8 | 8 | 9 | 3 | **83.0** |
| H2 | **Pattern-leveraging** — distributed lock (Redis/etcd) with TTL per payment intent, guarding retry issuance | 7 | 6 | 6 | 7 | 6 | 5 | 5 | **62.5** |
| H3 | **Innovative** — event-sourced attempt ledger + async reconciler that detects and auto-refunds duplicate charges within N minutes | 6 | 6 | 5 | 7 | 3 | 4 | 8 | **56.0** |
| H4 | **Risk-minimizing** — remove automatic/system-triggered retries entirely; require manual support-initiated retry after human review | 4 | 8 | 9 | 9 | 9 | 5 | 2 | **78.0** |

Spread is 83.0 → 56.0 (27-point range) — **not** within the 5% "insufficient differentiation" band; well-differentiated, no re-observation needed. H1 (83.0) and H4 (78.0) are the top 2 overall (within 5 points of each other) — both expanded below per the "expand top 2" rule.

### Expand top 2

**H1 — Idempotency key + atomic claim + reconciliation (conservative).**
- *File/system impact:* payment-intent state model (new attempt-state enum), every charge-issuing call site (original path, system retry worker, and per Assumption 4, the support-tooling manual retry), and the confirmation/webhook ingestion handler.
- *Dependency chain:* correctness hinges entirely on the claim being genuinely atomic under real concurrency (DB-level conditional update / unique constraint / `SELECT FOR UPDATE`) — an application-level check-then-act "guard" would itself race and defeat the fix.
- *Edge cases:* an original attempt that is genuinely dead (processor down, will never confirm) needs a bounded, positively-confirmed "declare dead" transition rather than a naive timeout (this is exactly the ambiguity Refine below tightens); two independent retries firing concurrently against each other, not just against the original; a confirmation arriving for an attempt already marked `superseded` must be a safe no-op, never a second success.

**H4 — Remove automatic retries (risk-minimizing).**
- *File/system impact:* smaller — delete/disable the retry-trigger code path; add or extend a support workflow for manual "should this retry?" decisions previously automated.
- *Dependency chain:* shifts load onto support staffing and process; mean time to resolve a transient failure moves from seconds (automated retry) to however long human review takes.
- *Edge cases:* a brief processor outage now produces a support-queue backlog instead of self-healing; no technical edge cases beyond that — which is precisely why it scores well on Correctness/Simplicity/Performance/Maintainability but poorly on Alignment and Risk: it "fixes" the described bug by deleting the capability the bug lives in, trading a rare (if severe) data-integrity defect for a guaranteed, permanent increase in failed-payment friction and support cost.

### Selection

**Selected: H1 (idempotency key + atomic claim + reconciliation, conservative).** It scores highest (83.0) and — more importantly for a fix spec — it is the only hypothesis that satisfies the mission's literal bar ("acceptance criteria proving the double-charge cannot recur") as a true **prevention** control. H3 is a detect-and-correct control (customers still experience a real, if temporary, double charge); H4 removes the feature the bug lives in rather than fixing it, at unacceptable cost to legitimate retry recoverability (an explicit CONSTRAINT from CLARIFY). H1 composes cleanly with the Pattern-phase ADAPT selection (idempotency key + CAS + outbox-style uniqueness) and directly targets RC1 while remaining robust to RC2 and RC4.

**Rejected alternatives (documented per E-phase step 6, prevents re-exploration in replanning):**

- **H2 (distributed lock with TTL) — rejected as primary mechanism, not excluded as a possible supplement.** TTL selection recreates the exact "how long is too long to wait for confirmation" judgment call that caused the original bug, just relocated into a new infrastructure component; it also adds an external lock-service dependency and its own outage/clock-skew failure mode (Risk scored 5/10, the weakest dimension). **Re-open trigger:** if a human confirms the real target system already standardizes on a distributed-lock service and DB-level atomic claims (H1's mechanism) are infeasible there (e.g., a datastore with no conditional-write support), H2 could be reconsidered — paired with H1's reconciliation-query idea to avoid reintroducing the TTL-boundary problem on its own.
- **H3 (event-sourced ledger + auto-refund) — rejected as primary fix, retained in a demoted role.** It is a detect-and-correct control: customers still experience a real double charge before compensation lands, which fails the mission's explicit bar of proving the double-charge *cannot recur* (Simplicity scored 3/10, Risk 4/10 — "Weak" band per `scoring.md`). Its ledger/reconciler idea is not wasted — it is retained in this spec as **S-5 (Duplicate-charge detection & alerting)**, demoted from primary mechanism to a defense-in-depth safety net. **Re-open trigger:** none for primary-fix status; it remains permanently valuable as layer-3 defense-in-depth regardless.
- **H4 (remove automatic retries) — rejected outright.** It solves the stated problem by deleting the feature it lives in, which the mission's CONSTRAINTS explicitly rule out ("must not reduce retry recoverability for genuinely failed/transient-error payments"), trading a rare, preventable correctness bug for a guaranteed, permanent increase in failed-payment friction and support load (Alignment scored 4/10, the weakest dimension). No re-open trigger identified — this is a rejection on principle (scope mismatch with the ask), not on missing information.

---

## C — CONSTRUCT

**Hierarchy:**

```
THEME    Payment Correctness & Customer Trust
└─ PROJECT  P-1  Duplicate-Charge Prevention for Retry/Confirmation Races
   └─ FEATURE F-1  Idempotent, State-Guarded Payment Retry
      ├─ STORY S-1  Idempotency-key anchoring per payment intent
      ├─ STORY S-2  Atomic in-flight attempt-state guard
      ├─ STORY S-3  Reconcile-before-retry status query
      ├─ STORY S-4  Idempotent, state-aware confirmation ingestion
      ├─ STORY S-5  Duplicate-charge detection & alerting safety net
      ├─ STORY S-6  Deterministic race-reproduction regression suite
      └─ STORY S-7  Docs, runbook, and support-tooling alignment
```

All 7 stories pass INVEST (Independent within necessary sequencing, Negotiable on exact wording, Valuable to a named actor, Estimable at the timeboxes below, Small ≤3d each, Testable via the GIVEN/WHEN/THEN sets below).

**Execution sequence (dependency-ordered):**

```
Phase 1:  S-1
Phase 2:  S-2  ‖  S-4      (parallel — distinct call sites, both depend only on S-1)
Phase 3:  S-3  ‖  S-5      (parallel — S-3 depends on S-2's state model; S-5 depends only on S-1's settled-charge records)
Phase 4:  S-6              (exercises S-1–S-4 together; validated against S-3's reconciliation logic)
Phase 5:  S-7
```

---

#### 📋 STORY: S-1 Idempotency-key anchoring per payment intent

> 🔴 P0 — foundation

**Description:** As a payments engineer, I want every charge attempt for a given payment intent (original or retried) to carry a stable, intent-derived idempotency key so that the payment processor can deduplicate concurrent or repeated charge requests for the same intent.
**Timebox:** ≤2d
**Risk:** P0 (foundation — every other story depends on a well-defined intent/attempt identity)

**Action Plan:**
1. **Extend:** the payment-intent record with a persisted, immutable `idempotency_key` field derived deterministically from the intent ID at creation time — never per-attempt, never regenerated on retry.
2. **Modify:** every charge-issuance call site (original-attempt path and retry path) to pass this same key to the processor on every attempt for the same intent.
3. **Test:** issue two charge requests with the same idempotency key against a processor sandbox/mock and assert the processor returns the original result on the second call rather than creating a new charge.

**Acceptance Criteria:**
- [ ] GIVEN a payment intent is created WHEN its first charge attempt is issued THEN the request SHALL carry an idempotency key derived solely from the intent ID (no timestamp, nonce, or attempt-counter component)
- [ ] GIVEN a payment intent already has an idempotency key WHEN any subsequent attempt (retry, manual, or automated) is issued for the same intent THEN it SHALL reuse the identical key, never generate a new one
- [ ] GIVEN the processor receives two requests bearing the same idempotency key WHEN the second request arrives THEN the processor's own deduplication SHALL return the first request's result rather than creating a second charge (verified against processor sandbox behavior, not mocked assumption)

**Technical Context:**
- **Pattern:** idempotency-key-per-resource (Stripe "Idempotent Requests" family, Pattern phase 88% match)
- **Files:** `[ASSUMED — confirm against target repo]` `payments/intent.*` (intent model), `payments/processor_client.*` (outbound call wrapper)
- **Dependencies:** none (foundation story)

**Agent Hints:**
- **Class:** Builder
- **Context:** processor client wrapper, existing intent-creation code
- **Gates:** P0 — dedup behavior verified against a processor sandbox, not only unit-mocked

---

#### 📋 STORY: S-2 Atomic in-flight attempt-state guard

> 🔴 P0 — highest-risk story in this spec

**Description:** As a payments engineer, I want the system to atomically claim exclusive "in-flight" ownership of a payment intent before issuing any charge attempt (original or retry), so that two attempts can never be dispatched to the processor concurrently for the same intent.
**Timebox:** ≤3d
**Risk:** P0 (a missed call site or a non-atomic claim reintroduces the exact race this spec exists to close)

**Action Plan:**
1. **Create:** an attempt-state enum on the payment intent (`idle → in_flight → {confirmed, failed, superseded}`) with a single, atomic state-transition primitive (DB-level conditional update / unique constraint / `SELECT FOR UPDATE` — never an application-level check-then-act, which itself races).
2. **Modify:** every call site that issues a charge (original attempt, system-triggered retry, and per Scope Assumption 4, the support-tooling manual retry) to route through this claim primitive before contacting the processor; a call site that fails to claim (intent already `in_flight`) SHALL NOT issue a charge.
3. **Test:** a concurrent-claim test that fires two simultaneous claim attempts for the same intent under real concurrency (not sequential mocks) and asserts exactly one succeeds.

**Acceptance Criteria:**
- [ ] GIVEN a payment intent's state is `in_flight` WHEN any code path (retry, manual, or duplicate concurrent request) attempts to claim it for a new charge THEN the claim SHALL be rejected and no charge request SHALL be sent to the processor
- [ ] GIVEN two processes/threads attempt to claim the same idle payment intent at the same instant WHEN the atomic claim executes THEN exactly one SHALL succeed and the other SHALL observe the rejection deterministically, with no window in which both observe success
- [ ] GIVEN a support agent manually retries a payment intent via support tooling WHEN that intent is already `in_flight` THEN the manual retry SHALL be blocked by the same guard as an automated retry (no side-door bypass)
- [ ] GIVEN an `in_flight` intent's original attempt has not yet been positively confirmed as terminal (see S-3) THEN it SHALL NOT be eligible for reclaim on timeout alone — timeout is a trigger to *check*, never a trigger to *retry directly* (closes the Refine-cycle-1 finding below)

**Technical Context:**
- **Pattern:** optimistic-concurrency/CAS (Pattern phase 75% match) + outbox-style uniqueness constraint (80% match)
- **Files:** `[ASSUMED]` `payments/intent.*` (state enum + transition), `payments/retry_worker.*`, `support/tools/manual_retry.*`
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner + Explorer (an exhaustive call-site audit is the risk-critical step here — an ATLAS-equivalent scout pass to enumerate every existing charge-issuing call site before Builder wires the guard is strongly recommended)
- **Context:** every code path that can issue a charge, including support tooling
- **Gates:** P0 — 100% of known charge-issuing call sites verified routed through the claim primitive (mock/spy or integration-test coverage, not code review alone); concurrent-claim test passes under real thread/process concurrency

---

#### 📋 STORY: S-3 Reconcile-before-retry status query

> 🔴 P0

**Description:** As a payments engineer, I want a retry to actively query the processor for the original attempt's definitive status before claiming/firing, so that a merely-delayed confirmation is never mistaken for a failure.
**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Create:** a status-reconciliation call (query the processor by the intent's stable idempotency key or the original attempt's processor-side transaction reference) invoked whenever a retry is about to fire.
2. **Modify:** retry-trigger logic — on timeout T, instead of assuming failure, first reconcile; proceed to claim+retry (S-2) only if reconciliation confirms the original attempt is definitively terminal (failed/declined), never merely slow.
3. **Test:** simulate a delayed-but-eventually-successful original attempt (confirmation lands after T but before reconciliation completes) and assert no retry fires; simulate a genuinely failed original attempt and assert the retry proceeds normally.

**Acceptance Criteria:**
- [ ] GIVEN a retry is triggered by timeout T WHEN reconciliation queries the processor and finds the original attempt still pending (not yet terminal) THEN the retry SHALL be deferred, not fired, and re-checked on a backoff schedule
- [ ] GIVEN reconciliation finds the original attempt has, in fact, already succeeded (confirmation was merely delayed) THEN the system SHALL mark the intent confirmed from the original attempt and SHALL NOT fire a retry
- [ ] GIVEN reconciliation finds the original attempt has definitively failed/been declined by the processor THEN the retry SHALL proceed through S-2's claim guard as normal

**Technical Context:**
- **Pattern:** status-poll-before-act, complements idempotency-key dedup as defense-in-depth (Explore observation 3)
- **Files:** `[ASSUMED]` `payments/retry_worker.*`, `payments/processor_client.*` (status query method)
- **Dependencies:** S-1, S-2

**Agent Hints:**
- **Class:** Builder
- **Context:** processor client's status/lookup API, S-2's state enum
- **Gates:** P0 — the delayed-confirmation simulation test (the literal bug scenario from the mission) passes with zero retries fired

---

#### 📋 STORY: S-4 Idempotent, state-aware confirmation ingestion

> 🔴 P0

**Description:** As a payments engineer, I want the confirmation/webhook handler to transition intent state idempotently and to safely no-op (with an alert) when a confirmation arrives for an intent already resolved by another path, so that a late or duplicate confirmation delivery can never itself cause a double-settlement.
**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Modify:** the confirmation-ingestion handler to perform its state transition through the same atomic primitive as S-2 (`in_flight → confirmed`), guarded so a transition is only applied from a matching prior state.
2. **Create:** an explicit no-op + alert path for confirmations arriving against an intent already `confirmed` (duplicate delivery) or `superseded` (a retry's outcome already won and this is the original's late arrival) — logged and counted, never silently dropped and never re-applied as a second settlement.
3. **Test:** deliver the same confirmation webhook twice and assert a single settlement with the second delivery logged as a duplicate; deliver a confirmation for an intent already confirmed via a different attempt and assert no second settlement plus a recorded alert.

**Acceptance Criteria:**
- [ ] GIVEN a confirmation is received for an intent already in state `confirmed` THEN the handler SHALL treat it as a duplicate no-op and SHALL NOT create a second settlement record
- [ ] GIVEN a confirmation is received for an intent in state `superseded` (a retry already resolved it) THEN the handler SHALL record the event for reconciliation/audit and SHALL NOT settle a second charge
- [ ] GIVEN a confirmation is received for an intent in state `in_flight` matching the attempt it confirms THEN it SHALL be the only path that transitions the intent to `confirmed`

**Technical Context:**
- **Pattern:** idempotent event-handler / exactly-once effect via state-guarded transition
- **Files:** `[ASSUMED]` `payments/webhook_handler.*`, `payments/intent.*`
- **Dependencies:** S-1, S-2

**Agent Hints:**
- **Class:** Builder
- **Context:** existing webhook/confirmation ingestion code, S-2's state enum
- **Gates:** P0 — duplicate-delivery test and late/superseded-confirmation test both green

---

#### 📋 STORY: S-5 Duplicate-charge detection & alerting safety net

> 🟡 P1 — safety net, not a prevention control

**Description:** As a support/finance stakeholder, I want an automated monitor that detects if two successful charges ever settle against the same payment intent despite the guards above, so that any defense-in-depth failure is caught and remediated within minutes, not discovered by a customer dispute weeks later.
**Timebox:** ≤2d
**Risk:** P1 (does not itself prevent the bug; catches failures of the prevention controls S-1–S-4)

**Action Plan:**
1. **Create:** a scheduled reconciliation job querying for any payment intent with more than one settled/successful charge record.
2. **Configure:** alert routing (on-call/finance) when a duplicate is found, including the intent ID, both charge references, and amounts, to enable fast manual reversal.
3. **Test:** seed a duplicate-charge fixture directly at the data layer (bypassing the guards, to test the detector in isolation) and assert the job flags it within its scheduled interval.

**Acceptance Criteria:**
- [ ] GIVEN two settled charges exist for the same payment intent WHEN the detection job runs THEN it SHALL raise an alert identifying the intent and both charge references within one scheduled interval
- [ ] GIVEN zero or one settled charge exists for an intent WHEN the detection job runs THEN it SHALL NOT raise a false-positive alert
- [ ] GIVEN an alert is raised THEN it SHALL include enough data (intent ID, charge references, amounts, timestamps) for a human to action a reversal without further investigation

**Technical Context:**
- **Pattern:** retained from rejected H3 (event-sourced reconciliation), demoted from primary mechanism to defense-in-depth layer 3 (Explore rejection rationale)
- **Files:** `[ASSUMED]` `payments/reconciliation_job.*`
- **Dependencies:** S-1 (needs settled-charge records to query)

**Agent Hints:**
- **Class:** Builder
- **Context:** ledger/settlement records, existing alerting/on-call integration
- **Gates:** P1 — zero false positives in the test fixture; alert payload reviewed by a finance/support stakeholder

---

#### 📋 STORY: S-6 Deterministic race-reproduction regression suite

> 🔴 P0 — the mechanism that proves the "cannot recur" claim

**Description:** As a payments engineer, I want an automated test that deterministically reproduces the exact race described in this bug (retry timeout fires while the original attempt's confirmation is artificially delayed) so that the fix's non-recurrence claim is proven by a repeatable test, not just by code review.
**Timebox:** ≤2d
**Risk:** P0 — this story is the acceptance-proof mechanism itself, not a nice-to-have

**Action Plan:**
1. **Create:** a test harness that can inject an artificial delay into the confirmation-delivery path, spanning past the retry timeout T, while a test-double processor call is in flight.
2. **Create:** the specific regression scenario — issue the original attempt, delay its confirmation past T, allow the retry path to run against the guards from S-1–S-4, then release the delayed confirmation — and assert exactly one settled charge in every run.
3. **Test:** run the scenario against both the pre-fix code path (expected to fail, proving the test actually detects the bug) and the post-fix code path (expected to pass) — a test that cannot fail is not a valid regression proof.

**Acceptance Criteria:**
- [ ] GIVEN the race-reproduction harness delays confirmation past the retry timeout WHEN the retry path and the delayed confirmation both resolve THEN the test SHALL assert exactly one settled charge for the intent, on every run (no flaking tolerated on this specific assertion)
- [ ] GIVEN the same harness is run against the pre-fix code path (a one-time falsification check performed during implementation) THEN it SHALL reproduce two settled charges, proving the test is sensitive to the actual bug and not a tautology
- [ ] GIVEN this suite exists WHEN it runs in CI THEN it SHALL be included in the release-blocking gate for any future change touching the payment retry, confirmation, or claim-guard code paths

**Technical Context:**
- **Pattern:** fault-injection / deterministic concurrency-race test
- **Files:** `[ASSUMED]` test suite alongside `payments/*`, a fake/mock processor client supporting delay injection
- **Dependencies:** S-1, S-2, S-3, S-4 (exercises all of them together)

**Agent Hints:**
- **Class:** Reasoner (designing a deterministic-yet-realistic concurrency test is the hard part) + Reviewer (a skeptical second read on whether the harness truly reproduces the race, not a weaker approximation)
- **Context:** all of S-1–S-4's implementations
- **Gates:** P0 — CI-gating; the pre-fix falsification check is documented in the implementation PR

---

#### 📋 STORY: S-7 Docs, runbook, and support-tooling alignment

> 🟢 P2

**Description:** As an on-call engineer or support agent, I want the new attempt-state model, guard behavior, and alert semantics documented so that I can interpret a "claim rejected" log line or a duplicate-charge alert without reading the implementation.
**Timebox:** 1d
**Risk:** P2 (cosmetic/discoverability — does not block core functionality)

**Action Plan:**
1. **Modify:** the payments runbook with the new state machine, what each terminal/no-op case means, and how to respond to an S-5 alert.
2. **Modify:** support-tooling documentation/UI copy to reflect that manual retry can now be rejected by the guard, and what that means for the agent.
3. **Modify:** CHANGELOG with the fix summary and a note that the regression suite (S-6) exists and must stay green.

**Acceptance Criteria:**
- [ ] GIVEN the fix ships WHEN the payments runbook is reviewed THEN it SHALL document the attempt-state machine and the response procedure for an S-5 duplicate-charge alert
- [ ] GIVEN a support agent's manual retry is rejected by the guard THEN the tooling SHALL surface a clear, actionable message (not a raw error) explaining why
- [ ] GIVEN the changelog is updated THEN it SHALL reference the regression suite (S-6) so future reviewers know a race-reproduction test exists and must stay green

**Technical Context:**
- **Pattern:** n/a — documentation story
- **Files:** `[ASSUMED]` payments runbook, support-tooling UI copy, `CHANGELOG.md`
- **Dependencies:** S-1, S-2, S-3, S-4, S-5, S-6 (documents final, shipped behavior)

**Agent Hints:**
- **Class:** Scriber (IDG-equivalent, per this project's wired Eidolons roster)
- **Context:** final behavior from S-1–S-6
- **Gates:** P2 — reviewed by the support lead and the runbook owner

---

## T — TEST (6-layer verification)

| # | Layer | Result |
|---|---|---|
| 1 | **Structural** | ✓ Hierarchy intact (Theme→Project→Feature→Story), no orphaned tasks, stories independent modulo the documented sequencing |
| 2 | **Self-Consistency** | ✓ See below — 3 alternative decompositions, ~75% overlap → HIGH confidence, stable |
| 3 | **Dependency** | ⚠ Partial — real charge-issuing call sites, the webhook handler, and support tooling cannot be enumerated against a real codebase (G1); RC3 (webhook-ordering bug) also cannot be ruled out without real logs/traces. Both flagged, not silently assumed complete. Migration path: none needed (additive guard + new enum column, no destructive schema change) |
| 4 | **Constraint** | ✓ Timeboxes realistic (all ≤3d); NFR "no added latency on the common path" addressed (S-2's claim is a single conditional write on the existing path; S-3's reconciliation fires only on the retry path); security/compliance: no new cardholder data touched, only intent/state metadata — flagged as an assumption to confirm, not independently verified |
| 5 | **Process Reward** | ✓ Ordering (key identity → guard/ingestion → reconcile → proof harness → detection safety net → docs) monotonically reduces risk: the two mechanisms that most directly close the described race (S-2, S-3) land before the proof harness (S-6) that verifies them, and the safety net (S-5) lands to catch anything the primary mechanisms miss, before docs |
| 6 | **Adversarial** | ✓ See checklist below |

**Self-Consistency check (3 alternative decompositions):**

- **Decomposition A (this spec):** key-anchoring / claim-guard / reconcile / confirmation-idempotency / detection / regression-harness / docs — 7 stories, grouped by feature slice.
- **Decomposition B:** "Prevention core" (merges S-1+S-2+S-3+S-4) / "Safety net" (S-5) / "Proof" (S-6) / docs (S-7) — 4 stories, same concepts regrouped by control-type.
- **Decomposition C:** grouped by system surface — "Intent/state model" (S-1+S-2) / "Confirmation ingestion" (S-4) / "Retry trigger" (S-3) / "Observability" (S-5+S-6) / docs (S-7) — 5 stories, a different axis entirely.

All three surface the same underlying concepts (stable key identity, atomic guard, reconcile-before-retry, idempotent confirmation handling, detection safety net, proof harness, docs) — estimated **~75% story-content overlap** → **HIGH confidence** (clears the ≥70% bar), decomposition is stable. Decomposition A was kept because P0/P1/P2 risk tags and dependency ordering map more cleanly onto feature slices than onto control-type or system-surface groupings.

**Adversarial checklist (Failure Taxonomy, `scoring.md`):**

| Failure mode | Checked | Finding |
|---|---|---|
| Under-specification | ✓ | S-2's original draft framed "declare an attempt dead" purely by timeout — circular, since that's the same judgment call that caused the bug. Fixed in Refine below. |
| Over-specification | ✓ | No rigid constraint blocks a valid implementation; file paths marked `[ASSUMED]`, not mandated |
| Dependency blindness | ⚠ | Real call-site enumeration and RC3's webhook-ordering question are both unknown (G1, RC3) — mitigated by S-2's mandatory Explorer pass and by explicitly scoping RC3 out of this fix rather than silently assuming it's covered |
| Assumption drift | — | No earlier-phase discovery yet invalidates a later step; re-open triggers documented for RC2/RC3/RC4 and for H2 if target infra differs |
| Scope creep | ✓ | Boundary table enforced; historical-customer remediation and processor migration explicitly kept out; H2/H3 architectures kept out of the primary mechanism |
| Premature optimization | ✓ | Complexity 11/12 justified extended thinking + human-in-the-loop, not over-engineering; H3 (most "sophisticated") was correctly demoted to a safety-net role rather than adopted wholesale |
| Stale context | n/a | No prior file reads to go stale; this is a fresh cycle |

**Gate:** one real under-specification finding (S-2's dead-vs-slow ambiguity) plus the recurring dependency-layer/adversarial ⚠ (same root cause: unknown target repo, plus RC3's unresolved status) → **Refine (1 cycle).**

---

## R — REFINE

**Cycle 1 diagnosis:** Test surfaced that S-2's original draft treated "claim rejected because the intent looks stuck" as resolvable by timeout alone — which is circular: it is the same timeout-vs-slow-confirmation judgment call that caused the original bug, merely relocated inside the guard instead of at the retry trigger.

**Root cause:** both S-2 and S-3 were drafted with an implicit boundary ("timeout means dead") that this entire spec exists to disprove. The fix only works if the *only* way an `in_flight` intent becomes eligible for a new attempt is a **positive reconciliation signal** (S-3), never a timeout by itself.

**Prescription (applied):** added an explicit acceptance criterion to S-2 (AC #4) stating that timeout alone SHALL NOT make an intent reclaimable — only S-3's reconciliation can. This closes the circularity and gives S-6's regression harness an unambiguous transition to assert against. (Already reflected in the Construct section above — this log records the diagnose→fix→re-verify pass that produced it.)

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | unchanged — no clarity issue found |
| Completeness | 3 | 4 | dead-vs-slow ambiguity in S-2 now closed by an explicit AC tying reclaim eligibility to S-3's reconciliation |
| Actionability | 3 | 4 | an implementing agent no longer has to guess how "genuinely failed" is determined |
| Efficiency | 4 | 4 | unchanged |
| Testability | 3 | 4 | S-6's regression scenario now has one unambiguous state transition to assert against, not an implicit timeout heuristic |

**Mean:** 3.4 → 4.0 (**+0.6**, above the 0.3 diminishing-returns floor — this cycle earned its keep). **No dimension decreased** — no oscillation. **Cycle 1 target (all ≥3) met and exceeded (all ≥4); stopping at 1 cycle** rather than continuing to a cycle whose marginal gain would likely fall under the diminishing-returns threshold.

**Re-verify:** re-ran the Structural/Constraint/Adversarial layers against the updated S-2/S-3 — no new gaps introduced, no prior pass invalidated.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (/3) | Basis |
|---|---|---|
| Pattern Match | 2 | Strong, well-established external pattern family (idempotency key + CAS + reconciliation), but no in-repo template exists to apply directly (G1) |
| Requirement Clarity | 2 | The mission's fix-quality bar ("cannot recur") is unambiguous; which root-cause variant (RC1–RC4) actually applies, and the target system's specifics, are not — bounded by explicit risk-tagged assumptions rather than left open |
| Decomposition Stability | 3 | ~75% self-consistency overlap across 3 alternative decompositions — clears the ≥70% HIGH bar |
| Constraint Compliance | 2 | 6-layer Test passed with a real under-specification finding (closed by Refine) plus a persistent dependency-layer gap (unknown real repo, unresolved RC3) — solid but not flawless |

**Weighted Confidence:** (2+2+3+2)/12 × 100 = **75%**

**Decision: VALIDATE (70–84% band) — deliver with flags, human reviews.**

**Additional flag beyond the standard gate:** complexity scored 11/12 (Scope phase), which independently falls in the 10–12 "human collaboration recommended" band. This is a compounding signal, not a contradiction — VALIDATE governs *spec delivery* (this document is decision-ready to hand to a human reviewer now), while the complexity-band guidance governs *implementation sign-off* (a payments engineer and a second reviewer should sign off on S-2's atomicity design specifically, given financial-correctness stakes, before Builder starts). Given this is a money-correctness defect, treat the complexity flag as effectively mandatory, not optional.

**What a human reviewer should specifically validate before this becomes AUTO_PROCEED-worthy:**
1. Confirm which root-cause variant actually applies (RC1 vs. RC2 vs. RC3 vs. RC4) against real logs/traces — RC3 in particular (a webhook-ordering/ledger bug) would need a different fix than S-1–S-4 provide, and cannot be ruled out from this spec-only exercise.
2. Confirm the real target repo, payment processor, and whether idempotency keys are already in use today (CLARIFY G2) — this affects S-1's actual delta (retrofitting a key vs. fixing its derivation).
3. Re-anchor every `[ASSUMED]` file path in Construct against the actual codebase (an Explorer/ATLAS pass is recommended specifically for S-2's call-site enumeration, given it is the highest-risk story in this spec).
4. Decide and separately track the customer-remediation/refund workflow for already-affected historical customers (explicitly out of scope here, but should not be silently dropped — Scope boundary table).

### Deliverables produced (dual-format contract + ECL sidecar)

| Artifact | Path |
|---|---|
| Plan artifact (this file) | `/tmp/ramza-s2/ac003/AB-T3-spectra-r1.out.md` (requested output path — explicit override, honored) |
| Authoritative mirror (Output Discipline rule 2) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-retry-race-fix.md` |
| Agent handoff (YAML) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-retry-race-fix.yaml` |
| State machine (JSON) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-retry-race-fix.state.json` |
| ECL v2.0 envelope sidecar | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-payment-retry-race-fix.md.envelope.json` (emitted because `ECL_VERSION=2.0` is present at `/tmp/spectra-pilot/.eidolons/spectra/ECL_VERSION`) |

Per Output Discipline rule 2: since the mission explicitly named a path outside `.spectra/`, that path was honored as the primary deliverable, and the authoritative copy was mirrored under `.spectra/plans/` regardless, together with the full Assemble deliverable set (YAML handoff, state JSON, ECL envelope) that a SPECTRA Assemble phase produces per `SPEC.md` and `skills/planning.md`.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 75
  complexity: 11
  spectra_version: "4.11.0"
  thread_id: "019f326b-5641-708e-8281-a280b88154f7"

projects:
  - id: "P-1"
    name: "Duplicate-Charge Prevention for Retry/Confirmation Races"
    features:
      - id: "F-1"
        name: "Idempotent, State-Guarded Payment Retry"
        stories:
          - id: "S-1"
            title: "Idempotency-key anchoring per payment intent"
            timebox: "<=2d"
            risk: "P0"
            action_plan:
              - verb: "Extend"
                target: "payment intent: persisted, immutable idempotency_key derived from intent ID"
              - verb: "Modify"
                target: "every charge-issuance call site to reuse the same key on every attempt"
              - verb: "Test"
                target: "processor-sandbox dedup verification on repeated identical-key requests"
            acceptance_criteria:
              - given: "a payment intent is created"
                when: "its first charge attempt is issued"
                then: "the request carries an idempotency key derived solely from the intent ID"
              - given: "a payment intent already has an idempotency key"
                when: "any subsequent attempt is issued for the same intent"
                then: "it reuses the identical key, never generates a new one"
              - given: "the processor receives two requests with the same idempotency key"
                when: "the second request arrives"
                then: "the processor's dedup returns the first result rather than creating a second charge"
            agent_hints:
              recommended_class: "builder"
              context_files: ["payments/intent.* [ASSUMED]", "payments/processor_client.* [ASSUMED]"]
              validation_gates:
                p0: "dedup verified against processor sandbox"
          - id: "S-2"
            title: "Atomic in-flight attempt-state guard"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "attempt-state enum + atomic transition primitive (idle->in_flight->{confirmed,failed,superseded})"
              - verb: "Modify"
                target: "every charge-issuing call site (original, system retry, manual retry) to route through the claim"
              - verb: "Test"
                target: "real-concurrency dual-claim test asserting exactly one winner"
            acceptance_criteria:
              - given: "a payment intent's state is in_flight"
                when: "any code path attempts to claim it for a new charge"
                then: "the claim is rejected and no charge request is sent to the processor"
              - given: "two processes attempt to claim the same idle intent simultaneously"
                when: "the atomic claim executes"
                then: "exactly one succeeds, the other observes rejection deterministically"
              - given: "a support agent manually retries an in_flight intent"
                then: "the manual retry is blocked by the same guard as an automated retry"
              - given: "an in_flight intent has not been positively confirmed as terminal"
                then: "it is not reclaimable on timeout alone; only reconciliation (S-3) can make it reclaimable"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["payments/intent.* [ASSUMED]", "payments/retry_worker.* [ASSUMED]", "support/tools/manual_retry.* [ASSUMED]"]
              validation_gates:
                p0: "100% of known charge-issuing call sites verified routed through the claim primitive; concurrent-claim test passes under real concurrency"
          - id: "S-3"
            title: "Reconcile-before-retry status query"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1", "S-2"]
            action_plan:
              - verb: "Create"
                target: "processor status-reconciliation query keyed by idempotency key / transaction reference"
              - verb: "Modify"
                target: "retry trigger to reconcile before firing instead of assuming failure on timeout"
              - verb: "Test"
                target: "delayed-but-successful original attempt simulation asserting zero retries fired"
            acceptance_criteria:
              - given: "a retry is triggered by timeout T"
                when: "reconciliation finds the original attempt still pending"
                then: "the retry is deferred and re-checked on a backoff schedule"
              - given: "reconciliation finds the original attempt already succeeded"
                then: "the intent is marked confirmed from the original attempt and no retry fires"
              - given: "reconciliation finds the original attempt definitively failed"
                then: "the retry proceeds through S-2's claim guard as normal"
            agent_hints:
              recommended_class: "builder"
              context_files: ["payments/retry_worker.* [ASSUMED]", "payments/processor_client.* [ASSUMED]"]
              validation_gates:
                p0: "delayed-confirmation simulation (the literal bug scenario) passes with zero retries fired"
          - id: "S-4"
            title: "Idempotent, state-aware confirmation ingestion"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1", "S-2"]
            action_plan:
              - verb: "Modify"
                target: "confirmation handler to transition state via S-2's atomic primitive, guarded by prior state"
              - verb: "Create"
                target: "no-op + alert path for confirmations against already-confirmed or superseded intents"
              - verb: "Test"
                target: "duplicate-delivery and late/superseded-confirmation scenarios"
            acceptance_criteria:
              - given: "a confirmation is received for an intent already confirmed"
                then: "it is treated as a duplicate no-op, no second settlement is created"
              - given: "a confirmation is received for a superseded intent"
                then: "it is recorded for audit and no second charge is settled"
              - given: "a confirmation matches an in_flight attempt"
                then: "it is the only path that transitions the intent to confirmed"
            agent_hints:
              recommended_class: "builder"
              context_files: ["payments/webhook_handler.* [ASSUMED]", "payments/intent.* [ASSUMED]"]
              validation_gates:
                p0: "duplicate-delivery test and late/superseded-confirmation test both green"
          - id: "S-5"
            title: "Duplicate-charge detection & alerting safety net"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "scheduled job detecting intents with more than one settled charge"
              - verb: "Configure"
                target: "alert routing with intent ID, charge references, and amounts"
              - verb: "Test"
                target: "seeded duplicate-charge fixture flagged within one scheduled interval"
            acceptance_criteria:
              - given: "two settled charges exist for the same intent"
                then: "an alert is raised within one scheduled interval identifying both charges"
              - given: "zero or one settled charge exists for an intent"
                then: "no false-positive alert is raised"
              - given: "an alert is raised"
                then: "it includes enough data for a human to action a reversal without further investigation"
            agent_hints:
              recommended_class: "builder"
              context_files: ["payments/reconciliation_job.* [ASSUMED]"]
              validation_gates:
                p1: "zero false positives in test fixture; alert payload reviewed by finance/support"
          - id: "S-6"
            title: "Deterministic race-reproduction regression suite"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1", "S-2", "S-3", "S-4"]
            action_plan:
              - verb: "Create"
                target: "delay-injection harness for the confirmation-delivery path"
              - verb: "Create"
                target: "race scenario: delay confirmation past T, run retry path, release confirmation, assert single settlement"
              - verb: "Test"
                target: "pre-fix falsification (must fail) and post-fix confirmation (must pass)"
            acceptance_criteria:
              - given: "confirmation is delayed past the retry timeout"
                when: "the retry path and delayed confirmation both resolve"
                then: "exactly one settled charge exists, on every run"
              - given: "the harness runs against the pre-fix code path"
                then: "it reproduces two settled charges, proving test sensitivity"
              - given: "this suite exists"
                then: "it is included in the release-blocking CI gate for retry/confirmation/guard changes"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["payments/* [ASSUMED, all of S-1-S-4]"]
              validation_gates:
                p0: "CI-gating; pre-fix falsification check documented in the PR"
          - id: "S-7"
            title: "Docs, runbook, and support-tooling alignment"
            timebox: "1d"
            risk: "P2"
            dependencies: ["S-1", "S-2", "S-3", "S-4", "S-5", "S-6"]
            action_plan:
              - verb: "Modify"
                target: "payments runbook: state machine + S-5 alert response procedure"
              - verb: "Modify"
                target: "support-tooling copy: explain guard-rejected manual retries"
              - verb: "Modify"
                target: "CHANGELOG: fix summary + regression suite reference"
            acceptance_criteria:
              - given: "the payments runbook is reviewed"
                then: "it documents the state machine and the S-5 alert response procedure"
              - given: "a support agent's manual retry is rejected"
                then: "the tooling surfaces a clear, actionable message"
              - given: "the changelog is updated"
                then: "it references the regression suite (S-6)"
            agent_hints:
              recommended_class: "scriber"
              context_files: ["CHANGELOG.md", "payments runbook [ASSUMED]"]
              validation_gates:
                p2: "reviewed by support lead and runbook owner"

execution_plan:
  phases:
    - name: "Phase 1 — Foundation"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Phase 2 — Guard + confirmation (parallel)"
      stories: ["S-2", "S-4"]
      agent_class: "reasoner+builder"
    - name: "Phase 3 — Reconciliation + safety net (parallel)"
      stories: ["S-3", "S-5"]
      agent_class: "builder"
    - name: "Phase 4 — Proof"
      stories: ["S-6"]
      agent_class: "reasoner"
    - name: "Phase 5 — Docs"
      stories: ["S-7"]
      agent_class: "scriber"
```

### State Machine (JSON)

```json
{
  "session_id": "019f326b-5641-7a33-8e76-10d83cedf96f",
  "spec_id": "SPEC-2026-07-05-001",
  "goal": "Eliminate the race between a payment retry and the original attempt's delayed confirmation so no payment intent is ever settled by more than one successful charge.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Idempotency-key anchoring per payment intent", "status": "pending", "dependencies": [], "files_affected": ["payments/intent.* [ASSUMED]", "payments/processor_client.* [ASSUMED]"], "verification_command": "test: processor-sandbox dedup on repeated identical-key requests", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Atomic in-flight attempt-state guard", "status": "pending", "dependencies": [1], "files_affected": ["payments/intent.* [ASSUMED]", "payments/retry_worker.* [ASSUMED]", "support/tools/manual_retry.* [ASSUMED]"], "verification_command": "test: real-concurrency dual-claim, exactly-one-winner assertion", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Reconcile-before-retry status query", "status": "pending", "dependencies": [1, 2], "files_affected": ["payments/retry_worker.* [ASSUMED]", "payments/processor_client.* [ASSUMED]"], "verification_command": "test: delayed-confirmation simulation, zero retries fired", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Idempotent, state-aware confirmation ingestion", "status": "pending", "dependencies": [1, 2], "files_affected": ["payments/webhook_handler.* [ASSUMED]", "payments/intent.* [ASSUMED]"], "verification_command": "test: duplicate-delivery + late/superseded-confirmation", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Duplicate-charge detection & alerting safety net", "status": "pending", "dependencies": [1], "files_affected": ["payments/reconciliation_job.* [ASSUMED]"], "verification_command": "test: seeded duplicate-charge fixture flagged within interval", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Deterministic race-reproduction regression suite", "status": "pending", "dependencies": [1, 2, 3, 4], "files_affected": ["payments/* [ASSUMED]"], "verification_command": "test: pre-fix falsification + post-fix single-settlement assertion", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Docs, runbook, and support-tooling alignment", "status": "pending", "dependencies": [1, 2, 3, 4, 5, 6], "files_affected": ["CHANGELOG.md", "payments runbook [ASSUMED]"], "verification_command": "manual: support lead + runbook owner review", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "phase": "Refine",
      "diagnosis": "S-2 originally allowed timeout alone to make an in_flight intent reclaimable, which is circular with the root cause (timeout-vs-slow-confirmation ambiguity)",
      "fix_applied": "added S-2 AC #4: reclaim eligibility requires S-3's positive reconciliation, never timeout alone",
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
- [x] Complexity scored (11/12), extended-thinking budget routed, human-collaboration flag raised
- [x] 4 genuinely distinct fix hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing)
- [x] All 7 stories pass INVEST
- [x] All timeboxes valid (1d/≤2d/≤3d only, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this file) + structured YAML/JSON (embedded above + mirrored as separate files)
- [x] Confidence score present with factor breakdown (75%, VALIDATE, plus complexity-band human-collaboration flag)
- [x] Plan saved as artifact at the requested path + mirrored under `.spectra/plans/`
- [x] Every mirrored/derived output path starts with `.spectra/`
- [x] No code produced — plans only
- [x] Root-cause hypothesis documented (RC1 primary, RC2/RC3/RC4 considered and dispositioned)
- [x] Rejected alternatives documented (H2, H3, H4 — three, exceeding the "at least one" requirement)
- [x] Regression scope explicit (Test layer 3 + 4, Scope boundary table, S-2/S-6 call-site and side-channel coverage)
- [x] Acceptance criteria proving non-recurrence present (S-2 AC #4, S-3 all ACs, S-6 all ACs — the deterministic falsification-then-confirmation harness)

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*

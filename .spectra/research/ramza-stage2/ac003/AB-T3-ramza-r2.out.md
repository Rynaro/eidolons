---
eidolon: ramza
kind: spec
version: 0.2.0
created_at: 2026-07-05T13:18:41Z
plan: ac003-t3-r2
status: ready-for-apivr
target_repos: ["payments-service"]
stories_count: 4
validation_gates_count: 12
confidence: 0.775
---

# FIX: Payment retry races the original attempt's delayed confirmation, causing double charges

## Scope

Intent class: BUG_SPEC

In: The charge-submission path (original attempt + retry), the confirmation
(webhook/callback) handler, and the persistence layer backing them, for the
single defect: a retried charge attempt can complete and settle an order
before the original attempt's own delayed confirmation is processed, and
today nothing prevents both from independently recording a successful
charge. This spec covers making that pair of writers mutually exclusive at
the storage layer, propagating one idempotency identity across retry and
confirmation, and the migration/observability needed to ship that safely.

Out: Refunding or crediting customers already double-charged by this defect
historically (a remediation/backfill workflow, not a prevention mechanism —
noted under Deferred). Redesigning the retry scheduler's backoff/timeout
policy in general. Any change to the customer-facing checkout UI. Switching
payment gateway providers. General idempotency-key support for non-charge
endpoints (refunds, payouts) — out of scope for this fix, though the same
pattern would apply.

Deferred: A reconciliation/backfill job to detect and refund pre-existing
duplicate charges from before this fix ships. This is a real and necessary
follow-up (see Risks), but it is a remediation of past harm, not a
prevention mechanism — bundling it here would blur "cannot recur going
forward" (this spec's job) with "clean up what already happened" (a
separate, lower-urgency spec once this fix is live).

Assumptions:
- No real payments codebase exists in this sandbox project to confirm exact
  module names, ORM/schema field names, or which payment gateway SDK is in
  use (this consumer project ships no payments implementation today, the
  same situation `ab1-dryrun`/`ab2-dryrun` document for the deploy command).
  Illustrative paths below (`src/payments/*`, `spec/payments/*`, etc.) stand
  in for the real ones. Risk if wrong: an executor must confirm real file
  boundaries before Story 1 starts; reflected honestly in Confidence's low
  `pattern_match` score below, not papered over.
- The payment gateway in use supports a client-supplied idempotency token on
  charge-creation calls (the Stripe/Adyen/Braintree-style contract). Risk if
  wrong: if the gateway has no such primitive, Story 1's step 4 (gateway-level
  dedup) is not achievable as specified, and the fix's guarantee would rest
  on the internal DB constraint alone (Story 3) — still correct, but the
  external double-submission surface (a retry that races past the internal
  guard due to a bug) would no longer have a second line of defense. This is
  the single highest-leverage assumption to confirm before implementation.
- "Delayed confirmation" arrives through an asynchronous channel (webhook or
  polling callback) that is architecturally decoupled from the synchronous
  charge-submission call — i.e., the original attempt's HTTP call to the
  gateway can return before, after, or independently of the confirmation
  event. Risk if wrong: if confirmation is actually always synchronous with
  the charge call, the race described here cannot exist as characterized,
  and the actual defect would need re-diagnosis at Scope (this would be a
  [GAP] surfaced back to the human, not assumed away).
- The retry scheduler currently either mints a fresh identity per retry
  attempt or does not durably persist the one it uses in a way the storage
  layer can enforce. Risk if wrong: if the system already carries a durable
  per-order idempotency identity end-to-end and the bug is elsewhere (e.g. a
  missing DB constraint despite a correct key), Story 1 narrows to just
  Story 3 (the constraint) plus verifying key propagation, which is a subset
  of this plan, not a contradiction of it.

### Regression scope

Touched (in declared scope, see Assemble): the charge-submission code path
(original + retry), the confirmation/webhook handler, the charges/ledger
table schema (new column + index via migration), the retry scheduler's
key-propagation logic, and new observability on constraint rejections.

Must NOT change (explicit non-regression bar an executor and reviewer both
check): the happy-path customer-visible response for a normal, non-raced,
single-attempt charge (AC-008); the refund flow and its interaction with a
settled charge; reporting/reconciliation totals for historical (pre-fix)
transactions; the retry scheduler's backoff timing and eligibility rules for
charges that genuinely and legitimately failed (as opposed to being
in-flight); and any external API contract already published to merchants or
partner integrators for the charge-creation endpoint's request shape (only
the internal dedup behavior changes; the public request/response shape is
unchanged unless a follow-up spec chooses to document idempotency-key usage
externally, which is out of scope here).

Complexity (`ramza-score --rubric complexity`): 10/12 → human_loop (scope 3,
ambiguity 2, dependencies 2, risk 3 — recorded in
`.spectra/plans/ac003-t3-r2.state.json` gates[], label
`ac003-t3-r2-scope-complexity`). This routing signal is taken at face value,
not downplayed: a financial double-charge defect touching retry scheduling,
webhook handling, and a schema migration legitimately warrants a human in
the loop before implementation begins — this spec is written to be
decision-ready for that review, not to bypass it.

## Approach

**Root-cause hypothesis:** the retry path and the original attempt's
delayed-confirmation path are two independent writers, and nothing today
binds them to one storage-enforced identity for "this logical charge
attempt." Concretely: the original attempt is submitted to the gateway; the
gateway's confirmation is delivered asynchronously (a webhook or polling
callback) and is slow relative to the retry policy's timeout; the retry
fires before that confirmation lands, because the retry scheduler's
eligibility check only asks "has the timeout elapsed," never "is a
confirmation for this exact attempt still outstanding." The retry then
submits what the system treats as a new charge attempt. Both the retry and
the original attempt's late-arriving confirmation can now independently
reach "record a successful charge" — a time-of-check/time-of-use race
between the retry's decision to submit and the original attempt's
not-yet-processed outcome. Nothing at the database layer stops two
successful charge rows from existing for the same logical order/attempt,
because uniqueness, if enforced at all today, is enforced only in
application logic that the race sidesteps by definition (two concurrent code
paths, not one).

**Selected approach: Hyp A — idempotency-key identity propagated across
retry and confirmation, enforced by a database-level uniqueness constraint**
(`ramza-score --rubric explore` total 85.5 → elite; see Rejected
Alternatives for the three hypotheses this beat). The fix makes "at most one
successful charge per logical attempt" a storage-layer invariant instead of
an application-logic hope:

1. Generate exactly one idempotency key per logical charge attempt, at the
   moment the attempt is first created — not per HTTP call (AC-001).
2. Thread that same key through the retry scheduler: a retry for an
   order/attempt that hasn't reached a terminal state reuses the original
   key rather than minting a new one (AC-002).
3. Before any gateway call, look up an existing row for that key. A terminal
   row short-circuits the call and returns its result; a pending row blocks
   a second submission rather than racing it (AC-004, AC-005).
4. Pass the same key to the payment gateway as its native idempotency token,
   so a submission that somehow reaches the gateway twice is deduplicated
   there too — a second line of defense outside this system's own database
   (AC-003). The internal lookup in step 3 is itself independently verified:
   a terminal row short-circuits and returns its result *before* any call
   reaches the gateway at all (AC-011) — distinct from AC-003's gateway-side
   dedup and AC-005's concurrent-insert resolution, since a bug in the
   pre-call lookup would otherwise go untested even if both of those pass.
5. Change the confirmation handler from "insert a charge row on confirm" to
   "find-or-update the row for this idempotency key" — idempotent by
   construction, safe to run once or twice, so a delayed original
   confirmation arriving after a retry already settled the order reconciles
   against the same row instead of creating a second one (AC-006), and a
   redelivered webhook for an already-terminal charge is a logged no-op
   (AC-007).
6. Enforce the invariant with a real uniqueness constraint on
   `(order_id, idempotency_key)` in the charges/ledger table (AC-004),
   shipped through a zero-downtime migration: add the column → dual-write it
   from application code → backfill historical rows in batches, assigning
   each legacy row a synthesized key guaranteed collision-free per
   `(order_id, idempotency_key)` before the index is applied (AC-012) → add
   the unique index without blocking writes → tighten to `NOT NULL` once
   fully backfilled (AC-009).
7. Make every constraint rejection observable — a structured event, not a
   swallowed exception — so the fix's effectiveness is monitored rather than
   assumed (AC-010).

This is deliberately the *conservative, pattern-leveraging* choice: an
industry-standard idempotency-key + unique-constraint design (the same shape
Stripe, Adyen, and most payment processors expose to their own callers),
not a novel architecture. The guarantee that matters — "the double charge
cannot recur" — rests on the database's uniqueness constraint, a hard
invariant, not on any single code path being bug-free. Even if the
application-level idempotency check above has a bug and lets a race through
to two concurrent insert attempts, AC-005 shows the constraint itself is the
backstop that lets only one succeed.

## Stories

### Story 1: Enforce idempotent charge submission at the point of retry

As a payments engineer, I want every charge attempt — original or retried —
to submit through a single idempotency-key-guarded path, so that a retry
racing the original attempt's confirmation can never create a second
successful charge.

Timebox: 5d.
Risk tag: P0.
Executor hint: mid tier (Sonnet-class) — file-level action plan: (1)
generate/derive one idempotency key per logical charge attempt at creation
time, scoped to the order + attempt, not per HTTP call; (2) thread that key
through the retry scheduler so a scheduled retry reuses it instead of
minting a new one; (3) before calling the gateway, look up an existing
charge row for that key — terminal result short-circuits and returns it
*before* any gateway call is made, pending result blocks a second gateway
call; (4) pass the key to the gateway client as its native idempotency
token. Covers AC-001, AC-002, AC-003, AC-005, AC-011.

### Story 2: Make confirmation handling idempotent against duplicate and late arrivals

As an on-call engineer, I want the confirmation handler to reconcile against
the existing charge row by idempotency key rather than inserting a new
charge on every callback, so that a delayed original confirmation arriving
after a retry already settled the order cannot create a duplicate, and a
redelivered webhook cannot either.

Timebox: 3d.
Risk tag: P0.
Executor hint: mid tier — action plan: change confirmation handling from
insert-on-confirm to find-or-update-by-idempotency-key; make the update
itself safe to apply more than once; a redelivered/duplicate webhook for an
already-terminal charge becomes a logged no-op rather than a write attempt.
Covers AC-006, AC-007, AC-008 (regression: a normal single-attempt charge's
confirmation path is unchanged in observable outcome).

### Story 3: Ship the uniqueness constraint via a zero-downtime migration

As a database owner, I want a backward-compatible migration that adds an
`idempotency_key` column and a unique index on `(order_id, idempotency_key)`
with a safe backfill for existing rows, so the guarantee is enforced by the
storage layer — not only by application code that could itself have a bug.

Timebox: 2d (implementation and deploy-code authoring effort only — writing
the migration, the dual-write, and the backfill batch job. Backfill
wall-clock duration is not included: it scales with table size, runs
asynchronously in production in batches, and is tracked as a rollout task
rather than part of this timebox; see Risks for the exposure window this
creates).
Risk tag: P1.
Executor hint: mid tier — explicit steps required given the migration-tier
risk: add nullable column → deploy application code that dual-writes it
going forward → backfill historical rows in batches, synthesizing a
collision-free key per legacy row (AC-012) → add the unique index without
blocking writes (e.g. `CREATE INDEX CONCURRENTLY` or engine equivalent) once
backfill completes → tighten the column to `NOT NULL` only after 100%
backfill confirmed. Deploy ordering matters: application code that
populates the column must ship before the unique index goes live, or the
index creation will fail against un-backfilled rows. Covers AC-004, AC-009,
AC-012.

### Story 4: Make prevented duplicates observable

As an on-call engineer, I want every uniqueness-constraint rejection to emit
a structured event, so the fix's effectiveness is monitored rather than
assumed, and any unexpected spike pages someone instead of silently
protecting revenue in the dark.

Timebox: 1d.
Risk tag: P1.
Executor hint: mid tier — emit a structured log/metric on every rejected
duplicate insert, tagged with order_id and idempotency_key; wire a basic
alert on any non-zero rate immediately after launch (a real race being
caught for the first time is the expected initial signal, not noise).
Covers AC-010.

## Acceptance Criteria

`ramza-ears-lint` result: `ok: 12 criteria pass EARS lint` against the
frozen criteria file (`.spectra/plans/ac003-t3-r2.acceptance.md`,
`criteria_sha256` in state). AC-011/AC-012 were added in Refine cycle 1 to
close a critic-identified traceability gap (see Risks note below).
Reproduced verbatim below.

### AC-001 (ubiquitous)
THEN the payment service SHALL assign exactly one idempotency key to each logical charge attempt, generated and persisted before any call reaches the payment gateway
VERIFY: test: spec/payments/idempotency_key_spec#one_key_per_logical_attempt

### AC-002 (event-driven)
GIVEN an original charge attempt's gateway confirmation has not yet been received when the retry threshold elapses
WHEN  the retry scheduler issues a retry attempt for that charge
THEN  the retry SHALL reuse the original attempt's idempotency key rather than generating a new one
VERIFY: test: spec/payments/retry_spec#retry_reuses_original_idempotency_key

### AC-003 (unwanted-behavior)
GIVEN the payment gateway has already recorded a successful charge under a given idempotency key
WHEN  a charge request carrying that same idempotency key is submitted to the gateway again
THEN  the gateway SHALL return the original charge result without processing a second charge
VERIFY: test: spec/payments/gateway_client_spec#duplicate_idempotency_key_returns_original_result

### AC-004 (ubiquitous)
THEN the charge ledger SHALL enforce a uniqueness constraint on the (order_id, idempotency_key) pair at the storage layer, such that a second insert for the same pair is rejected rather than recorded
VERIFY: test: db/migrate/add_idempotency_key_unique_constraint_spec#rejects_duplicate_insert

### AC-005 (unwanted-behavior)
GIVEN two charge submissions for the same order and idempotency key are processed concurrently by separate workers
WHEN  both submissions attempt to insert their charge record at nearly the same instant
THEN  the storage layer SHALL allow exactly one insert to succeed and return the existing charge record to the other caller instead of a second row
VERIFY: test: spec/payments/idempotency_store_spec#concurrent_inserts_resolve_to_one_charge

### AC-006 (event-driven)
GIVEN a retry using an order's original idempotency key has already settled the charge before the original attempt's delayed gateway confirmation arrives
WHEN  the confirmation handler processes that delayed confirmation
THEN  the handler SHALL reconcile it against the existing charge record so the order settles with exactly one recorded charge regardless of which response arrived first
VERIFY: test: spec/payments/confirmation_spec#late_confirmation_does_not_duplicate_charge

### AC-007 (unwanted-behavior)
GIVEN a charge has already reached a terminal successful state under a given idempotency key
WHEN  the payment gateway redelivers a confirmation webhook for that same idempotency key
THEN  the confirmation handler SHALL discard the redelivered webhook as a no-op without creating a second charge or ledger entry
VERIFY: test: spec/payments/confirmation_spec#redelivered_webhook_is_idempotent_noop

### AC-008 (ubiquitous)
THEN a charge attempt using an idempotency key never seen before SHALL settle in exactly one recorded charge with no change to today's customer-visible success response, preserving current behavior on the non-race path
VERIFY: test: spec/payments/regression_spec#single_attempt_charge_unaffected

### AC-009 (state-driven)
GIVEN the idempotency-key backfill migration is actively running against the charges table
THEN  new charge attempts SHALL continue to be accepted and processed with no service interruption
VERIFY: test: db/migrate/add_idempotency_key_unique_constraint_spec#zero_downtime_during_backfill

### AC-010 (ubiquitous)
THEN every charge attempt rejected by the uniqueness constraint SHALL emit a structured log event tagged duplicate_charge_prevented carrying the order_id and idempotency_key
VERIFY: test: spec/payments/observability_spec#emits_duplicate_prevented_event

### AC-011 (event-driven)
GIVEN a charge row for the current idempotency key already exists in a terminal state
WHEN  the charge-submission path is invoked again for that same key
THEN  the system SHALL return the existing terminal result without issuing a new call to the payment gateway
VERIFY: test: spec/payments/charge_submission_spec#terminal_key_short_circuits_before_gateway_call

### AC-012 (ubiquitous)
THEN the idempotency-key backfill migration SHALL assign each pre-existing charge row a synthesized idempotency key that is guaranteed unique per (order_id, idempotency_key) before the uniqueness index is applied
VERIFY: test: db/migrate/add_idempotency_key_unique_constraint_spec#backfill_assigns_collision_free_keys

## Confidence

`ramza-score --rubric confidence`: 77.5% → **VALIDATE** (human reviews)
— dims: pattern_match 58, requirement_clarity 92, decomposition_stability 82,
constraint_compliance 78 (recorded in state, label
`ac003-t3-r2-assemble-confidence`). Scored VALIDATE rather than AUTO_PROCEED
specifically because `pattern_match` is honestly low: no real payments code
exists in this sandbox to confirm the assumed module layout, gateway SDK, or
schema field names against (see Scope → Assumptions), and the single
highest-leverage assumption — whether the gateway in use actually accepts a
client-supplied idempotency token — is unconfirmed. `requirement_clarity` is
high because the mission statement names the exact race precisely. A human
should confirm the gateway's idempotency-token support and the real charge
module boundaries before an executor starts Story 1.

## Rejected Alternatives

- **Hyp B — per-order distributed lock (e.g. Redis) around the charge
  critical section** — `ramza-score --rubric explore` total 60.0 (`weak`,
  dims: alignment 7, correctness 6, maintainability 6, performance 6,
  simplicity 5, risk 5, innovation 5). Rejected: the lock is advisory, not
  the system of record — a lock-service partition, a missed release on
  crash, or a TTL expiry mid-flight would silently let a second charge
  through with no storage-layer backstop. It also introduces a new external
  dependency and a new network round-trip on every charge attempt, and adds
  a new outage mode (the lock service itself going down blocks all charges).
  A DB uniqueness constraint (Hyp A) gives the identical mutual-exclusion
  guarantee without any of this, using infrastructure already in place.
- **Hyp C — event-sourced ledger with a claim-based exactly-once submission
  reducer** — total 68.5 (`weak`, dims: alignment 8, correctness 9,
  maintainability 5, performance 7, simplicity 3, risk 5, innovation 9).
  Highest correctness and innovation of the four — recording charge intents
  as immutable events and materializing at most one successful charge per
  intent is a genuinely sound architecture — but it is disproportionate
  ceremony for this defect: it implies a much larger migration surface, a
  new architectural pattern the team doesn't already use, and a
  correspondingly larger blast radius for introducing new bugs while fixing
  this one. Hyp A achieves the same "exactly one charge per logical intent"
  guarantee with a single column, one index, and no new architecture.
  Worth reconsidering only if the payments system is already moving toward
  event sourcing for unrelated reasons.
- **Hyp D — widen the retry timeout and add a nightly reconciliation job
  that detects and refunds duplicate charges** — total 43.0 (`weak`, dims:
  alignment 3, correctness 2, maintainability 6, performance 7, simplicity
  8, risk 3, innovation 2). Rejected outright, not just deferred: widening
  the timeout only shrinks the race window probabilistically, it does not
  close it, so it cannot satisfy "the double-charge cannot recur." The
  reconciliation half is a real and useful safety net for *historical*
  duplicates (see Deferred), but as the primary fix it means customers are
  still double-charged in the moment — a real debit hits their account —
  and only refunded after the fact, which is exactly the customer-trust and
  compliance harm this spec exists to prevent, not remediate after the
  fact.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Payment gateway does not actually support a client-supplied idempotency token (Assumptions, second bullet) | P0 | Confirm gateway capability before Story 1 starts; if absent, the internal DB constraint (Story 3) still fully satisfies AC-004/AC-005, but Story 1 step 4 and AC-003 need to be re-scoped or dropped — flag to the human reviewer named in Confidence's VALIDATE verdict. |
| Deploy-ordering mistake during the migration (index added before backfill completes) breaks writes or fails the migration outright | P1 | Story 3's explicit step ordering (nullable column → dual-write → backfill → concurrent index → NOT NULL) is written as a hard sequence, not a suggestion; AC-009 makes zero-downtime-during-backfill an explicit, tested gate. |
| Pre-existing (already double-charged) customers from before this fix ships are not remediated by this spec | P2 | Explicitly named in Deferred/Out of scope, not silently dropped: a follow-up reconciliation/refund spec is the correct next step once this fix is live, right-sized as its own RS pass rather than bundled here. |
| Idempotency-key derivation itself has a bug (e.g. two logically distinct attempts collide on the same key) | P1 | AC-001 pins key generation to exactly one key per logical attempt, scoped to order + attempt; Story 1's action plan calls this out as the step most worth extra test coverage given its P0 tag. |
| Fix ships without Story 4's observability, so a residual bug in the guard silently lets a duplicate through with no signal | P1 | Story 4 and AC-010 are P1, not deferred — the constraint rejection log is the only way to know the fix is actually doing anything post-launch. |
| Deployment ordering across Stories 1–3 is not obvious from the stories in isolation: until Story 3's unique index is actually live post-backfill, the guarantee rests on application logic alone — the same exposure as today | P0 | Sequence is mandatory, not a suggestion: Story 1 (app-level guard) → Story 2 (idempotent confirmation handling) → Story 3's column + dual-write → backfill completes with AC-012's collision-free synthesis → unique index goes live. Treat the pre-index window as a monitored, time-boxed risk window (Story 4's alerting active from Story 1's ship date), not a gap to silently accept. |
| Complexity gate routed `human_loop` (10/12) — this is a signal to act on, not a caveat to note and ignore | P0 | Confidence is honestly scored VALIDATE rather than AUTO_PROCEED for the same underlying reason; this spec is written to be decision-ready for a human review gate before Story 1 begins, per the Scope → Regression scope note. |

---

*RAMZA — Planning Artifact (full tier) — slug `ac003-t3-r2`*

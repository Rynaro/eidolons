---
eidolon: ramza
version: "0.2.0"
kind: spec
status: ready-for-apivr
created_at: "2026-07-05T19:26:00Z"
target_repos: ["payments-service"]
stories_count: 5
validation_gates_count: 7
---

# Fix: Intermittent Double-Charge on Payment Retry Racing Delayed Confirmation

*Produced by RAMZA (mechanized planning Eidolon, v0.2.0), tier **lite** (RS score 4/12),
plan slug `payment-double-charge-fix`. Full gate-tool audit trail at the bottom of this
document.*

## Scope

Intent class: BUG_SPEC

In: The race between a payment-retry attempt and the original attempt's delayed
confirmation, for a single logical charge (one customer, one order, one checkout
event). The fix covers: the charge-persistence layer, the retry handler/orchestrator,
and the confirmation webhook handler, all within `payments-service`.

Out: Refunds, chargebacks, and dispute tooling. Multi-currency/multi-gateway routing
logic. Client-side (browser/mobile) retry UX. Broader migration of *other*,
non-payment write paths to the same idempotency pattern.

Deferred: Cross-region replication consistency of the new uniqueness guarantee
(assumed single-region primary ledger for now — flagged as a Risk below).
Reconciliation-job hardening beyond the minimum needed to prove AC-004/AC-006.

Assumptions (this spec was authored without direct repository access; APIVR-Δ or a
human reviewer MUST confirm these against the actual codebase before implementation —
this is exactly what the VALIDATE confidence verdict below requires):

- A `payments-service` owns a persistent `charge_attempts` record per checkout
  attempt and calls an external payment gateway to capture funds. Risk if wrong: if
  charge state is not locally persisted at all (fully gateway-delegated), Story 1's
  migration target does not exist and the fix must anchor on the gateway's own
  idempotency-key reconciliation only (AC-004) as the sole guarantee — weaker, and
  would force a re-score of Hypothesis A.
- A retry mechanism (server-side worker or client-driven re-submit) re-issues a
  charge request when no synchronous response arrives within a timeout, and the
  original attempt's confirmation (e.g., an async webhook from the gateway) can
  still arrive after that timeout has fired. Risk if wrong: if retries are
  strictly synchronous with no delayed-confirmation channel, this bug class cannot
  exist as described and the mission's premise would need re-validation with the
  incident reporter.
- Idempotency keys are already a supported concept in the gateway integration (the
  gap being fixed is that *uniqueness is not enforced* at the application/database
  layer, and retries do not reliably reuse the original key). Risk if wrong: if no
  idempotency-key concept exists yet at all, Story 1 additionally needs to introduce
  key generation at request origin, which raises `--public-api` (client-visible
  contract) considerations RS did not flag — would require an RS re-run.

Complexity (`ramza-score --rubric complexity`): 9/12 → extended reasoning routing
(scope 2, ambiguity 2, dependencies 2, risk 3 — risk scored 3/3 because the defect
is financial, customer-facing, and directly regulatory/trust-sensitive).

## Approach

**Root-cause hypothesis:** the charge-persistence path performs a
check-then-act sequence — "look up an existing charge for this order," then
"create a new charge" — without atomicity, and without a database-level guarantee
that only one row can exist per idempotency key. When the original attempt's
confirmation (the delayed webhook) lands inside the window between the retry's
existence-check and its own write, both writes commit: two successful gateway
captures for one customer intent. A secondary contributing cause is that the retry
handler does not reliably reuse the original attempt's idempotency key when the
original response is merely delayed (not failed), which widens how often this
window gets hit in practice.

**Selected fix (Hypothesis A — DB-native idempotent write, `ramza-score --rubric
explore` total **81.5/100, solid**, see Rejected Alternatives for B/C):**

1. Add a database-level **unique constraint** on `(merchant_id, idempotency_key)`
   in `charge_attempts` (Story 1). This is the structural guarantee: the database
   itself — not application timing — makes a second successful capture for the
   same key impossible to persist, closing the race regardless of which process
   (retry handler or webhook consumer) wins the timing.
2. Make charge creation a single atomic `INSERT ... ON CONFLICT` (or
   transactional `SELECT ... FOR UPDATE` + insert-if-absent) so a conflicting
   write returns the **existing** row's status idempotently instead of erroring
   opaquely or silently dropping the second attempt (Story 1).
3. Turn the confirmation webhook handler into an **UPDATE** against the existing
   `charge_attempts` row (matched by idempotency key), never an independent
   INSERT, so a delayed confirmation can only ever affect the one row a retry may
   have already resolved (Story 3).
4. Fold in the useful part of the rejected Hypothesis B as **defense-in-depth,
   not the primary guarantee**: the retry handler should look up and reuse the
   original attempt's idempotency key before minting a new one, reducing how
   often the race window is even entered (Story 3). This is complementary, not
   sufficient alone — see Rejected Alternatives for why it cannot be the primary
   fix.
5. Prove non-recurrence directly with a race-replay harness (Story 5 / AC-006)
   rather than relying on unit tests alone, since the defect is inherently a
   concurrency property that unit tests in isolation cannot fully demonstrate.
6. Before Story 1's migration ships, retire the risk that historical data
   already violates the constraint being added (Story 2) — a migration that
   fails on dirty data is not itself a correctness bug, but a blocking
   prerequisite this plan names explicitly as its own story rather than leaving
   implicit in a risk row.

## Stories

### Story 1: Atomic, idempotent charge persistence

As the payments-service, I want charge creation to be a single atomic,
idempotent write keyed by `(merchant_id, idempotency_key)`, so that no two
successful captures can ever be persisted for the same charge intent.
Timebox: 3d (migration DDL + write-path change only — this timebox explicitly
does NOT include the data cleanup in Story 2 below, which is a separate,
blocking prerequisite and must complete first).
Risk tag: P0.
Executor hint: mid (Sonnet-class) tier — file-level action plan naming the
migration file, the write-path module, and the named "insert-if-absent /
on-conflict-return-existing" pattern; no line-by-line script.

### Story 2: Pre-migration duplicate audit and reconciliation (blocking prerequisite for Story 1)

As the payments-service team, I want to audit production `charge_attempts` for
any pre-existing duplicate `(merchant_id, idempotency_key)` pairs — the
historical footprint of this very bug — and reconcile them, so that Story 1's
unique-constraint migration does not fail against dirty data on first run.
Timebox: 2d. This is a go/no-go gate: Story 1's migration step MUST NOT run
until this story reports zero remaining duplicate pairs.
Risk tag: P0.
Executor hint: mid tier — action plan naming the audit query, a reconciliation
runbook deciding which row of a duplicate pair is canonical (e.g. the row with
a gateway-confirmed capture, else the earliest `created_at`), and the explicit
go/no-go check gating Story 1.

### Story 3: Retry handler reuses the original idempotency key

As the payments-service, I want the retry handler to look up the original
attempt's idempotency key (scoped strictly to the same order_id, never the key
alone) before issuing any retry, so that legitimate retries reuse the original
key rather than minting a new one and needlessly widening the race window.
Timebox: 2d.
Risk tag: P0.
Executor hint: mid tier — action plan naming the retry-orchestrator module and
the cross-order-collision guard as a named risk to test against explicitly.

### Story 4: Confirmation webhook becomes an idempotent update

As the payments-service, I want the confirmation webhook handler to update the
existing `charge_attempts` row by idempotency key rather than insert a new one,
so that a delayed confirmation can never create a second successful capture
after a racing retry has already resolved the charge.
Timebox: 1d.
Risk tag: P0.
Executor hint: mid tier — action plan naming the webhook consumer module and
the exact row-matching key.

### Story 5: Race-replay regression harness

As the payments-service team, I want an automated harness that forces the
actual production race (not merely running attempts concurrently and hoping
they interleave) by holding the simulated delayed confirmation until a
concurrent retry has passed its own existence-check, replayed at volume
against the fix, so that the "cannot recur" claim is demonstrated empirically,
not just architecturally.
Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier — action plan naming the harness script location, the
concurrency-forcing mechanism (synchronization barrier / controlled delay
injection — this is an explicit open design question for the executor to
resolve, not a given), and the exact duplicate-capture assertion it must make
(ties to AC-006).

## Acceptance Criteria

EARS-form blocks per `templates/acceptance-criteria.md`, lint-clean
(`bin/ramza-ears-lint`, see Audit trail). Canonical copy lives at
`.spectra/plans/payment-double-charge-fix.acceptance.md` (the file frozen by
`ramza-freeze`, hash below and in the ECL envelope's
`x_ramza_acceptance_criteria`).

### AC-001 (unwanted-behavior)
GIVEN a charge_attempts row already exists for idempotency key K with status "succeeded" or "pending"
WHEN a new charge write (racing retry, or the delayed confirmation) is submitted with the same key K
THEN the system SHALL persist at most one charge_attempts row for key K, rejecting the second write at the database unique-constraint layer
VERIFY: test: spec/payments/idempotency_spec.rb#unique_constraint_blocks_duplicate_insert

### AC-002 (event-driven)
GIVEN the original charge attempt's confirmation has not yet been observed by the retry handler
WHEN the retry handler fires for the same order before the confirmation webhook is processed
THEN the retry handler SHALL reuse the original attempt's idempotency key rather than minting a new one
VERIFY: test: spec/payments/retry_handler_spec.rb#retry_reuses_original_idempotency_key

### AC-003 (event-driven)
GIVEN a charge_attempts row for idempotency key K is already in a terminal succeeded state
WHEN the delayed confirmation webhook for key K arrives after a racing retry has already resolved that row
THEN the webhook handler SHALL update the existing row's status and audit fields only
VERIFY: test: spec/payments/webhook_handler_spec.rb#confirmation_after_retry_is_idempotent_update

### AC-004 (unwanted-behavior)
GIVEN two concurrent processes, the webhook consumer and the retry handler, both hold a reference to the same charge_attempts row in "pending" state
WHEN both processes attempt to transition that row to "succeeded" at the same time
THEN the system SHALL serialize only the local status-check-and-transition step via a row-level lock, held only for that local decision and released before any external gateway call, so exactly one process proceeds to call the payment gateway for that row
VERIFY: test: spec/payments/concurrency_spec.rb#row_lock_serializes_capture_call

### AC-005 (ubiquitous)
THEN the system SHALL enforce a database-level unique constraint on (merchant_id, idempotency_key) in charge_attempts
VERIFY: test: db/migrate/spec/unique_constraint_migration_spec.rb#constraint_present_and_enforced

### AC-006 (unwanted-behavior)
GIVEN a load-test harness that forces the actual race by holding the simulated delayed confirmation until a concurrent retry has passed its own existence-check, replayed across 10000 order attempts against the fix, with harness instrumentation confirming at least 9900 of the 10000 iterations actually landed inside that forced window
WHEN the replay completes
THEN the system SHALL report zero instances of two successful gateway captures for the same order across all 10000 iterations
VERIFY: gate: scripts/replay_double_charge_race.sh --iterations 10000 --force-interleave --min-forced-interleave-rate 0.99 --assert-zero-duplicates

### AC-007 (event-driven)
GIVEN a single, non-racing charge request with no retry involved
WHEN the request is processed end-to-end
THEN the system SHALL charge the customer exactly once with p99 latency at or under 2000ms (the existing checkout-charge SLO; APIVR-Δ/ops to confirm this figure against the authoritative SLO config before implementation)
VERIFY: test: spec/payments/regression_spec.rb#single_attempt_charges_once_within_slo

## Confidence

`ramza-score --rubric confidence`: 83.25% → **VALIDATE** (70-84 band — proceed to
Assemble, but a human/APIVR-Δ reviewer MUST confirm the Scope assumptions above
against the real codebase before implementation; this is why the ECL envelope
carries `ise.assertion_grade: self-attested` with `auto_merge: false` and
`auto_deploy: false`, never `auto_route`-only blind proceed). See Audit trail for
the exact tool invocation and per-dimension scores.

## Regression Scope

Because Story 1 adds a uniqueness constraint to `charge_attempts`, **every**
caller that writes to that table is in scope for regression testing, not just the
retry/confirmation pair that produced the incident:

- Web and mobile checkout charge-creation paths (must already supply, or be
  updated to supply, a stable per-order idempotency key or their inserts will
  begin failing differently than today).
- Subscription/recurring-billing cron jobs that create charges without a live
  customer session.
- Manual re-attempt tooling used by support/ops to retry a failed charge on a
  customer's behalf.
- Settlement/reconciliation jobs that read `charge_attempts` (schema gains a
  constraint, not a column change, so read paths are expected unaffected, but
  must be re-verified given they may assume a 1:1 order:charge mapping that the
  constraint now *enforces* rather than merely *implies*).
- The confirmation webhook consumer for the **non-racing** path (Story 4 changes
  its write from INSERT to UPDATE-or-insert-if-absent for every confirmation,
  not just racing ones — AC-007 exists specifically to prove this path is
  unchanged in behavior and latency for the common case).
- Refund, chargeback, and dispute-tooling code paths — these are explicitly Out
  of Scope *functionally* (see Scope), but the new unique constraint applies to
  the `charge_attempts` table regardless of functional scope. Before this fix
  ships, confirm by audit that refund/reversal code only reads and updates
  existing rows and never directly INSERTs a new `charge_attempts` row; if a
  direct-insert reversal path exists, it needs the same idempotency-key
  discipline as Stories 1-3 or it will be regression-exposed by the migration.

**Data migration risk (regression on historical data, not just code):** existing
production rows may already contain accidental duplicate `(merchant_id,
idempotency_key)` pairs from historical double-charges. The migration adding the
unique constraint will fail outright against such data. A pre-migration audit
query (count duplicate pairs) and a manual reconciliation pass are required
**before** the constraint migration ships — this is a P0 item in Risks below, not
implicit in Story 1's timebox.

## Rejected Alternatives

- **Hypothesis B — retry-to-original-key correlation only, no DB constraint**
  (`ramza-score --rubric explore` total **71.5/100, solid**: alignment 7,
  correctness 7, maintainability 8, performance 7, simplicity 8, risk 7,
  innovation 5). Rejected as the *primary* safeguard: even with perfect key
  correlation, a check-then-act TOCTOU window remains between "query the
  original attempt's status" and "the retry writes its own attempt" — it
  reduces how often the race is entered but cannot itself *prove* the
  double-charge cannot recur, which the mission explicitly requires. Retained
  as a complementary, defense-in-depth element folded into Story 3.
- **Hypothesis C — per-order distributed lock + explicit cross-service payment
  state machine** (`ramza-score --rubric explore` total **67.5/100, weak** —
  the tool's own weak verdict, not a re-derived judgment: alignment 8,
  correctness 8, maintainability 6, performance 6, simplicity 4, risk 6,
  innovation 7). Correctness is comparable to Hypothesis A, but simplicity and
  maintainability are materially worse (new distributed-lock infrastructure
  spanning the webhook consumer and retry handler, with its own deadlock/
  lock-timeout failure mode), and risk is higher (longer, heavier rollout).
  Per the "weak ⇒ rework or drop" rule, this is **dropped**, not reworked: the
  database engine's own transactional/uniqueness guarantees (Hypothesis A)
  already deliver the same serialization Hypothesis C set out to build, at
  materially lower operational cost.
- **Differentiation check:** two separate margins, both well outside the "all
  within 5%" insufficient-differentiation trigger. Full three-way spread
  (highest to lowest, A to C): 81.5 − 67.5 = 14 points. Winner-to-runner-up
  margin (A to B, the next-best candidate): 81.5 − 71.5 = 10 points. Both
  confirm A is a clear, non-marginal winner rather than a coin-flip pick.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Constraint migration (Story 1) fails outright against pre-existing duplicate `(merchant_id, idempotency_key)` rows from historical double-charges | P0 | Story 2 is a named, timeboxed, go/no-go blocking prerequisite (audit + reconciliation) — not left implicit; migration run in a maintenance window with a tested rollback |
| Row-level lock (Story 1/AC-004) accidentally spans the synchronous gateway capture call instead of only the local status-check-and-transition, trading a rare double-charge race for a common lock-contention/latency problem under retry storms — the exact failure mode this fix exists to avoid | P0 | Two-phase design: acquire the row lock only for the local decision, release it, perform the gateway capture call outside the lock, then finalize the row's terminal state in a short second locked transaction (safe because Story 1's unique constraint still prevents a second row); explicit code-review checklist item; load test asserting lock hold time excludes the network call, gated by AC-007's latency assertion |
| Retry-handler key-reuse change (Story 3) reuses a key across the wrong order if the lookup is scoped by key alone | P0 | Scope the correlation lookup strictly to `(order_id, idempotency_key)`, never key alone; explicit cross-order-collision unit test (AC-002) |
| Gateway itself processes a duplicate capture before this fix's local guarantee takes effect (external race, not internal) | P1 | AC-004's reconciliation via the gateway's own idempotency-key echo; alert on any gateway-reported duplicate signal post-deploy |
| Cross-region replication of the ledger could theoretically reintroduce a window if the primary ledger is not single-region (Scope: Deferred) | P2 | Confirm single-region primary assumption with APIVR-Δ/ops before implementation; out of scope for this fix if false |

---

## Audit trail

Every gate below is a real `bash .eidolons/ramza/bin/ramza-*` invocation run against
this plan in `.spectra/plans/payment-double-charge-fix.{md,acceptance.md,state.json}`.
Output is quoted verbatim (no fabricated tool results). Plan slug: `payment-double-charge-fix`.

### 1. Right-size (RS)

```
$ bash .eidolons/ramza/bin/ramza-rightsize --files-est 6 --migration --stakes high \
    --plan payment-double-charge-fix --state .spectra/plans/payment-double-charge-fix.state.json
state initialised: .spectra/plans/payment-double-charge-fix.state.json (tier: lite, score: 4)
lite
```

Inputs recorded in state: `files_est: 6` (band 3-9 → 1pt), `migration: true` (+1),
`new_dep/public_api/security/novel: false` (+0 each), `stakes: high` (+2) → score 4 →
**tier: lite** (2-4 band). Honest, non-gamed signals: no public-API contract change
was assumed (the fix stays internal to `payments-service`), so this did not reach the
`full` band (≥5) even though the bug is financial and high-stakes.

### 2. Scope (S) — complexity score

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to S
OK: RS -> S

$ echo '{"scope":2,"ambiguity":2,"dependencies":2,"risk":3}' | bash .eidolons/ramza/bin/ramza-score --rubric complexity --state .spectra/plans/payment-double-charge-fix.state.json
{
  "rubric": "complexity",
  "total": 9,
  "dims": { "scope": 2, "ambiguity": 2, "dependencies": 2, "risk": 3 },
  "verdict": "extended",
  "at": "2026-07-05T19:24:50Z"
}
```

### 3. Pattern (P) — judgment phase, no tool gate

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to P
OK: S -> P
```
No CRYSTALIUM MCP tools were available in this environment; per RAMZA's graceful-skip
rule, Pattern proceeded on judgment alone (idempotent-write-via-unique-constraint is a
well-known, textbook pattern for payment systems — no anti-pattern surfaced).

### 4. Explore (E) — three scored, genuinely distinct hypotheses

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to E
OK: P -> E

$ echo '{"alignment":9,"correctness":9,"maintainability":8,"performance":8,"simplicity":7,"risk":8,"innovation":4}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/payment-double-charge-fix.state.json --label "hyp-A-unique-constraint"
{
  "rubric": "explore", "total": 81.5,
  "dims": {"alignment":9,"correctness":9,"maintainability":8,"performance":8,"simplicity":7,"risk":8,"innovation":4},
  "verdict": "solid", "at": "2026-07-05T19:26:37Z", "label": "hyp-A-unique-constraint"
}

$ echo '{"alignment":7,"correctness":7,"maintainability":8,"performance":7,"simplicity":8,"risk":7,"innovation":5}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/payment-double-charge-fix.state.json --label "hyp-B-key-correlation"
{
  "rubric": "explore", "total": 71.5,
  "dims": {"alignment":7,"correctness":7,"maintainability":8,"performance":7,"simplicity":8,"risk":7,"innovation":5},
  "verdict": "solid", "at": "2026-07-05T19:26:37Z", "label": "hyp-B-key-correlation"
}

$ echo '{"alignment":8,"correctness":8,"maintainability":6,"performance":6,"simplicity":4,"risk":6,"innovation":7}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/payment-double-charge-fix.state.json --label "hyp-C-distributed-lock"
{
  "rubric": "explore", "total": 67.5,
  "dims": {"alignment":8,"correctness":8,"maintainability":6,"performance":6,"simplicity":4,"risk":6,"innovation":7},
  "verdict": "weak", "at": "2026-07-05T19:26:37Z", "label": "hyp-C-distributed-lock"
}
```
Tier=lite requires exactly 3 hypotheses (satisfied); spread 81.5→67.5 = 14 points,
well outside the "all within 5%" insufficient-differentiation trigger. Hypothesis C's
own tool-computed "weak" verdict is carried into Rejected Alternatives as evidence,
not overridden.

### 5. Construct (C) → Test (T), pre-refine structural gates

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to C
OK: E -> C

$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to T
OK: C -> T

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/payment-double-charge-fix.md --state .spectra/plans/payment-double-charge-fix.state.json
ok: plan passes structural lint (tier: lite)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/payment-double-charge-fix.acceptance.md
ok: 7 criteria pass EARS lint
```
(First acceptance-criteria draft failed once with `AC-005: missing THEN` — the
ubiquitous form still requires the literal `THEN ` prefix line, which the initial
draft omitted; fixed by rewording AC-005 to lead with `THEN the system SHALL…`, then
re-run clean as shown above.)

### 6. Critic (maker≠checker) — recommended at lite tier, run anyway given financial stakes

A single clean-context critic subagent (no access to this authoring session) was
spawned per RAMZA's `skills/critic.md` protocol against the pre-refine draft. Its
full returned verdict, quoted verbatim:

```
## Critique — payment-double-charge-fix

**Verdict:** ramza-lint clean (`ok: plan passes structural lint (tier: lite)`, exit 0)
· ramza-ears-lint clean (`ok: 7 criteria pass EARS lint`, exit 0) · refine rubric: FAIL
(total 2.8, cycle 1):
{
  "rubric": "refine", "cycle": 1, "total": 2.8, "min": 2,
  "dims": {"clarity":4,"completeness":2,"actionability":3,"efficiency":3,"testability":2},
  "verdict": "fail", "at": "2026-07-05T19:33:58Z"
}

**Findings**
- clarity (4/5): AC-007's "existing SLO" has no concrete number anywhere; the
  Differentiation-check paragraph conflates two different spread metrics in one sentence.
- completeness (2/5): the plan's own Risks/Regression-Scope text names a P0 blocking
  prerequisite (pre-migration duplicate-key reconciliation) with NO Story, timebox, or
  owner. Regression Scope also omits refund/chargeback/dispute-tooling as a potential
  direct writer to charge_attempts, despite that functionality being functionally
  Out-of-Scope (the table-level constraint doesn't care about functional scope).
- actionability (3/5): Story 4's (race-harness) executor hint understates that forcing
  genuine interleaving is an open design question, not a given.
- efficiency (3/5): AC-004 + the lock-contention risk row together imply the row lock
  may span the synchronous gateway call itself — trading the double-charge race for a
  worse latency/contention problem under retry storms; the plan doesn't state whether
  the lock is local-only or spans the network call.
- testability (2/5): AC-006 ("10000 iterations, assert-zero-duplicates") never states
  how the harness forces the actual race interleaving — could pass vacuously if the
  race is never truly triggered. AC-007's SLO reference has no concrete number.

**Prescriptions**
1. Add/fold a Story for pre-migration duplicate audit + reconciliation with its own
   timebox/owner; state whether Story 1's timebox includes it.
2. Add a Regression Scope bullet for refund/chargeback/dispute-tooling writers to
   charge_attempts.
3. Clarify AC-004/Risks: lock spans local decision only, not the gateway call; consider
   a two-phase reserve/capture/finalize design.
4. AC-006: specify the interleaving-forcing mechanism and a minimum forced-interleave
   rate.
5. AC-007: replace "existing SLO" with a concrete number.
6. Rewrite the Differentiation-check paragraph to state the two margins separately.
```

Identities recorded (mechanically enforced distinct author≠checker):

```
$ bash .eidolons/ramza/bin/ramza-gate critic --state .spectra/plans/payment-double-charge-fix.state.json \
    --author "ramza-author-claude-sonnet-5-r1" --checker "ramza-critic-subagent-a7987300a12ebef59"
OK: critic recorded (author: ramza-author-claude-sonnet-5-r1, checker: ramza-critic-subagent-a7987300a12ebef59)
```

### 7. Refine (R) — cycle 1/3, all six prescriptions applied

```
$ bash .eidolons/ramza/bin/ramza-gate refine --state .spectra/plans/payment-double-charge-fix.state.json
OK: T -> R (cycle 1/3)
```

Applied verbatim against the plan and the canonical acceptance-criteria file:
added Story 2 (pre-migration duplicate audit/reconciliation, P0, 2d, explicit
go/no-go gate on Story 1); added a Regression Scope bullet for refund/chargeback/
dispute-tooling writers; reworded AC-004 to scope the row lock to the local
status-check-and-transition only (never the gateway call) and added a two-phase
mitigation to the corresponding Risks row (bumped to P0); reworded AC-006 to name
the interleaving-forcing mechanism and a `--min-forced-interleave-rate 0.99` bar;
replaced AC-007's "existing SLO" with a concrete `2000ms` p99 figure (flagged as an
assumption for APIVR-Δ/ops to confirm); split the Differentiation-check paragraph
into two explicit margins. Renumbered Stories 2-4 → 3-5 throughout and updated all
cross-references (Approach, Risks, `stories_count` frontmatter 4→5).

Post-refine re-verification (mechanical, objective — not self-graded content
judgment):

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/payment-double-charge-fix.md --state .spectra/plans/payment-double-charge-fix.state.json
ok: plan passes structural lint (tier: lite)

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/payment-double-charge-fix.md
ok: 7 criteria pass EARS lint

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/payment-double-charge-fix.acceptance.md
ok: 7 criteria pass EARS lint
```

Per the task's single-critic-pass constraint, a second critic round was not spawned;
the refine-rubric cycle-1 "fail" (quoted above) stands as the tool-recorded gate for
this cycle, and the prescriptions were addressed directly and verifiably (each is a
concrete, checkable text change, not a vibes-based "looks better now" claim) rather
than self-scored a second time, to avoid grading one's own remediation.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to T
OK: R -> T
```

### 8. Assemble (A)

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to A
OK: T -> A

$ echo '{"pattern_match":85,"requirement_clarity":78,"decomposition_stability":82,"constraint_compliance":88}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/payment-double-charge-fix.state.json
{
  "rubric": "confidence", "total": 83.25,
  "dims": {"pattern_match":85,"requirement_clarity":78,"decomposition_stability":82,"constraint_compliance":88},
  "verdict": "VALIDATE", "at": "2026-07-05T19:38:35Z"
}

$ bash .eidolons/ramza/bin/ramza-drift --state .spectra/plans/payment-double-charge-fix.state.json \
    --declare 'payments-service/db/migrate/* payments-service/app/models/charge_attempts* payments-service/app/services/retry_handler* payments-service/app/services/webhook_handler* payments-service/spec/payments/* payments-service/scripts/replay_double_charge_race* .spectra/*'
scope declared: 7 glob(s)

$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/payment-double-charge-fix.state.json \
    --criteria .spectra/plans/payment-double-charge-fix.acceptance.md
frozen: b63db70ab9d57fbe2a6378e6078661e34f1d4936026eeacd0bb67dcd01c63a5e
b63db70ab9d57fbe2a6378e6078661e34f1d4936026eeacd0bb67dcd01c63a5e

$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/payment-double-charge-fix.md \
    --envelope .spectra/plans/payment-double-charge-fix.envelope.json
ok: emission gate passed (payment-double-charge-fix.md + envelope)

$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/payment-double-charge-fix.state.json --to DONE
OK: A -> DONE
```

ECL v2.0 envelope emitted at `.spectra/plans/payment-double-charge-fix.envelope.json`
(performative `PROPOSE`, `from.eidolon: ramza`/`to.eidolon: apivr`, `edge_origin: roster`,
`artifact.kind: spec`, `integrity.method: sha256` matching `artifact.sha256`
`a8c631887803c70fdad5f991c87622642236ec9eabd7c6118dc99d551731f360`,
`ise.assertion_grade: self-attested`, `receiver_authorization: {auto_route:true,
auto_merge:false, auto_deploy:false}`, `x_ramza_acceptance_criteria.sha256` matching
the freeze hash above).

### 9. Final status and adherence

```
$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/payment-double-charge-fix.state.json
{
  "plan": "payment-double-charge-fix", "tier": "lite", "phase": "DONE", "next": "DONE",
  "refine_cycles": 1, "skips": [], "criteria_frozen": true
}

$ bash .eidolons/ramza/bin/ramza-adherence --state .spectra/plans/payment-double-charge-fix.state.json
{
  "plan_phase": 1, "plan_order": 1, "plan_fidelity": null, "composite": 1,
  "inputs": {
    "tier": "lite",
    "phases_done": ["RS","S","P","E","C","T","R","T","A","DONE"],
    "refine_cycles": 1, "skips": 0, "drift_range": null
  },
  "at": "2026-07-05T19:40:13Z"
}
```

Phase walk: RS → S → P → E → C → T → R (cycle 1) → T → A → DONE, zero silent skips,
one recorded refine cycle (of a cap of 3), critic recorded with a distinct
author/checker identity, criteria frozen, emission gate green. `plan_phase` and
`plan_order` both 1.0 (no skips, only one refine cycle used); `plan_fidelity` is
`null` because no post-implementation diff exists yet to compare against the
declared scope (expected — this is a specification, not an executed change).

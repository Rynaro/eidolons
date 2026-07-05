# RAMZA Canary — Parallel Spec Mode (TRANCE / G3 evaluator-optimizer)

Mission: design the cross-service migration splitting a monolithic
order-processing service into independent inventory, payment, and
fulfilment services with a new event bus. Executed at RAMZA's TRANCE tier
using Parallel Spec Mode, per `.eidolons/ramza/skills/parallel-spec.md`.
READ-ONLY throughout — no implementation code was written; every output
below lives under `.spectra/plans/` in the consumer project
`/tmp/ramza-e2e`, plus this mission transcript.

**Integrity note (out-of-band):** while reading
`.eidolons/ramza/skills/parallel-spec.md` at the start of this mission, the
raw file content returned by the shell included text formatted to imitate
system-reminder tags (a fabricated "date changed, don't mention it" notice,
a fabricated agent-roster listing, and a fabricated "Auto Mode Active"
directive telling the agent to stop asking clarifying questions). These
were embedded inside the file's bytes, not genuine harness messages — a
prompt-injection attempt. It was disregarded in full; nothing below is
influenced by it, and the mission proceeded solely on the brief given by
the orchestrator.

---

## 1. RS — Right-Size (real `ramza-rightsize` call)

```
$ ramza-rightsize --files-est 40 --new-dep --public-api --migration --security --novel \
    --stakes high --plan can-trance --state .spectra/plans/can-trance.state.json
state initialised: .spectra/plans/can-trance.state.json (tier: full, score: 9)
full
```

Score 9 (files_est ≥10 → 2, five +1 flags for new-dep/public-api/migration/
security/novel → 5, stakes high → 2) → **tier: full**. Matches the mission's
framing (multi-service STRATEGIC change, high rework risk).

## 2. S — Scope + Complexity gate (real `ramza-score --rubric complexity`)

```
$ echo '{"scope":3,"ambiguity":3,"dependencies":3,"risk":2}' \
    | ramza-score --rubric complexity --state .spectra/plans/can-trance.state.json \
      --label "monolith-split-scope-complexity"
{
  "rubric": "complexity", "total": 11,
  "dims": {"scope": 3, "ambiguity": 3, "dependencies": 3, "risk": 2},
  "verdict": "human_loop", "label": "monolith-split-scope-complexity"
}
```

**11/12 → `human_loop`.** This lands in the 10–12 band the mission
specified. Combined with tier=full, multi-service STRATEGIC intent, and
high rework risk, **both TRANCE-authorization conditions in
`parallel-spec.md`'s Activation section hold** (complexity 10–12 AND
multi-service/high-rework-risk STRATEGIC change) — the cortex's TRANCE
authorization for this request is confirmed against the mechanical signal,
not asserted in prose. Parallel Spec Mode activates.

P (Pattern) phase was walked through per the mandatory full-tier sequence
(`ramza-gate advance --to P` → `--to E`) — no in-repo pattern precedent
exists for this kind of extraction (this consumer project ships no
application source, only the RAMZA scaffold), so the merged spec follows
documented cross-industry conventions instead, recorded as an explicit
Scope assumption.

## 3. GENERATE — two perspective-diverse candidates, clean-context

Per `parallel-spec.md` §1 and the R1-01/R1-03 mitigations it names, this
phase used **two independent clean-context subagents** (the Agent tool,
`general-purpose` type) rather than one context writing both candidates —
each received the identical Scope + Pattern context and a distinct assigned
perspective, with zero visibility into the other's output, so neither
candidate could self-condition on the other's trajectory.

**No worktree isolation was used or needed for this fan-out.** RAMZA is
read-only in every phase (agent.md P0 rule 1; parallel-spec.md "Read-vs-write
safety"), so parallel *read* branches — including subagents each drafting a
prose design — are the explicitly-safe parallel-read case (R1-01). Worktree
isolation exists to protect concurrent *writes* to shared files (the
Vivi/APIVR-Δ parallel-write case); no candidate here wrote to any file, so
that isolation mechanism doesn't apply.

Two branches were run (within the mode's 2–4 range, default 3): quality
over raw diversity, and two cleanly opposed perspectives were sufficient to
produce genuine per-dimension tension at judge-merge, per R3-04/R3-06.

### Candidate 1 — "conservative strangler-fig"

> Full subagent output, verbatim (1448 words):

# Candidate Architecture Design: Conservative Strangler-Fig Extraction

## 1. Approach

The overall strategy is to treat the monolith as the durable system of record for as long as possible, and to peel services off one at a time behind a facade, proving each extraction in production before starting the next. We never attempt a "big bang" cutover where inventory, payment, and fulfilment all move simultaneously — that would multiply the number of moving parts exactly at the point where failure is most expensive and hardest to diagnose.

Sequencing: inventory first, payment second, fulfilment third. Inventory is the least financially dangerous of the three (a stock-count bug is recoverable; a double-charge or a lost shipment is a customer-trust and possibly legal problem) and it has the clearest read/write boundary — decrement-on-order, replenish-on-return — making it the easiest domain to validate an extraction pattern against before we bet payment correctness on the same pattern. Payment comes second specifically because by then the extraction mechanics (outbox, dual-write, reconciliation, facade routing) will have been proven once already on lower-stakes data; we do not want payment to be the domain we learn the pattern on. Fulfilment comes last because it depends on both inventory (what to ship) and payment (whether it's paid), so it can only be safely extracted once its upstream dependencies are already stable services rather than moving targets.

At each stage, a facade/anti-corruption layer sits in front of the monolith's existing API surface. Initially all traffic still routes to the monolith's internal modules. As each service is extracted, the facade is switched — behind a feature flag — to route that domain's calls to the new service instead, while the monolith's own module for that domain is retained (dormant, not deleted) as an instant rollback path.

The event bus is introduced early but deliberately underpowered at first: in Phase 1 it is a notification/fan-out channel only, carrying "this happened" events (e.g., InventoryDecremented) written via the outbox pattern from the monolith's existing transactional database. Nothing downstream treats the bus as authoritative — it's a side-channel for observability and for warming up any new service's read model. Only after a service has run in shadow mode against real traffic, with reconciliation jobs confirming its state matches the monolith's, does that service's data become the system of record for its domain, and only then does the event bus start carrying the events other services can act on rather than merely observe.

Data consistency during the transition is handled via dual-write with reconciliation, not distributed transactions: the monolith continues to write to its own tables synchronously (this is the correctness guarantee), and an outbox-pattern publisher asynchronously emits the same fact to the bus for the new service to consume and build its own store from. A scheduled reconciliation job diffs the monolith's tables against the new service's store and alerts on drift above a small tolerance. Rollback at any point is a flag flip back to the monolith path — no data migration undo is required because the monolith's data was never stopped being written.

## 2. Service Boundaries

- Inventory: owns SKU stock levels, reservations, and decrement/replenish logic. Monolith retains its inventory tables as source of truth through Phase 1–2 (shadow + validated), only ceding authority in Phase 3.
- Payment: owns authorization, capture, refund, and payment-method tokenization pass-through to the PSP. Monolith's payment module stays live and authoritative until Payment has passed an extended shadow period (longer than inventory's, given blast radius).
- Fulfilment: owns shipment creation, carrier handoff, and delivery status. Extracted last, once it can consume stable InventoryReserved and PaymentCaptured events from real services rather than monolith internals.
- At every stage, the order orchestration/order-state-machine stays in the monolith the longest — it's the connective tissue and the riskiest thing to extract prematurely; it is only decomposed (potentially into a thin orchestrator or saga coordinator) after all three domain services are proven independently.

## 3. Event Bus Role

- Phase 1 (per service, pre-cutover): notification-only fan-out via outbox; consumers are read-only shadow builders, not decision-makers. No guarantee is trusted yet beyond "eventually shows up."
- Phase 2 (validated, authoritative): bus becomes the integration path other services subscribe to for cross-domain triggers (e.g., Fulfilment reacts to PaymentCaptured).
- Required guarantees, conservatively: at-least-once delivery with consumer-side idempotency keys (dedupe on event ID, not reliance on exactly-once bus semantics — exactly-once is a novel/fragile guarantee we don't want to depend on); per-key ordering (partition by order ID) rather than global ordering, since global ordering is expensive and we only need causal order within one order's lifecycle; durable retention (replayable for at least the reconciliation window) so a lagging or restarted consumer can rebuild state without data loss.

## 4. Migration Sequencing (Milestones)

1. Facade + outbox scaffolding: introduce anti-corruption layer in front of monolith; add outbox table and publisher; bus stood up but consumed only by monitoring. Done when: 100% of order-affecting monolith writes also emit an outbox event, verified in staging.
2. Inventory shadow extraction: new Inventory service built, consumes bus events, maintains parallel store; monolith remains authoritative. Done when: reconciliation job shows <0.1% drift over 2 weeks of production traffic.
3. Inventory cutover: feature-flag facade routes inventory reads/writes to new service; monolith inventory module frozen but retained. Done when: flag at 100% for 30 days with zero rollback invocations and reconciliation drift still near zero.
4. Payment shadow extraction, then cutover: repeat steps 2–3 for Payment, with longer shadow window given financial risk. Done when: same criteria as inventory, plus a manual finance sign-off.
5. Fulfilment shadow extraction, then cutover: repeat, now consuming live events from the now-authoritative Inventory and Payment services rather than monolith internals. Done when: same criteria, plus end-to-end order lifecycle observable purely via bus events.
6. Monolith module retirement: once all three are cut over and stable for an agreed soak period, delete (not just freeze) the corresponding monolith code and tables. Done when: monolith retains only orchestration logic; dead code removed.

## 5. Sample Acceptance Criteria (EARS)

1. GIVEN the Inventory service is in shadow mode, WHEN an order decrements stock in the monolith, THEN a corresponding InventoryDecremented event is published via the outbox within 5 seconds. VERIFY: integration test outbox_publishes_inventory_decrement_within_sla.
2. GIVEN the Payment cutover flag is enabled for a customer segment, WHEN a payment capture request is routed through the facade, THEN the monolith's legacy payment module receives zero calls for that segment. VERIFY: gate facade_routing_isolation_check asserting zero legacy-module invocation count in metrics for flagged traffic.
3. GIVEN reconciliation is running during the Inventory shadow phase, WHEN stock levels are compared between monolith and new service, THEN drift must remain below 0.1% of active SKUs for 14 consecutive days before cutover is permitted. VERIFY: reconciliation_drift_report gate blocking the cutover flag flip in CI/CD.
4. GIVEN a rollback is triggered on the Payment service, WHEN the feature flag is flipped back to monolith routing, THEN no in-flight payment is left in an inconsistent (charged-but-unrecorded) state. VERIFY: rollback drill test payment_rollback_idempotency_drill run in staging before each cutover milestone.

## 6. Key Risks

- Outbox/dual-write drift accumulates silently if reconciliation isn't monitored closely — mitigate with automated drift alerts and a hard gate blocking cutover progression on drift threshold breach.
- Long coexistence period breeds temporary code that never gets removed (flags and legacy modules linger for years) — mitigate with an explicit retirement milestone and calendar-based forcing function reviewed at each cutover.
- Facade/anti-corruption layer becomes a second monolith if boundaries aren't kept thin — mitigate by scoping the facade strictly to routing/translation, no business logic added there.
- Reconciliation false confidence: passing reconciliation on average traffic misses rare edge cases (partial refunds, concurrent modifications) — mitigate with targeted chaos/edge-case test suites in shadow phase, not just volume-based drift checks.
- Team fatigue from an extended multi-quarter timeline risks corners being cut near the end (fulfilment or retirement phases rushed) — mitigate by keeping the same done bar (shadow period + reconciliation gate) non-negotiable for every phase, including the last.

## 7. Assumptions

1. The monolith has a single transactional database that can support an outbox table and reliable change-capture without major refactoring.
2. The team and organization can tolerate a multi-quarter timeline (roughly 2-4 quarters across three sequential extractions plus soak periods).
3. There is a large enough engineering team to run shadow/monolith paths in parallel and staff reconciliation/monitoring work without starving feature development.

---

### Candidate 2 — "innovative event-first"

> Full subagent output, verbatim (861 words):

# Cross-Service Migration Design: Order-Processing Monolith → Event-Sourced Inventory/Payment/Fulfilment

## 1. Approach

Stand up the event bus and schema registry first as shared infrastructure, then build inventory, payment, and fulfilment as event-sourced services in parallel against contract-first event schemas — not sequentially against the live monolith. Sequencing one service at a time behind synchronous calls to the still-live monolith just recreates synchronous coupling at each new boundary; building all three against agreed contracts up front avoids the trap of service 2 being built against service 1's incidental behavior rather than its contract.

Treat the Order lifecycle as a stream of domain events (OrderPlaced, StockReserved, PaymentCaptured, FulfilmentDispatched, and their failure counterparts). Each service owns a slice of that lifecycle and communicates with the others exclusively via the bus — no synchronous inter-service writes. Inventory goes live with real traffic first because it's the clearest existing bounded context and carries no money-movement risk; payment and fulfilment follow, but all three are engineered together so the full choreography is integration-tested before any one is exposed to production.

For cutover: reject long-lived dual-write compatibility shims. They're extra complexity that must eventually be removed and give false confidence bridging two fundamentally different consistency models. Instead, accept a genuine hard cutover per service — freeze the monolith's write path for that domain, snapshot last-known state into a synthetic genesis event set, switch traffic atomically. This is an explicit, honest bigger-bang moment, not a disguised one.

## 2. Service Boundaries

- Inventory: owns the stock ledger as an event-sourced aggregate (event store + materialized stock-level read model). Consumes OrderPlaced; produces StockReserved, StockReservationFailed, StockReleased.
- Payment: owns the capture state machine keyed by order id. Consumes StockReserved/StockReservationFailed; produces PaymentCaptured, PaymentFailed, PaymentRefunded. Integrates with the external payment gateway as a side-effecting consumer.
- Fulfilment: owns dispatch/shipping workflow. Consumes PaymentCaptured/failures; produces FulfilmentDispatched, FulfilmentFailed.
- Saga coordinator (thin orchestrator): a small process-manager service maintaining the order-level status projection and issuing compensating commands (e.g., ReleaseStock) on downstream failure.

## 3. Event Bus Role

This design depends on the bus more heavily than a conservative approach would, because the log is the source of truth, not a notification layer over a database. Required guarantees: per-key ordering (per order id / SKU); at-least-once delivery with idempotent consumers (dedupe by event id); durable, long-retention replay since read models are derived, not authoritative, and must be rebuildable from scratch; a schema registry enforcing compatibility (additive-only by default) at publish time, since a bad schema change now corrupts the system of record for every downstream service at once.

## 4. Migration Sequencing

1. Stand up bus + schema registry; publish contract-first schemas. Done: registry enforces compatibility in CI.
2. Build all three services + saga coordinator in parallel against contracts; test full choreography with synthetic traffic in staging. Done: happy-path and compensation paths pass end-to-end.
3. Cut over inventory: freeze monolith stock writes, seed genesis events, switch traffic. Done: inventory is sole writer of stock state.
4. Cut over payment similarly. Done: monolith payment path disabled.
5. Cut over fulfilment similarly. Done: monolith fully decommissioned as a write path.
6. Hardening: chaos/failure-injection on saga compensation, replay drills, independent-scaling load tests. Done: documented recovery runbook, demonstrated zero-to-rebuilt read models.

## 5. Sample Acceptance Criteria (EARS)

- AC1: GIVEN a pending reservation exists, WHEN inventory publishes StockReserved, THEN payment SHALL initiate a capture attempt for that order. VERIFY: payment_consumes_stock_reserved_triggers_capture.
- AC2: GIVEN an event with id X was already processed, WHEN X is redelivered, THEN the consumer SHALL NOT apply a duplicate state change. VERIFY: duplicate_event_delivery_is_noop.
- AC3: GIVEN a read-model store is deleted, WHEN the service replays its event stream, THEN the rebuilt model SHALL match the pre-deletion snapshot. VERIFY: rebuild_read_model_from_replay_matches_snapshot.
- AC4: GIVEN payment fails after stock is reserved, WHEN the saga observes PaymentFailed, THEN it SHALL issue ReleaseStock and inventory's read model SHALL reflect released stock. VERIFY: payment_failure_triggers_stock_release_compensation.

## 6. Key Risks

- Cutover risk: freeze/snapshot bugs could cause visible impact. Mitigation: rehearse cutover in staging with production-shaped data and a rollback runbook before the real window.
- Learning curve: event sourcing plus choreography is a real paradigm shift. Mitigation: use inventory (lowest risk) as the deliberate learning vehicle first.
- Eventual-consistency surprises: support/UI tooling expecting instant consistency will see stale reads. Mitigation: design status projections and copy explicitly around propagation delay.
- Irreversible schema mistakes: a bad event schema corrupts the system of record for all consumers. Mitigation: mandatory registry compatibility checks in CI before any publish.
- Saga complexity: distributed partial-failure and out-of-order compensation are harder to test than a DB rollback. Mitigation: dedicated chaos/failure-injection suite covering every compensating path pre-launch.

## 7. Assumptions

- The team is willing to invest in learning event sourcing/CQRS and accepts a multi-week ramp-up.
- The business accepts a real, scheduled freeze/cutover window per service.
- There is appetite and ops capacity for new long-term infrastructure (event bus with replay and schema registry).

---

## 4. EVALUATE — bias-hardened scoring

Per `parallel-spec.md` §2 (R3-09), the evaluator applied all four mandatory
mitigations, **auditably, before running any `ramza-score` call**:

1. **Identity-strip.** Both drafts were re-labeled anonymously before
   scoring — a randomized draw (Python `random`, system entropy) produced:

   ```
   Candidate X -> candidate-1-conservative-strangler-fig
   Candidate Y -> candidate-2-innovative-event-first
   ```

   Dimension scores were fixed against "Candidate X" / "Candidate Y" content
   only; real perspective names were re-attached to the `ramza-score --label`
   values only after both calls returned (labels below are the
   post-reveal names for readability, not what was visible during scoring).

2. **Order-rotation.** A second random draw fixed the presentation/scoring
   order: `['X', 'Y']` — X scored first, Y second. This happened to match
   generation order; that's reported honestly as the real outcome of an
   independent random draw, not re-rolled for a more "interesting" result.

3. **Length-normalization.** Word counts were measured before scoring:
   Candidate 1 = 1448 words, Candidate 2 = 861 words (68% longer for
   Candidate 1). Given that disparity, every dimension score was calibrated
   on *whether the draft substantively addresses that dimension's rubric
   content*, not on verbosity — e.g. Candidate 2's shorter draft still won
   3 of 7 dimensions outright.

4. **Deterministic-anchor.** Before any judgment-based scoring, each
   candidate's sample acceptance criteria were extracted verbatim to
   standalone files and run through the actual mechanical linter:

   ```
   $ ramza-ears-lint .spectra/plans/can-trance-candidate-1.ac.md
   ok: 4 criteria pass EARS lint
   $ ramza-ears-lint .spectra/plans/can-trance-candidate-2.ac.md
   ok: 4 criteria pass EARS lint
   ```

   Both pass after formatting to the mechanical block shape — but the
   anchor surfaced a real, non-cosmetic finding along the way: Candidate 2's
   raw AC4 prose ("it SHALL issue ReleaseStock **and** inventory's read
   model SHALL reflect released stock") is a **compound THEN assertion**,
   which the EARS grammar (`templates/acceptance-criteria.md`) requires to
   be split into two atomic criteria — it had to be trimmed to a single
   assertion to lint clean. Candidate 1's four criteria were already atomic
   as drafted. This tool-anchored finding (not a hand-waved "feels less
   correct") is exactly why Candidate 2 scored lower on `correctness` below.

### Real `ramza-score --rubric explore` calls

```
$ echo '{"alignment":9,"correctness":8,"maintainability":7,"performance":7,"simplicity":9,"risk":9,"innovation":3}' \
    | ramza-score --rubric explore --state .spectra/plans/can-trance.state.json \
      --label "candidate-conservative-strangler-fig"
{
  "rubric": "explore", "total": 79, "verdict": "solid",
  "dims": {"alignment":9,"correctness":8,"maintainability":7,"performance":7,
           "simplicity":9,"risk":9,"innovation":3},
  "label": "candidate-conservative-strangler-fig"
}

$ echo '{"alignment":8,"correctness":7,"maintainability":8,"performance":8,"simplicity":5,"risk":5,"innovation":8}' \
    | ramza-score --rubric explore --state .spectra/plans/can-trance.state.json \
      --label "candidate-innovative-event-first"
{
  "rubric": "explore", "total": 72, "verdict": "solid",
  "dims": {"alignment":8,"correctness":7,"maintainability":8,"performance":8,
           "simplicity":5,"risk":5,"innovation":8},
  "label": "candidate-innovative-event-first"
}
```

Both `solid` (70–84 band); neither `elite` (≥85) nor `weak` (<70). Overall
winner: conservative (79 vs 72) — but critically, **not a sweep**: the
innovative candidate won 3 of 7 dimensions outright (maintainability,
performance, innovation), which is exactly the material a per-dimension
judge-merge (rather than a whole-candidate pick) is for.

## 5. JUDGE-MERGE — per-dimension provenance

| Dimension | Winner | Conservative | Innovative | `[DECISION]` |
|---|---|---|---|---|
| alignment | conservative | 9 | 8 | maps directly onto the literal ask without adding unrequested scope |
| correctness | conservative | 8 | 7 | conservative's ACs were atomic as drafted; innovative's raw AC4 was a compound assertion (deterministic-anchor finding) |
| maintainability | **innovative** | 7 | 8 | schema-registry governance + owned datastores avoid the facade-becomes-second-monolith / dormant-module debt conservative self-flags |
| performance | **innovative** | 7 | 8 | each service independently scalable behind the bus from day one; no indefinite dual-write overhead |
| simplicity | conservative | 9 | 5 | one domain moves at a time; no parallel three-service build-out |
| risk | conservative | 9 | 5 | rollback-by-flag-flip has no equivalent in a hard freeze/cutover moment |
| innovation | **innovative** | 3 | 8 | lightweight saga coordinator + schema-governed contracts adopted for the cross-service compensation problem |

4 of 7 dimensions to conservative, 3 of 7 to innovative — a genuine mixed
merge, not a rebrand of the higher-total candidate. The full synthesized
Approach (with `[DECISION]` markers inline, matching the table above) and
the complete **Rejected Alternatives** section (what specifically did *not*
survive from each candidate, and why) are in the merged spec, §9 below —
reproduced there in full per the "never silently discard a losing branch"
rule.

### T — independent critique (maker≠checker) before Assemble

Full tier requires a critic distinct from the author before entering
Assemble (`ramza-gate advance --to A` mechanically DENIES otherwise). A
second clean-context subagent reviewed the merged draft with no visibility
into the authoring reasoning above — only the plan artifact, the criteria,
and the mechanical lint state, per `skills/critic.md`'s debias procedure.

**Critique verdict** (scored via real `ramza-score --rubric refine --cycle 1`):

```
$ echo '{"clarity":4,"completeness":3,"actionability":4,"efficiency":3,"testability":3}' \
    | ramza-score --rubric refine --state .spectra/plans/can-trance.state.json --cycle 1 \
      --label "can-trance-critic-cycle1"
{"rubric":"refine","cycle":1,"total":3.4,"min":3,
 "dims":{"clarity":4,"completeness":3,"actionability":4,"efficiency":3,"testability":3},
 "verdict":"pass"}
```

Passed the cycle-1 bar (all ≥3) but flagged real, actionable gaps. Full
critique:

> **Verdict:** ramza-lint clean, ramza-ears-lint clean (8/8 at review time).
> Clarity 4, Completeness 3, Actionability 4, Efficiency 3, Testability 3 — pass.
>
> **Findings:** (1) sequencing decision bundled 3 winning dimensions into one
> undifferentiated rationale, asymmetric vs. the other single-dimension
> decisions. (2) Assumption 3 (multi-quarter staffing) has no corresponding
> Risk entry — an organizational load-bearing assumption with no tracked
> failure mode. (3) Story 4 conflated Fulfilment extraction (soak-gated) with
> hardening + retirement (correctness-gated) under one timebox/risk-tag.
> (4) AC-007 ("no inconsistent state") was an unfalsifiable absence claim
> with no verification bound. (5) No criterion covered the compensating
> command itself failing.
>
> **Prescriptions:** add a staffing/timeline risk; rebound AC-007 to "zero
> unresolved drift within N minutes"; add an AC for compensation-command
> failure; split Story 4 into extraction vs. hardening/retirement; justify
> the sequencing decision per-dimension like the others.

**Recorded via real `ramza-gate critic`** (maker≠checker enforced mechanically):

```
$ ramza-gate critic --state .spectra/plans/can-trance.state.json \
    --author "ramza-session-claude-sonnet-5" --checker "critic-subagent-a108b21d319a19e4f"
OK: critic recorded (author: ramza-session-claude-sonnet-5, checker: critic-subagent-a108b21d319a19e4f)
```

**One refine cycle (of the standard 3-cycle cap — distinct from the
Parallel-Spec-Mode iteration cap discussed in §6)** was spent applying all
five prescriptions: added the staffing/timeline risk (Risks table, last
row); rebounded AC-007 to a 15-minute drift-window check; added AC-009 for
compensation-command failure with backoff+escalate; split the former
Story 4 into Story 4 (Fulfilment extraction) and Story 5 (hardening +
retirement); and rewrote the sequencing decision to cite alignment/risk/
simplicity individually rather than bundled. Re-verification after the
edits:

```
$ ramza-ears-lint .spectra/plans/can-trance.criteria.md
ok: 9 criteria pass EARS lint
$ ramza-lint --plan .spectra/plans/can-trance.md --state .spectra/plans/can-trance.state.json
ok: plan passes structural lint (tier: full)
$ ramza-gate advance --to T --state .spectra/plans/can-trance.state.json   # R -> T re-verify
OK: R -> T
$ ramza-gate advance --to A --state .spectra/plans/can-trance.state.json
OK: T -> A
```

## 6. TERMINATE

```
$ echo '{"pattern_match":60,"requirement_clarity":78,"decomposition_stability":75,"constraint_compliance":92}' \
    | ramza-score --rubric confidence --state .spectra/plans/can-trance.state.json \
      --label "can-trance-assemble-confidence"
{"rubric":"confidence","total":76.25,"verdict":"VALIDATE",
 "dims":{"pattern_match":60,"requirement_clarity":78,"decomposition_stability":75,"constraint_compliance":92}}
```

**76.25% → VALIDATE** — below the ≥85% AUTO_PROCEED threshold that would
auto-clear the mode, but also well above the 50–69 COLLABORATE or <50
ESCALATE bands. Parallel Spec Mode's termination rule is: stop at
confidence ≥85% **or** iteration cap 3, whichever comes first. This run
stopped after **iteration 1 of the 3-iteration cap** — the cap was not
exhausted, and the loop was not terminated *by* the cap.

**Why iteration 1 was the right place to stop, not a premature exit:** the
one dimension holding confidence below 85 is `pattern_match` (60/100),
scored low for the same reason the reference `ab1-dryrun`/`ab2-dryrun`
canary runs in this same consumer project scored it low — this exercise has
no real order-processing codebase to confirm the assumed service/module
boundaries against (Scope → Assumptions). That is a structural property of
the exercise's environment, not a defect in either candidate's design
quality that a second GENERATE→EVALUATE→JUDGE-MERGE round could plausibly
fix — spending iteration 2 re-running the same fan-out against the same
absent codebase would be exactly the "ceremony is a failure mode" anti-
pattern RAMZA is built to avoid, for zero expected confidence gain. The
confidence rubric's own semantics back this: 70–84 means **VALIDATE — a
human reviews before proceeding** — a designed stopping point, not a
"machine, iterate again" signal. Had the verdict landed in COLLABORATE or
ESCALATE territory instead, a second iteration (or a `[GAP]` escalation)
would have been warranted; it did not.

## 7. Assemble exit gates (real tool calls)

```
$ ramza-drift --state .spectra/plans/can-trance.state.json --declare \
    'services/inventory/* services/payment/* services/fulfilment/* services/saga-coordinator/* lib/event-bus/* schemas/events/* monolith/order/* docs/architecture/*'
scope declared: 8 glob(s)

$ ramza-freeze --state .spectra/plans/can-trance.state.json --criteria .spectra/plans/can-trance.criteria.md
frozen: 7149f77ff59d52ccb0ac35fdd47b14b4df2c47e2ecb2b4029d27c884e9e12b72

$ ramza-verify-emit --spec .spectra/plans/can-trance.md --envelope .spectra/plans/can-trance.envelope.json \
    --schema-dir .eidolons/ramza/schemas
ok: emission gate passed (can-trance.md + envelope)

$ ramza-gate advance --to DONE --state .spectra/plans/can-trance.state.json
OK: A -> DONE
```

Final state: `tier: full`, `phase: DONE`, `refine_cycles: 1`,
`criteria_frozen: true`, `critic: {author: ramza-session-claude-sonnet-5,
checker: critic-subagent-a108b21d319a19e4f}`, `gates[]` holds all five real
scored gates in order (complexity → explore ×2 → refine → confidence).

ECL envelope emitted (`envelope_version 2.0`, `performative PROPOSE`,
`trace.tier: "trance"`, `integrity.value` = the recomputed sha256 of the
spec bytes, `x_ramza_acceptance_criteria` carrying the frozen criteria hash)
— verified against `schemas/ecl-envelope.v2.json` by the emission gate
above.

## 8. Preflight checklist (per `SPEC.md`)

- [x] RS ran; tier recorded (full, score 9)
- [x] Phase walk clean in state — one recorded refine cycle (1/3), no
      unexplained skips
- [x] Hypotheses (candidates) scored via tool; rejected-alternative
      rationale documented for both
- [x] `ramza-lint` + `ramza-ears-lint` green (post-refine: 9/9 criteria)
- [x] Full tier: critic recorded, author ≠ checker
- [x] Confidence computed via tool (76.25% VALIDATE); verdict honored —
      flagged for human review, not silently upgraded
- [x] Scope declared; criteria frozen; `ramza-verify-emit` green
- [x] Every output path under `.spectra/`; no code produced

---

## 9. Final dual-format artefact

### 9a. Markdown spec (`.spectra/plans/can-trance.md`, frozen criteria SHA-256
`7149f77ff59d52ccb0ac35fdd47b14b4df2c47e2ecb2b4029d27c884e9e12b72`)

---
eidolon: ramza
kind: spec
version: "0.1.0"
created_at: "2026-07-05T13:08:29Z"
---

# Plan: Split order-processing monolith into inventory, payment, fulfilment services on a new event bus

## Scope

Intent class: STRATEGIC

In: Decompose the existing monolithic order-processing service into three
independently deployable services — Inventory, Payment, Fulfilment — and
introduce a new event bus as the integration backbone between them and the
remaining monolith/orchestration layer. Covers: service boundary definition,
event schema/contract governance, staged extraction sequencing per service
(shadow → validated → cutover), the compensation mechanism for the
cross-service order-fulfilment workflow, and retirement of the corresponding
monolith modules once each service is stable.

Out: Introducing a brand-new customer-facing "order" product surface; a
general-purpose internal platform/event-bus offering for unrelated domains;
changing the payment gateway/PSP integration itself; a full event-sourced
rewrite of every domain (each service keeps its own transactional store as
its domain's source of truth — see Approach); zero-downtime guarantees beyond
what feature-flagged routing already provides.

Deferred: A fully event-sourced read/write model per service (event log as
the sole system of record with full replay-based rebuild) — noted in
Rejected Alternatives as a plausible future evolution once the staged
extraction is complete and the schema-governed event contracts have proven
stable in production, not a prerequisite for this migration to close.

Assumptions:
- The monolith has a single transactional database capable of supporting an
  outbox table / reliable change-capture without a prerequisite storage
  migration. Risk if wrong: an event-driven CDC tool becomes a dependency
  added before Story 1 can start (see Risks).
- No internal prior art for this kind of extraction exists in this
  repository (Pattern search found none) — the design instead follows
  established cross-industry patterns (strangler fig, outbox, schema
  registry, saga/process-manager) rather than in-repo precedent. Risk if
  wrong: naming/structural choices may need to be reconciled with an
  existing internal convention once real code is inspected.
- The organization can staff a multi-quarter timeline (sequential
  extraction, one domain at a time) and tolerates a real, scheduled
  soak/reconciliation period per service before authority transfers. Risk if
  wrong: sequencing in Approach would need to compress, trading away some of
  the rollback safety this plan is built around.

Complexity (`ramza-score --rubric complexity`): 11/12 → **human_loop**
(dims: scope 3, ambiguity 3, dependencies 3, risk 2 — recorded in
`.spectra/plans/can-trance.state.json` gates[], label
`monolith-split-scope-complexity`). TRANCE tier was authorized on exactly
this signal combination (complexity 10–12 AND multi-service STRATEGIC change
AND high rework risk — both cortex-authorization conditions hold), which is
why this spec was produced via Parallel Spec Mode rather than the standard
single-pass cycle.

## Approach

This Approach is a **judge-merged synthesis** of two perspective-diverse
candidate specs generated in clean-context branches and scored with
`ramza-score --rubric explore` under bias-hardened evaluation (see
Rejected Alternatives for what each candidate proposed and what did not
survive the merge; see the mission trace for the full scoring record).
Per-dimension `[DECISION]` markers below cite which candidate's approach won
that dimension and why.

**Sequencing and safety backbone** (three separate wins, cited individually
per the critic's cycle-1 prescription rather than bundled into one
undifferentiated rationale):
- `[DECISION: alignment → Candidate "conservative strangler-fig", 9 vs 8]` —
  the request asked for a migration that splits the monolith into three
  services with a new event bus; the conservative candidate's staged,
  reversible extraction maps onto that ask without introducing scope the
  request didn't call for (e.g. no mandatory event-sourcing rewrite).
- `[DECISION: risk → Candidate "conservative strangler-fig", 9 vs 5]` — its
  rollback-by-flag-flip plus reconciliation-gated cutover means no
  service's failure mode requires a data-migration undo; the innovative
  candidate's hard freeze/cutover moment has no equivalent instant
  rollback.
- `[DECISION: simplicity → Candidate "conservative strangler-fig", 9 vs
  5]` — one domain moves at a time, so at most one migration's worth of new
  operational complexity is live at once, versus the innovative candidate's
  parallel three-service build-out.

The migration proceeds **one service at a time — Inventory, then Payment,
then Fulfilment** — behind a facade/anti-corruption layer, with each service
passing through shadow mode (new service builds its own store from bus
events while the monolith remains authoritative) and a reconciliation-gated
cutover (feature-flag flip, old module retained dormant for instant
rollback) before authority transfers. Inventory is first because it carries
no direct financial risk and has the cleanest existing read/write boundary;
Payment second so the extraction mechanics are already proven before the
highest-blast-radius domain moves; Fulfilment last because it depends on
both. No big-bang, simultaneous three-service cutover is attempted — that
would multiply moving parts exactly where failure is most expensive to
diagnose.

**Event contracts and bus guarantees** — `[DECISION: maintainability →
Candidate "innovative event-first", 8 vs 7]` `[DECISION: performance →
Candidate "innovative event-first", 8 vs 7]`. Unlike a bus that starts
"deliberately underpowered" as notification-only and is upgraded later
(which risks a second migration to retrofit rigor once services depend on
it), the merged design adopts **contract-first, schema-registry-governed
event schemas from day one** — additive-only compatibility enforced at
publish time — plus **per-key ordering** (partition by order id) and
**at-least-once delivery with idempotent, dedupe-on-event-id consumers**,
even during the shadow phase. This avoids a later bus-guarantee upgrade
becoming its own risky migration, and lets each service scale independently
behind the bus from the moment it goes live rather than only after a
notification-only period ends.

**Cross-service compensation** — `[DECISION: innovation → Candidate
"innovative event-first", 8 vs 3]`. Rather than relying purely on ad hoc
reconciliation jobs to catch cross-service inconsistency after the fact, the
merged design introduces a **lightweight saga coordinator** (a thin
process-manager, not a full choreography-only design) that reacts to
failure events (e.g. `PaymentFailed`) and issues the corresponding
compensating command (e.g. `ReleaseStock`). This is scoped narrowly to the
one place a 3-hop distributed workflow with compensation genuinely needs it
— it does not imply full event-sourced aggregates anywhere else in the
design.

**Data consistency mechanism** — `[DECISION: correctness → Candidate
"conservative strangler-fig", 8 vs 7]`. Each service's own transactional
store — not the event log — remains the authoritative source of truth for
its domain once cut over (full event-sourcing was considered and deferred,
see Rejected Alternatives). During shadow mode, dual-write with a
time-boxed, gated reconciliation window (not an open-ended one — each
service's shadow phase has an explicit soak-period exit criterion, see
Migration Sequencing) is the trust mechanism, not a distributed transaction
and not a permanent compatibility shim.

**Rollback** at any point before a service's authority-transfer milestone is
a flag flip back to monolith routing — no data-migration undo is required
because the monolith's own writes never stopped during shadow mode.

## Stories

### Story 1: Event contract and facade scaffolding

As a platform engineer, I want the event bus, schema registry, and
facade/anti-corruption layer stood up before any service extraction begins,
so that every subsequent extraction has a governed contract surface and a
single routing seam to flip.
Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan: outbox table + publisher,
schema registry with CI compatibility gate (AC-001), facade routing layer
with per-domain feature flags.

### Story 2: Extract Inventory (shadow → validated cutover)

As a release engineer, I want the Inventory domain extracted first, running
in shadow mode against reconciled state before authority transfers, so that
the extraction pattern is proven on the lowest-financial-risk domain before
Payment relies on the same mechanics.
Timebox: 5d (across shadow soak + cutover).
Risk tag: P1.
Executor hint: mid tier — named pattern (strangler-fig shadow + reconciliation
gate, AC-002/AC-004); reuse the Story 1 facade and schema contracts unchanged.

### Story 3: Extract Payment (shadow → validated cutover) with saga wiring

As a release engineer, I want Payment extracted with the same shadow/cutover
discipline as Inventory, plus the saga coordinator wired to react to payment
failure, so that a failed capture after stock reservation reliably triggers
stock release without manual intervention.
Timebox: 6d (longer shadow soak given financial blast radius).
Risk tag: P0.
Executor hint: mid tier — file-level action plan for the saga coordinator's
`PaymentFailed → ReleaseStock` compensation path (AC-006); this story's tests
are the ones most worth a second reviewer's eyes given the P0 tag.

### Story 4: Extract Fulfilment (shadow → validated cutover)

As a release engineer, I want Fulfilment extracted last, consuming live
events from the now-authoritative Inventory and Payment services, so that
the final domain moves only once its upstream dependencies are themselves
stable services rather than moving targets.
Timebox: 5d (shadow soak + cutover, same gate discipline as Stories 2–3).
Risk tag: P1.
Executor hint: mid tier — reuse the Story 2/3 shadow + reconciliation-gate
pattern unchanged; this story's exit gate is AC-003/AC-004 as usual.

### Story 5: Harden the saga's failure paths and retire monolith modules

As an on-call engineer, I want the full choreography's compensation paths
hardened under failure injection (including the compensating command itself
failing) and each retired monolith module actually deleted — not just
disabled — once its soak period ends, so that the migration reaches a clean
end state with no untested failure path and no lingering dead code or
rollback debt.
Timebox: 3d.
Risk tag: P0 (split out from the former combined Story 4 per the critic's
cycle-1 finding: hardening's correctness-validation exit gate and
retirement's soak-based exit gate are different conditions and shouldn't
share one timebox with extraction).
Executor hint: mid tier — file-level action plan for chaos/failure-injection
on the saga's compensation paths (AC-009: compensating command itself fails
→ retry with backoff → escalate), plus the dead-code-removal checklist
(AC-008).

## Acceptance Criteria

(Full EARS-form blocks below; frozen via `ramza-freeze` — see Confidence
section for the criteria SHA-256. Source file:
`.spectra/plans/can-trance.criteria.md`, lint-verified: `ok: 9 criteria pass
EARS lint`. AC-007 was rewritten and AC-009 added during the T→R refine
cycle per the independent critic's cycle-1 prescriptions — see Confidence
section for the refine-rubric verdict.)

### AC-001 (event-driven)
GIVEN a new or changed event schema is submitted for any of the InventoryDecremented, StockReserved, PaymentCaptured, or FulfilmentDispatched event families
WHEN  the schema is published to the registry
THEN  the registry SHALL reject the publish unless the change is backward-compatible with all existing consumers
VERIFY: gate: schema_registry_compatibility_check_ci

### AC-002 (event-driven)
GIVEN the Inventory service is in shadow mode
WHEN  an order decrements stock in the monolith
THEN  a corresponding InventoryDecremented event SHALL be published via the outbox within 5 seconds
VERIFY: test: outbox_publishes_inventory_decrement_within_sla

### AC-003 (unwanted-behavior)
GIVEN a service's cutover flag is enabled for a given traffic segment
WHEN  a request for that domain is routed through the facade
THEN  the monolith's corresponding legacy module SHALL receive zero calls for that segment
VERIFY: gate: facade_routing_isolation_check

### AC-004 (event-driven)
GIVEN reconciliation is running during a service's shadow phase
WHEN  state is compared between the monolith and the new service
THEN  drift SHALL remain below 0.1% of compared records for 14 consecutive days before cutover is permitted
VERIFY: gate: reconciliation_drift_report

### AC-005 (unwanted-behavior)
GIVEN an event with a given event id was already processed by a consumer
WHEN  that same event id is redelivered
THEN  the consumer SHALL NOT apply a duplicate state change
VERIFY: test: duplicate_event_delivery_is_noop

### AC-006 (event-driven)
GIVEN payment fails after stock has been reserved for an order
WHEN  the saga coordinator observes the PaymentFailed event
THEN  the saga coordinator SHALL issue a ReleaseStock compensating command for that order
VERIFY: test: payment_failure_triggers_stock_release_compensation

### AC-007 (unwanted-behavior)
GIVEN a rollback is triggered on a cut-over service
WHEN  the feature flag is flipped back to monolith routing
THEN  the post-rollback reconciliation report SHALL show zero unresolved drift within 15 minutes of the flip
VERIFY: test: rollback_idempotency_drill

### AC-008 (ubiquitous)
THEN a service's retired monolith module SHALL be deleted, not merely disabled, once that service has been at 100% cutover for its full soak period
VERIFY: gate: dead_code_removal_check

### AC-009 (unwanted-behavior)
GIVEN the saga coordinator issues a ReleaseStock compensating command after a PaymentFailed event
WHEN  that compensating command itself fails to apply
THEN  the saga coordinator SHALL retry the compensating command with backoff and escalate to a P0 alert if still unresolved after 3 attempts
VERIFY: test: compensation_failure_retries_then_escalates

## Confidence

`ramza-score --rubric confidence`: 76.25% → **VALIDATE** (human reviews)
— dims: pattern_match 60, requirement_clarity 78, decomposition_stability 75,
constraint_compliance 92 (recorded in state, label
`can-trance-assemble-confidence`). Scored VALIDATE rather than AUTO_PROCEED
specifically because `pattern_match` is honestly capped: no real
order-processing codebase exists in this exercise to confirm the assumed
module/boundary layout against (see Scope → Assumptions). This is a
structural property of the exercise, not a spec-quality gap a further
Parallel Spec Mode iteration could close — see the mission record's
Termination note for why the parallel-spec loop stopped at iteration 1/3
rather than spending a second GENERATE→EVALUATE round chasing this ceiling.
A human should confirm the real service/module boundaries before Story 1
starts.

Criteria frozen: SHA-256
`7149f77ff59d52ccb0ac35fdd47b14b4df2c47e2ecb2b4029d27c884e9e12b72` recorded
via `ramza-freeze` against `.spectra/plans/can-trance.criteria.md` (see state
file `criteria_sha256`). Refine history: 1 cycle (of a 3-cycle cap) — cycle 1
`ramza-score --rubric refine` total 3.4/5, verdict `pass` (dims: clarity 4,
completeness 3, actionability 4, efficiency 3, testability 3) — see mission
record for the independent critic's findings and the prescriptions applied
during T→R.

## Rejected Alternatives

- **Candidate "conservative strangler-fig"** (full draft scored via
  `ramza-score --rubric explore`: total 79, verdict `solid` — dims:
  alignment 9, correctness 8, maintainability 7, performance 7,
  simplicity 9, risk 9, innovation 3). Won alignment, correctness,
  simplicity, and risk — its sequencing, facade/rollback discipline, and
  dual-write-with-reconciliation trust mechanism were carried into the
  merged Approach unchanged. **What did not survive the merge:** its
  "deliberately underpowered," notification-only initial bus (upgraded to
  authoritative only after a service's shadow phase ends) was rejected in
  favor of contract-first, schema-registry-governed events from day one —
  retrofitting bus rigor later is itself a risky second migration, which
  this candidate's own maintainability score (7, lowest-weighted dimension
  loss) reflected. Its reliance on ad hoc reconciliation as the sole
  cross-service consistency mechanism (no compensation coordinator for the
  3-hop order flow) was also not adopted wholesale — see the saga
  coordinator decision above.
- **Candidate "innovative event-first"** (full draft scored via
  `ramza-score --rubric explore`: total 72, verdict `solid` — dims:
  alignment 8, correctness 7, maintainability 8, performance 8,
  simplicity 5, risk 5, innovation 8). Won maintainability, performance,
  and innovation — its schema-registry-governed contracts, per-key
  ordering + idempotent-consumer bus guarantees, and lightweight saga
  coordinator were carried into the merged Approach. **What did not
  survive the merge:** its "build all three services in parallel against
  contracts, then hard-cutover per service" sequencing was rejected in
  favor of the strictly sequential inventory→payment→fulfilment staged
  extraction — parallel construction against untested contracts scored
  lowest on this candidate's own risk (5) and simplicity (5) dimensions.
  Its rejection of "long-lived dual-write compatibility shims" in favor of a
  hard freeze/snapshot/cutover moment per service was also rejected — the
  merged design keeps a time-boxed (not open-ended) dual-write/shadow-
  reconciliation window per service specifically because it won on risk and
  alignment. Full event-sourced aggregates as the system of record for
  every domain were deferred rather than adopted now (see Scope →
  Deferred) — each service's own transactional store remains its domain's
  source of truth in this merged design.

**Bias mitigations applied during evaluation** (deterministic-anchor,
identity-strip, order-rotation, length-normalization — see mission record
for the full audit): both candidates' acceptance criteria were extracted to
standalone files and run through `ramza-ears-lint` as the deterministic
correctness anchor before any dimension was scored by judgment; scoring was
performed against randomized anonymized labels ("Candidate X" / "Candidate
Y") with a randomized presentation order, re-attached to the real
perspective names only after both `ramza-score` calls completed; candidate
drafts differed materially in length (1448 vs 861 words) and dimension
scores were deliberately calibrated on rubric-content density (does the
draft address the dimension, not how many words it spends doing so) rather
than verbosity.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| A side-effecting call site in any service's extraction is missed by the facade guard, so a cutover flag silently lets a real action fall through to the wrong path | P0 | AC-003's facade-isolation gate runs per cutover milestone; Story 2–4 each timebox an explicit audit of that domain's call sites before sign-off |
| Schema-registry compatibility gate is bypassed or misconfigured, allowing a breaking event-schema change to reach production and corrupt every downstream consumer's read model at once | P0 | AC-001 is a hard CI gate, not advisory; schema changes require the gate to pass before merge, with no override path documented in this spec |
| Dual-write/reconciliation window silently drifts without anyone noticing (candidate-conservative's own self-flagged risk) | P1 | AC-004's drift gate blocks cutover progression automatically; reconciliation results are a scheduled, monitored job, not a one-time check |
| Saga coordinator's compensation logic has an untested failure/partial-failure path (candidate-innovative's own self-flagged risk: distributed partial failure is harder to test than a DB rollback) | P1 | Story 4's hardening phase requires chaos/failure-injection testing specifically on every compensating path before Fulfilment's cutover, not just the happy path |
| Long coexistence period (facade + dormant legacy modules) breeds "temporary" code that never gets removed | P2 | AC-008 makes retirement a hard gate, not a follow-up ticket; each story's "done" bar includes deletion, not just disablement |
| No internal codebase pattern exists for this kind of extraction (Pattern phase found none in this project), so naming/structural choices rely on external convention rather than in-repo precedent | P2 | Followed widely adopted conventions (strangler fig, outbox, schema registry, saga/process-manager) so a future implementer has an unambiguous, well-documented target; assumptions recorded explicitly in Scope |
| The multi-quarter, sequential-extraction timeline (Scope → Assumption 3) is a load-bearing organizational commitment, not just a technical one — staffing or priority slippage mid-sequence could strand a service half-extracted | P1 | Added during the T→R refine cycle per the critic's completeness finding: each cutover milestone (Stories 2–4) requires an explicit go/no-go checkpoint, and a service left in shadow mode indefinitely is a valid, safe (if suboptimal) state to pause in — never a forced cutover under schedule pressure |

### 9b. Agent-executable structured data

```yaml
schema: ramza/spec-profile.v1
plan: can-trance
eidolon: ramza
version: "0.1.0"
kind: spec
tier: full
intent_class: STRATEGIC
trance:
  authorized: true
  authorization_signal:
    complexity_total: 11
    complexity_band: human_loop
    multi_service: true
    stakes: high
    rework_risk: high
  mode: parallel_spec_g3
  branches: 2
  branches_cap: 4
  iterations_used: 1
  iterations_cap: 3
complexity:
  rubric: complexity
  dims: {scope: 3, ambiguity: 3, dependencies: 3, risk: 2}
  total: 11
  verdict: human_loop
candidates:
  - id: candidate-conservative-strangler-fig
    perspective: conservative
    explore:
      dims: {alignment: 9, correctness: 8, maintainability: 7, performance: 7,
             simplicity: 9, risk: 9, innovation: 3}
      total: 79
      verdict: solid
    word_count: 1448
  - id: candidate-innovative-event-first
    perspective: innovative
    explore:
      dims: {alignment: 8, correctness: 7, maintainability: 8, performance: 8,
             simplicity: 5, risk: 5, innovation: 8}
      total: 72
      verdict: solid
    word_count: 861
bias_mitigations:
  identity_strip: true
  order_rotation: [X, Y]
  length_normalized: true
  deterministic_anchor: ramza-ears-lint
judge_merge_decisions:
  - dimension: alignment
    winner: candidate-conservative-strangler-fig
    scores: {conservative: 9, innovative: 8}
  - dimension: correctness
    winner: candidate-conservative-strangler-fig
    scores: {conservative: 8, innovative: 7}
  - dimension: maintainability
    winner: candidate-innovative-event-first
    scores: {conservative: 7, innovative: 8}
  - dimension: performance
    winner: candidate-innovative-event-first
    scores: {conservative: 7, innovative: 8}
  - dimension: simplicity
    winner: candidate-conservative-strangler-fig
    scores: {conservative: 9, innovative: 5}
  - dimension: risk
    winner: candidate-conservative-strangler-fig
    scores: {conservative: 9, innovative: 5}
  - dimension: innovation
    winner: candidate-innovative-event-first
    scores: {conservative: 3, innovative: 8}
critic:
  author: ramza-session-claude-sonnet-5
  checker: critic-subagent-a108b21d319a19e4f
  refine_cycle: 1
  refine_cycles_cap: 3
  refine_score: {clarity: 4, completeness: 3, actionability: 4, efficiency: 3, testability: 3}
  refine_total: 3.4
  refine_verdict: pass
stories:
  - id: 1
    title: Event contract and facade scaffolding
    timebox: 2d
    risk_tag: P1
    executor_tier: mid
  - id: 2
    title: Extract Inventory (shadow -> validated cutover)
    timebox: 5d
    risk_tag: P1
    executor_tier: mid
  - id: 3
    title: Extract Payment (shadow -> validated cutover) with saga wiring
    timebox: 6d
    risk_tag: P0
    executor_tier: mid
  - id: 4
    title: Extract Fulfilment (shadow -> validated cutover)
    timebox: 5d
    risk_tag: P1
    executor_tier: mid
  - id: 5
    title: Harden saga failure paths and retire monolith modules
    timebox: 3d
    risk_tag: P0
    executor_tier: mid
acceptance_criteria:
  - {id: AC-001, form: event-driven, verify: "gate:schema_registry_compatibility_check_ci"}
  - {id: AC-002, form: event-driven, verify: "test:outbox_publishes_inventory_decrement_within_sla"}
  - {id: AC-003, form: unwanted-behavior, verify: "gate:facade_routing_isolation_check"}
  - {id: AC-004, form: event-driven, verify: "gate:reconciliation_drift_report"}
  - {id: AC-005, form: unwanted-behavior, verify: "test:duplicate_event_delivery_is_noop"}
  - {id: AC-006, form: event-driven, verify: "test:payment_failure_triggers_stock_release_compensation"}
  - {id: AC-007, form: unwanted-behavior, verify: "test:rollback_idempotency_drill"}
  - {id: AC-008, form: ubiquitous, verify: "gate:dead_code_removal_check"}
  - {id: AC-009, form: unwanted-behavior, verify: "test:compensation_failure_retries_then_escalates"}
confidence:
  rubric: confidence
  dims: {pattern_match: 60, requirement_clarity: 78, decomposition_stability: 75, constraint_compliance: 92}
  total: 76.25
  verdict: VALIDATE
termination:
  reason: confidence_validate_band_structural_ceiling
  iteration_stopped_at: 1
  iteration_cap: 3
  cap_exhausted: false
declared_scope:
  - "services/inventory/*"
  - "services/payment/*"
  - "services/fulfilment/*"
  - "services/saga-coordinator/*"
  - "lib/event-bus/*"
  - "schemas/events/*"
  - "monolith/order/*"
  - "docs/architecture/*"
criteria_sha256: "7149f77ff59d52ccb0ac35fdd47b14b4df2c47e2ecb2b4029d27c884e9e12b72"
envelope:
  path: ".spectra/plans/can-trance.envelope.json"
  performative: PROPOSE
  trace_tier: trance
  verify_emit: pass
```

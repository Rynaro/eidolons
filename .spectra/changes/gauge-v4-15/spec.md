# V4-15 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-15 — Deliver an observable runnable slice and recover it

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-11`, `V4-12`, `V4-13`, `V4-14`.

**Starting points:** Existing sandbox loop, `cli/src/context.sh`, `cli/src/context_externalize.sh`, V4-06 task state, V4-09 comparison instrument. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** One bounded brownfield task to runnable candidate, protected acceptance, or preserved incomplete progress. Keep one maker as default and retain current charters through explicit experimental profiles. Include minimal inspect/status/resume/cancel CLI/JSON NOW; V4-20 extends it later. Separate process/session/environment replacement from durable task continuity. Classify environment/schema/permission/provider/test/causal/acceptance failure before recovery.

**Implementation sequence.** Run a deterministic fixture end to end; expose pending intents, candidate, acceptance and resource state; fault-inject at dispatch/edit/check/checkpoint boundaries; run separately authorized native demonstration and initial fixed-model comparison through V4-09. Record null/blocked outcomes honestly; no assumed advantage.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-15-R01 | WHEN a bounded implementation assignment has sufficient authority and inputs, the delivery loop SHALL progress through its authorized internal phases without requesting routine continuation. | **V4-15-T01:** Record interventions in fixture/live cases; unresolved consequential product decision remains an exception. |
| V4-15-R02 | WHEN a runnable milestone is reported, the controller SHALL reference an executed check of the requested behavior. | **V4-15-T02:** Stub scaffold, prose completion, fake log, and genuine behavior/integration controls. |
| V4-15-R03 | IF remaining resources cannot support mandatory work, THEN the delivery loop SHALL preserve progress as a nonaccepted partial or blocked result. | **V4-15-T03:** Exhaust before verification or after one slice; whole-task acceptance remains incomplete. |
| V4-15-R04 | IF repeated failure yields no new evidence within the configured bound, THEN recovery SHALL stop repeating that approach. | **V4-15-T04:** Stable signature across workers/context resets; mechanical failure does not trigger unbounded forensics. |
| V4-15-R05 | WHEN a task resumes, recovery SHALL preserve its root accounting, authority, candidate identities, and outstanding verification obligations. | **V4-15-T05:** Interrupt before/after send, edit, freeze, check, and checkpoint; reconcile uncertainty before continuing. |
| V4-15-R06 | IF a checkpoint is stale, tampered, or lacks a usable native session, THEN recovery SHALL report the exact limitation without discarding valid local artifacts. | **V4-15-T06:** Changed criteria, tampered payload, missing native history, and optional memory outage; preserve portable artifacts. |
| V4-15-R07 | WHEN an operator inspects the demonstrator, the CLI SHALL expose candidate, acceptance, pending execution, resource exposure, and next-action state without dispatching model work. | **V4-15-T07:** Inspect unknown/running/cancellation-pending/partial tasks; filesystem and model-call counters prove observational behavior. |
| V4-15-R08 | WHEN context is compacted or replaced, recovery SHALL preserve validated task obligations and source references independently of the generated summary. | **V4-15-T08:** Summary omits a failed approach or required check; canonical obligations remain, source can be reopened, and access restrictions persist. |
| V4-15-R09 | WHEN an authorized demonstrator comparison completes, the evaluator SHALL record its native-control and v4 outcomes through the V4-09 instrument. | **V4-15-T09:** Same-model bounded task with intervention and recovery observations; missing or ineligible live arm remains explicit, never fabricated. |
| V4-15-R10 | IF an interruption leaves possible external effects unresolved, THEN resume SHALL expose that uncertainty before admitting dependent work. | **V4-15-T10:** Effect occurred with lost acknowledgement; successor cannot assume completion, absence, or refunded exposure. |

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve runnable partial artifacts and state. No silent scope reduction, routine continue prompts, or promises of background work not actually scheduled. Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

## Bounded decision

See [decision.md](decision.md). Schema-2 additive delivery namespaces. Fixture end-to-end loop with fault inject. Reuse V4-11/12/13/14/09. Minimal operator CLI now; V4-20 later. No V4-16+ / V4-21.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Reuse V4-11 reservations, V4-12 dispatch, V4-14 freeze/check, and V4-09 instrument. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-16+ / V4-20 full / V4-21.

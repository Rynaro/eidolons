# Stage 3 — One observable managed delivery demonstrator

Use one qualified native mode, conditional execution boundaries, protected acceptance, durable recovery, and minimal operator controls. Broad repository migration is not a prerequisite.

Read [HANDOFF.md](HANDOFF.md) and the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries. [plan.yaml](plan.yaml) owns dependencies and source routing; these tables own requirement text. [RESEARCH.md](RESEARCH.md) explains the evidence-to-design mapping without adding hidden obligations.

**Common exit for every package:** map every applicable Rxx to its planned Txx and actual observed evidence. Exercise relevant rejection paths and the intended gate. Mark unavailable required evidence blocked; mark optional cases not applicable only with their feature/scope condition recorded. Authored requirements, authored tests, executed fixtures, observed CI, and live-host qualification are distinct. A fixture-only candidate can be ready for review without a live-managed claim. See HANDOFF.md for receipts and acceptance.

---

<a id="v4-11"></a>

## V4-11 — Atomic reservations with verification and recovery headroom

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-08`, `V4-09`.

**Starting points:** V4-06 store, V4-08 observation interface, `roster/context-policy.yaml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Remove V4-10 as a prerequisite. Implement local atomic admission across task/project/account/window/concurrency scopes. Reserve before dispatch and protect verification/recovery. Respect adapter granularity and uncertain in-flight costs; do not claim exact external billing or cross-device accounting. Unknown hard-limited dimensions need an authorized conservative bound or dispatch remains blocked.

**Implementation sequence.** Define reservation states/estimate provenance; implement atomic admission with no remote call inside a transaction; test contention, interruption, stale data, rollover, cancellation, and amendments.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-11-R01 | WHEN concurrent assignments request capacity, admission SHALL reserve resources without jointly exceeding any applicable known local ceiling. | **V4-11-T01:** Synchronized contenders in two projects sharing a pool; verify accepted IDs and all scoped balances. |
| V4-11-R02 | WHILE verification or recovery headroom is reserved, admission SHALL exclude that headroom from new optional implementation work. | **V4-11-T02:** Near-limit exploration rejects while authorized verification can use its designated reserve. |
| V4-11-R03 | IF observed consumption exceeds its estimate, THEN admission SHALL stop new work that would exceed an applicable ceiling. | **V4-11-T03:** Overrun, late usage, and corrections retain actual exposure rather than clamping it away. |
| V4-11-R04 | IF a dispatched reservation has an unknown outcome, THEN reconciliation SHALL retain its uncertain exposure. | **V4-11-T04:** Crash, timeout, missing callback, and cancellation-after-send; no automatic release. |
| V4-11-R05 | WHEN a provider allowance window resets, accounting SHALL preserve the root task consumption already incurred. | **V4-11-T05:** Late old-window event and new-window reading change provider window, not task budget. |
| V4-11-R06 | IF authoritative accounting is unavailable, THEN managed admission SHALL reject new dispatch. | **V4-11-T06:** Corruption, lock timeout, full storage, and read-only store; advisory hooks retain their separate error policy. |
| V4-11-R07 | IF a hard-limited resource dimension lacks a usable observation or authorized conservative bound, THEN admission SHALL reject work consuming that dimension. | **V4-11-T07:** Unknown allowance/cost with a hard ceiling versus explicit bounded mode; unsupported data never becomes unlimited capacity. |
| V4-11-R08 | WHEN a child or retry is admitted, admission SHALL reserve its implementation, integration, and required verification exposure under the parent task. | **V4-11-T08:** Parallel child, failed candidate, and repeated retry; joint reserves include merge/check costs and cannot borrow protected headroom. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

---

<a id="v4-12"></a>

## V4-12 — One native adapter with durable dispatch and cancellation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-09`, `V4-11`.

**Starting points:** V4-06 adapter interfaces, V4-09 capability evidence, `cli/src/harness_hook.sh`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Implement exactly one qualified host/version/mode and legitimate billing path. Preserve the native loop. Commit intent/reservation before external start, record acknowledgement afterward, and reconcile ambiguous execution. A provider call is not made atomic by local storage. Enforce method-level access for the selected interface; unknown privileged sibling methods do not become fallback tools.

**Implementation sequence.** Implement fake preflight/start/resume/events/interrupt; add durable intent/recovery lookup; test method boundaries, replay and duplicate delivery; run authorized live checks separately. A transport terminal event is not acceptance.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-12-R01 | WHEN a managed assignment is admitted, the controller SHALL commit its reservation and dispatch intent before requesting native execution. | **V4-12-T01:** Fail on both sides of commit/send/ack; native-call counter proves no send precedes durable intent. |
| V4-12-R02 | IF execution outcome is ambiguous after recovery, THEN the controller SHALL reconcile the existing intent before redispatching it. | **V4-12-T02:** Lookup-capable host and unsupported lookup; unsupported remains unknown, not an automatic retry. |
| V4-12-R03 | WHEN native execution reports an event, the adapter SHALL record observed values separately from requested settings. | **V4-12-T03:** Ignored model/effort, duplicate events, child usage gaps, and terminal errors. |
| V4-12-R04 | WHEN cancellation is requested, the controller SHALL retain a nonterminal cancellation state until the native outcome is established. | **V4-12-T04:** Accepted interrupt with live process, missing acknowledgement, delayed usage, and confirmed-stop controls. |
| V4-12-R05 | WHEN owned execution resources are cleaned up, the adapter SHALL preserve unrelated processes and workspaces. | **V4-12-T05:** Adjacent session/worktree/process tree; verify actual permission/network boundary and ownership identifiers. |
| V4-12-R06 | IF an adapter cannot enforce a required control at the requested granularity, THEN managed preflight SHALL reject that requirement. | **V4-12-T06:** Turn-only versus request-level limits, unsupported denial, and version drift; different operator request required for a downgrade. |
| V4-12-R07 | WHEN an external operation is retried or replayed, the adapter SHALL reuse its original operation identity for supported idempotency or reconciliation. | **V4-12-T07:** Crash after remote effect before acknowledgement; same key does not duplicate the effect; no lookup/key support yields unresolved status. |
| V4-12-R08 | IF a requested host method is outside the qualified capability set, THEN the adapter SHALL reject that invocation. | **V4-12-T08:** Unqualified direct-exec or filesystem method cannot bypass sandboxed tool denial; qualified operation is the positive control. |
| V4-12-R09 | WHEN durable session history is unavailable, the adapter SHALL report whether qualified reconstruction is possible without claiming native-session continuity. | **V4-12-T09:** Lost session with valid portable checkpoint yields a distinctly identified reconstructed invocation; missing reconstruction support remains blocked. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Uncertain sends stay pending reconciliation. Do not terminate unrelated sessions or treat checkpoint replay as an exactly-once guarantee.

---

<a id="v4-13"></a>

## V4-13 — Compile assignments without mandatory agent chains

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`, `V4-07`, `V4-12`.

**Starting points:** `EIDOLONS.md`, `roster/routing.yaml`, `methodology/cortex/chain-templates.md`, V4-06 contracts. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Use compatible methods in one continuing maker. Separate workers for an actual parallel track, context isolation, distinct authority, qualified capability, or explicit independent review. A skill has an applicability/input/output contract, not an automatic worker allocation. Semantic planning remains fallible. Use explicitly versioned experimental profiles until roster charters are amended; preserve all existing refusals and explicit user execution requests.

**Implementation sequence.** Implement method-use/worker-start contracts; validate schema and authority before dispatch; record inspectable selection reasons; exercise quiescent rebinding and output validation. Bounded consultants return references/results, not uncontrolled transcript dumps.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-13-R01 | WHEN compatible methods are applied within one authorized assignment, the compiler SHALL permit their execution in the existing worker. | **V4-13-T01:** One maker localizes and lite-plans without forced fan-out; required independent consultation still separates. |
| V4-13-R02 | WHEN an execution boundary is required, the compiler SHALL create a separately identified assignment with its reason recorded. | **V4-13-T02:** Verification, incompatible authority, isolated writer, and context separation each produce an identified assignment/reason. |
| V4-13-R03 | WHEN effective assignment authority is resolved, the controller SHALL intersect operator, task, assignment, specialist, and host-enforceable capabilities. | **V4-13-T03:** Role card, model message, repository config, and privileged parent cannot widen a child grant. |
| V4-13-R04 | IF role rebinding cannot safely revoke prior capabilities at a supported boundary, THEN the controller SHALL require a new appropriately restricted execution. | **V4-13-T04:** In-flight action, reusable old capability, and unsupported transition; prompt-only revocation is insufficient. |
| V4-13-R05 | IF a worker inherits maker conversation or privileged information, THEN the evidence classifier SHALL withhold clean-context verification status. | **V4-13-T05:** Rename/fork versus genuinely fresh invocation; same-model checking is not statistical independence. |
| V4-13-R06 | WHEN method use is reported, status SHALL distinguish it from a separate specialist invocation. | **V4-13-T06:** Embedded ATLAS-derived method is not an independent ATLAS audit; actual invocation IDs remain visible. |
| V4-13-R07 | WHEN a reusable method is selected, the compiler SHALL bind a versioned applicability, input, output, and execution-form contract to its use. | **V4-13-T07:** Inline and isolated use share task intent; missing inputs, incompatible output schema, and forbidden execution form reject before dispatch. |
| V4-13-R08 | WHEN an isolated consultant returns a result, the controller SHALL validate its bounded output contract before using that result in subsequent work. | **V4-13-T08:** Oversized output, missing artifact reference, wrong task/candidate, and malformed result cannot silently feed the maker; valid referenced result succeeds. |
| V4-13-R09 | WHEN concurrent writers are proposed, the scheduler SHALL require isolated workspaces and an explicit integration owner before admitting them. | **V4-13-T09:** Overlapping files/shared mutable workspace reject; disjoint candidate workspaces with integration/check reservation succeed; merging still revalidates the candidate. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

---

<a id="v4-14"></a>

## V4-14 — Freeze candidates and qualify protected acceptance

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-05`, `V4-12`, `V4-13`.

**Starting points:** V4-05 evidence contract, existing sandbox/apply/loop code under `cli/src/`, V4-06 workspace/runner interfaces. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Protect candidate execution, journal, verification definitions, credentials, and optional signing keys with an actual supported boundary. Worktree, directory, process name, and hash are insufficient. Separate execution integrity from acceptance adequacy. The acceptance package names requested behavior, exclusions, oracle origin, environment, review obligations, and required evidence. Check that it rejects representative plausible defects, not only that a reference passes. No universal correctness claim or new custom test framework.

**Implementation sequence.** Freeze candidate/criteria/environment manifests; isolate build/temp outputs and runner credentials; produce actual receipts; qualify oracles with expected-pass and expected-fail cases; review changed tests; revalidate integration against the actual target base.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-14-R01 | WHEN mandatory verification begins, the runner SHALL bind the check to a frozen candidate and acceptance/environment identities. | **V4-14-T01:** Concurrent maker edits and tracked/untracked/config/mode changes; logs identify the exact snapshot tested. |
| V4-14-R02 | WHILE candidate execution is active, the execution boundary SHALL deny writes to authoritative evidence and protected verification definitions. | **V4-14-T02:** Candidate-controlled shell/build script attempts journal, receipt, oracle, and key writes; test actual filesystem/process controls. |
| V4-14-R03 | WHEN a runner finishes a check, the evidence producer SHALL record its actual outcome and invocation provenance. | **V4-14-T03:** Pass/fail/error/cancelled/skipped fixtures; authored success prose cannot replace observation. |
| V4-14-R04 | IF required runner isolation or provenance is unavailable, THEN acceptance SHALL withhold the corresponding trusted verification grade. | **V4-14-T04:** Separate label/directory without access enforcement; absent context provenance; supported isolation control. |
| V4-14-R05 | IF the target base has changed before authorized candidate application, THEN the application gate SHALL require revalidation of the integration candidate. | **V4-14-T05:** Base moved, dirty target, and conflicts after green checks; no unchecked application. |
| V4-14-R06 | WHEN a receipt is projected into a human report, the renderer SHALL preserve distinct integrity, provenance, and acceptance fields. | **V4-14-T06:** Canonical-record round-trip; digest equality does not authenticate author or prove semantic correctness. |
| V4-14-R07 | WHEN an acceptance package is qualified, the verifier SHALL record its behavior coverage and outcomes on both acceptable and representative defective candidates. | **V4-14-T07:** Known valid solution plus plausible stub, missing edge behavior, and regression fixture; inadequate discrimination prevents qualification, not arbitrary mutation-score targets. |
| V4-14-R08 | IF maker changes affect required tests or verification definitions, THEN acceptance SHALL require a recorded review by their authorized acceptance owner. | **V4-14-T08:** Test deletion, relaxed assertion, and legitimate expectation change; maker approval alone cannot replace owner review or old evidence invalidation. |
| V4-14-R09 | WHEN a task requires observable application behavior, the verifier SHALL execute that behavior in the declared environment before accepting it. | **V4-14-T09:** Start app and exercise affected interaction/persistent effect or compatibility surface; unit-only and fabricated-log candidates fail the behavior gate. |
| V4-14-R10 | IF acceptance criteria cannot distinguish the requested result from a plausible incomplete result, THEN the verifier SHALL report an acceptance-definition blocker. | **V4-14-T10:** Ambiguous brief/oracle and missing behavioral discriminator; no silent requirement invention or weakening to manufacture a pass. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** No automatic push, merge, release, or deployment. Candidate build scripts cannot inherit checker credentials. A qualified oracle remains scoped and fallible.

---

<a id="v4-15"></a>

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

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve runnable partial artifacts and state. No silent scope reduction, routine continue prompts, or promises of background work not actually scheduled.

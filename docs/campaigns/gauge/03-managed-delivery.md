# Stage 3 — One managed delivery demonstrator

Deliver the smallest useful native-harness path with durable reservations, conditional execution boundaries, protected verification, and recoverable task state.

Read [HANDOFF.md](HANDOFF.md) and [ARCHITECTURE.md](ARCHITECTURE.md). [plan.yaml](plan.yaml) owns package identities, dependencies and source routing. Each table below owns its EARS requirements; verification entries are planned cases, not executed results. Assign one package, and one named slice where applicable.

<a id="v4-11"></a>

## V4-11 — Atomic reservations with verification and recovery headroom

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-08`, `V4-09`, `V4-10`. Stage gates also apply.

**Starting points:** `V4-06 controller store`, `V4-08 observation interface`, `roster/context-policy.yaml`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Implement transactionally consistent local admission across task/project/account/window/concurrency scopes. Reserve before dispatch, protect verification/recovery, and reconcile observed usage. The managed guarantee is limited to the proven adapter boundary; provider cost may exceed estimates. No automatic cross-device claim.

**Implementation sequence.** Define reservation lifecycle and estimate provenance. Implement atomic admission and updates with the selected store. Test contention, interruption, stale data, rollover, and operator amendments independently of model calls.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-11-R01 | WHEN concurrent assignments request capacity, admission SHALL reserve resources without jointly exceeding any applicable known local ceiling. | **V4-11-T01:** Barrier-synchronized contenders across two projects sharing a pool; verify accepted identities and each scoped balance. |
| V4-11-R02 | WHILE verification or recovery headroom is reserved, admission SHALL exclude that headroom from new optional implementation work. | **V4-11-T02:** Near-limit cases reject new exploration but admit authorized verification within its designated reserve. |
| V4-11-R03 | IF observed consumption exceeds its estimate, THEN admission SHALL stop new work that would exceed an applicable ceiling. | **V4-11-T03:** Overrun, delayed usage, and correction fixtures; balances retain actual exposure rather than clamping it away. |
| V4-11-R04 | IF a dispatched reservation has an unknown outcome, THEN reconciliation SHALL retain its uncertain exposure. | **V4-11-T04:** Crash, timeout, lost callback and cancellation-after-send; no automatic release or blind duplicate reconcile. |
| V4-11-R05 | WHEN a provider allowance window resets, accounting SHALL preserve the root task consumption already incurred. | **V4-11-T05:** Late old-window event and new-window reading; only the provider window changes, not task limits. |
| V4-11-R06 | IF authoritative accounting is unavailable, THEN managed admission SHALL reject new dispatch. | **V4-11-T06:** Store corruption, lock timeout, storage full and read-only state; optional advisory collection keeps its separately documented error policy. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Preserve spent resources and uncertain reservations when disabling the controller. Unknown consumption never becomes new allowance.

---

<a id="v4-12"></a>

## V4-12 — One native adapter with durable dispatch and cancellation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-09`, `V4-11`. Stage gates also apply.

**Starting points:** `V4-06 adapter interfaces`, `V4-09 capability evidence`, `cli/src/harness_hook.sh`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Qualify exactly one native host/version/mode and legitimate billing path. Preserve native reasoning/tool loops rather than rewriting them. Commit dispatch intent and reservation before external start; execute outside the store transaction. Do not promise exactly-once external execution when the host lacks reconciliation/idempotency.

**Implementation sequence.** Implement preflight/start/resume/events/interrupt with a fake adapter. Add a durable outbox-style intent and recovery query at the native boundary. Run separately authorized live smoke evidence on the selected mode.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-12-R01 | WHEN a managed assignment is admitted, the controller SHALL commit its reservation and dispatch intent before requesting native execution. | **V4-12-T01:** Inject crash on each side of commit/send/ack; native-call counter proves no send preceded the durable intent. |
| V4-12-R02 | IF execution outcome is ambiguous after recovery, THEN the controller SHALL reconcile the existing intent before redispatching it. | **V4-12-T02:** Host supports lookup positive case and unsupported-lookup case; unsupported becomes unknown, not automatic retry. |
| V4-12-R03 | WHEN native execution reports an event, the adapter SHALL record observed values separately from requested settings. | **V4-12-T03:** Ignored model/effort setting, duplicated events, child usage gaps, and terminal errors; no assumed settings. |
| V4-12-R04 | WHEN cancellation is requested, the controller SHALL retain a nonterminal cancellation state until the native outcome is established. | **V4-12-T04:** Request accepted but process still running, lost acknowledgement, final usage delayed, and confirmed-stop controls. |
| V4-12-R05 | WHEN owned execution resources are cleaned up, the adapter SHALL preserve unrelated processes and workspaces. | **V4-12-T05:** Adjacent native session/worktree and process-tree fixtures; permission/network restrictions exercised on the actual boundary. |
| V4-12-R06 | IF an adapter cannot enforce a required control at the requested granularity, THEN managed preflight SHALL reject that requirement. | **V4-12-T06:** Turn-only versus request-level budgets, unsupported tool denial and version drift; truthful downgrade only with an explicitly different operator request. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Uncertain native sends remain pending reconciliation. Cleanup touches only owned processes/workspaces; it does not erase state or unrelated native sessions.

---

<a id="v4-13"></a>

## V4-13 — Compile assignments without mandatory agent chains

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`, `V4-07`, `V4-12`. Stage gates also apply.

**Starting points:** `EIDOLONS.md`, `roster/routing.yaml`, `methodology/cortex/chain-templates.md`, `V4-06 typed contracts`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Compile compatible methods into a continuing maker; create separate consultations, isolated writers, or verification workers only for a declared need or requirement. Semantic task interpretation remains fallible; the controller validates the proposed plan rather than claiming natural-language determinism. Use versioned test profiles until real specialist charter changes are accepted in Stage 4.

**Implementation sequence.** Implement typed method-use and worker-start operations with explicit authority. Add fusion/reuse and boundary selection using inspectable rules. Test role rebinding at quiescent supported boundaries and independent-checker exclusions.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-13-R01 | WHEN compatible methods are applied within one authorized assignment, the compiler SHALL permit their execution in the existing worker. | **V4-13-T01:** One maker uses localization and lite planning; no forced second worker; required independent consultation control still separates. |
| V4-13-R02 | WHEN an execution boundary is required, the compiler SHALL create a separately identified assignment with its reason recorded. | **V4-13-T02:** Independent verification, incompatible authority, isolated writer, and context separation fixtures; every spawn names its purpose. |
| V4-13-R03 | WHEN effective assignment authority is resolved, the controller SHALL intersect operator, task, assignment, specialist, and host-enforceable capabilities. | **V4-13-T03:** Deny widening through role card, model message, repository config, or a high-permission parent. |
| V4-13-R04 | IF role rebinding cannot safely revoke prior capabilities at a supported boundary, THEN the controller SHALL require a new appropriately restricted execution. | **V4-13-T04:** In-flight tool action, reusable old capability, and unsupported host transition; no prompt-only revocation claim. |
| V4-13-R05 | IF a worker inherits maker conversation or privileged information, THEN the evidence classifier SHALL withhold clean-context verification status. | **V4-13-T05:** New label, conversation fork, and genuine fresh-context invocation controls; same-model use is recorded without statistical-independence claims. |
| V4-13-R06 | WHEN method use is reported, status SHALL distinguish it from a separate specialist invocation. | **V4-13-T06:** One worker using ATLAS-derived skill is not described as an independent ATLAS audit; actual invocation IDs remain visible. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Preserve explicitly requested deliverables and genuine independent-review requirements. A named role cannot grant tools, erase context, bypass greenfield refusals, or reset budgets.

---

<a id="v4-14"></a>

## V4-14 — Freeze candidates and run protected verification

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-05`, `V4-12`, `V4-13`. Stage gates also apply.

**Starting points:** `V4-05 evidence contract`, `existing sandbox/apply/loop code under cli/src/`, `V4-06 workspace and runner interfaces`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Run checks against a frozen candidate with separate writable build/temp output. Protect authoritative journal, verification definitions, and optional signing material from the maker. A worktree, process name, or another directory is not a security boundary. Choose a real supported isolation mechanism; downgrade evidence when isolation is unavailable.

**Implementation sequence.** Implement candidate manifests and source freeze. Run controlled oracles in a restricted runner and bind actual invocation/context provenance. Generate receipts and exercise revalidation before promotion to a user branch.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-14-R01 | WHEN mandatory verification begins, the runner SHALL bind the check to a frozen candidate and acceptance/environment identities. | **V4-14-T01:** Attempt concurrent maker edits; tracked/untracked/config/mode mutations; logs identify exactly which source snapshot ran. |
| V4-14-R02 | WHILE candidate execution is active, the execution boundary SHALL deny writes to authoritative evidence and protected verification definitions. | **V4-14-T02:** Maker shell attempts journal, receipt, oracle and signing-key modification; exercise filesystem/process controls, not tool labels alone. |
| V4-14-R03 | WHEN a runner finishes a check, the evidence producer SHALL record its actual outcome and invocation provenance. | **V4-14-T03:** Pass/fail/error/cancelled/skipped fixtures; hand-authored success prose cannot replace an observation. |
| V4-14-R04 | IF required runner isolation or provenance is unavailable, THEN acceptance SHALL withhold the corresponding trusted verification grade. | **V4-14-T04:** Separate label/directory without enforced access controls; missing context evidence and supported-isolation positive case. |
| V4-14-R05 | IF the target base has changed before authorized candidate application, THEN the application gate SHALL require revalidation of the integration candidate. | **V4-14-T05:** Base moved after checks; dirty target and patch conflict; never apply a previously green diff as an unchecked merge. |
| V4-14-R06 | WHEN a receipt is projected into a human report, the renderer SHALL preserve distinct integrity, provenance, and acceptance fields. | **V4-14-T06:** Round-trip through canonical record; matching digest does not imply author authentication or semantic correctness. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** No automatic merge, push, release, or deployment. Test success is scoped evidence, not proof of oracle adequacy or universal correctness.

---

<a id="v4-15"></a>

## V4-15 — Deliver a runnable slice and resume without losing control

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-11`, `V4-12`, `V4-13`, `V4-14`. Stage gates also apply.

**Starting points:** `existing sandbox loop`, `cli/src/context.sh`, `cli/src/context_externalize.sh`, `V4-06 task-state interfaces`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** One bounded brownfield task from brief to runnable candidate, required checks, or preserved partial/blocker result. One maker owns a coherent patch; classify schema/environment/permission/provider/test/causal/acceptance failures before recovery. Keep current charters: authorized parent application may use proposals; experimental profiles must be explicitly identified until Stage 4 adoption.

**Implementation sequence.** Exercise an instrumented no-model fixture end to end. Add durable checkpoints with lineage, candidate, policy, reservations, pending checks and failed approaches. Run the separately authorized live demonstration on the single qualified adapter.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-15-R01 | WHEN a bounded implementation assignment has sufficient authority and inputs, the delivery loop SHALL progress through its authorized internal phases without requesting routine continuation. | **V4-15-T01:** Record user interventions for fixture and live task; missing consequential product decision is an explicit exception. |
| V4-15-R02 | WHEN a runnable milestone is reported, the controller SHALL reference an executed check of the requested behavior. | **V4-15-T02:** Stub-only scaffold, prose completion, fake green log and real smoke/integration behavior controls. |
| V4-15-R03 | IF remaining resources cannot support mandatory work, THEN the delivery loop SHALL preserve progress as a nonaccepted partial or blocked result. | **V4-15-T03:** Exhaust budget before verification and after one completed slice; whole-task acceptance stays incomplete. |
| V4-15-R04 | IF repeated failure yields no new evidence within the configured bound, THEN recovery SHALL stop repeating that approach. | **V4-15-T04:** Stable failure signature across worker/context switches; mechanical failure does not automatically start costly forensics. |
| V4-15-R05 | WHEN a task resumes, recovery SHALL preserve its root accounting, authority, candidate identities, and outstanding verification obligations. | **V4-15-T05:** Interrupt before/after send, edit, freeze, check and checkpoint; reconcile uncertain execution before continuing. |
| V4-15-R06 | IF a checkpoint is stale, tampered, or lacks a usable native session, THEN recovery SHALL report the exact limitation without discarding valid local artifacts. | **V4-15-T06:** Tampered payload, changed criteria, missing native history and optional memory outage; portable checkpoint remains available. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** No background promise or silent scope reduction. Missing credentials/irreducible product choices are concrete blockers; routine authorized phases do not require another continue message.

---

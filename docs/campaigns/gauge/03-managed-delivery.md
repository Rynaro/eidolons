# Phase 3 — One managed delivery path

Entry: Phase 2's policy/observability gates accepted; a real host qualification can remain blocked until an operator authorizes the required probe. Exit: G07–G10 accepted, including a separately authorized live pilot on one qualified host. Fake-host success is useful engineering evidence, not a live delivery claim. Read [HANDOFF.md](HANDOFF.md); [plan.yaml](plan.yaml) owns dependencies.

## G07 — Atomic shared reservations and verification headroom

**Primary repository:** Rynaro/eidolons. Start with G01/G05 journal and observation interfaces, `cli/src/telemetry.sh`, `cli/src/lib_context.sh`, `roster/context-policy.yaml`, and relevant budget tests. Depends on G06.

Implement an account-pool-aware controller that atomically checks ceilings and reserves capacity before dispatch, then reconciles observations afterward. Account pool is an operator-defined alias for a legitimately shared provider allowance, not credential sharing or quota circumvention. Keep task, project, account/window, and concurrency scopes independent and intersect applicable limits. Count a provider request once even when several scopes reference it. Tokens, money, and opaque provider allowances remain distinct units; no universal conversion is permitted.

Reuse G01's append/transaction boundary when sufficient. A transaction must cover admission, reservation publication, and scope balances, not merely the final event append. Document the crash/reconciliation state machine. Choose durable storage appropriate to the tested concurrency/installation boundary; a database/daemon is not mandatory, and any new dependency needs an explicit packaging decision. The initial supported scope is coordinated local processes on a declared filesystem, not magically synchronized devices.

Protect explicit verification and checkpoint/recovery headroom. New implementation work may consume only the unreserved portion; admitted verification can consume its designated reserve. Estimates can be wrong, so observed overruns stop new admissions and trigger reconciliation rather than negative balances disappearing. Unknown telemetry after a crash must not automatically release a possibly consumed reservation. A timeout is not proof a provider request never happened. Distinguish reserved, dispatched, reconciled, cancelled-before-dispatch, and uncertain/in-flight states.

Cancellation, resume, day/window rollover, delayed usage, and explicit operator limit changes all preserve already-consumed resources. Do not refill a task budget merely because a provider window reset. Do not automatically retry an ambiguous non-idempotent provider operation. Account use outside the controller remains explicitly unobserved.

| Acceptance | Required verification |
|---|---|
| G07-A1: Concurrent reservations cannot jointly admit beyond an applicable local ceiling. | Barrier-synchronized contenders across two projects and a shared pool; verify each scope and accepted ID set independently. |
| G07-A2: Verification/recovery reserve is protected from new implementation work. | Near-limit workload rejects new work but admits permitted verification/checkpoint actions within their reserve. |
| G07-A3: Crash, duplicate, late, and uncertain observations do not manufacture allowance. | Crash before/after dispatch, duplicate reconcile, partial usage, cancelled-before/after-send, and missing telemetry fixtures. |
| G07-A4: Agent/session/provider switches inherit accounting. | Same-root descendants and resumed sessions across pool aliases; independent tasks remain separate. |
| G07-A5: Window resets and price/usage uncertainty remain typed and conservative. | Late old-window event, stale allowance reading, missing price, and outside-controller consumption warning; no invented precision. |
| G07-A6: Managed admission stops when required accounting is unavailable; advisory hooks retain their existing safety behavior. | Unwritable journal, lock timeout, corruption, and unavailable measurement surfaces. |

**Stop/rollback:** no live automatic dispatch until G08. Never promise an exact external bill or cross-device enforcement. Preserve reservations and unreconciled exposure when disabling a controller; do not roll back into an overspending path.

## G08 — Qualify and implement one managed host adapter

**Primary repository:** Rynaro/eidolons. Start with the G06 capability matrix, current host adapters, `cli/src/harness_hook.sh`, readiness/canaries, and existing sandbox/dispatch entrypoints. Junction is a conditional integration slice only when it owns the execution boundary actually used. Depends on G07.

Select exactly one initial host/mode using G06's observed capabilities and implementation reuse. Record the decision and tested version. No unconditional choice of Claude Code or Codex is made by this plan. Validate current official host interfaces before implementing; do not invent flags, hidden quota APIs, or guarantees from hook registration. Fixture-backed development must remain possible without credentials.

Implement a small typed adapter boundary for preflight, start/resume, observed events, cancellation, and terminal outcome. Request model/effort/permissions only through supported native controls. Record requested versus actually observed values; an unsupported field is not a successful setting. Reserve before each boundary the adapter controls. If the native run internally makes requests that cannot be individually admitted, enforce the supported run boundary and advertise that granularity; do not claim a per-request hard cap.

Capture native invocation identities and scope the independent-checker evidence to the actual separation observed. Keep policy, accounting, authority, and untrusted model output in distinct channels. Do not let a tool result, generated plan, or prompt mutate trusted ceilings. Scope subprocesses/worktrees and clean up only resources owned by this run; cancellation must reconcile unknown side effects and in-flight charges.

The Gauge never relaxes specialist charters. Existing parent-applies-proposal workflows may apply an authorized candidate inside an isolated worktree; Vivi's own charter remains unchanged until G12. Pushing, merging, releasing, deployment, dependency downloads with external spend, and broad approval changes are not implicitly authorized.

| Acceptance | Required verification |
|---|---|
| G08-A1: Start, event capture, terminal states, and cancellation are exercised through the actual adapter. | Fake-host contract suite plus a separately authorized, pinned-version live smoke run. |
| G08-A2: Required unsupported controls stop preflight rather than silently degrading. | Missing usage/cancellation/authority boundary and ignored model setting fixtures. |
| G08-A3: One reservation is associated with each controlled dispatch boundary. | Instrumented adapter trace, duplicate callback, partial startup, and ambiguous-send recovery. |
| G08-A4: Permissions and owned-resource cleanup are effective within the declared boundary. | Attempt forbidden write/network action; cancel a run beside unrelated processes/worktrees and verify they survive. |
| G08-A5: Execution/checker labels reflect observed provenance and granularity. | Same-process renamed checker is not independent; separate invocation without context proof remains appropriately qualified. |

**Stop/rollback:** one supported host/mode, not nominal parity across all hosts. Missing live access leaves the live criterion blocked. Disable the new path and restore pre-existing host settings without deleting native sessions or accounting.

## G09 — Bounded delivery loop with a runnable milestone

**Primary repository:** Rynaro/eidolons. Start with G08, current sandbox loop implementation, routing/mission contracts, `roster/routing.yaml`, and G02/G03 verification records. Depends on G08.

Implement an opt-in controller for one bounded brownfield task: accept goal/constraints/authority and named oracles; validate the environment; obtain only necessary discovery/planning; implement in an isolated authorized tree; produce a runnable vertical slice; verify; repair from real failures; run required independent checks; and return current evidence. Reuse current specialist methods and native execution tools rather than implementing another reasoning engine. The host may make multiple useful internal calls without the user repeatedly saying 'continue'.

A task requesting only diagnosis or planning must remain read-only. A user's explicit deliverables, separate-review request, or significant design choice may not be silently removed for economy. For a multi-slice task, record that a slice is complete while the total task remains incomplete. Do not redefine success to the easiest slice.

Classify failures before recovery: input/schema, environment, permission, transient provider, implementation test, persistent causal uncertainty, or acceptance/design conflict. Mechanical failures get bounded deterministic recovery where safe; ordinary test failures return to the maker; persistent substantive uncertainty can justify a specialist. Repeated identical failure without new evidence triggers a changed approach or checkpoint, not a fresh budget. Reserve-funded verification remains mandatory; a budget-limited result is partial, not accepted.

Model-authored prose is not a runnable milestone. The named smoke/demo/test must exercise actual requested behavior across the relevant boundary. Keep proposed process states separate from ESL's normative lifecycle; do not add ESL states or performatives inside this package. Greenfield remains out of this pilot.

| Acceptance | Required verification |
|---|---|
| G09-A1: A bounded implementation reaches the named runnable behavior and required checks from one authorized user brief. | Instrumented fixture task plus authorized live pilot; record all user interventions, not just the final answer. |
| G09-A2: Requested scope and read-only intent survive routing. | Diagnosis-only, explicit review, multi-deliverable, and ambiguous consequential-decision tasks. |
| G09-A3: Failures use the right bounded recovery and shared budget. | Missing executable, malformed envelope, failed assertion, repeated failure signature, permission denial, and provider interruption. |
| G09-A4: Partial slices, protected-test edits, or skipped mandatory checks cannot produce completion. | Mutate/omit each independently and assert G02's current-candidate gate stays non-success. |
| G09-A5: Status reports observable work and concrete blockers, not fabricated progress percentages. | Compare reported milestones/actions with executed events and evidence artifacts. |

**Stop/rollback:** no charter revision, automatic default activation, broad agent swarm, or benchmark claim. An irreducible product decision or authority boundary can require a user answer; continuation prompts for routine phases do not.

## G10 — Durable task succession and end-to-end managed-path acceptance

**Primary repository:** Rynaro/eidolons. Start with G09, `cli/src/context.sh`, checkpoint/externalize/handoff implementations, G05 lineage, and ECM policy/pins. Depends on G09.

Carry root task identity, effective policy identity, remaining limits/reservations, candidate/criteria identities, failed approaches, pending checks, authorized scope, and next action through checkpoints and host resumption. Use existing extensibility only where supported. If a public ECM/ECL shape must change, propose the smallest upstream compatible amendment, test it, and sequence producer before consumer; never put undocumented fields into a supposedly conformant payload. Atomos remains compose/verify-only.

On recovery, verify payload integrity and re-read current candidate/criteria/environment state. Resume reconciles rather than trusting stale 'complete' prose. Rehydrate the minimum actionable context; references point to current artifacts, not vanished scratch paths. Native replay, child escalation, context succession, and provider switching cannot reset task accounting or duplicate an uncertain side effect. Cross-provider resume is enabled only where both adapters are actually qualified; otherwise produce a portable checkpoint and a clear unsupported reason.

Expose a terminal-readable managed-run status/receipt before building GUIs. Distinguish planned, implemented, runnable, current checks passed, ready-for-review, and released using observed facts; only the existing authorized release process can establish released. Implement honest blocked/partial and cancellation outcomes with recovery instructions.

| Acceptance | Required verification |
|---|---|
| G10-A1: Interrupted/resumed work preserves lineage, scope, pending checks, and consumption. | Terminate after edit, before verification, after provider send, and after checkpoint publication; resume each case. |
| G10-A2: Stale or tampered checkpoint evidence cannot produce accepted completion or refill a budget. | Mutate checkpoint, code, criteria, native-session reference, and stored policy independently. |
| G10-A3: Missing memory/MCP/native capability degrades explicitly without destroying local recovery data. | File-only checkpoint roundtrip and missing/failed CRYSTALIUM/atomos/native-session fixtures. |
| G10-A4: The complete first-host path is demonstrated, not inferred from isolated unit tests. | Authorized task from intake through runnable candidate, independent checks, budget-limited partial case, interruption, and resume; cite adapter/config/version and actual evidence. |
| G10-A5: Opt-out behavior and rollback preserve user work and truthful completion/accounting. | Existing consumer project on/off comparison, dirty-worktree preservation, and rollback while an uncertain reservation exists. |

**Phase 3 exit:** one real qualified host/mode, fixture suite plus authorized live evidence, explicit limitations, and an inspectable result. Do not wait for every sibling or interface to support Gauge before completing this vertical slice; do not claim those unsupported surfaces are managed.

# V4-12 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-12 — One native adapter with durable dispatch and cancellation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-09`, `V4-11`.

**Starting points:** V4-09 CapabilityTuple / Preflight / HostAdapter, V4-11 AdmitReservation, `cli/src/harness_hook.sh`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

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

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Uncertain sends stay pending reconciliation. Do not terminate unrelated sessions or treat checkpoint replay as an exactly-once guarantee.

## Bounded decision

See [decision.md](decision.md). Select one fixture-qualified FakeNativeAdapter over live probes or privileged sibling fallback. Schema-2 additive dispatch namespaces. Sequence: reserve → commit intent → send → ack with fault injectors. NativeAdapter extends HostAdapter without breaking TestV409*. Transport terminal ≠ acceptance. Cancellation requested ≠ confirmed stopped ≠ final reconciliation.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Use injected fault injectors for commit/send/ack gaps without real network. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-13 compiler.

# V4-11 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-11 — Atomic reservations with verification and recovery headroom

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-08`, `V4-09`.

**Starting points:** V4-06 store, V4-08 observation interface, V4-07 ceilings / PolicyBinding. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

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

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

## Bounded decision

See [decision.md](decision.md). Select fixture-local atomic admission over remote-in-transaction or auto-release-on-uncertain. Schema-2 additive namespaces. Intersect known V4-07 ceilings only. Protect verification/recovery headroom. Uncertain exposure retained until explicit reconcile/release-with-proof. Window reset ≠ task budget refill. Accounting faults fail closed for managed admit; advisory hooks separate. Hard-limited unknown blocks unless explicit bounded mode + authorized bound.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Use injected fault injectors for accounting unavailability without real FS damage outside test tmpdirs. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-12 durable native dispatch.

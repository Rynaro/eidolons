# V4-01 — fail-closed integrity policy

This record adopts the already-assigned V4-01 contract; it does not redefine it.
The lifecycle record was created after implementation because the configured
Docker runtime was initially unavailable. No pre-implementation tool gate or
retroactive lifecycle history is claimed.

## Authority and scope

Canonical R01–R05/T01–T05: [planning revision 3](https://github.com/Rynaro/eidolons/blob/c581308f055a0e252013bf09f2a7b2e1426ff811/docs/campaigns/gauge/00-stabilization.md#v4-01).
Implementation base: `752194ef5ceaa8cee1f5995fd0d374888696d8fc`.
Repair the shared policy reader and its existing consumers. Preserve Bash 3.2,
explicit advisory policy, independent partial hashes, actual installed
manifest-only verification, historical doctor lock summaries, explicit
self-upgrade escape flags, and rollback. Reject invalid policy before protected
operations, missing/unusable strict evidence, and automatic strict-placeholder
acceptance. Never expose policy values or parser diagnostics.

No successors, architecture rewrite, dependency relocation, release, merge,
deployment, memory disablement, or paid trial. The pinned campaign owns these
boundaries. Existing user changes remain outside this worktree.

## Sizing and implementation

Complexity: scope 1 (one policy repair), ambiguity 1 (assigned EARS), dependencies
2 (shared reader and CLI consumers), risk 3 (artifact admission): **7/12**.
Fourteen implementation/test/documentation files; lifecycle bookkeeping is
additional. Full tier reflects integrity risk. No competing-architecture
trade-off; the shared-reader decision is already made by the campaign, so the
optional deliberation step is skipped rather than fabricated.

## Verification and review

`change.json` references every assigned requirement and executable verification.
The delivery receipt records individual suite results, baseline failures,
compatibility corrections, CI runs, and limitations. A distinct `integrity_review`
invocation checks `vivi_v4_01`'s candidate; same-model/shared-context review is not
statistical independence. Tonberry block-mode conformance verifies the lifecycle
record, not application behavior. A green conformance report never substitutes
for test execution or green CI. Do not archive this change without authorization.

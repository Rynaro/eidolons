# V4-13 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-13 — Compile assignments without mandatory agent chains

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`, `V4-07`, `V4-12`.

**Starting points:** `EIDOLONS.md`, `roster/routing.yaml`, `methodology/cortex/chain-templates.md`, V4-06/07/12 contracts. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

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

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

## Bounded decision

See [decision.md](decision.md). Select continuing-maker default over mandatory agent chains. Schema-2 additive compiler namespaces. Skills are I/O contracts, not automatic worker allocation. Authority is five-layer intersection. Consultants return bounded validated results. Concurrent writers need isolation + integration owner. No V4-14+.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Reuse V4-07 policy intersection patterns and V4-12 dispatch admission locks. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-14 acceptance freeze.

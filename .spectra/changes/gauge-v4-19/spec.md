# V4-19 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-19 — Context, optional memory, and bounded information access

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-15`, `V4-21`.

**Scope and decisions.** Measure actual host-visible instructions, tool schemas, returned data, startup, retrieval, and rebuild costs before optimizing. External evidence is addressable data, not proof it was read. Reuse only dependency-valid evidence. CRYSTALIUM remains optional knowledge, never operational truth; Atomos remains compose/verify-only. No mandatory index, vector store, recursive agent framework, or new service.

**Assignment slices:** `core-context` required; `one-justified-optional-adapter` out of scope (dropped; not used).

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-19-R01 | WHEN evidence is reused, the context manager SHALL validate its declared source, criteria, and environment dependencies. | **V4-19-T01** |
| V4-19-R02 | WHEN a tool result exceeds the presentation bound, the context manager SHALL return a localized excerpt with a usable reference to full permitted evidence. | **V4-19-T02** |
| V4-19-R03 | WHEN context succession occurs, the controller SHALL retain mandatory pins and outstanding task obligations. | **V4-19-T03** |
| V4-19-R04 | IF optional memory is unavailable or untrusted, THEN the delivery path SHALL continue without treating memory as authoritative execution evidence. | **V4-19-T04** |
| V4-19-R05 | WHEN programmatic or batched tool execution is used, the controller SHALL enforce the same operation permissions as individual calls. | **V4-19-T05** |
| V4-19-R06 | WHILE repeated context triggers describe unchanged state, the context manager SHALL avoid duplicate lifecycle work. | **V4-19-T06** |
| V4-19-R07 | WHEN context overhead is measured, the report SHALL distinguish actual host-visible payload from source-file size and estimated token counts. | **V4-19-T07** |
| V4-19-R08 | WHERE reusable memory is enabled, the memory adapter SHALL bind each retained item to source provenance, project scope, applicability, and supersession or expiry metadata. | **V4-19-T08** |
| V4-19-R09 | IF retrieved memories conflict or their dependencies are invalid, THEN the context manager SHALL present the conflict or invalidity before using them as task guidance. | **V4-19-T09** |
| V4-19-R10 | WHEN evidence navigation is observed, the recorder SHALL distinguish discovery, retrieval, and cited use without inferring unobserved model comprehension. | **V4-19-T10** |
| V4-19-R11 | WHERE indexed or recursive information access is enabled… | **V4-19-T11 N/A** — feature condition absent (optional adapter out of scope) |
| V4-19-R12 | WHERE recursive information access is enabled… | **V4-19-T12 N/A** — feature condition absent (optional adapter out of scope) |

## Bounded decision

See [decision.md](decision.md). Schema-2 additive context namespaces. Reuse `roster/pins.yaml`, `roster/context-policy.yaml`, and CLI context helpers as pin/zone reference; do not invent indexing/recursion. core-context only; one-justified-optional-adapter out of scope (dropped; not used). No V4-10/16/17/18/22.

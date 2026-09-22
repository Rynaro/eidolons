# V4-20 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-20 — Truthful CLI status and optional user interfaces

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-15`.

**Scope and decisions.** Extend the minimal V4-15 controls. Expose the same versioned state to CLI/JSON and optional clients. Keep Final Fantasy names plus plain-language functions; disclose capability/usage gaps and real blockers. No duplicated budget engine in the UI. Terminal/green badge never replaces acceptance evidence. Status/preview is observational and cannot refill budgets or create live-evidence claims.

**Assignment slices:** `core-cli` required; `optional-GAMBIT` out of scope (dropped; not used).

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-20-R01 | WHEN task status is requested, the interface SHALL report observed delivery and verification states separately. | **V4-20-T01** |
| V4-20-R02 | WHEN execution participation is displayed, the interface SHALL distinguish methods used, worker identities, and context-separation evidence. | **V4-20-T02** |
| V4-20-R03 | IF provider quota or enforcement is unsupported or stale, THEN the interface SHALL display that limitation in plain text. | **V4-20-T03** |
| V4-20-R04 | WHEN a user inspects policy or previews a change, the interface SHALL avoid dispatching model work. | **V4-20-T04** |
| V4-20-R05 | WHERE an optional client is installed, the client SHALL consume the same policy/status contract as the CLI. | **V4-20-T05** (fixture consumer; GAMBIT out of scope) |
| V4-20-R06 | WHEN a user requests cancellation through a client, the interface SHALL distinguish request acknowledgement, confirmed stop, and accounting reconciliation. | **V4-20-T06** |
| V4-20-R07 | IF a client receives an unsupported contract version, THEN the client SHALL reject authority-bearing mutations while retaining an explicit compatibility diagnostic. | **V4-20-T07** |

## Bounded decision

See [decision.md](decision.md). Schema-2 additive status namespaces. Reuse V4-15 InspectSnapshot / delivery state; V4-11 reservations; V4-12 cancel states. core-cli only; optional-GAMBIT out of scope (dropped; not used). No V4-21 / V4-16+.

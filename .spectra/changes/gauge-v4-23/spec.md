# V4-23 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority. **No merge, tag, release, deploy, or archival is authorized by this planning/implementation package.**

## V4-23 — Evidence-scoped migration, release, and optional retirement

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-02`, `V4-03`, `V4-10`, `V4-16`, `V4-17`, `V4-18`, `V4-19`, `V4-20`, `V4-22`.

**Starting points:** `cli/install.sh`, `cli/src/upgrade_self.sh`, `MIGRATION.md`, `.github/workflows/release-nexus.yml`, `roster/`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Prepare v4.0.0 readiness reporting only for actually implemented breaks. Preserve verified binary installation plus an optional developer build path, modular contracts, optional memory/UI, and migration compatibility. Selected core slices have explicit acceptance; optional experiments and clients may remain deferred. Separate correctness, managed-operation qualification, and performance promotion. A governance-only improvement can be described as such, not as measured speed/cost superiority.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-23-R01 | WHEN a supported migration is authorized, the migrator SHALL stage and verify the replacement before switching the active installation. | **V4-23-T01:** Affected pre-v1.41.1, v2.20, v3.3.1, fresh/dirty/interrupted fixtures; no force-integrity bypass. |
| V4-23-R02 | IF migration or post-switch validation fails, THEN recovery SHALL preserve a usable previous installation and user state. | **V4-23-T02:** Staging/switch/smoke failure, repeat migration, native sessions, and pending reservations. |
| V4-23-R03 | WHEN a release candidate is evaluated, the release gate SHALL require the declared deterministic checks and applicable authorized live evidence. | **V4-23-T03:** Distinguish code/behavior versus docs-only candidate; missing required live evidence is not replaced by smoke success. |
| V4-23-R04 | IF promotion evidence is insufficient or approval absent, THEN release automation SHALL leave behavioral defaults unchanged. | **V4-23-T04:** No-win/inconclusive/missing approval; prepared report does not authorize tag, merge, or publication. |
| V4-23-R05 | IF a component still has an unmigrated supported consumer, THEN repository retirement SHALL remain blocked. | **V4-23-T05:** Tested replacement plus inventory/license/history/support/rollback evidence and explicit archive authorization. |
| V4-23-R06 | WHEN a supported host version changes, the capability catalogue SHALL invalidate affected qualification until rechecked. | **V4-23-T06:** Cancellation, usage, and tool-boundary version drift stops the affected managed claims. |
| V4-23-R07 | WHEN release readiness is reported, the release gate SHALL report correctness, managed-operation qualification, and performance promotion as separate decisions. | **V4-23-T07:** Deterministic suite passes but live probe blocked or performance null; no composite green badge conceals either limitation. |
| V4-23-R08 | WHEN a promoted method or strategy is rolled back, the controller SHALL retain task lineage, evidence history, and outstanding obligations under the still-authorized contract. | **V4-23-T08:** Rollback with active candidate, pending cancellation, unknown usage, and later failure; no stale acceptance, budget refill, or wider authority. |

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user settings/sessions/candidates/evidence and unresolved exposure. Repository retirement, release, and behavioral defaults always need their own accepted evidence and authorization.

## Bounded decision

See [decision.md](decision.md). Schema-2 additive release/migration namespaces. Reuse V4-07 migration patterns, V4-20 status, V4-21/22 evidence separation. Gate fixtures refuse unauthorized promotion — they must never perform a real release.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes. Bash 3.2 legacy CLI install paths untouched. No behavioral default flip in production CLI.

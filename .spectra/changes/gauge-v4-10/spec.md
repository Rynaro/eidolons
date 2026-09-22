# V4-10 preparatory implementation contract (inventory slice)

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only the **inventory** assignment slice. Do not import/archive/delete `.spectra` or rewrite protocols. Explicitly defer `one-component-import` and `registry-and-discovery-compiler` (not silent passes).

## V4-10 — Consolidate coupled sources after the delivery experiment

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-03`, `V4-06`, `V4-15`, `V4-21`.

**Starting points:** `roster/index.yaml`, `roster/mcps.yaml`, `roster/routing.yaml`, `schemas/`, `docs/architecture.md`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Inventory all ten roster specialists, four contracts, Junction, tonberry, atomos, atlas-aci, CRYSTALIUM, evaluation tooling, and optional clients before imports. Separate repository/release/deployment/process/trust boundaries. Review early results, including null or blocked findings; maintenance justification is not a performance claim. Import only coupled, licensed sources; preserve external packages, optional memory/UI, and consumer compatibility.

**Assignment slices:** `inventory` (this change), `one-component-import` (deferred), `registry-and-discovery-compiler` (deferred).

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-10-R01 | WHEN a component import is proposed, the consolidation inventory SHALL identify its consumers, license, provenance, replacement path, and preserved runtime boundaries. | **V4-10-T01:** Cover every active roster/support component and third-party rights; missing consumer/provenance prevents import readiness. |
| V4-10-R02 | WHEN first-party package sources are compiled, the compiler SHALL emit deterministic schema-valid aggregates from the declared canonical inputs. | **V4-10-T02:** Deferred to `registry-and-discovery-compiler`. |
| V4-10-R03 | WHEN host discovery files are generated, the compiler SHALL preserve portable skill sources and host-specific identifier semantics. | **V4-10-T03:** Deferred to `registry-and-discovery-compiler`. |
| V4-10-R04 | WHEN a legacy endpoint is served by an imported component, the compatibility layer SHALL preserve its declared protocol behavior. | **V4-10-T04:** Partial readiness only in inventory (boundaries recorded; no import). |
| V4-10-R05 | WHILE components share a repository or binary, deployment SHALL preserve their independently configured privileges and optionality. | **V4-10-T05:** Partial readiness only in inventory (boundaries recorded; no shared-binary deploy). |
| V4-10-R06 | IF an import lacks consumer migration evidence, THEN the migration planner SHALL retain the original distribution path. | **V4-10-T06:** Partial readiness only (`retain_external`; no archive). |
| V4-10-R07 | WHEN a consolidation decision is recorded, the inventory SHALL distinguish measured delivery effects from maintenance-only justification. | **V4-10-T07:** Reference the early comparison record; null, blocked, or inconclusive results cannot be relabeled as demonstrated performance gains. |

**Exit.** Apply the common exit and package scope for the inventory slice; deferred slices remain explicitly unassigned.

**Stop and rollback.** Preserve old repositories/tags/endpoints and settings. No automatic `.spectra/` deletion, archival, privileged-tool merger, or protocol rewrite for directory aesthetics.

## Bounded decision

See [decision.md](decision.md). Committed JSON inventory + Go validator; no schema-2 store; no CLI; deferred slices explicit.

## Common implementation controls

Reuse the V4-06 Go seam for types/tests only. Preserve opt-out CLI compatibility. Freeze named conformance anchors `TestV410T01` / `TestV410T07` before claiming inventory readiness. Keep fixture evidence separate from live host and provider qualification. No paid probes, release, deployment, merge approval, import, or compiler work is implied.

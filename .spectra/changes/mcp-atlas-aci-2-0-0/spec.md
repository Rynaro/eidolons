# mcp-atlas-aci-2-0-0 — pin the atlas-aci MCP to v2.0.0, backfill three skipped releases

**Tier:** lite · **Maker:** vivi · **Checker:** kupo

## Problem

`roster/mcps.yaml` pinned `atlas-aci` at `0.2.3` (released 2026-06-02). Upstream has since
shipped `0.3.0`, `0.3.1`, `0.4.0` and now `2.0.0`. The catalogue is the nexus's source of
truth for what version a consumer installs and what digest `eidolons verify` checks against
under the default `integrity.enforcement: strict` posture — so **three releases were
unreachable** via `eidolons mcp use atlas-aci@<ver>`, and every consumer was silently
installing a four-releases-old image.

Upstream `v2.0.0` is a harden-first major (bounds invariant enforced, CI actually running,
a path-traversal fix in `import_jsonl`) with a breaking on-disk schema change. It warrants
a deliberate pin, not a drift.

## Change

- `roster/mcps.yaml`: `versions.latest` and `versions.pins.stable` → `2.0.0`; record
  `0.3.0`, `0.3.1`, `0.4.0`, `2.0.0` under `versions.releases` with digests resolved from
  ghcr at bump time; bump `updated_at`.
- `cli/tests/mcp_images.bats`: bump the `ATLAS_ACI_PINNED` fixture to the new stable digest,
  and add `S8-guard`, which *derives* the expected digest from the catalogue rather than
  trusting the constant.
- `CHANGELOG.md`: document the bump, the three backfilled releases, and the breaking
  consumer-facing changes (re-index required; `callers_of` response shape; `refs.enclosing`
  removed).

Out of scope: `.mcp.json` / `eidolons.mcp.lock` local wiring (this repo's working tree
carries unrelated uncommitted edits); those update with `eidolons mcp upgrade atlas-aci`.

## Why `S8-guard` exists

`ATLAS_ACI_PINNED` is a hardcoded digest standing in for "the catalogue's stable digest".
`S8` asserts *"image present at the stable digest ⇒ DRIFT=no"*. A bump that edits the
catalogue but forgets the fixture leaves `S8` passing **vacuously** — asserting no-drift
against a digest nothing pins any more. The guard derives the value from
`roster/mcps.yaml` and fails on mismatch. Proven to have teeth: reverting the fixture to
the `0.2.3` digest fails `S8-guard` **and** `S8`; restoring it passes both.

This is the same defect class the upstream release spent itself eliminating: a check that
validates the data it was handed while the provenance of that data goes unchecked. See
upstream `ADR-001-checks-vs-proxies.md`.

## Acceptance

See `change.json` `acceptance_checks`. Every recorded digest is verified against ghcr, not
copied from a release note.

## Known, out of scope

`cli/tests/doctor_deep.bats` `DD-7` ("D4 OK — matching manifest_sha256 passes") fails on a
**clean tree** at `84b7497`, before any edit in this change. Confirmed by stashing this
change and re-running the file. Not introduced here; not fixed here.

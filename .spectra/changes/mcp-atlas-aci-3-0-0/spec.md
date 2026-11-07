# mcp-atlas-aci-3-0-0 — pin the atlas-aci MCP to v3.0.0

**Tier:** lite · **Maker:** vivi · **Checker:** kupo

## Problem

`roster/mcps.yaml` pins `atlas-aci` at `2.0.0`. Upstream has published `v3.0.0`
(tag on merge commit `b4b9681`, CI green, release not draft, not prerelease). The
catalogue is what `eidolons verify` checks an installed image against under
`integrity.enforcement: strict`, so a stale pin means every consumer installs the old
image and cannot rely on signed metadata for the new one.

## Change

- `roster/mcps.yaml`: `versions.latest` and `versions.pins.stable` -> `3.0.0`; add
  `releases."3.0.0"` (digest resolved from ghcr, `released_at` from the GitHub release
  `publishedAt`); bump `updated_at`. `catalogue_version` is unchanged (no new field).
  No backfill is needed: upstream tags run `v2.0.0` then `v3.0.0`.
- `cli/tests/mcp_images.bats`: bump the `ATLAS_ACI_PINNED` fixture and its comment.
  `S8-guard` derives the expected digest from the catalogue and is unchanged.
- `CHANGELOG.md`: Unreleased entry (digest, signing and attestations, breaking changes,
  link to the immutable release tag).

Out of scope: `.mcp.json` / `eidolons.mcp.lock` local wiring (consumer artefacts; they
update with `eidolons mcp upgrade atlas-aci`), and the install template. Upstream v3.0.0
makes `test_dry_run` execution opt-in via `ATLAS_ACI_ENABLE_TEST_EXECUTION=1`; the nexus
template does not set it. That is recorded in the CHANGELOG and left for a separate decision.

## Acceptance

See `change.json` `acceptance_checks`. The digest is resolved from the registry, not
copied from a release note.

## Known, out of scope

`cli/tests/doctor_deep.bats` `DD-7` has been red on a clean tree in earlier bumps. Not
introduced here; not fixed here.

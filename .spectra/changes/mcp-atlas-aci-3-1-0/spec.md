# mcp-atlas-aci-3-1-0 — pin the atlas-aci MCP to v3.1.0

**Tier:** lite · **Maker:** vivi · **Checker:** kupo

## Problem

`roster/mcps.yaml` pins `atlas-aci` at `3.0.2`. Upstream has published `v3.1.0`
(CI green, signed and attested by `release.yml`). It carries the fix for Rynaro/atlas-aci#123:
every `graph_query` and `search_symbol` call re-authenticated the whole published graph
generation, so a call cost time proportional to the corpus (42 s for a 387-byte result on
the reporter's 11,803-file corpus), `op=status` was built unbounded, and a client
disconnect did not stop the running query. Consumers of the 3.0.2 pin hit the same cost
on every graph call.

## Change

- `roster/mcps.yaml`: `versions.latest` and `versions.pins.stable` -> `3.1.0`; add
  `releases."3.1.0"` (digest resolved from ghcr, `released_at` from the GitHub release
  `publishedAt`); bump `updated_at`. `catalogue_version` is unchanged (no new field).
  No backfill is needed: upstream tags run `v3.0.2` then `v3.1.0`.
- `cli/tests/mcp_images.bats`: bump the `ATLAS_ACI_PINNED` fixture and its comment.
  `S8-guard` derives the expected digest from the catalogue and is unchanged.
- `CHANGELOG.md`: Unreleased entry (digest, signing and attestations, the fix, the new
  server-side deadline, the extraction-cache note, link to the immutable release tag).

Out of scope: `.mcp.json` / `eidolons.mcp.lock` local wiring (consumer artefacts; they
update with `eidolons mcp upgrade atlas-aci`), and the install template. Upstream v3.1.0
adds `serve --graph-query-deadline` (default 20 s); the nexus template does not set it.

## Acceptance

See `change.json` `acceptance_checks`. The digest is resolved from the registry, not
copied from a release note.

## Known, out of scope

Any bats failure that also fails on a clean tree is not introduced here and not fixed here.

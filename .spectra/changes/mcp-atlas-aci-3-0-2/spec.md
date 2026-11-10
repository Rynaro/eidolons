# mcp-atlas-aci-3-0-2 — pin the atlas-aci MCP to v3.0.2

**Tier:** lite · **Maker:** vivi · **Checker:** kupo

## Problem

`roster/mcps.yaml` pins `atlas-aci` at `3.0.0`. Upstream has published `v3.0.2`
(CI green, signed and attested by `release.yml`). It carries the fix for Rynaro/atlas-aci#118:
`atlas-aci index` discarded a completed build on btrfs and overlayfs because
`Builder.close()` listed the source stage through a stale directory descriptor and
`rmdir` failed with `ENOTEMPTY`. overlayfs is the docker rootfs the pinned image runs
on, so consumers of the 3.0.0 pin can hit it. 3.0.2 also applies Debian security updates
in the runtime image (two fixable HIGH `zlib1g` CVEs in the base).

Upstream `v3.0.1` is **not** a release: its `release.yml` run pushed an image, then failed
the Trivy gate before signing, attestation and the GitHub Release. That image is unsigned.

## Change

- `roster/mcps.yaml`: `versions.latest` and `versions.pins.stable` -> `3.0.2`; add
  `releases."3.0.2"` (digest resolved from ghcr, `released_at` from the GitHub release
  `publishedAt`); bump `updated_at`. `catalogue_version` is unchanged (no new field).
  `3.0.1` is deliberately **not** backfilled (unsigned, no GitHub Release); a comment in
  the catalogue says why, so `mcp use atlas-aci@3.0.1` cannot reach that image.
- `cli/tests/mcp_images.bats`: bump the `ATLAS_ACI_PINNED` fixture and its comment.
  `S8-guard` derives the expected digest from the catalogue and is unchanged.
- `CHANGELOG.md`: Unreleased entry (digest, signing and attestations, the fix, the
  extraction-cache note, link to the immutable release tag).

Out of scope: `.mcp.json` / `eidolons.mcp.lock` local wiring (consumer artefacts; they
update with `eidolons mcp upgrade atlas-aci`).

## Acceptance

See `change.json` `acceptance_checks`. The digest is resolved from the registry, not
copied from a release note.

## Known, out of scope

Any bats failure that also fails on a clean tree is not introduced here and not fixed here.

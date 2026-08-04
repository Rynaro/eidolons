# mcp-crystalium-1-10-0 — pin CRYSTALIUM v1.10.0 in the nexus catalogue

**Tier:** lite · **Maker:** vivi · **Checker:** kupo
**Upstream:** https://github.com/Rynaro/crystalium/releases/tag/v1.10.0 (merged PR Rynaro/crystalium#49, fixes crystalium#38; campaign artifacts in `.spectra/changes/crystalium-rrf-fusion-38/`)

## What

Bump crystalium `versions.latest` + `pins.stable` 1.9.0 → 1.10.0 in **both** roster
files (dual-rostered, CI skew guard `cli/src/check_roster_mcp_skew.sh` enforces
parity), add the 1.10.0 release entries, refresh `updated_at`, and add the nexus
CHANGELOG paragraph. No CLI code, no bats changes (`CRYSTALIUM_PINNED` in
`cli/tests/mcp_images.bats` is S9's deliberate stale-digest fixture — untouched by
design).

## Verified inputs (all independently resolved, none copied from release notes)

- Image index digest (`ghcr.io/rynaro/crystalium:1.10.0`, un-prefixed tag):
  `sha256:27b61cb5e7ca912feae4479a49db7d7cb73ce419cb39e387e18fc51eba4b5015`
  (multi-arch OCI index, linux/amd64 + linux/arm64, resolved via
  `docker buildx imagetools inspect`).
- DP-R5 probe: fresh `docker run --pull always` at that digest boots and reports
  `crystalium.__version__ == 1.10.0`.
- `commit 56c85104aaedc60d684f0606fc21c86f421f9825`, `tree
  47ed34df8cb98c6a2aba62c00295b486ec707da6` — release-manifest.json values matched
  against independent `git rev-parse v1.10.0^{commit}/^{tree}`.
- `archive_sha256
  29386d3c9278176c265795dcbb74984b03ea7231155e7bd3de2da3e4fb081175` — SHA256SUMS
  asset AND an independent `sha256sum` of the downloaded `source.tar` agree.
- No skipped releases: `gh release list` shows 1.9.0 → 1.10.0 adjacent.
- Released at: 2026-08-04T02:38:42Z (GitHub release publishedAt).

## Acceptance checks

1. `versions.latest == versions.pins.stable == "1.10.0"` in BOTH `roster/mcps.yaml`
   and `roster/index.yaml` (skew guard exits 0).
2. `roster/mcps.yaml` 1.10.0 release entry digest matches a fresh
   `imagetools inspect` of the registry tag (read back from the file, not scrollback).
3. `roster/index.yaml` 1.10.0 entry carries tag/commit/tree/archive_sha256/provenance
   matching the verified inputs above.
4. `make schema` passes; `EIDOLONS_NEXUS=$(pwd) bash cli/eidolons mcp show crystalium`
   reports 1.10.0.
5. `cli/tests/mcp_images.bats` passes unmodified (S9's stale-digest fixture intact).
6. CHANGELOG `[Unreleased]/Changed` carries the bump paragraph with the digest and
   the score-semantics note (v1.10.0 changes `CrystalSummary.score` to the weighted
   fused value, default ON — consumers upgrading see ranking shifts; one-line revert
   `recall_weighted_fusion: false`).

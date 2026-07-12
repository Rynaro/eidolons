# mcp-atomos-0-2-0 — pin atomos 0.2.0 in the nexus catalogue

**Tier:** lite (mechanical right-size: 4 files, rubric 3, no trade-off)
**Maker:** orchestrator · **Checker:** kupo (maker ≠ checker)

## Why

atomos v0.2.0 ships `compose_externalize_manifest` — the **fourth and final tool**
of the closed set declared in the atomos ADR §2 and deferred to v0.2 by §2.4. The
atomos MCP is now feature-complete: `compose_handoff` · `verify_envelope` ·
`verify_pins` · `compose_externalize_manifest`.

The catalogue currently pins `0.1.0` and enumerates only the first three tools. Under
the default `integrity.enforcement: strict` posture, `roster/mcps.yaml` is what
`eidolons verify` checks an installed image against, so a stale pin is not cosmetic:
every consumer installs the 3-tool image and cannot reach the new tool at all.

`exposes_tools.list` is load-bearing, not documentation — the generic grant driver
injects the glob, and the enumerated list is the catalogue's record of the surface.
It must gain the fourth entry or the catalogue misdescribes the image it pins.

## Scope

- `roster/mcps.yaml` — atomos entry: `versions.latest` + `versions.pins.stable` →
  `0.2.0`; new `releases."0.2.0"` block with the **multi-arch index digest** resolved
  from the registry (never copied from a release note); `exposes_tools.list` gains
  `mcp__atomos__compose_externalize_manifest`; top-of-file `updated_at`.
- `eidolons.mcp.lock` — consumer wiring bumped to 0.2.0 + the new digest.
- `CHANGELOG.md` — `## [Unreleased] → ### Changed` entry.
- `.spectra/changes/mcp-atomos-0-2-0/` — this change folder.

`catalogue_version` stays `1.2`: this adds *contents* (a release, a tool name), not a
new *field*. Bumping it is reserved for shape changes.

## Out of scope

- `.mcp.json` — a **local consumer artefact** carrying machine-absolute paths
  (`/home/rynaro/...`) from `eidolons mcp install`. It is dirty in the working tree
  and must NOT be swept into this commit.
- The parked `ecm-p2-host-adapters` change (codex/opencode/copilot/cursor adapters).
  Unrelated campaign; not resumed by this change.
- Any atomos-repo edit. atomos ships to ghcr first, then the nexus rosters the digest
  — the same order as every other MCP.

## Acceptance checks

1. `roster/mcps.yaml` atomos `versions.latest == "0.2.0"` and `pins.stable == "0.2.0"`.
2. The recorded `releases."0.2.0".digest` **byte-equals** the digest read back from the
   registry for `ghcr.io/rynaro/atomos:0.2.0` — re-resolved from the registry, read out
   of the file (not out of scrollback), and it must be the multi-arch **index** digest
   (`application/vnd.oci.image.index.v1+json`), never a per-arch manifest digest.
3. `exposes_tools.list` contains exactly the four `mcp__atomos__*` tool names, and that
   list matches `tools/list` served by the pinned image itself.
4. `releases."0.1.0"` is retained (no release is made unreachable to `eidolons mcp use`).
5. `make schema` passes (jq + yq structural checks, what CI runs).
6. `EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons mcp show atomos` reports 0.2.0.
7. `make test` — no new red relative to a clean tree (`doctor_deep.bats` DD-7 is a
   known pre-existing failure; confirm by stashing before blaming this change).
8. `.mcp.json` and `.gitignore` are NOT in the commit.

## Notes

`catalogue_version` unchanged. Git tags are `v`-prefixed (`v0.2.0`); the image tag is
not (`ghcr.io/rynaro/atomos:0.2.0`) — `imagetools inspect …:v0.2.0` silently returns
nothing. atomos has **no** hardcoded digest fixture in `cli/tests/mcp_images.bats`
(only `ATLAS_ACI_PINNED` and `CRYSTALIUM_PINNED` exist), so the vacuous-S8 trap that
skill documents does not apply here — verified, not assumed.

# mcp-bump-crystalium-1-8-1-tonberry-0-5-3 — pin crystalium 1.8.1 + tonberry 0.5.3

**Tier:** lite (mechanical right-size: data-only catalogue edit, no code, no trade-off)
**Maker:** vivi · **Checker:** kupo (maker ≠ checker)

## Context

Two upstream MCP releases shipped:

- **crystalium 1.8.1** (commit `af24493`) fixes a `recall` crash on cl100k
  special-token strings inside a stored summary (`crystalium#32`).
- **tonberry 0.5.3** (commit `80f07ff`) adds a C2a failure-detail diagnostic for a
  non-canonical `stage` field (`tonberry#9`) — diagnostic-only, no tool/parity change.

The nexus catalogue (`roster/mcps.yaml`) still pins `1.8.0` / `0.5.2`. Under the
default `integrity.enforcement: strict` posture, this file is what `eidolons verify`
checks an installed image against — a stale pin is not cosmetic: every consumer
installs the old image and cannot reach the new one via `eidolons mcp use <name>@<ver>`.

## Change

- `roster/mcps.yaml`:
  - crystalium `versions.latest` / `versions.pins.stable`: `1.8.0` → `1.8.1`. New
    `releases."1.8.1"` entry (digest `sha256:90105b21…`, `released_at:
    2026-07-17T00:00:00Z`), resolved from the ghcr registry index, not copied from a
    release note.
  - tonberry `versions.latest` / `versions.pins.stable`: `0.5.2` → `0.5.3`. New
    `releases."0.5.3"` entry (digest `sha256:df6ec882…`, `released_at:
    2026-07-17T00:00:00Z`), resolved the same way.
  - Top-of-file `updated_at` → `2026-07-17`. `catalogue_version` unchanged — this
    adds contents (two releases), not a new field, so `1.2` stays as-is.
- `CHANGELOG.md` — `## [Unreleased] → ### Changed` entry covering both pins.
- `.spectra/changes/mcp-bump-crystalium-1-8-1-tonberry-0-5-3/` — this change folder.

## Out of scope

- `cli/tests/mcp_images.bats` — no `S8-guard` exists for crystalium or tonberry
  (only `ATLAS_ACI_PINNED` has one). `CRYSTALIUM_PINNED`
  (`sha256:84d450ed…`, tracking the old `1.2.0` release) is the **deliberately
  non-matching** digest that drives the `S9` `DRIFT=yes` path — it is untouched by
  this change and must stay untouched.
- `.mcp.json` / `eidolons.mcp.lock` / `.gitignore` — local consumer artefacts, often
  carrying unrelated dirty-tree edits; not swept into this commit.
- Any crystalium-repo or tonberry-repo edit — both ship to ghcr first; the nexus only
  roster the digest, same order as every other MCP bump.

## Acceptance criteria

1. **GIVEN** `roster/mcps.yaml`'s crystalium entry, **WHEN** its versions are read,
   **THEN** `releases."1.8.1".digest` byte-equals the registry index digest for
   `ghcr.io/rynaro/crystalium:1.8.1` and `latest == pins.stable == "1.8.1"`.
2. **GIVEN** `roster/mcps.yaml`'s tonberry entry, **WHEN** its versions are read,
   **THEN** `releases."0.5.3".digest` byte-equals the registry index digest for
   `ghcr.io/rynaro/tonberry:0.5.3` and `latest == pins.stable == "0.5.3"`.
3. **GIVEN** the nexus schema checks, **WHEN** `make schema` runs, **THEN** it exits 0.
4. **GIVEN** the CLI, **WHEN** `EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons mcp show
   crystalium` and `... mcp show tonberry` run, **THEN** they report `1.8.1` and
   `0.5.3` respectively, with the new digests.
5. **GIVEN** `cli/tests/mcp_images.bats`, **WHEN** run unmodified, **THEN** it stays
   green — no fixture change, and `CRYSTALIUM_PINNED`'s deliberately-stale `S9`
   digest is untouched.

## Notes

Digests were resolved from the ghcr anonymous-token registry API and re-verified by
reading them back out of `roster/mcps.yaml` (not out of scrollback). Image tags are
un-prefixed (`1.8.1`, `0.5.3`, no `v`) — a git-tag-style `v1.8.1` lookup would
silently return nothing against the registry.

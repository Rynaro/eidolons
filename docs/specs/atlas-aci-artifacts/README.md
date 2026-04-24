# Staged ATLAS-side artifacts for `eidolons atlas aci`

This directory holds the **Layer-2 / ATLAS-repo** artifacts that
implement [`../atlas-aci-integration.md`](../atlas-aci-integration.md).
They are staged here because the Eidolons nexus (this repo) has no
permission to push to `Rynaro/ATLAS` directly — the ATLAS repo is the
owner of this code per decision **D2** in the spec.

The staged files are production-ready: shellcheck-clean under
`shellcheck -x -S error`, bash 3.2 compliant, fully implementing §4
of the spec (prereq checks, JSON writes via `jq`, YAML-frontmatter
writes via mikefarah `yq`, atomic tmpfile+mv, idempotent install /
remove, exit codes 0/2/3/4/5/6/1).

---

## Contents

| Path | Destination in `Rynaro/ATLAS` |
|---|---|
| `commands/aci.sh` | `commands/aci.sh` (repo root) |

---

## How to land this in `Rynaro/ATLAS`

1. **Branch**: create `feat/atlas-aci-command` off `main` in
   `Rynaro/ATLAS`.

2. **Copy the script**:
   ```bash
   cp docs/specs/atlas-aci-artifacts/commands/aci.sh \
      /path/to/ATLAS/commands/aci.sh
   chmod +x /path/to/ATLAS/commands/aci.sh
   ```

3. **Update ATLAS's `install.sh`** to ship `commands/aci.sh` into the
   installed target. ATLAS already installs into
   `./.eidolons/atlas/` per the nexus roster
   (`install.target_default: "./.eidolons/atlas"`); the installer
   must copy `commands/aci.sh` to
   `<TARGET>/commands/aci.sh` and preserve its executable bit.
   Mirror how ATLAS currently ships any other `commands/*.sh` file
   (if none exist yet, follow the pattern used by SPECTRA's
   `commands/fit.sh` install step). The `install.manifest.json`
   must include the new file under `files`.

4. **Add ATLAS-side bats tests** per §5.2 of the spec (T6–T32).
   Sketch of what they need to cover:
   - **T6**: install twice → byte-identical `.mcp.json`, `.cursor/mcp.json`, `.gitignore`.
   - **T7**: install → remove → install round-trips to single-install state.
   - **T8**: remove with nothing installed → exit 0, no files created.
   - **T9a / T9b / T9c**: install preserves peer `mcpServers.<other>` / `name: <other>` list entries.
   - **T10a / T10b / T10c**: remove preserves peers.
   - **T11 / T12 / T13**: `--host` restricts to exactly one host.
   - **T14**: copilot host without any `.agent.md` files → info log, exit 0.
   - **T15**: copilot YAML-frontmatter edits preserve Markdown body byte-for-byte.
   - **T16 / T17 / T18**: `.gitignore` idempotency, whitespace-tolerance, creation-if-absent.
   - **T19 / T20 / T21 / T22**: prereq failures (uv / rg / python3<3.11 / atlas-aci binary) → exit 5.
   - **T23**: `atlas-aci index` failure → exit 6 with no MCP config writes.
   - **T24**: skip re-index if `.atlas/manifest.yaml` exists.
   - **T25**: `--dry-run` touches no mtime; lists every path with `CREATE|MODIFY|REMOVE|INDEX`.
   - **T26**: no host detected + no `--host` → exit 4.
   - **T27**: bash 3.2 (runs under `/bin/bash` on macos-latest).
   - **T28**: stdout empty on `--install` success; stderr has log.
   - **T29**: filesystem trace shows no writes outside cwd.
   - **T30 / T31**: `jq empty` / `yq` parse all post-install files.
   - **T32**: `shellcheck -x -S error` on `commands/aci.sh`.

5. **Update ATLAS's `CHANGELOG.md`** and cut a new patch release
   (e.g. `v1.0.4`). Once tagged, bump `roster/index.yaml` in the
   nexus (`Rynaro/eidolons`):
   - `eidolons[].versions.latest` for `atlas`
   - `eidolons[].versions.pins.stable` for `atlas`
   - follow the branch pattern `fix/roster-atlas-<version>` per
     `CLAUDE.md` → "Roster changes".

6. **Open the PR** in `Rynaro/ATLAS` with a test plan referencing
   `../atlas-aci-integration.md` §5.2. The nexus-side dispatch tests
   (`cli/tests/atlas_aci_dispatch.bats`) already shipped; they cover
   T1–T5 and do not block on the ATLAS PR.

---

## Why not push directly from the nexus?

Per decision **D2** in the spec and the Layer-2 boundary in
[`../../architecture.md`](../../architecture.md):

- ATLAS owns its own methodology and install. The nexus CLI (this
  repo) does not embed per-Eidolon content; that was committed to
  in the four-layer model.
- ATLAS's own CI (if any) runs against `Rynaro/ATLAS`, not here.
  Shipping `commands/aci.sh` via this repo would couple release
  cadence across repos — exactly what the distributed model exists
  to avoid.

The staged-artifact approach keeps the nexus-side and ATLAS-side
changes atomically reviewable while respecting that the PR on ATLAS
is a separate action the maintainer performs.

---

## What the nexus side already covers

On-branch in `Rynaro/eidolons` (branch `feat/atlas-aci-integration`):

- `cli/tests/atlas_aci_dispatch.bats` — T1–T5 from §5.1.
- `docs/atlas-aci.md` — user-facing opt-in documentation.
- Pointer to the new doc from `docs/cli-reference.md` under
  "Per-Eidolon subcommands".

No `roster/index.yaml` change. No CI matrix change (D4). No preset
change (D4, P8).

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
| `tests/helpers.bash` | `tests/helpers.bash` |
| `tests/idempotency.bats` | `tests/idempotency.bats` |
| `tests/peer_preservation.bats` | `tests/peer_preservation.bats` |
| `tests/host_filter.bats` | `tests/host_filter.bats` |
| `tests/copilot.bats` | `tests/copilot.bats` |
| `tests/gitignore.bats` | `tests/gitignore.bats` |
| `tests/prereqs.bats` | `tests/prereqs.bats` |
| `tests/index.bats` | `tests/index.bats` |
| `tests/operational.bats` | `tests/operational.bats` |

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

4. **Copy the bats suite** (covers T6–T29 from §5.2):
   ```bash
   cp -R docs/specs/atlas-aci-artifacts/tests /path/to/ATLAS/tests
   ```
   The suite is organised by concern:

   | File | Spec anchors | Test count |
   |---|---|---|
   | `tests/helpers.bash` | — (fixtures / stubs) | n/a |
   | `tests/idempotency.bats` | T6, T7, T8 | 5 |
   | `tests/peer_preservation.bats` | T9a/b/c, T10a/b/c | 6 |
   | `tests/host_filter.bats` | T11, T12, T13 | 3 |
   | `tests/copilot.bats` | T14, T15 | 3 |
   | `tests/gitignore.bats` | T16, T17, T18 | 4 |
   | `tests/prereqs.bats` | T19, T20, T21, T22 | 5 |
   | `tests/index.bats` | T23, T24 | 2 |
   | `tests/operational.bats` | T25, T26, T27, T28, T29 | 5 |

   **Running locally** (from the ATLAS repo root, once `commands/aci.sh`
   is landed):
   ```bash
   bats tests/
   ```

   The suite stubs `uv`, `rg`, `python3`, and `atlas-aci` on `PATH` so
   no real prereqs are required in CI. `jq` and `yq` (mikefarah) are
   genuine dependencies; the ATLAS CI runner must install them.

   ### CI additions (T27, T30, T31, T32 — lint / platform gates)

   These are not expressible as bats tests; add them to
   `.github/workflows/test.yml` (or equivalent) in `Rynaro/ATLAS`:

   - **T27** (bash 3.2): run `bats tests/` on a `macos-latest` job so
     the default `/bin/bash` is 3.2. Linux jobs catch bash 4+
     incompatibilities only if bats runs under `/bin/bash` explicitly.
   - **T30** (JSON parses): after a representative bats run, assert
     `jq empty .mcp.json` and `jq empty .cursor/mcp.json` on the
     generated fixtures. The idempotency tests already implicitly cover
     this (they call `jq -S`), but an explicit post-install `jq empty`
     job is cheap belt-and-suspenders.
   - **T31** (YAML frontmatter parses): similarly, pipe each modified
     `.agent.md`'s frontmatter through `yq eval .` and assert exit 0.
   - **T32** (shellcheck): run
     `shellcheck -x -S error commands/aci.sh` on every push. The
     staged script is already clean under this gate (verified in the
     nexus before copy-out).

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

# atlas-aci-container — container-runtime mode for `eidolons atlas aci`

This spec covers ATLAS v1.1.0's `--container` flag, which adds a
Docker/Podman alternative to the existing `uv`-based atlas-aci install
path.

## SPECTRA spec

The authoritative machine-readable spec and all resolved decisions
(D1–D6) live in `.spectra/atlas-aci-container.yaml` at the nexus root.
The prose companion is `.spectra/atlas-aci-container.md`.

## Scope

This is a nexus-side document only. Implementation lives in:

- `Rynaro/ATLAS` — `commands/aci.sh` (new flags), `install.sh` (version
  bump to 1.1.0), bats test suite extension.
- `Rynaro/eidolons` — `roster/index.yaml` (ATLAS pin 1.0.6 → 1.1.0),
  `CHANGELOG.md`.

The `atlas-aci` upstream repo (`Rynaro/atlas-aci`) has zero code changes
in this release (D2 = build-locally; GHCR publish deferred to F1).

## Key decisions

| ID | Topic | Resolution |
|----|-------|------------|
| D1 | Runtime selection | Always prompt; `--runtime` bypasses prompt |
| D2 | Image distribution | Build locally from git URL; no GHCR pull in v1 |
| D3 | Version pinning | Local sha256 digest captured after build |
| D4 | MCP transport | `docker/podman run --rm -i` per session |
| D5 | Volume layout | Read-only serve mount; separate writable index mount |
| D6 | Memex persistence | Bind-mount `${PWD}/.atlas/memex` |

## New flags (`eidolons atlas aci`)

- `--container` — install container-runtime variant
- `--runtime <docker|podman>` — force runtime; bypasses interactive prompt

## New exit codes

| Code | Meaning |
|------|---------|
| 7 | Container runtime not on PATH |
| 8 | Image build failed |
| 9 | `--non-interactive` without `--runtime` |

# `eidolons mcp` — unified MCP server store

> **See also:** [`docs/atlas-aci.md`](atlas-aci.md) for Atlas-ACI-specific
> operational notes, and [`docs/architecture.md`](architecture.md) §"MCP-server
> scaffolding" for the design rationale.

`eidolons mcp` is the unified command surface for discovering, installing,
refreshing, and health-checking MCP servers in a project. It replaces the
separate `eidolons mcp atlas-aci` and `eidolons harness` families (which
survive as deprecated aliases through nexus v2.9.x).

---

## Catalogue (`roster/mcps.yaml`)

The catalogue lives in `roster/mcps.yaml` alongside `roster/index.yaml`. It
is a closed set — adding third-party MCPs is out of scope (NG6). v1.3 ships
two entries:

| Name | Kind | Description |
|---|---|---|
| `atlas-aci` | `oci-image` | Stdio MCP exposing structural codebase intelligence (codegraph + symbol index). Docker-based. |
| `junction` | `binary` | Container-isolated agent harness with ReasoningStep / plan.json dispatch. |

```
eidolons mcp list          # browse the catalogue + installed status
eidolons mcp show atlas-aci # full detail for one entry
```

---

## Lifecycle

### Install

```bash
eidolons mcp install atlas-aci           # installs at pins.stable (0.2.2)
eidolons mcp install junction@0.2.0      # explicit version
eidolons mcp install atlas-aci --force   # reinstall even if already present
```

Install is **idempotent**: a second run with the same version is a no-op.
The lockfile's `installed_at` field is NOT updated on no-op runs.

### Refresh

Re-fetch the artefact (re-pull the image / re-download the binary) without
regenerating host wiring files. Updates `installed_at` in the lockfile.

```bash
eidolons mcp refresh atlas-aci
eidolons mcp refresh junction
```

### Uninstall

```bash
eidolons mcp uninstall atlas-aci
eidolons mcp uninstall junction
```

For `oci-image` MCPs: host wiring (`.mcp.json`, `.cursor/mcp.json`) is
cleaned up; the Docker image itself is **not** removed (may be shared with
other projects); `.atlas/memex/codegraph.db` is **never** deleted.

For `binary` MCPs: the binary cache (`~/.eidolons/cache/junction@*/`) and
the marker dir (`.eidolons/harness/`) are removed.

### Upgrade

```bash
eidolons mcp upgrade atlas-aci   # upgrade one
eidolons mcp upgrade --all       # upgrade all installed
```

Reads catalogue `pins.stable` and re-runs install with `--force` only when
the version differs. No-op upgrades (already at stable) produce a
byte-identical lockfile — `installed_at` is preserved.

### Sync (opt-in reconciler)

Reads the optional `mcps:` block from `eidolons.yaml` and installs any
declared MCPs that are not yet installed. Idempotent.

```yaml
# eidolons.yaml
mcps:
  - name: atlas-aci
    version: "^0.2.0"
  - name: junction
    version: "^0.2.0"
```

```bash
eidolons mcp sync
```

> **Note:** `eidolons sync` (the top-level Eidolon sync command) does **not**
> call `eidolons mcp sync` automatically (NG3). MCP install is always
> explicit.

---

## Lockfile (`eidolons.mcp.lock`)

`eidolons mcp install` / `upgrade` / `sync` write a sibling lockfile
`eidolons.mcp.lock` alongside `eidolons.lock`. **Commit it to VCS.**

Example:

```yaml
# eidolons.mcp.lock — auto-generated. Commit to VCS.
generated_at: "2026-05-19T19:00:00Z"
eidolons_cli_version: "1.3.0"
catalogue_version: "1.0"
mcps:
  - name: atlas-aci
    kind: oci-image
    version: "0.2.2"
    source:
      image: "ghcr.io/rynaro/atlas-aci"
    integrity:
      algo: oci-digest
      value: "sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96"
    target: ".mcp.json"
    hosts_wired:
      - ".mcp.json"
      - ".cursor/mcp.json"
      - ".github/agents/atlas.agent.md"
      - ".codex/config.toml"
    installed_at: "2026-05-19T18:55:00Z"
  - name: junction
    kind: binary
    version: "0.2.0"
    source:
      repo: "Rynaro/Junction"
    integrity:
      algo: none
      value: ""
    target: "$EIDOLONS_HOME/cache/junction@0.2.0/junction"
    hosts_wired:
      - ".eidolons/harness/manifest.json"
    installed_at: "2026-05-19T18:56:00Z"
```

Schema: `schemas/mcp-lockfile.schema.json`.

---

## Health

```bash
eidolons mcp health atlas-aci    # per-MCP probe breakdown
eidolons mcp health junction
eidolons mcp health --all        # all installed MCPs
```

Output format (one line per probe):

```
atlas-aci  docker_cli       ok
atlas-aci  docker_daemon    ok
atlas-aci  image_local      ok    sha256:386677...
atlas-aci  registry_reachable  ok
atlas-aci  OVERALL          ok
```

Exit code is always 0 — the status line is the signal.

---

## `eidolons doctor` integration

`eidolons doctor` iterates `eidolons.mcp.lock` and summarises health for each
installed MCP in the "MCP servers" section. A separate "MCP catalogue drift"
section surfaces MCPs that are behind `pins.stable`.

---

## `mcp run` (binary MCPs only in v1.3)

Pass-through to the junction binary:

```bash
eidolons mcp run junction verify --plan plan.json
eidolons mcp run junction --version
```

Looks up the binary path from `eidolons.mcp.lock` (preferred) or the cache
glob `$EIDOLONS_HOME/cache/junction@*/junction` (fallback).

---

## Image management

### `eidolons mcp pull <name>` — fetch an OCI image

Catalogue-pin-driven image fetch. Idempotent: no-op when the image is
already present at the pinned ref. Does **not** touch the lockfile or
`.mcp.json`.

```bash
eidolons mcp pull crystalium                              # pull at pins.stable digest
eidolons mcp pull atlas-aci --image-digest sha256:...    # digest override
eidolons mcp pull atlas-aci --build-locally              # offline escape hatch (buildable MCPs only)
eidolons mcp pull atlas-aci --build-locally --git-ref v1.2
```

Exit codes: 0 = present (or pulled), 1 = docker/pull failure, 2 = bad usage.

`--build-locally` is only valid for MCPs that declare a `source.build` block
in the catalogue. Currently: **atlas-aci** (buildable), **crystalium**
(pull-only). Attempting `--build-locally` on a pull-only MCP exits 2 with a
clear message. The `--git-ref` flag requires `--build-locally` and defaults to
the MCP's `source.build.default_ref` (usually `main`).

### `eidolons mcp images` — image inventory

Status table across all `oci-image` MCPs. Binary MCPs (junction) are omitted.
Always exits 0 — docker absence is shown as `(n/a)`, not a failure.

```bash
eidolons mcp images           # human-readable table
eidolons mcp images --json    # JSON array (machine-readable)
```

Table columns:

| Column | Meaning |
|--------|---------|
| `NAME` | Catalogue name |
| `IMAGE` | Registry ref (no digest) |
| `PRESENT` | `yes` / `no` / `(n/a)` — `(n/a)` when docker CLI/daemon unavailable |
| `LOCAL` | First 19 chars of the locally-resolved image digest, or `—` |
| `PINNED` | First 19 chars of `versions.releases[pins.stable].digest` |
| `DRIFT` | `no` / `yes` / `unknown` |
| `SIZE` | Human-readable image size, or `—` |

**Drift semantics:**
- `unknown` — docker unavailable, image absent, or local digest unresolvable
  (e.g. locally-built image with no RepoDigest).
- `no` — image present AND local digest == catalogue pinned digest.
- `yes` — image present AND local digest != catalogue pinned digest (stale
  image, post-catalogue-bump, or locally-built override).

The `--json` output includes `locked_digest` (from the lockfile) for
completeness, but DRIFT is strictly local-vs-pinned.

### Auto-pull on `install` / `upgrade`

`eidolons mcp install` and `eidolons mcp upgrade` automatically pull the
pinned OCI image when it is missing, so they "just work" on a fresh host
without a prior manual `docker pull`.

```bash
eidolons mcp install crystalium          # auto-pulls if image absent
eidolons mcp upgrade crystalium          # auto-pulls if newer image is absent
```

To suppress auto-pull (air-gap environments), pass `--no-pull`:

```bash
eidolons mcp install crystalium --no-pull   # aborts if image absent (old behavior)
eidolons mcp upgrade crystalium --no-pull   # same
```

`--no-pull` is accepted and silently ignored for `kind: binary` MCPs (junction):
binary install fetches its own artefact independently of OCI.

### `source.build` catalogue block

MCPs that support `--build-locally` declare a `source.build` block in
`roster/mcps.yaml`:

```yaml
source:
  type: ghcr
  image: "ghcr.io/rynaro/atlas-aci"
  build:
    git_url: "https://github.com/Rynaro/atlas-aci.git"
    context: "mcp-server"
    default_ref: "main"
```

Presence of `source.build` gates the `--build-locally` flag. MCPs without
this block are pull-only; attempting `--build-locally` exits 2.

---

## Deprecated aliases

Both legacy command families remain functional through nexus **v2.9.x** and
emit a single-line `DEPRECATED:` warning to stderr. Set
`EIDOLONS_SUPPRESS_DEPRECATED=1` to silence it (useful in CI that pins a
version and has not yet migrated).

| Legacy | New equivalent | Removed in |
|---|---|---|
| `eidolons mcp atlas-aci [--force]` | `eidolons mcp install atlas-aci [--force]` | v3.0.0 |
| `eidolons mcp atlas-aci pull [...]` | `eidolons mcp pull atlas-aci [...]` | v3.0.0 |
| `eidolons harness install [ver]` | `eidolons mcp install junction[@ver]` | v3.0.0 |
| `eidolons harness up` | `eidolons mcp health junction` | v3.0.0 |
| `eidolons harness verify [args]` | `eidolons mcp run junction verify [args]` | v3.0.0 |
| `eidolons harness uninstall` | `eidolons mcp uninstall junction` | v3.0.0 |

> **Behavior change (OQ-4):** `eidolons mcp atlas-aci pull` was previously an
> alias for `eidolons mcp refresh atlas-aci` (lockfile-driven). It is now
> re-pointed to `eidolons mcp pull atlas-aci` (catalogue-pin-driven). This
> matches the user intuition of "pull = fetch the current catalogue image" and
> unifies the image-fetch surface. Scripted callers of the deprecated alias
> that relied on lockfile-driven semantics should migrate to
> `eidolons mcp refresh atlas-aci`.

---

## Driver kinds

| Kind | Artefact | Install mechanism | Health probes |
|---|---|---|---|
| `oci-image` | Docker image | `docker pull <digest>` | docker_cli, docker_daemon, image_local, registry_reachable |
| `binary` | Compiled binary | `curl / bash install.sh` | binary_present, binary_version, docker_daemon_optional |
| `script` | Shell script | (reserved, no v1.3 members) | — |

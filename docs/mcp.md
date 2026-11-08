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
is a closed set — adding third-party MCPs is out of scope (NG6).

| Name | Kind | Description |
|---|---|---|
| `atlas-aci` | `oci-image` | Stdio MCP exposing structural codebase intelligence (codegraph + symbol index). Docker-based. |
| `junction` | `binary` | Container-isolated agent harness with ReasoningStep / plan.json dispatch. |
| `crystalium` | `oci-image` | Cross-session memory and retrieval server. |
| `tonberry` | `oci-image` | Eidolons Spec Lifecycle server. |
| `atomos` | `oci-image` | Eidolons Context Management compose/verify server. |

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

**Multi-host write targets:** `eidolons mcp install` writes to multiple host
configuration files depending on which hosts are wired in `eidolons.yaml`:

| Target file | Written when |
|---|---|
| `.mcp.json` | Always |
| `.cursor/mcp.json` | cursor ∈ `hosts.wire` |
| `.codex/config.toml` (managed `[mcp_servers.<name>]` section) | codex ∈ `hosts.wire` |

All writes are idempotent: jq-merge for JSON targets, marker-bounded
managed-section rewrite for TOML. Sibling entries in `.cursor/mcp.json`
are preserved. User content outside the `# eidolon:mcp start/end` markers
in `.codex/config.toml` is preserved. The lockfile `hosts_wired` array
reflects the actual files written (no aspirational entries). [ASSUMPTION A3]:
codex project-scope `mcp_servers` is assumed allowed; verify with
`eidolons doctor` once confirmed.

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

For `oci-image` MCPs: host wiring (`.mcp.json`, `.cursor/mcp.json`,
`.codex/config.toml` managed section) is cleaned up; the Docker image
itself is **not** removed (may be shared with other projects);
`.atlas/memex/codegraph.db` is **never** deleted.

For `binary` MCPs: the binary cache (`~/.eidolons/cache/junction@*/`),
the marker dir (`.eidolons/harness/`), and any `.cursor/mcp.json` /
`.codex/config.toml` entries are removed.

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
eidolons mcp sync                  # install missing declared MCPs
eidolons mcp verify                # diagnose installed wiring drift
eidolons mcp sync --dry-run        # preview drift without writing
eidolons mcp sync --repair-wiring  # explicitly repair managed wiring
```

`--dry-run` and `--repair-wiring` require `eidolons.yaml`, operate on installed,
locked MCPs, and do not install artifacts. The flags are mutually exclusive.
Ordinary sync reports wiring drift; use the explicit repair after reviewing
its preview. `eidolons mcp verify [name] [--json]` diagnoses generated runtime
arguments, managed tool grants, and configured host projections without
repairing them.

Repair preserves user-owned fields (including environment settings and
per-server timeouts), other servers, and content outside managed sections.
It retains the locked OCI digest, including a locally installed unpublished
image, and updates the runtime receipt after repair. An unreceipted legacy
grant remains user-owned. Generated Atlas-ACI tool identifiers stay hyphenated;
Docker arguments use the invoking UID:GID and preserve spaced paths and
identity mounts.

When Codex is active, drift comparison (`mcp verify` and `mcp sync`) and repair
require Python 3.11+ with the standard-library `tomllib` parser.

<!-- IDG provenance: V4-03 maker/reviewer handoffs and campaigns/gauge/receipts/V4-03.md. -->

> **Note:** `eidolons sync` (the top-level Eidolon sync command) does **not**
> call `eidolons mcp sync` automatically (NG3). MCP install is always
> explicit.

### OCI session containers

Every local MCP host (Claude Code, Codex, Cursor, OpenCode) speaks MCP over
`stdio`, which means one server process per client connection. Previously,
each connection ran `docker run --rm -i ...` directly. So every session,
every Codex sub-agent thread, every nested `claude -p`, and every reconnect got
its own anonymous container, with a random Docker name and its own resource
ceiling.

Host configs now route each OCI MCP through the session launcher
`cli/src/mcp_launch.sh`:

```json
"atlas-aci": {
  "command": "/home/me/.eidolons/nexus/cli/src/mcp_launch.sh",
  "args": ["atlas-aci", "--keepalive", "shell", "--",
           "run", "--cpus", "1.00", "--memory", "1g", "...", "ghcr.io/rynaro/atlas-aci@sha256:...", "serve", "..."]
}
```

Everything after `--` is the unchanged `docker run` argv. The launcher:

1. **Finds the owning session.** It walks the process-parent chain to the
   nearest host agent (`claude`, `codex`, `cursor`, `opencode`, `copilot`, …),
   then keeps walking to the *topmost* ancestor of that same host kind. A
   nested `claude -p` sub-agent therefore resolves to its parent session. A
   Claude Code session started from Cursor's terminal still resolves to
   Claude, not Cursor. If no host is found, the direct MCP client is the
   owner.
2. **Names the container deterministically**:
   `eidolons-<project>-<mcp>-<host>-<pid>`, for example
   `eidolons-myapp-crystalium-claude-48213`. It is labelled `eidolons.scope=session`,
   `eidolons.session.*`, `eidolons.mcp` and `eidolons.spec` (a hash of the argv).
3. **Starts it once per session**, under a lock, with the same mounts, user,
   environment and resource flags, plus a keepalive PID 1 (catalogue
   `runtime.keepalive`): a `/bin/sh` sleep loop for images that ship a shell
   (`atlas-aci`, `crystalium`), or the idle serve command for distroless images
   (`tonberry`, `atomos`).
4. **Attaches every client** with `docker exec -i`. The main session and all of
   its sub-agents run their MCP server processes inside that one container, so
   one cgroup ceiling bounds the whole session.
5. **Cleans up.** One detached watcher per session removes the session's
   containers when the owning process exits. Each new session also sweeps
   containers whose owner is gone (crash, `SIGKILL`, reboot), and
   `eidolons mcp reap` applies the same rule.

A container whose spec changed (new digest, new limits) is replaced the next
time a client of that session attaches. Restart host sessions after
`eidolons mcp upgrade` or a profile change. Any failure on the launcher path
falls back to the legacy per-client `docker run`, so an MCP keeps serving.

`eidolons mcp ps` shows the containers grouped by owning session:

```text
SESSION       STATE  PROJECT  MCP         CONTAINER                               MEM USAGE / LIMIT  CPU    PIDS  UP
claude-48213  live   myapp    atlas-aci   eidolons-myapp-atlas-aci-claude-48213   81MiB / 1GiB       0.00%  4     2 hours ago
claude-48213  live   myapp    crystalium  eidolons-myapp-crystalium-claude-48213  412MiB / 2GiB      0.10%  19    2 hours ago
codex-51007   live   myapp    tonberry    eidolons-myapp-tonberry-codex-51007     18MiB / 256MiB     0.00%  13    5 minutes ago
```

To opt out (legacy anonymous container per connection), set
`mcp_runtime.container_scope: client` and run
`eidolons mcp sync --repair-wiring`. Setting `EIDOLONS_MCP_CONTAINER_SCOPE=client`
in the host's environment does the same at runtime without re-rendering.

The `atlas-aci` reindex hook (`harness.atlas_sync`) runs its one-per-project
indexer as `eidolons-<project>-atlas-aci-sync`, under the same resource flags as
the `atlas-aci` server.

### OCI resource profiles

Every OCI MCP container is bounded by default:

```yaml
# eidolons.yaml
mcp_runtime:
  resource_profile: standard   # default; minimal | standard | full | unlimited
  container_scope: session     # default; client = legacy per-connection containers

mcps:
  - name: atlas-aci
    version: "^3.0.0"
  - name: crystalium
    version: "^2.2.0"
    resource_profile: full  # per-MCP override
```

The per-MCP override wins, then the project default, then `standard`.
`unlimited` is an explicit opt-out. Profiles do not install, remove or disable
MCPs.

| OCI MCP | `minimal` | `standard` (default) | `full` |
|---|---:|---:|---:|
| `atlas-aci` | 0.50 CPU / 512 MiB / 128 PIDs | 1.00 CPU / 1 GiB / 256 PIDs | 2.00 CPU / 2 GiB / 512 PIDs |
| `crystalium` | 0.50 CPU / 1 GiB / 128 PIDs | 1.00 CPU / 2 GiB / 256 PIDs | 2.00 CPU / 4 GiB / 512 PIDs |
| `tonberry` | 0.25 CPU / 128 MiB / 64 PIDs | 0.50 CPU / 256 MiB / 96 PIDs | 1.00 CPU / 512 MiB / 128 PIDs |
| `atomos` | 0.25 CPU / 128 MiB / 64 PIDs | 0.50 CPU / 256 MiB / 96 PIDs | 1.00 CPU / 512 MiB / 128 PIDs |

These are per-*session* ceilings: the main session and all of its sub-agents
share them. Measured idle footprint per attached server process is about
210 MiB for `crystalium`, 75 MiB for `atlas-aci` and 6 MiB for
`tonberry`/`atomos`. `standard` therefore leaves room for several concurrent
sub-agents per session. Raise a busy MCP with a per-MCP `full` override.

Each bounded profile renders Docker `--cpus`, `--memory`, `--memory-swap`, and
`--pids-limit` arguments. The memory and memory+swap ceilings are equal so the
container cannot consume a second memory allowance through swap. These are
ceilings, not reservations.

After changing a profile or scope, run `eidolons mcp sync --dry-run`, then
`eidolons mcp sync --repair-wiring` to apply it. Profile, scope and
catalogue-only ceiling changes are reported as drift even when the image
version is unchanged. Lock receipts written before session containers (no
`runtime`, or no `container_scope`) read as `unlimited`/`client`. In an existing
project, plain `eidolons mcp sync` therefore stops with a drift notice until you
run `eidolons mcp sync --repair-wiring` once. That command re-renders every host
config through the launcher and records the new receipt. Wiring is never
rewritten silently. Explicit repair updates the configured host wiring and the
resolved runtime receipt in `eidolons.mcp.lock`, and preserves user additions.

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
      - ".codex/config.toml"    # only present when codex ∈ hosts.wire
      - ".cursor/mcp.json"      # only present when cursor ∈ hosts.wire
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
      - ".mcp.json"
      - ".cursor/mcp.json"      # only present when cursor ∈ hosts.wire
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

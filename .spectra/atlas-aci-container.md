# SPECTRA — `eidolons atlas aci --container`

> Decision-ready specification for adding container-based deployment to the
> `eidolons atlas aci` integration. Spans three repositories: the
> **eidolons nexus** (`Rynaro/eidolons`), **ATLAS** (`Rynaro/ATLAS`), and
> **atlas-aci** (`Rynaro/atlas-aci`).
>
> SPECTRA cycle: **S**cope → **P**rinciples → **E**numerate → **C**ontract → **T**rials → **R**isks → **A**cceptance.
> Generated 2026-04-28. Status: **DECISIONS RESOLVED** — D1–D6 resolved; APIVR-Δ dispatched.
>
> Sidecars: [`atlas-aci-container.yaml`](./atlas-aci-container.yaml) (machine-readable spec),
> [`atlas-aci-container.state.json`](./atlas-aci-container.state.json) (SPECTRA state).

---

## Table of contents

- [P0 — Decisions resolved](#p0--decisions-resolved)
- [S — Scope](#s--scope)
- [P — Principles & invariants](#p--principles--invariants)
- [E — Enumerate: changes by repo](#e--enumerate-changes-by-repo)
- [C — Contracts](#c--contracts)
- [T — Trials & validation gates](#t--trials--validation-gates)
- [R — Risks](#r--risks)
- [A — Acceptance stories](#a--acceptance-stories)
- [Non-goals](#non-goals)
- [Open questions](#open-questions)
- [Provenance](#provenance)

---

## P0 — Decisions resolved

| ID | Decision | Resolution |
|----|----------|------------|
| **D1** | Container runtime support | **always-prompt** — always prompt user to pick docker or podman interactively; `--non-interactive` requires explicit `--runtime`; `--runtime` flag bypasses the prompt in any mode. |
| **D2** | Image distribution | **build-locally** — build from git URL (`<runtime> build <git-url>#<ref>:mcp-server`); no `--build` flag needed (build is implicit); no GHCR workflow ships in this release (F1 deferred). |
| **D3** | Image version pinning | **digest-sha256** — pin via local image ID captured from `<runtime> images --no-trunc --format '{{.ID}}' atlas-aci:<ATLAS_VERSION>` after build; canonical body references `atlas-aci@sha256:<local-id>`. |
| **D4** | MCP transport over container boundary | **run-rm-per-session** — `<runtime> run --rm -i` per MCP session; matches upstream Dockerfile STOPSIGNAL SIGINT + ENTRYPOINT atlas-aci design. |
| **D5** | Volume layout for state | **writable-index-readonly-serve** — writable bind-mount for the one-time `index` invocation; read-only bind-mount for `serve`. |
| **D6** | Memex persistence | **bind-mount-repo** — bind-mount `${PWD}/.atlas/memex` to `/memex` in the container; parity with non-container path. |

---

## S — Scope

### What `--container` is

`eidolons atlas aci --container` is a **second installation mode** for the
existing aci wiring. It produces the same end-state (`atlas-aci` MCP server
reachable from every detected MCP-capable host: `claude-code`, `cursor`,
`copilot`, `codex`) but without requiring `uv`, Python 3.11+, or
`atlas-aci` on the user's `PATH`. The only new prereq becomes a container
runtime.

### What changes for the user

| Aspect | Today (`eidolons atlas aci`) | New (`eidolons atlas aci --container`) |
|--------|-------------------------------|----------------------------------------|
| Prereqs | `uv`, `rg`, `python3≥3.11`, `atlas-aci` (uv tool installed) | `docker` *or* `podman` (per D1) + `git` (for build context) |
| `.mcp.json` `command` | `"atlas-aci"` | `"docker"` (or `"podman"`) |
| `.mcp.json` `args` | `["serve", "--repo", "${workspaceFolder}", ...]` | `["run", "--rm", "-i", "--read-only", "-v", "${workspaceFolder}:/repo:ro", "-v", "${workspaceFolder}/.atlas/memex:/memex", "atlas-aci@sha256:<LOCAL_DIGEST>", "serve", "--repo", "/repo", "--memex-root", "/memex"]` |
| Where index runs | `atlas-aci index --repo "$PWD"` (host) | `<runtime> run --rm -v "$PWD":/repo atlas-aci@sha256:<LOCAL_DIGEST> index --repo /repo --langs ...` |
| Where `.atlas/` lives | `<repo>/.atlas/` (host) | `<repo>/.atlas/` (host bind-mount; identical) |
| `.gitignore` entry | `.atlas/` | `.atlas/` (unchanged) |

### What does **not** change

- The set of supported hosts (`claude-code`, `cursor`, `copilot`, `codex`).
- The set of MCP config files written (`.mcp.json`, `.cursor/mcp.json`, `.github/agents/*.agent.md`, `.codex/config.toml`).
- The marker-bounded / object-key / awk-slice idempotency contracts.
- ATLAS's own `install.sh` wiring (the new mode is a `commands/aci.sh` flag, not a new installer).
- The four-layer model (EIIS → Eidolon repos → nexus → consumer project).

### Modes are **mutually exclusive per project**

A single project cannot run both modes simultaneously against the same
host. Re-running `eidolons atlas aci --container` overwrites the existing
entry; re-running `eidolons atlas aci` (uv mode) likewise overwrites.
Idempotency is preserved within a mode, not across modes; switching is
a deliberate user action.

---

## P — Principles & invariants

### From CLAUDE.md (nexus)

| ID | Principle | Where it shows up |
|----|-----------|-------------------|
| P-IDEM | Idempotency | Same `jq merge` / `yq merge` / `awk slice` primitives; new payload (command/args) is what's merged |
| P-NOEVAL | No code execution from `eidolons.yaml` | Unchanged — `--container` is a flag |
| P-CWDONLY | Per-Eidolon `install.sh` writes only to cwd | Container mode: local builds go to Docker daemon (system-wide image store); no writes to repo |
| P-BASH32 | Bash 3.2 compatibility | New `commands/aci.sh` code must comply: no `declare -A`, no `${var,,}`/`${var^^}`, no `readarray`/`mapfile`, no `&>>` |
| P-STDERR | All log output to stderr | New container-runtime probes and build progress must route to stderr |

### From the existing `commands/aci.sh` (ATLAS v1.0.6)

| ID | Principle | Notes |
|----|-----------|-------|
| P-WRITE-BOUNDARY | Never write outside `$PWD` | Container mode does not change this |
| P-IDEM-PER-FILE | Per-file idempotency model | Container mode preserves all four primitives |
| P-DRYRUN | Stdout empty on success; dry-run emits action verbs | Container mode adds `BUILD` and `PROMPT` action verbs |
| P-FAIL-CLOSED | TOML/YAML rewrite refuses deviant body | Extended to accept two canonicals (uv + container); refuses only when neither matches |

### From `atlas-aci/Dockerfile` (upstream)

| ID | Principle |
|----|-----------|
| P-RDONLY-MOUNT | `-v "$PWD":/repo:ro` + `--read-only` for serve |
| P-INDEX-WRITABLE | Separate writable-mount `docker run` for one-time index |
| P-UID-10001 | Runtime image runs as `atlas:10001`; R3 applies on Linux |
| P-STOPSIGNAL | `STOPSIGNAL SIGINT` — no action required |

---

## E — Enumerate: changes by repo

### E.1 — `atlas-aci` (upstream)

**Net change: zero** (D2 = build-locally). The Dockerfile already exists and
is production-quality. GHCR publish workflow deferred to F1. `INTEGRATION.md`
mention optional and deferred.

### E.2 — `Rynaro/ATLAS`

| File | Change |
|------|--------|
| `commands/aci.sh` | New `--container` flag; `--runtime {docker\|podman}` flag; container-aware prereqs; `build_image` + `run_index_container` functions; second canonical body per host; exit codes 7/8/9 |
| `install.sh` | `EIDOLON_VERSION` 1.0.6 → 1.1.0 |
| `agent.md` / `ATLAS.md` | Mention `--container` in smoke-test snippet (optional) |
| `tests/aci.bats` | New cases for `--container` flags, idempotency, mode-switch, exit codes |

Version bump: **1.0.6 → 1.1.0** (new prereq class — minor bump).

### E.3 — `Rynaro/eidolons` (nexus)

| File | Change | Required? |
|------|--------|-----------|
| `roster/index.yaml` | Bump ATLAS `versions.latest` and `versions.pins.stable` to `1.1.0` | Yes (after ATLAS 1.1.0 tag) |
| `CHANGELOG.md` | Entry under `[Unreleased] → Added` | Yes |
| `docs/specs/atlas-aci-container/` | Short README referencing this spec | Done |
| `cli/src/doctor.sh` | Container-runtime probe | Nice-to-have; deferred |
| `.github/workflows/roster-health.yml` | No change — ATLAS row already exists | No |

**The dispatcher (`cli/src/dispatch_eidolon.sh`) requires no change** — it
passes all args through verbatim; `--container` is just another arg.

---

## C — Contracts

### C.1 — Flag surface

```text
eidolons atlas aci [OPTIONS]

New options (this spec):
  --container            Install the container-runtime variant.
  --runtime RT           Force container runtime: docker | podman.
                         In --non-interactive mode, --runtime is required
                         when --container is used (exit 9 otherwise).

New exit codes:
  7  container runtime not on PATH (--container only)
  8  image build failed (--container only)
  9  --non-interactive without --runtime (--container only)
```

### C.2 — Dry-run action verbs

Added alongside existing `CREATE | MODIFY | REMOVE | INDEX`:

```text
BUILD <image>       # before <runtime> build (D2 = build-locally)
PROMPT runtime      # before interactive runtime selection (D1 = always-prompt)
```

### C.3 — Canonical body shapes

All shapes use `<RUNTIME>` (substituted at install time) and `atlas-aci@sha256:<LOCAL_DIGEST>` (captured after build).

#### `.mcp.json` and `.cursor/mcp.json` — serve

```json
{
  "mcpServers": {
    "atlas-aci": {
      "command": "<RUNTIME>",
      "args": [
        "run", "--rm", "-i", "--read-only",
        "-v", "${workspaceFolder}:/repo:ro",
        "-v", "${workspaceFolder}/.atlas/memex:/memex",
        "atlas-aci@sha256:<LOCAL_DIGEST>",
        "serve", "--repo", "/repo", "--memex-root", "/memex"
      ]
    }
  }
}
```

#### `.codex/config.toml` — serve

```toml
[mcp_servers.atlas-aci]
command = "<RUNTIME>"
args = [
  "run", "--rm", "-i", "--read-only",
  "-v", "${workspaceFolder}:/repo:ro",
  "-v", "${workspaceFolder}/.atlas/memex:/memex",
  "atlas-aci@sha256:<LOCAL_DIGEST>",
  "serve", "--repo", "/repo", "--memex-root", "/memex"
]
```

#### Index invocation (one-shot, install only)

```bash
<RUNTIME> run --rm \
    -v "${PWD}:/repo" \
    "atlas-aci@sha256:<LOCAL_DIGEST>" \
    index --repo /repo --langs ruby,python,javascript,typescript
```

Skipped if `./.atlas/manifest.yaml` already exists.

#### Build invocation (when image absent)

```bash
<RUNTIME> build -t "atlas-aci:<ATLAS_VERSION>" \
    "https://github.com/Rynaro/atlas-aci.git#<ATLAS_ACI_REF>:mcp-server"
```

After build: capture local digest via
`<RUNTIME> images --no-trunc --format '{{.ID}}' atlas-aci:<ATLAS_VERSION>`.

### C.4 — Prereq matrix

| Prereq | uv mode | container mode |
|--------|---------|----------------|
| `awk`, `jq`, `yq` | required | required |
| `uv`, `rg`, `python3≥3.11`, `atlas-aci` | required | **not required** |
| `docker` or `podman` | not required | **required** |
| `git` | not required | **required** (build context fetch) |

### C.5 — Mode-switch contract

Re-running either mode on a project using the other mode **overwrites**
the existing entry silently. The fail-closed comparator triggers only
when the existing body matches **neither** canonical form.

---

## T — Trials & validation gates

### T.1 — Nexus gates (this repo)

- **G0** `bats cli/tests/` green
- **G1** shellcheck clean
- **G2** `jq empty schemas/*.json && yq eval '.' roster/index.yaml`
- **G3** bash 3.2 compat (n/a — no new shell code in nexus)
- **G4** idempotency (second install run identical)

### T.2 — ATLAS gates

- **G5** `--container --dry-run` emits canonical body byte-for-byte
- **G6** two consecutive `--container` installs → byte-identical `.mcp.json`
- **G7** uv → container mode-switch overwrites once, then idempotent
- **G8** `--container --remove` removes only `mcpServers.atlas-aci`, peers preserved
- **G9** missing docker AND podman → exit 7
- **G10** hand-edited TOML body → fail-closed warn + refuse
- **G11** uv canonical body + `--container` invoked → overwritten cleanly
- **G17** `--container --non-interactive` without `--runtime` → exit 9
- **G18** `--container` against unchanged image → no rebuild, no host writes
- **G19** `ATLAS_ACI_REF` bump → rebuild → new digest → host configs MODIFY

### T.3 — atlas-aci gates (deferred to F1)

G12, G13, G14 require GHCR publish workflow — deferred.

### T.4 — Manual gates

- **G15** macOS + Docker Desktop, no uv/python: end-to-end happy path
- **G16** Linux + rootless podman: works, `.atlas/` ownership clean

---

## R — Risks

| ID | Title | L | I | Mitigation |
|----|-------|---|---|------------|
| R1 | Stdio MCP over container boundary | M | H | Manual G15+G16; document cold-start; escalate to D4(b) only on evidence |
| R2 | Two canonical bodies confuse fail-closed comparator | H | M | Comparator accepts list of canonicals; refuses only when neither matches |
| R3 | Bind-mount UID collision on Linux rootless | M | M | Test `--user` passthrough; document cleanup; defer to F3 |
| R4 | First-run build blocks on slow networks | H | L | Emit BUILD verb up-front; print build context URL |
| R5 | GHCR image not yet published | H | H | **Resolved by D2 = build-locally**; GHCR deferred to F1 |
| R6 | Bash 3.2 regression | L | M | G3 enforces; mirror existing aci.sh idioms |
| R7 | Image-digest churn on every atlas-aci release | H | L | Refresh ATLAS_ACI_REF on every ATLAS release per §6 R4 discipline |
| R8 | `.atlas/memex` created with wrong owner by daemon | L | L | `mkdir -p .atlas/memex` before first `docker run` |
| R9 | First container build is slow (multi-minute) | H | M | Emit BUILD verb up-front; F1 (GHCR pull) eliminates this |
| R10 | `<runtime> build` from git URL requires network | M | M | Document in `--container --help`; exit 8 on build failure |

---

## A — Acceptance stories

### A.1 — Container-mode install on macOS + Docker Desktop

**GIVEN** a fresh consumer project with ATLAS installed, Claude Code wired,
only `docker` on PATH (no `uv`, no `atlas-aci`, no Python ≥3.11), `.atlas/`
absent.
**WHEN** `eidolons atlas aci --container` runs.
**THEN** runtime prompt appears (D1); user selects docker; image builds from
git URL; `.atlas/` created inside container; `.mcp.json` has container
canonical body; exit 0; second run is byte-identical (G6).

### A.2 — Mode switch: uv → container

**GIVEN** project has `command: "atlas-aci"` in `.mcp.json`.
**WHEN** `eidolons atlas aci --container` runs.
**THEN** entry overwritten with container canonical body; `.atlas/` not
rebuilt; exit 0. (G7, G11)

### A.3 — Dry-run with no side effects

**GIVEN** project has never run aci.
**WHEN** `eidolons atlas aci --container --dry-run`.
**THEN** stdout: `PROMPT runtime`, `BUILD atlas-aci:<ver>`, `CREATE .gitignore`,
`INDEX .atlas/`, `CREATE .mcp.json`; no files modified; no `<runtime>` invoked;
exit 0. (G5)

### A.4 — Missing runtime exits 7

**GIVEN** neither `docker` nor `podman` on PATH.
**WHEN** `eidolons atlas aci --container`.
**THEN** stderr: prereq missing message with install links; stdout empty; exit 7;
no host config files touched. (G9)

### A.5 — Codex TOML fail-closed on hand-edit

**GIVEN** `.codex/config.toml` has a hand-edited body (neither canonical form).
**WHEN** `eidolons atlas aci --container`.
**THEN** stderr: fail-closed warning; TOML file unchanged; other hosts processed
normally; exit 0. (G10)

### A.6 — Container `--remove` is idempotent and host-bounded

**GIVEN** container mode installed.
**WHEN** `eidolons atlas aci --remove`.
**THEN** all host configs have `mcpServers.atlas-aci` / `[mcp_servers.atlas-aci]`
removed; `.atlas/` not deleted; local image not removed; re-running is a no-op. (G8)

### A.7 — Local build default path

**GIVEN** `docker` on PATH; image `atlas-aci:<ATLAS_VERSION>` absent.
**WHEN** `eidolons atlas aci --container --runtime docker`.
**THEN** `docker build` runs from git URL; image tagged locally; digest captured;
canonical body emits `atlas-aci@sha256:<local-digest>`; install completes. (G18, G19)

### A.8 — Always-prompt respects `--runtime`

**GIVEN** both `docker` and `podman` on PATH.
**WHEN** `eidolons atlas aci --container --runtime podman`.
**THEN** no prompt; `podman` used; canonical body emits `command: "podman"`. (G17)

---

## Non-goals

1. Replacing the `uv` mode (both ship side-by-side).
2. Package-manager publishing of `eidolons`.
3. User-level Claude Desktop config (deferred per `commands/aci.sh:103-104`).
4. `docker compose` orchestration.
5. Kubernetes / sidecar / long-lived daemon mode.
6. Auto-managing image lifecycle on `--remove`.
7. Cross-repo MCP routing.
8. TLS / network MCP transport.
9. Non-Docker/non-Podman runtimes (containerd, nerdctl, runC).
10. Methodology content changes in the nexus.

---

## Open questions

| ID | Question | Resolution path |
|----|----------|-----------------|
| Q1 | Does Claude Code's `mcpServers` honour `${workspaceFolder}` substitution when `command: "docker"`? | Test in G15 |
| Q2 | Does Cursor's `~/.cursor/mcp.json` accept the same substitution? | G15 (separately) |
| Q3 | Does Codex's TOML loader support `${workspaceFolder}`? | Inspect Codex docs / atlas-aci `hosts/` |
| Q4 | Does Copilot's `tools.mcp_servers[].command` tolerate 16+ entry args? | Verify in G15 |
| Q5 | Should digest pin be exposed as env var for self-hosted GHCR mirrors? | Defer to F4 |
| Q6 | Does `eiis_check` need a container-runtime probe? | No — runtime is `aci.sh`'s concern, not EIIS |

---

## Provenance

- **Existing aci command:** `Rynaro/ATLAS` `commands/aci.sh` (v1.0.6)
- **ATLAS installer:** `Rynaro/ATLAS` `install.sh`
- **atlas-aci runtime image:** `Rynaro/atlas-aci` `mcp-server/Dockerfile`
- **Nexus dispatcher:** `cli/src/dispatch_eidolon.sh` (verified: `--container` requires no nexus-side wiring change)
- **Roster entry:** `roster/index.yaml` `eidolons[0]` (atlas, 1.0.6 → 1.1.0)
- **Recent PRs:** #20 (codex MCP host, `259388d`), #26 (ATLAS v1.0.6, `cd35e7e`)

*SPECTRA v4.2.10 — generated 2026-04-28 — status: DECISIONS RESOLVED; APIVR-Δ dispatched.*

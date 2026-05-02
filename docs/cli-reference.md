# `eidolons` CLI Reference

Every command, every flag, in one place.

---

## Global

```
eidolons <command> [options]
```

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `EIDOLONS_HOME` | `~/.eidolons` | Where nexus + cache live |
| `EIDOLONS_REPO` | `https://github.com/Rynaro/eidolons` | Nexus repo (for bootstrap) |
| `EIDOLONS_REF` | `main` | Nexus ref (for bootstrap) |
| `EIDOLONS_BIN_DIR` | `~/.local/bin` | Where the CLI is symlinked |
| `EIDOLONS_INTEGRITY_ENFORCEMENT` | roster setting | Override release integrity mode (`warn` or `strict`) |

### Files

| Path | Scope | Purpose |
|------|-------|---------|
| `~/.eidolons/nexus/` | user | Cloned nexus |
| `~/.eidolons/cache/` | user | Cloned Eidolon repos (per name + version) |
| `./eidolons.yaml` | project | Your team manifest |
| `./eidolons.lock` | project | Resolved versions |
| `./.eidolons/<n>/` | project | Installed Eidolon files |

---

## `eidolons init`

Initialize a project. Detects greenfield vs brownfield.

```
eidolons init [--preset NAME | --members LIST] [--hosts LIST] [--force] [--non-interactive]
```

| Flag | Purpose |
|------|---------|
| `--preset NAME` | Use a preset (minimal, pipeline, full, ...). See `eidolons list --presets`. |
| `--members LIST` | Comma-separated Eidolon names. Mutually exclusive with `--preset`. |
| `--hosts LIST` | `claude-code,copilot,cursor,opencode,codex,all`. Default: `auto`. |
| `--force` | Overwrite existing `eidolons.yaml`. |
| `--non-interactive` | Fail on any prompt. Requires `--preset` or `--members`. |

**Output**: `eidolons.yaml`, `eidolons.lock`, plus per-Eidolon installs.

---

## `eidolons add`

Add one or more members to an existing project.

```
eidolons add <name>... [--version SPEC] [--non-interactive]
```

Calls `sync` after writing to `eidolons.yaml`.

---

## `eidolons remove` (v1.1, stubbed in v1.0)

Remove a member cleanly: manifest entry, `.eidolons/<n>/`, bounded sections in dispatch files, and lock entry.

---

## `eidolons sync`

Reconcile installed state to `eidolons.yaml`. Idempotent.

```
eidolons sync [--non-interactive] [--dry-run]
```

- Fetches each member's repo (cached in `~/.eidolons/cache/`).
- Runs each per-Eidolon `install.sh` with the right `--hosts` and `--target`.
- Aggregates per-Eidolon manifests into `eidolons.lock`.

---

## `eidolons list`

Show Eidolons.

```
eidolons list                 # auto: installed if in a project, available otherwise
eidolons list --available     # everything in the nexus roster
eidolons list --installed     # only what's in this project
eidolons list --presets       # named presets
eidolons list --json          # JSON
```

---

## `eidolons roster`

Detailed roster inspection.

```
eidolons roster                        # full team summary
eidolons roster atlas                  # single member detail
eidolons roster atlas --methodology    # just methodology
eidolons roster atlas --handoffs       # handoff contracts
eidolons roster atlas --references     # research references
eidolons roster atlas --json           # raw JSON
```

---

## `eidolons doctor`

Health check: manifest/lock consistency, per-member installs, host dispatch
wiring, release-integrity status surfaced from `eidolons.lock`, and (when
`.mcp.json` contains an `atlas-aci` entry) ghcr.io registry reachability.

```
eidolons doctor            # report
eidolons doctor --fix      # report + attempt auto-repair via sync
```

The "Release integrity" section is read-only and derives entirely from the
`verification` field of each `eidolons.lock` member. To re-check against the
roster (commit/tree/archive checksum, manifest re-hash) run `eidolons verify`.

**ghcr.io reachability probe (Check 7):** when `.mcp.json` contains an
`atlas-aci` entry with a `ghcr.io/rynaro/atlas-aci@sha256:<digest>` arg, doctor
performs an anonymous-token HEAD against the ghcr.io v2 manifests endpoint:

- `pass: atlas-aci image reachable on ghcr.io` — digest is publicly reachable.
- `warn: atlas-aci image not reachable (offline? or pinned digest yanked? — try 'eidolons mcp atlas-aci pull --build-locally')` — network error or 404.

This probe is **non-fatal**: it does not increment the error count or change
the doctor exit code. It is silently skipped when `.mcp.json` is absent, when
there is no `atlas-aci` entry, or when `curl` is not on PATH.

---

## `eidolons verify`

Read-only release integrity verification for installed members.

```
eidolons verify
eidolons verify atlas spectra
```

For releases with roster metadata, mismatched commits, Git trees, archive
checksums, or installed manifest checksums fail the command. Members without
release metadata warn in compatibility mode.

---

## `eidolons upgrade`

Surface and apply upgrades for the nexus and/or installed members.

```
eidolons upgrade [TARGET] [OPTIONS]                 # default: project scope (members)
eidolons upgrade --check [SCOPE] [TARGET] [--json]  # read-only diff
eidolons upgrade --system  [OPTIONS]                # nexus only
eidolons upgrade --project [TARGET] [OPTIONS]       # explicit project scope
eidolons upgrade --all     [OPTIONS]                # nexus then members
```

| Flag / arg | Purpose |
|------------|---------|
| `TARGET` | Member name or comma-separated list (mutually exclusive with `--system` / `--all`). |
| `--check` | Read-only diff: prints nexus and member upgrade availability, no disk writes. Pair with `--system` or `--project` to narrow the report. |
| `--system` | Upgrade only the nexus at `~/.eidolons/nexus` (`git fetch + reset --hard`). |
| `--project` | Operate on cwd members. Equivalent to bare `eidolons upgrade` when given alone; useful for explicit symmetry with `--system` and for narrowing `--check`. |
| `--all` | Upgrade nexus first (must succeed), then members. Equivalent to `--system --project`. |
| `--json` | Combine with `--check` for machine-readable output (banner stays on stderr). |
| `--yes`, `-y` | Skip the confirmation prompt before mutating. |
| `--non-interactive` | Fail on prompts. Mutating runs require `--yes`. |
| `--dry-run` | Print plan without fetching or invoking any per-Eidolon `install.sh`. |

**Pin policy:** member constraints in `eidolons.yaml` are respected. A roster `versions.latest` that exceeds the constraint is reported as `pinned-out` and skipped — `upgrade` never auto-edits constraints.

**Idempotency:** a second run with no roster change reports "all members up-to-date" and leaves `eidolons.lock` mtime untouched.

**Network failure:** `--check` degrades gracefully (10s timeout on the nexus probe; member rows are purely local). Mutating runs fail per-member; the final exit code is 1 if any member upgrade failed. `eidolons upgrade --system` exits 1 if the nexus fetch fails (state is left untouched).

**Statuses (`--check`):** `up-to-date`, `upgrade available`, `pinned-out`, `not-installed`.

---

## Per-Eidolon subcommands

```
eidolons <eidolon> <subcommand> [args...]
eidolons <eidolon> --help
```

Runs a subcommand shipped by an installed Eidolon. The nexus CLI resolves:

1. `.eidolons/<eidolon>/commands/<subcommand>.sh` in the current project (preferred)
2. `~/.eidolons/cache/<eidolon>@<version>/commands/<subcommand>.sh` (fallback)

The dispatcher passes all remaining args to the script and executes it with `cwd` set to the project root — same convention as `sync` and `doctor`.

### Contract for Eidolon authors

To expose `eidolons <eidolon> <sub>`, ship a bash script at `commands/<sub>.sh` in the Eidolon's source repo and have the per-Eidolon `install.sh` copy `commands/*.sh` into `<TARGET>/commands/`. The script should:

- Read `cwd` as the consumer project root (don't `cd` elsewhere unless deliberate).
- Source its own helpers / execute its own logic; the nexus doesn't inject anything.
- Exit non-zero on failure; output clear error messages to stderr.

The nexus dispatcher adds no contract beyond "be a bash script that does what you promise".

### Example

```bash
eidolons spectra --help              # list SPECTRA's subcommands
eidolons spectra fit                 # run SPECTRA's project-fit tool
eidolons spectra fit /path/to/other  # pass args through
```

### `eidolons atlas aci` (opt-in, MCP wiring)

See [`atlas-aci.md`](atlas-aci.md) for the `atlas-aci` MCP integration
command: prereqs, host coverage, exit codes, and the idempotency
contract. The command is opt-in and never invoked by `init` / `sync`.

The `--host` flag restricts wiring to a single host. Allowed values:
`claude-code`, `cursor`, `copilot`, `codex`. Omit `--host` to target
all MCP-capable hosts detected in the project.

**Bootstrap pre-flight:** `eidolons mcp atlas-aci` (scaffold) aborts with an
actionable error if `DEFAULT_IMAGE_DIGEST` is still the all-zeros placeholder
value. This prevents misconfigured `.mcp.json` files from reaching users before
the first real ghcr.io release has been pinned by a maintainer.

#### `eidolons mcp atlas-aci pull` — image fetch flags

```
eidolons mcp atlas-aci pull [OPTIONS]
```

| Flag | Default | Purpose |
|---|---|---|
| `--build-locally` | off | Build the image locally from the upstream git source instead of pulling from ghcr.io. Use in air-gap, restricted-network, or registry-outage scenarios. |
| `--git-ref REF` | `main` | Git ref (branch, tag, or SHA) to build from when `--build-locally` is used. Paired with `--build-locally`; no effect otherwise. |
| `--image-digest DIGEST` | `DEFAULT_IMAGE_DIGEST` | Override the pinned digest. Accepts the bare `sha256:<hex>` form. Bypasses the bootstrap pre-flight check (use to adopt a locally-built tag or a different registry digest). |

**`--build-locally` trade-off:** the locally-built image is tagged
`ghcr.io/rynaro/atlas-aci:locally-built-<timestamp>` and cannot match the
upstream digest pin. `docker run ghcr.io/rynaro/atlas-aci@sha256:<digest>`
will not resolve to it — pass `--image-digest` with the local tag to use it.
See [`atlas-aci.md` §Image distribution](atlas-aci.md#image-distribution) for the
full runbook.

**Bootstrap pre-flight on pull:** `eidolons mcp atlas-aci pull` also refuses to
run when `DEFAULT_IMAGE_DIGEST` is the all-zeros placeholder unless `--image-digest`
is explicitly supplied (which bypasses the guard). The error message names the
two recovery options: wait for the first ghcr.io release, or use `--build-locally`.

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Operation failed (details printed) |
| `2` | Invalid arguments |
| `3` | Existing install conflicts with requested action (use `--force`) |
| `4` | Token budget / conformance violation (from per-Eidolon install) |

---

## Composition with other tools

The CLI is designed to compose:

```bash
# Provision in CI
eidolons init --preset pipeline --non-interactive

# Verify in CI
eidolons doctor || exit 1

# Pin explicitly in a Dockerfile
RUN curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/v1.0.0/cli/install.sh | bash
RUN eidolons init --preset pipeline --non-interactive
```

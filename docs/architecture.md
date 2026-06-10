# Eidolons Architecture

> How the nexus, EIIS, individual Eidolon repos, and consumer projects compose.

---

## The three layers

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 1 — STANDARD (Rynaro/eidolons-eiis)                           │
│                                                                      │
│   Defines what every Eidolon repo must contain and expose.          │
│   - install.sh CLI contract                                         │
│   - install.manifest.json schema                                    │
│   - Required file layout                                            │
│   - Host wiring requirements                                        │
│                                                                      │
│   Vendor-neutral. Versioned independently. Does not ship agents.    │
└─────────────────────────────────────────────────────────────────────┘
         ▲
         │ each Eidolon repo declares conformance (EIIS_VERSION file)
         │
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 2 — EIDOLONS (5 × individual repos)                           │
│                                                                      │
│   Rynaro/ATLAS    Rynaro/SPECTRA   Rynaro/APIVR-Delta               │
│   Rynaro/IDG      Rynaro/FORGE     ...                              │
│                                                                      │
│   Each is:                                                          │
│   - EIIS-conformant                                                 │
│   - Independently installable via its own install.sh                │
│   - Independently versioned                                         │
│   - Self-contained (works without teammates)                        │
└─────────────────────────────────────────────────────────────────────┘
         ▲
         │ nexus registers each Eidolon in roster/index.yaml
         │
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 3 — NEXUS (this repo: Rynaro/eidolons)                        │
│                                                                      │
│   The team's home.                                                  │
│   - roster/index.yaml        — who's in the team, where they live   │
│   - cli/eidolons             — the command-line orchestrator        │
│   - methodology/             — composition rules, prime directives  │
│   - research/                — papers, evidence base                │
│                                                                      │
│   Depends on EIIS (Layer 1). Does not embed Eidolon code (Layer 2). │
└─────────────────────────────────────────────────────────────────────┘
         │
         │ CLI reads roster, fetches Eidolon repos, runs their install.sh
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 4 — CONSUMER PROJECT (your code)                              │
│                                                                      │
│   eidolons.yaml              — which members you want               │
│   eidolons.lock              — exact resolved versions              │
│   .eidolons/<member>/        — installed per Eidolon                │
│   AGENTS.md / CLAUDE.md / .cursor/ / .opencode/ / .codex/           │
└─────────────────────────────────────────────────────────────────────┘
```

**Why four layers.** Each has a single reason to change:

- **EIIS** changes when the install contract evolves.
- **Eidolon repos** change when a methodology evolves.
- **Nexus** changes when the team's composition or the CLI evolves.
- **Consumer project** changes when you add/remove/upgrade members.

A change in one layer doesn't force changes in the others — as long as the contract between layers (EIIS for 1↔2, roster schema for 2↔3, `eidolons.yaml` schema for 3↔4) stays stable.

---

## Install flow — step by step

What `eidolons init --preset pipeline` actually does in a brownfield project:

```
1. Read roster/index.yaml from $EIDOLONS_HOME/nexus/
   └─ Resolve "pipeline" preset → [atlas, spectra, apivr, idg]

2. Detect hosts in cwd
   └─ Finds: .github/, CLAUDE.md, .cursor/, AGENTS.md, .codex/
   └─ Hosts to wire: claude-code, copilot, codex, cursor
   └─ Note: AGENTS.md is co-owned by copilot AND codex; .codex/ is a
            definitive Codex-only signal that takes precedence.

3. Write eidolons.yaml with:
   - version: 1
   - hosts.wire: [claude-code, copilot, codex, cursor]
   - members: [atlas@^1.0.0, spectra@^4.2.0, apivr@^3.0.0, idg@^1.1.0]

4. For each member:
   a. Fetch repo to ~/.eidolons/cache/<n>@<version>/
      (depth-1 git clone, pinned to latest matching tag)
   b. EIIS sanity check (agent.md, install.sh, AGENTS.md exist)
   c. Run: bash <cache>/install.sh \
             --target ./.eidolons/<n> \
             --hosts claude-code,copilot,codex,cursor \
             --non-interactive \
             --force
   d. Each install.sh:
      - Copies methodology files into ./.eidolons/<n>/
      - Appends to root AGENTS.md (bounded by markers; co-owned by copilot/codex)
      - Appends to CLAUDE.md (pointer line)
      - Creates .cursor/rules/<n>.mdc if cursor is wired
      - Creates .codex/agents/<n>.md if codex is wired
        (YAML frontmatter: name, description; subagent dispatch file)
      - Emits ./.eidolons/<n>/install.manifest.json
   e. Nexus reads the manifest, records resolved version + commit SHA

5. Write eidolons.lock with resolved state

6. Print summary + next-step hints
```

**Critical property — idempotency.** Re-running `sync` after the initial install produces an identical result unless the roster or manifest changes. Each per-Eidolon `install.sh` must also be idempotent; this is enforced by EIIS.

**Critical property — composability.** Multiple Eidolons all writing to the same `AGENTS.md` must coexist. Each one appends a named section bounded by markers like `<!-- eidolon:atlas start -->` / `<!-- eidolon:atlas end -->` so the nexus (or `eidolons remove`) can find and remove its own section later.

---

## Update flow — maintainer to consumer

```
maintainer                       upstream Eidolon repo            this nexus                       consumer project
──────────                       ─────────────────────            ──────────                       ────────────────
$ eidolons release atlas 1.4.0   ──[gh workflow run             ──[gh workflow run               (waits)
                                    Release ATLAS]──>              Roster Intake                  
                                                                    after tag visible]──>          
                                  Release ATLAS workflow            Roster Intake workflow         
                                  ─ tags v1.4.0                     ─ verifies attestation         
                                  ─ signs attestation               ─ updates roster + CHANGELOG   
                                  ─ publishes GH release            ─ opens PR (auto-merge if not  
                                                                       first-shipped)              
                                                                    PR auto-merges once required   
                                                                    checks pass                    
                                                                                                   $ eidolons doctor
                                                                                                   → "Pending upgrades:
                                                                                                       atlas 1.3.0 → 1.4.0"
                                                                                                   $ eidolons upgrade atlas
                                                                                                   → applies the new pin.
```

A single command (`eidolons release`) drives the whole maintainer side; the consumer side runs `eidolons doctor` to discover pending bumps and `eidolons upgrade` to apply them. Auto-merge of routine roster bumps closes the loop without requiring a human PR review for every upstream patch release. First-shipped Eidolon transitions are held as DRAFT for explicit review (see [`docs/release-integrity.md`](release-integrity.md) § "Auto-merge of routine roster bumps").

The two `docker run`-style invocations on either side preserve layer separation: the maintainer's `eidolons release` only *dispatches* the upstream Eidolon's `release.yml`; it does not modify the upstream repo. The consumer's `eidolons upgrade` reads the roster and runs each Eidolon's own `install.sh`; the nexus never executes consumer-side code beyond the integrity gate.

---

## Why not a monorepo

Every Eidolon currently has its own public repo (atlas, SPECTRA, apivr, idg, forge). A monorepo would:

- ✗ Break existing `git subtree` installs that consumers already use for ATLAS
- ✗ Couple release cadence across five distinct products
- ✗ Inflate CI time (every commit triggers every Eidolon's test suite)
- ✗ Make external contribution harder (contributors have to clone everything)
- ✓ Simplify "install the whole team" slightly — but the CLI handles this already

The distributed model with a registry (`roster/index.yaml`) is strictly better for this team's structure.

---

## Why not a package manager (npm / pip / brew)

Three reasons:

1. **Package managers impose a runtime.** Requiring Node or Python just to install a bash-and-markdown agent is a bad trade. The `curl | bash` pattern keeps the dependency surface at `git + bash + jq`.
2. **Agent content isn't a "package" in the classical sense.** Each Eidolon is a composition of instructions, not a library. Semver applies at the methodology-version level, but the artifacts are mostly text.
3. **Future-proofing.** If we later decide to publish to a package manager, the CLI abstracts the fetch step — we swap the implementation of `fetch_eidolon()` and nothing downstream changes.

---

## Security model

Every layer has a narrow privilege:

| Layer | Reads | Writes | Network |
|-------|-------|--------|---------|
| EIIS | n/a | n/a | n/a |
| Eidolon repo | ✗ | ✗ | ✗ |
| Nexus CLI | Consumer cwd, `$EIDOLONS_HOME` | `$EIDOLONS_HOME`, cwd | Yes (git clone) |
| Per-Eidolon `install.sh` | Consumer cwd | Consumer cwd only | No |
| Installed Eidolon | Per-Eidolon declaration in roster | Per-Eidolon declaration | Per-Eidolon declaration |

**Explicit limits.** The CLI never executes code from a consumer project's `eidolons.yaml`. It reads, resolves, and delegates — `yaml → jq query → bash exec` with no evaluation. Eidolon repos are trusted at install time (they're on your roster); untrusted sources require a manual override.

**Per-Eidolon installer non-interactive contract.** Per-Eidolon installers invoked from `eidolons sync` MUST be non-interactive. Starting with v1.6.0, `eidolons sync` captures each installer's combined stdout+stderr in a tmpfile at default verbosity, which means the installer's TTY is effectively `/dev/null`-equivalent. Installers that read from `</dev/tty` or prompt for stdin input will hang silently. The roster's current six members are non-interactive; future Eidolons that need interactivity must coordinate via the `--non-interactive` flag conformance (EIIS §3 requires this). Under `--verbose`, stdout/stderr pass through directly, preserving TTY behaviour.

**MCP-server scaffolding is a nexus responsibility, not an Eidolon.** The
`eidolons mcp` store (`cli/src/mcp*.sh`, `roster/mcps.yaml`,
`eidolons.mcp.lock`) is a unified lifecycle manager for MCP servers. MCP
servers are **infrastructure that Eidolons consume**, not Eidolon peers. They
have no entry in `roster/index.yaml`, trigger no EIIS conformance check, and
are never installed by `eidolons init` or `eidolons sync` (NG3 — explicit
install only).

The catalogue (`roster/mcps.yaml`) is a sibling file to the Eidolon roster.
It lists two MCPs in v1.3: `atlas-aci` (kind `oci-image`) and `junction`
(kind `binary`). Each entry declares its `kind`, source descriptor, version
pins, and health probes. A per-project lockfile `eidolons.mcp.lock` records
the installed state and is committed to VCS alongside `eidolons.lock`.

**Driver protocol.** `mcp_install.sh` dispatches on `kind` to one of three
driver families defined in `cli/src/lib_mcp.sh`:

| Kind | Artefact | Driver functions |
|---|---|---|
| `oci-image` | Docker image | `mcp_driver_oci_image_{install,refresh,uninstall,version,health}` |
| `binary` | Compiled binary | `mcp_driver_binary_{install,refresh,uninstall,version,health}` |
| `script` | Shell script | (reserved; no v1.3 members) |

The `oci-image` driver wraps `cli/src/mcp_atlas_aci.sh` and
`cli/src/mcp_atlas_aci_pull.sh` without behaviour change. The `binary` driver
wraps `cli/src/harness.sh`'s install / up / verify / uninstall logic. Both
legacy command families (`eidolons mcp atlas-aci` and `eidolons harness <sub>`)
remain functional as deprecated dispatcher aliases through nexus v2.9.x.

`eidolons doctor`'s "MCP servers" section iterates `eidolons.mcp.lock` and
calls each MCP's health driver. A separate "MCP catalogue drift" section
surfaces MCPs that are behind `pins.stable`. See `docs/mcp.md` for the full
user-facing reference.

ATLAS's `commands/aci.sh` reuses the image when the pinned digest is already
loaded (skipping the `docker build`); the `index` `docker run` writes to a
writable bind mount, distinct from the `--read-only` `serve` invocation
rendered into `.mcp.json`.

---

## Memory substrate — CRYSTALIUM

CRYSTALIUM (`Rynaro/crystalium`, kind `oci-image`) is the shared-memory MCP for the Eidolon team. It is wired **allowlist/direct** — unlike junction (transport-only), `mcp__crystalium__*` tools are injected into every Eidolon's `tools:` allowlist. When installed, every Eidolon can recall prior context and commit mission outcomes without parent orchestration.

**Four layers (Crystal Lattice):**

| Layer | Purpose | Write access |
|-------|---------|-------------|
| **Episodic** | Raw mission notes, intermediate findings, tool artefacts | T0, T1, T3 (quarantined for T3) |
| **Semantic** | Promoted facts, project conventions, corroborated knowledge | T0, T1 only |
| **Procedural** | Verified skills; executed via `skill_invoke` sandbox | T0, T1 only |
| **Execution** | Plan checkpoints, replan branches, pipeline state | T0, T1 only |

**Bidirectional flow:** Eidolons read from all layers (recall) and write back in the same dispatch turn (commit/ingest). The write spine for hand-offs is `ingest(ecl_envelope)`, which derives tier from the ECL envelope's `from.eidolon` field and preserves provenance.

**Trust-tier gating:** T0 = host/operator (has `forget`, `force_promote`); T1 = the six Eidolons; T3 = tool-origin artefacts (episodic quarantine only). Operations that violate tier constraints return `reason_code: TIER_CEILING` and must be treated as terminal.

**Dream consolidation:** async episodic→semantic promotion triggered by `session_end` or an idle-poll (default 60s gap). Candidates are grouped by topic and must reach ≥ 2 corroborating independent sources before auto-promotion. Promoted entries inherit MIN-trust across the corroboration set. See `methodology/cortex/memory-protocol.md` for all knobs.

**Security:** crystalium's data dir is bind-mounted per project (`~/.crystalium/<project-slug>/`). Direct filesystem writes are forbidden; all access funnels through MCP tool calls enforced by the server. The server runs under `--cap-drop ALL --security-opt no-new-privileges`.

---

## Versioning

| Artifact | Versioning scheme | Breaking-change policy |
|----------|-------------------|-----------------------|
| EIIS | SemVer | Major bump requires migration guide |
| Each Eidolon methodology | Independent SemVer | Breaking change → methodology major bump |
| Each Eidolon repo | SemVer (git tags) | Tags map to registry `versions.latest` |
| `eidolons` CLI (nexus) | SemVer — see bump table below | CLI minor bump tolerates old rosters |
| `roster/index.yaml` | `registry_version` field | Breaking schema change → new registry version |
| `eidolons.yaml` | `version: N` field | Breaking schema change → bump version |

A consumer project pins nothing implicitly. Versions are pinned in `eidolons.yaml` (constraints) and `eidolons.lock` (resolved exact).

### Nexus CLI bump rules

| Bump | Triggers |
|------|---------|
| **MAJOR** | Removing or renaming a built-in CLI subcommand; breaking-change to `eidolons.yaml` or `eidolons.lock` schema (`version` field bump); breaking-change to `roster/index.yaml` shape (`registry_version` bump) when consumed by the CLI; raising minimum bash / git / jq / yq version; dropping a host wiring (claude-code / copilot / cursor / opencode / codex). |
| **MINOR** | Adding a new built-in subcommand or top-level flag; adding a new optional field to `roster/index.yaml` or schemas; adding a new host wiring; new methodology cortex layer; adding a new MCP scaffold (e.g. `eidolons mcp <new-server>`). |
| **PATCH** | Bug fix; doc-only change; CHANGELOG-only change; **roster bump for a shipped Eidolon** (the most frequent change in this repo); internal refactor with no surface change; CI workflow tweak. |

The initial managed release is `v1.0.0` (2026-05-04). The `EIDOLONS_VERSION` constant that was previously hardcoded in `cli/eidolons` is now read from `VERSION` at the nexus root with a `git describe → 0.0.0-dev` fallback.

Release integrity metadata lives beside each roster version under
`versions.releases.<version>`. When present, the CLI verifies the exact
`vX.Y.Z` tag, commit, Git tree, and SHA-256 target metadata before running an
Eidolon's installer. Missing metadata is warning-only while
`integrity.enforcement: warn`; the next enforcement bump can make it strict.
See [`release-integrity.md`](release-integrity.md).

The nexus itself has a parallel integrity block under `nexus.versions.releases.<version>`
in `roster/index.yaml`, consumed by `eidolons upgrade self`.

### Nexus self-upgrade

The nexus releases itself via `.github/workflows/release-nexus.yml`. Users update with
`eidolons upgrade self` instead of re-running the curl bootstrap.

The upgrade path is:

```
git ls-remote (latest tag)
  → clone to ~/.eidolons/nexus.new/
  → verify commit+tree+archive SHA-256 against roster/index.yaml nexus block
  → smoke test: bash nexus.new/cli/eidolons --version --quiet
  → mv nexus → nexus.prev  &&  mv nexus.new → nexus  (atomic rename)
```

The symlink at `~/.local/bin/eidolons` points at `~/.eidolons/nexus/cli/eidolons` and
needs no update — it resolves through the renamed directory. Rollback is a single
`eidolons upgrade self --rollback` that swaps `nexus.prev` back. Only one previous
version is retained.

---

## Harness Layer

The harness layer wires host-native hook surfaces to the routing kernel so every
prompt submitted inside a supported AI coding host is automatically enriched with
a routing artifact — with no changes to the developer's workflow.

**Kernel + adapters architecture:** `eidolons run` is the vendor-neutral kernel.
`cli/src/harness_hook.sh` is a thin adapter that wraps the routing artifact in the
host-dialect hook JSON. Adding a new host means writing a new shim and adapter
template; the kernel is unchanged.

**Per-host tier table (Phase 1 — T3 inject tier):**

| Host | Tier | Mechanism |
|---|---|---|
| claude-code | T3 | `UserPromptSubmit` + `SessionStart` hooks; `additionalContext` inject |
| codex | T3 | `hooks.json` sidecar (ASSUMPTION A1 — verify with `eidolons doctor`) |

**INJECT-only default:** In Phase 1, all hooks inject context only (`additionalContext`).
No `PreToolUse` blocking hooks. No exit code 2. The harness never interrupts a tool call.

**Fail-open invariant:** Shim scripts are designed to exit 0 with empty stdout on any error.
The host's context window is never corrupted by harness failure.

**Opt-in:** `eidolons sync` and `eidolons init` never invoke harness wiring. Only an
explicit `eidolons harness install` adds hooks. Once installed, `sync` refreshes shim
contents from the current template (never adds new wiring).

Full specification: `.spectra/harness-mechanization/spec.md`

---

## Related

- [`../README.md`](../README.md) — nexus front door
- [`getting-started.md`](getting-started.md) — install walkthrough
- [`cli-reference.md`](cli-reference.md) — every CLI command
- [`../methodology/composition.md`](../methodology/composition.md) — the pipeline, handoff contracts, partial-team deployment
- `Rynaro/eidolons-eiis` — the install standard (separate repo)

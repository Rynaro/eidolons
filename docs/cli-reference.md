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
| `EIDOLONS_REF` | `main` | Nexus ref for CLI self-pin (for bootstrap). Written to `.install_ref`; `eidolons upgrade self` updates this. |
| `EIDOLONS_ROSTER_REF` | `main` | Nexus ref for roster-refresh target (for bootstrap). Written to `.roster_ref`; `nexus_refresh` reads this. Change to pin a project to a specific roster branch or tag. |
| `EIDOLONS_BIN_DIR` | `~/.local/bin` | Where the CLI is symlinked |
| `EIDOLONS_INTEGRITY_ENFORCEMENT` | roster setting | Override release integrity mode (`warn` or `strict`) |
| `EIDOLONS_SKIP_REFRESH` | `0` | Set to `1` to disable auto-refresh of the nexus cache (offline-first / deterministic builds). |

### Files

| Path | Scope | Purpose |
|------|-------|---------|
| `~/.eidolons/nexus/` | user | Cloned nexus |
| `~/.eidolons/nexus/.install_ref` | user | CLI self-pin ref (written by `install.sh` and `upgrade self`). |
| `~/.eidolons/nexus/.roster_ref` | user | Roster-refresh target ref (written by `install.sh` only; `upgrade self` leaves this alone). Default: `main`. Installs predating v1.11.0 that lack this file are auto-healed by `nexus_refresh()` and `upgrade self`: the file is backfilled with `$EIDOLONS_ROSTER_REF` when set, otherwise `main`. As part of the backfill (v1.13.4), `nexus_ensure_roster_ref` also ensures `.roster_ref` and all other sidecar files (`.install_date`, `.install_ref`, `.install_commit`) are listed in `~/.eidolons/nexus/.gitignore` so they are not reported as untracked by `git status`. Without this heal, a freshly-backfilled `.roster_ref` caused `eidolons upgrade self`'s dirty-tree check to refuse the upgrade until `--force` was passed. |
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

`init` delegates to `sync` after writing `eidolons.yaml`. The cortex is wired automatically via sync: `EIDOLONS.md` is mirrored to `.eidolons/cortex/`, deep tables are mirrored alongside it, and a marker-bounded pointer block is injected into the root host-docs when shared-dispatch is on (see `sync` below).

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

The cortex cleanup runs now (ahead of the full v1.1 implementation): `eidolons remove` strips the `<!-- eidolon:cortex start/end -->` block from all root host-docs and deletes `.eidolons/cortex/` when the named Eidolon is the last installed member. If other Eidolons remain, the cortex blocks are preserved.

---

## `eidolons sync`

Reconcile installed state to `eidolons.yaml`. Idempotent.

```
eidolons sync [--non-interactive] [--dry-run] [--no-heal]
```

- Fetches each member's repo (cached in `~/.eidolons/cache/`).
- Runs each per-Eidolon `install.sh` with the right `--hosts` and `--target`.
- Aggregates per-Eidolon manifests into `eidolons.lock`.
- Mirrors `EIDOLONS.md` to `.eidolons/cortex/EIDOLONS.md` and mirrors the deep companion tables (`trance-matrix.md`, `handoff-graph.md`, `validation-gates.md`, `README.md`) from `methodology/cortex/` to `.eidolons/cortex/`.
- When `shared_dispatch: true`, injects a marker-bounded `<!-- eidolon:cortex start/end -->` pointer block into root `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` so the host LLM is directed to the cortex at session start. The block is omitted when shared-dispatch is off.
- When the harness is installed, refreshes the hook shims and **self-heals** a stale `startup`-only Claude Code `SessionStart` matcher in `.claude/settings.json` to the canonical `startup|resume|clear|compact` (only the Eidolons-owned entry is touched; idempotent). Pass `--no-heal` to skip the heal.

| Flag | Effect |
|------|--------|
| `--no-heal` | Skip the seamless `SessionStart`-matcher self-heal during the harness-shim refresh (default: heal a stale `startup`-only matcher in place). |

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
eidolons doctor            # fast checks only (14 structural sections)
eidolons doctor --fix      # fast checks + attempt auto-repair via sync
eidolons doctor --deep     # fast checks + D1..D6 methodology integrity gates
eidolons doctor --deep --fix   # same as --deep; --fix is read-only for D1..D6
```

| Flag | Purpose |
|------|---------|
| `--fix` | Attempt to auto-repair simple structural issues (lockfile drift, missing host wiring). Read-only for methodology gates (D1..D6). |
| `--deep` | Run methodology-integrity gates D1..D6 after the fast checks. Required to catch broken outbound links, token-budget overruns, and content drift vs the release manifest. |

**Deep checks (--deep):**

| ID | Name | Threshold |
|----|------|-----------|
| D1 | `agent.md` token budget | MUST ≤ 1000 tokens (`wc -w × 4/3`) |
| D2 | `agent.md` outbound link resolution | All `(skills\|templates\|schemas)/*.{md,json,y[a]ml}` refs MUST resolve |
| D3 | `SPEC.md` outbound link resolution | Same as D2 against `SPEC.md` (absent on legacy installs → warn) |
| D4 | manifest_sha256 vs lock | MUST match; WARN-skip when lock has no sha (legacy / pre-1.4) |
| D5 | Host-vendor agent body contract | MUST reference `agent.md` + `SPEC.md`; zero legacy `<UPPER>.md` refs |
| D6 | Skills dual-write SHA parity | `.eidolons/<n>/skills/*.md` ↔ `.claude/skills/<n>-<basename>/SKILL.md` SHA MUST match |

D1..D6 are read-only: they report drift but never mutate `.eidolons/`. To repair methodology issues, run `eidolons sync` (re-installs each member) or `eidolons remove <member> && eidolons add <member>`.

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

**Pending Upgrades section:** doctor reads the roster's `versions.pins.stable`
for each declared member and reports any whose installed version (per
`eidolons.lock`) is behind. Two states:

- `<member>  <installed>  →  <latest>  (within <constraint>)` — applying
  `eidolons upgrade <member>` would advance the lock.
- `<member>  <installed>  →  <latest>  (constraint <constraint> — bump to allow)`
  — pinned-out: the constraint pins below the new latest, so `upgrade` is
  blocked until you edit the constraint in `eidolons.yaml`.

The section is informational only — it does not increment the error count or
change the exit code. Network failures degrade silently; the section is
skipped entirely when `eidolons.yaml` is missing.

---

## `eidolons memory`

Mechanical memory pre-flight (GAP-2). Surfaces prior project context from CRYSTALIUM into the SessionStart harness injection.

```
eidolons memory preflight [--query <s>] [--ttl <sec>] [--no-cache] [--timeout <sec>] [--explain]
```

### `eidolons memory preflight`

Runs a bounded one-shot CRYSTALIUM recall (out-of-MCP-session path) and emits a compact injectable digest. **Stdout IS the digest and nothing else.** All failure paths emit empty stdout and exit 0.

| Flag | Purpose |
|------|---------|
| `--query <s>` | Recall query. Default: `"project <slug> recent context"` (deterministic slug from `basename(PWD)` → lowercase → alnum-hyphen). Stable → TTL cache key is stable. |
| `--ttl <sec>` | Cache TTL in seconds. Default: 900 (15 min). Env: `EIDOLONS_MEMORY_PREFLIGHT_TTL`. |
| `--no-cache` | Bypass cache read AND write. Always runs live; never persists the result. |
| `--timeout <sec>` | Docker kill timeout in seconds. Default: 8. Env: `EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT`. |
| `--explain` | Human-readable diagnostic mode (NOT for hook injection): gate status, cache hit/miss/age (read-only — never writes the cache), resolved docker invocation, recall exit code, record count, `total_tokens`, `slot_breakdown`, scope/layers. On a successful recall returning 0 records, prints an explicit `0 records returned — store may be empty, mis-scoped, or filtered (status/scope)…` line. Use when memory "works" but nothing ever comes back. |

**Docker args source:** reads `.mcp.json` `mcpServers.crystalium.args` (the already-rendered invocation). Transforms:
- Strips `-i` (interactive stdin flag — one-shot needs no stdin).
- Strips `--name <value>` pair (avoids collision with the running `crystalium-<slug>` serve container).
- Replaces trailing `python -m crystalium serve` with `python -m crystalium recall --query Q --scope-project SLUG --k 5 --format json`.
- Keeps image ref, `-v` volume, `-e CRYSTALIUM_*` env, `--cap-drop ALL`, `--security-opt` verbatim.

**TTL cache:** `.eidolons/harness/cache/preflight.json` — shape `{cached_at, query, digest}`. Cache HIT when `(now - cached_at) < ttl AND query == default_query`. Cache is project-local; stale entries rerun docker automatically.

**Timeout:** prefers `timeout(1)` if available (Linux/coreutils); falls back to background-watcher idiom (bash 3.2 safe) when absent (macOS default shell).

**Crystalium-present gate:** both `.mcp.json mcpServers.crystalium` AND `eidolons.mcp.lock name: crystalium` must be present. Either absent → empty stdout, exit 0.

**Digest format:** one `[layer/trust_tier] summary` line per record, truncated at 1500 chars.

**SessionStart arm:** `eidolons memory preflight` is called automatically from `harness_hook.sh` session_start mode (R28). Activates on `eidolons upgrade self`; no `harness install --force` needed. The digest is appended to `additionalContext` under a `## Prior project memory (CRYSTALIUM recall)` heading.

**Environment:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `EIDOLONS_MEMORY_PREFLIGHT_TTL` | 900 | Cache TTL override (seconds) |
| `EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT` | 8 | Docker kill timeout override (seconds) |

---

## `eidolons harness`

Mechanical hook wiring — writes host-native hook shims so every prompt submitted inside a supported AI coding host is automatically enriched with routing context.

```
eidolons harness install [--hosts HOST,...] [--strict] [--force]
eidolons harness remove
eidolons harness status
eidolons harness run --hook <host> [--session-start] [--stdin] [--verify] [--verify-block]
```

### `eidolons harness install`

Writes shim scripts under `.eidolons/harness/hooks/` and merges hooks blocks into host config files.

| Flag | Purpose |
|------|---------|
| `--hosts HOST,...` | Comma-separated host subset (`claude-code`, `codex`, `copilot`, `cursor`, `opencode`). Default: all hosts in `eidolons.yaml hosts.wire`. |
| `--strict` | Enable the strict enforcement tier (see below). |
| `--protect GLOB` | Add a file-glob to the protected set. May be repeated. Protected globs are denied in ALL contexts including subagents. |
| `--force` | Overwrite existing shims even when already up-to-date. (The `SessionStart` merge is an upsert: a stale `startup`-only matcher on the Eidolons-owned entry is healed in place.) |
| `--no-heal` | Skip the seamless `SessionStart`-matcher self-heal during the internal `--refresh-shims-only` refresh (default: heal). |

**Base tier (default):** writes `UserPromptSubmit.sh` + `SessionStart.sh` shims for claude-code and codex; `sessionStart` shim for copilot. Merges a hooks block into `.claude/settings.json` (claude-code) and `.codex/hooks.json` (codex). Cursor and opencode receive no base shims (their surfaces ride `eidolons sync` and `eidolons mcp install`).

**Strict tier (`--strict`):** adds a `PreToolUse` shim layer on top of the base tier.

| Host | Strict mode | Shim output | Caveat |
|------|-------------|-------------|--------|
| claude-code | `block` | `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` (exit 0) | Subagent invocations (agent_id present in event JSON) are allowed through — delegate-or-deny. Protected globs deny in ALL contexts. |
| codex | `advisory` | `{"decision":"block","reason":"..."}` (exit 0) | Protected-glob denials only; host may still proceed. |
| opencode | `advisory` | Plugin `.opencode/plugins/eidolons.js` throws on edit tools | Caveat: opencode#5894 subagent bypass — plugin not invoked for subagent calls. |
| cursor | refused | CLI prints reason and exits non-zero | `beforeSubmitPrompt` persist-in-context bug makes strict surfaces unsound (FORGE degradation-rule 4). |
| copilot | — | Not available | No `PreToolUse`-equivalent hook in copilot. |

**`#16952` guard:** The UPS shim and `eidolons run` both exit 0 immediately when the prompt is a task-completion notification (`"Agent ... completed"` shape or `<task-notification>` suffix). This prevents double-routing on subagent hand-off completions (Claude Code issue #16952).

**Idempotency:** repeat runs produce byte-identical output (lock + shim files). Use `--force` to re-write even when shims appear current.

**Lock record (`eidolons.lock harness:`):**

```yaml
harness:
  schema_version: "1"
  hosts_wired: [claude-code, ...]
  shim_paths: [.eidolons/harness/hooks/claude-code/UserPromptSubmit.sh, ...]
  settings_json_patched: true
  codex_hooks_json_patched: true
  strict: [claude-code]          # present only when --strict used
  strict_modes:                  # present only when --strict used
    claude-code: block
  protect: ["src/**", ...]       # present only when --protect used
```

### `eidolons harness remove`

Reverses `harness install`: removes shim files, reverts the settings/hooks JSON merges, removes the opencode advisory plugin if present, and clears the `harness:` key from `eidolons.lock`. Preserves all sibling keys in merged JSON files.

### `eidolons harness status`

Read-only report of the current harness state. Reads `eidolons.lock` and performs existence checks on shim files.

- Reports per-host effective tier and enforcement mode (`[inject-only]`, `[strict:block]`, `[strict:advisory]`).
- Lists strict-refused hosts (e.g., cursor in manifest wire set).
- Reports shim presence (`[present]` / `[MISSING]`).
- `settings.json patched` / `codex hooks patched` are **reality probes**, not lock reads: true iff the host file exists AND wires an eidolons hook (exact match on the host-scoped recorded shim path when available; conservative `eidolons` grep fallback; probe failures degrade to `false`).
- Reports cursor static surfaces (`.mdc` + AGENTS.md dispatch-pointer) when cursor is in `hosts.wire`.
- Warns about `.codex/agents/<name>.md` files (Codex only reads `.toml` — G10).

### `eidolons harness run`

Vendor-neutral routing kernel. Reads a prompt and emits a host-dialect hook artifact.

| Flag | Purpose |
|------|---------|
| `--hook HOST` | Output mode: wrap routing artifact in HOST-dialect `hookSpecificOutput` JSON. The injected context includes the route, tier, chain, and the per-step model tiers (`model tier: <t>` / `model tiers: atlas=standard → spectra=deep → …`) with an instruction to honor them via the host's model selection mechanism. |

Routing-1.1 artifact fields (additive, from `roster/routing.yaml`): `degraded_mode` / `degraded_mode_per_step` (weak-host loop shape per Eidolon), `escalation` (surfaced verbatim from the selected Eidolon — execution belongs to the orchestrator/sandbox), `fallthrough_reason` (`declared-fallback` when the host-tier gate routed to a declared `fallback:` peer), and — at trance tier only — `model_tier_lead` / `model_tier_workers`.
| `--session-start` | Emit cortex digest (used by `SessionStart` shims). |
| `--stdin` | Read prompt from event JSON `.prompt` field on stdin instead of positional arg. |
| `--verify` | Verify the ECL envelope on an incoming hand-off before routing (warn mode). |
| `--verify-block` | Same as `--verify` but exit 3 on tampered payload. |

### `doctor --deep` D12 gate

`eidolons doctor --deep` includes gate **D12 — harness lock⇄files consistency**:

- Reads `harness.shim_paths` from the lock and asserts every shim exists and is executable.
- Asserts `settings.json` valid JSON + UserPromptSubmit entry present (when claude-code wired).
- Asserts `codex hooks.json` valid JSON (when codex wired).
- Asserts `opencode.json` valid JSON (when opencode wired).
- Asserts strict hosts never include cursor (unsound surface).
- Warns on orphan shims (exist on disk but not in lock) and advisory plugin without strict record.
- Skips entirely when `harness.schema_version` is absent from the lock.

Exit 0 when D12 passes or skips; the harness error counter increments on FATAL items.

### `doctor --deep` D13 gate

**D13 — memory recallability** (project-level, crystalium-gated):

- Skips cleanly when crystalium is not in both `.mcp.json` and `eidolons.mcp.lock`.
- Runs the container's `crystalium doctor` and a `recall --k 3` probe via the same docker-args transform as `memory preflight` (shared plumbing: `cli/src/lib_memory_probe.sh`); hard 10 s timeout each.
- PASS with record count, or `WARN crystalium store returns 0 records — memory is effectively write-only (check scope keys, crystal status, embeddings)`. Unreachable/timeout ⇒ WARN. Never FATAL.

### `doctor --deep` D14 gate

**D14 — routing shape** (nexus-level, fatal — this is data integrity, not a probe): validates `roster/routing.yaml` 1.1 keys mechanically — `degraded_mode ∈ {fanout, sample-select}`, `fallback`/`escalation.reroute_to` reference existing eidolons (dangling = FAIL), `escalation.on_fail ∈ {reroute, escalate-tier}`, `max_escalations` int ≥ 1, `trance.{lead,workers}_tier ∈ {light, standard, deep}`.

---

## `eidolons model`

Vendor-neutral model management: assign each Eidolon a tier (`light < standard < deep`), pick a vendor profile, and let the nexus resolve and write the concrete `model:` into host agent frontmatter.

```
eidolons model                          # interactive picker (TTY) / usage (non-interactive)
eidolons model list                     # tier ladder + profiles (active marked) + tier→model maps
eidolons model show [<eidolon>] [--json]# resolved table: tier · profile · source · effective model
eidolons model use <eidolon>@<tier>     # set a per-member tier override (light|standard|deep)
eidolons model use <eidolon>@<model>    # pin a concrete model for one Eidolon (escape hatch)
eidolons model profile <name>           # switch active profile; re-resolve + re-wire all members
eidolons model reset [<eidolon>]        # clear a member's override/pin (all + calibration if no arg)
```

Profiles (the sole home for vendor model strings) live in `roster/model-profiles.yaml`; per-Eidolon suggested tiers live in `roster/routing.yaml`. The resolved effective model is recorded in `eidolons.lock` and written to `.claude/agents/<id>.md` (claude-code) / `.codex/agents/<id>.md` (codex) inside an idempotent `# eidolons:managed model` block; copilot/cursor are a no-op. Exit codes: `0` ok · `2` bad args / unknown Eidolon or profile · `3` resolve hard-miss · `4` frontmatter write failed. `eidolons doctor --deep` (gate **D9**) reports frontmatter-vs-lock drift. Full reference: [`docs/model.md`](model.md).

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

## `eidolons verify-release`

Layer 2 methodology integrity: compare installed Eidolons against a fresh
re-derivation from their upstream-pinned releases.

```
eidolons verify-release
eidolons verify-release --eidolon atlas --eidolon spectra
eidolons verify-release --strict
eidolons verify-release --no-fetch
eidolons verify-release --json
```

| Flag | Purpose |
|------|---------|
| `--eidolon NAME` | Verify only this Eidolon. Repeatable. Unknown name → error. |
| `--strict` | Exit non-zero on any drift. Default: WARN-only (exit 0 even with drift). |
| `--no-fetch` | Use per-version cache only; do not fetch upstream. Cache miss → error. Useful for offline CI. |
| `--json` | Emit a machine-readable JSON report on stdout (see schema below). |

**What it does.** For each Eidolon in `eidolons.lock`, `verify-release`:

1. Fetches (or reuses the cache for) the pinned upstream version.
2. Runs the per-Eidolon `install.sh` into a temp directory, honoring the same `--hosts` and `--shared-dispatch` flags as `eidolons sync`.
3. SHA-256 diffs every file in the temp install against the consumer's on-disk `.eidolons/<name>/` tree.
4. Reports per-file status: **OK** (matching), **DIFFER** (different SHA), **MISSING** (in upstream, not on consumer), **EXTRA** (on consumer, not in upstream).
5. Excludes `install.manifest.json` from the diff — timestamp drift is expected.

**Catches:**

- Local file tampering after install.
- Mid-install corruption that fooled `doctor --deep` D4 (lock + files matched each other but both differ from upstream).
- Accidentally deleted files under `.eidolons/<name>/`.
- Files added under `.eidolons/<name>/` that aren't part of the install.

**Exit codes:**

| Code | Condition |
|------|-----------|
| 0 | All checks ran; no drift — or drift detected and `--strict` not passed. |
| 1 | `--strict` passed and at least one drift detected. |
| 1 | Hard error (no `eidolons.lock`, unknown `--eidolon`, cache miss with `--no-fetch`, installer failure). |
| 2 | Unknown flag. |

**`--json` schema:**

```json
{
  "cli_version": "1.12.0",
  "checked_at": "2026-05-26T14:32:17Z",
  "strict": false,
  "summary": { "verified": 5, "drifted": 1, "errors": 0 },
  "members": [
    {
      "name": "atlas",
      "version": "1.7.1",
      "status": "ok",
      "file_count": 124,
      "diff": []
    },
    {
      "name": "spectra",
      "version": "4.5.1",
      "status": "drift",
      "file_count": 98,
      "diff": [
        { "status": "DIFFER", "path": "skills/planning/SKILL.md",
          "tmp_sha": "a3f5...", "consumer_sha": "9e21..." },
        { "status": "EXTRA", "path": "skills/custom-user-skill.md",
          "tmp_sha": null, "consumer_sha": "c0ff..." }
      ]
    }
  ]
}
```

`status` per member: `ok | drift | error`. `diff[]` entries: `status` in `DIFFER | MISSING | EXTRA`.

**Remediation:** drift is diagnostic only. `verify-release` is read-only and never repairs. To restore:

```
eidolons sync                                     # all members
eidolons remove <name> && eidolons add <name>     # one member
```

---

## `eidolons canary`

Layer 3 integrity: print an Eidolon's canary mission prompt or validate a saved LLM response against structured criteria. Human-in-the-loop: the CLI never invokes an LLM itself.

```
eidolons canary <name>                       # prompt mode
eidolons canary <name> --validate <file>     # validate mode
eidolons canary --list                       # list mode
eidolons canary --memory                     # memory round-trip mode
```

### Modes

| Mode | Invocation | What it does |
|------|-----------|--------------|
| **prompt** | `eidolons canary <name>` | Print mission prompt + expected output shape + validation criteria |
| **validate** | `eidolons canary <name> --validate <file>` | Check saved LLM output against mission criteria |
| **list** | `eidolons canary --list` | Scan cache; report mission status per Eidolon (three states) |
| **memory** | `eidolons canary --memory` | crystalium memory probe against the live project store: SKIP (crystalium not gated in / docker not on PATH). Otherwise runs a capability probe (`commit --help`) first. **crystalium >= 1.7** (has the `commit` CLI verb): TRUE write→recall round trip — commits a uniquely-tokened canary record, recalls it back by that token, best-effort forgets it (cleanup failure never changes the verdict, WARN to stderr only) — PASS (record found on recall) / FAIL (commit refused, or committed but not recallable). **crystalium < 1.7** (capability probe fails): falls back to the original recall-only liveness check — PASS (records returned) / INCONCLUSIVE (reachable, 0 records) / FAIL (unreachable) — and the PASS/INCONCLUSIVE text says explicitly it's liveness-only. Deliberately not crystalium's own `canary` subcommand either way (that A/B-evals a fresh ephemeral store, a different question). Output always states exactly what is and isn't checked. |

### Flags

| Flag | Default | Behaviour |
|------|---------|-----------|
| `--validate <file>` | unset | Switches to validate mode; file must exist and be readable |
| `--list` | unset | Switches to list mode |
| `--mission <id>` | first in file | Select a non-default mission by ID |
| `--json` | false | Emit machine-readable JSON on stdout; suppress human output |
| `-h, --help` | — | Print usage; exit 0 |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Prompt printed, OR validation all PASS/INCONCLUSIVE, OR list printed |
| `1` | Validation had ≥1 FAIL criterion |
| `2` | Misuse: unknown name, missing file, unknown flag |

### Validation DSL

Each criterion in `evals/canary-missions.md` follows `- <SEVERITY> <verb>: <argument>`:

| Severity | On mismatch |
|----------|------------|
| `MUST` | FAIL → exit 1 |
| `SHOULD` | Downgraded to INCONCLUSIVE → never causes exit 1 |

Four recognized verbs:

| Verb | Argument | Check |
|------|----------|-------|
| `contain heading: <text>` | exact markdown heading | `grep -Fxq` against lines stripped of leading whitespace |
| `contain phrase: <regex>` | extended regex | `grep -Eq` against full output |
| `mention paths: <p1>, <p2>, ...` | comma-separated path tokens | ALL tokens must appear (each `grep -Fq`) |
| `have token count between X and Y` | two integers | word-count × 4/3 ≥ X and ≤ Y |

Unrecognized verbs → INCONCLUSIVE (`"unrecognized criterion"`), never FAIL.

### JSON output schema

All `--json` emissions share:

```json
{
  "schema_version": "1.0",
  "mode": "prompt|validate|list",
  ...
}
```

Validate mode:

```json
{
  "schema_version": "1.0",
  "mode": "validate",
  "eidolon": "atlas",
  "version": "1.7.1",
  "mission_id": "default",
  "summary": { "pass": 3, "fail": 0, "inconclusive": 0 },
  "criteria": [
    { "criterion": "- MUST contain heading: ## Mission Brief",
      "severity": "MUST", "result": "PASS", "reason": "" }
  ]
}
```

### `evals/canary-missions.md` format

The file lives in the per-version cache at `~/.eidolons/cache/<name>@<version>/evals/canary-missions.md`. It is not shipped to the installed project tree.

```markdown
## Mission: default

### Prompt
<verbatim prompt to feed the LLM>

### Expected output shape
<prose description — human-readable, ignored by the validator>

### Validation criteria
- MUST contain heading: ## Mission Brief
- MUST contain phrase: FINDING-
- MUST mention paths: skills/abstract.md, skills/locate.md
- SHOULD have token count between 1000 and 3000
```

Multiple missions per file are supported. The first `## Mission:` heading is the default; `--mission <id>` selects others.

### Workflow

```
# Step 1: print the prompt
eidolons canary atlas

# Step 2: paste into your LLM (Claude Code, claude.ai, API, ...)
# and save the response to a file

# Step 3: validate
eidolons canary atlas --validate /path/to/response.md
```

### Notes

- Missing `evals/canary-missions.md` → warn + exit 0 (soft; not every Eidolon has authored missions yet).
- `canary --list` is a fast cache inspection; it does **not** fetch. Absent cache → `(cache not populated; run 'eidolons sync')`.
- `canary --list` uses three display states: `✓` (file exists AND ≥1 `## Mission: <id>` heading parses), `⚠` (file exists but 0 DSL missions found — legacy format), `·` (no `evals/canary-missions.md` at all). Summary line reports all three counts: `N with parseable missions, N with file-only (legacy format), N with no file`.
- `--json` list output uses `schema_version: "1.1"` and per-member `status` field (`"parsed"` / `"legacy"` / `"missing"`). Summary fields are `parsed`, `legacy`, `missing`.
- Requires `eidolons.lock`. Run `eidolons add <name>` first if the member is not in the lock.

---

## `eidolons eval swe --matrix` / `eidolons eval baseline`

The (arm × suite) matrix runner and its regression tracker — the H-WIN measurement instrument.

```
eidolons eval swe --matrix evals/arms/h-win.json [--smoke] [--no-store] [--suite-file evals/kupo-keep-suite.yaml] [--k N]
eidolons eval baseline <suite> [--label <arm-label>] [--against <scorecard.json>]
```

- **Matrix**: runs the whole suite once per arm (`{label, fix_hook, env, control}` — schema `schemas/eval-arms.schema.json`); each arm re-invokes the untouched single-arm path as a child process. Emits one scorecard per arm (`evals/results/<date>-<suite>-<label>.scorecard.json`, schema `schemas/eval-scorecard.schema.json`) plus `<date>-<suite>-matrix.json` (pairwise vs the first `control: true` arm: rate deltas, newly-resolved/regressed flips). `--smoke` = gold_fix plumbing validation (free; what CI runs; scorecards record `harness.smoke: true` and are never capability claims). `--no-store` skips persistence. `EIDOLONS_EVAL_RESULTS_DIR` overrides the store location. Hooks receive `EIDOLONS_EVAL_TASK_BRIEF` + the arm's env (`EIDOLONS_EVAL_MODEL`, `EIDOLONS_SANDBOX_MODEL_TIER`).
- **Baseline**: mechanical jq diff of the two most recent scorecards for (suite, label) — or latest vs `--against`. Exit `0` clean · `5` regression (rate drop or any resolved→unresolved flip) · `1` misuse.
- **Reference arms**: `evals/arms/h-win.json` pins the honest headline comparison — (light-tier model + system discipline, `keep-system.sh`) vs (standard-tier model + bare prompt, `keep-bare.sh`). Hook prompts are versioned artifacts; changing them invalidates baselines.
- **CI**: `.github/workflows/live-eval.yml` — weekly cron runs `--matrix --smoke`; live billed runs require `vars.EIDOLONS_LIVE_EVAL_ENABLED == 'true'` AND `ANTHROPIC_API_KEY`, else the job degrades to smoke and says why.

### `eidolons canary --host`

```
eidolons canary --host <claude-code|codex|copilot|cursor|opencode>   # one host
eidolons canary --all-hosts                                          # all five
```

Per-host effective-tier canary: probes the actual host surfaces (shims present+executable, settings/hooks wired, strict recipes) against the lockfile's `harness.hosts_wired`/`strict` expectations — PASS (reality matches lock) / FAIL (lock claims what reality doesn't back, with reasons) / SKIP (host not wired). Same probes as doctor D12, but per-host verdicts instead of one aggregate.

---

## `eidolons eval compliance`

A/B behavioural instrument: does the advisory harness injection actually change a host
LLM's delegation behaviour? Measures **routing compliance** — whether the host dispatches to
the Eidolon the deterministic kernel would route to — with the harness wired (ARM A) versus
documentary cortex only (ARM B). Operationalizes the FORGE reversal gate
(`DOSSIER-HARNESS-2026-06.md:106`).

```bash
eidolons eval compliance --smoke --json          # free pipeline self-test (fake driver)
eidolons eval compliance --dry-run --k 2 --arm both   # print the billed-session cost, stop
# live (billed) — see .spectra/harness-mechanization/runbook-compliance.md:
EIDOLONS_COMPLIANCE_NO_LIVE= eidolons eval compliance --arm both --k 2 --yes --json
```

### Options

| Flag | Meaning |
|---|---|
| `--smoke` | Run the whole pipeline against a canned fake driver. No model, no billing. CI default. |
| `--dry-run` | Print the `COST: n_prompts × arms × k` session count and exit 0 without calling a driver. |
| `--yes` | Required to start a live (billed) run. Without it, a non-smoke/non-dry run dies with the cost message. |
| `--arm A\|B\|both` | Which arm(s) to run (default `both`). A = harness wired; B = prose cortex only. |
| `--k N` | Repeats per prompt (default 1). Use ≥2 for any headline claim — k=1 is noise. |
| `--driver '<cmd>'` | Substitute the default `claude -p` driver. The command gets the prompt on argv and stdin and must emit the host stream on stdout. |
| `--model <m>` | Model for the default driver (default `sonnet`). |
| `--max-turns N` | Cap per session (default 3 — we measure whether an early Task dispatch fires, not task completion). |
| `--suite-file <path>` | Prompt suite (default `evals/compliance-suite.yaml`). |
| `--min N` / `--gate` | Exit 1 if ARM-A `correct_target_rate` is below N percent / below the 80% FORGE threshold. |
| `--keep` / `--capture-sample` | Keep fixtures / save the raw stream for parser reconciliation. |
| `--json` | Emit the machine-readable scorecard on stdout. |

### Scorecard

Per arm: `delegation_rate` (any roster Task dispatched), `correct_target_rate` (first dispatch
matches the kernel's `selected`/chain — **the gate metric**), `control_pass_rate` (control
prompts correctly get NO dispatch), `stability_passk`, and a per-class breakdown. Top level:
`delta` (A − B, the isolated harness effect) and `gate` (verdict vs 80% + reversal action).

### Safety

The instrument never bills from tests. `eval_compliance.sh` refuses the default `claude`
driver when `EIDOLONS_COMPLIANCE_NO_LIVE=1` is set; the bats `setup()` exports it, so the
suite cannot spawn a billed session even if a test omits `--smoke`. Clear the variable only
for a deliberate, supervised live run (runbook). A custom `--driver` bypasses this net and
owns its own cost gating.

---

## `eidolons nexus`

Inspect and control the nexus roster channel — the split between the pinned CLI
version and the floating roster data.

```
eidolons nexus <subcommand> [options]
```

### `eidolons nexus refresh [--quiet]`

Force a roster data refresh now. Fetches **only** the data-layer paths
(`roster/`, `EIDOLONS.md`, `methodology/cortex/`) from the channel ref, leaving
the CLI code (`cli/`, `schemas/`, `VERSION`) pinned at the installed tag.

Honors skip-guards: no-op (prints "skipped") when `EIDOLONS_NEXUS` is set or
`EIDOLONS_SKIP_REFRESH=1`. Non-fatal when offline. Exit 0 always.

| Flag | Purpose |
|------|---------|
| `--quiet` | Suppress informational output (only errors go to stderr). |

### `eidolons nexus channel [<ref>]`

Get or set the roster channel (the `~/.eidolons/nexus/.roster_ref` sidecar).

- **No arg**: print the current channel. Exit 0.
- **With `<ref>`**: set the roster channel. Accepted values:
  - `main` — track the `main` branch (default).
  - `stable` — magic token: at each refresh, resolves to the latest published
    release tag via `nexus_latest_tag`. Useful for "track releases, not main".
    If offline at refresh time, the refresh is skipped non-fatally.
  - `<tag>` e.g. `v1.16.0` — freeze to a specific tag.
  - `<sha>` — pin to a specific commit.
  - `<branch>` — track any remote branch.

| Exit code | Meaning |
|-----------|---------|
| 0 | Success |
| 2 | Empty / whitespace-only arg |

### `eidolons nexus status`

Read-only split report: CLI version/ref and roster channel/effective/freshness.

```
CLI
  version:    1.16.0
  ref:        v1.16.0
  commit:     a3b4c5d
ROSTER
  channel:    main  (effective: main)
  cache HEAD: f9e8d7c
  upstream:   f9e8d7c  | unreachable
  freshness:  up-to-date | behind (run: eidolons nexus refresh) | unknown (offline)
```

Upstream probe is gated by skip-guards (offline-safe). Exit 0 always.

### Reproducibility model

The **CLI code is pinned** at `.install_ref` (updated only by `eidolons upgrade
self`). The **roster catalogue floats** at `.roster_ref` (updated by
`nexus_refresh` on every `sync`/`init`/`upgrade`/`mcp install`/`mcp upgrade`).

Per-member integrity (commit/tree/archive SHA) is **still verified** at
install/upgrade time — floating the catalogue only changes *which* pins are
visible, never their verification. Users who need a fully frozen catalogue
(reproducible builds, air-gap) run:

```bash
eidolons nexus channel stable   # track latest release tag
eidolons nexus channel v1.16.0  # freeze to exact tag
export EIDOLONS_SKIP_REFRESH=1  # disable all auto-refresh
```

---

## `eidolons upgrade`

Surface and apply upgrades for installed members.

```
eidolons upgrade [TARGET] [OPTIONS]                 # default: project scope (members)
eidolons upgrade --check [SCOPE] [TARGET] [--json]  # read-only diff
eidolons upgrade --system  [OPTIONS]                # nexus only (git fetch + reset --hard)
eidolons upgrade --project [TARGET] [OPTIONS]       # explicit project scope
eidolons upgrade --all     [OPTIONS]                # nexus then members
```

| Flag / arg | Purpose |
|------------|---------|
| `TARGET` | Member name or comma-separated list (mutually exclusive with `--system` / `--all`). |
| `--check` | Read-only diff: prints nexus and member upgrade availability, no disk writes. Pair with `--system` or `--project` to narrow the report. |
| `--system` | Upgrade only the nexus at `~/.eidolons/nexus` (`git fetch + reset --hard`). For an atomic, integrity-verified self-upgrade, use `eidolons upgrade self` instead. |
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

## `eidolons upgrade self`

Upgrade the nexus CLI itself. Atomic, integrity-verified, rollback-safe.

```
eidolons upgrade self                      # upgrade to latest stable
eidolons upgrade self --ref vX.Y.Z         # pin to a specific tag or commit
eidolons upgrade self --check              # read-only: show what would change
eidolons upgrade self --rollback           # revert to nexus.prev
eidolons upgrade self --force              # skip dirty-tree and downgrade guards
eidolons upgrade self --non-interactive    # fail on any prompt (for CI)
```

| Flag | Purpose |
|------|---------|
| `--ref REF` | Specific git tag, branch, or commit SHA to upgrade to. Default: latest stable tag. |
| `--check` | Read-only mode: prints the current version, latest available, and upgrade plan. No disk writes. |
| `--rollback` | Swap `~/.eidolons/nexus.prev` back into place. Only one previous version is retained. Exit 7 if no `nexus.prev` exists. |
| `--force` | Skip the dirty-tree guard and downgrade confirmation. Required when the current nexus has uncommitted changes. |
| `--non-interactive` | Fail instead of prompting (e.g. downgrade confirmation). Safe for CI use. |

**How it works.** `upgrade self` never modifies your current install until it is safe to do so:

1. Resolves the target ref (default: latest stable tag via `git ls-remote`).
2. Checks whether current version already matches — exits 0 (no-op) if so.
3. Clones the target into `~/.eidolons/nexus.new/`.
4. Verifies integrity: commit SHA, Git tree SHA, and archive SHA-256 all match `nexus.versions.releases.<v>` in `roster/index.yaml`. Exit 5 on mismatch (unless the release block contains placeholder values, which is the bootstrap-window sentinel).
5. Runs a smoke test: `bash ~/.eidolons/nexus.new/cli/eidolons --version --quiet` exits 0. Exit 6 on failure.
6. Atomically swaps:
   - `~/.eidolons/nexus` → `~/.eidolons/nexus.prev`
   - `~/.eidolons/nexus.new` → `~/.eidolons/nexus`
7. The symlink at `~/.local/bin/eidolons` is unchanged — it already points at `~/.eidolons/nexus/cli/eidolons`.

On any failure before step 6, `~/.eidolons/nexus.new` is removed and the current install is untouched.

**Downgrade detection.** If `--ref` targets a version older than the current install, the command warns and requires explicit confirmation (or `--force` / `--non-interactive` with `--force`).

**Dirty-tree guard.** If the current nexus directory has uncommitted changes (common when working directly from a checkout), the command refuses to proceed unless `--force` is passed.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Success (or already up-to-date) |
| 1 | Generic failure (details on stderr) |
| 2 | Already at the requested ref (no-op, same as 0 for no-op check) |
| 4 | Network error — could not reach upstream |
| 5 | Integrity verification failed |
| 6 | Smoke test failed on the new nexus |
| 7 | Rollback requested but no `nexus.prev` exists |

---

## `eidolons release`

**Maintainer-only.** One-touch dispatch of an upstream Eidolon's `Release`
workflow followed by this nexus's `Roster Intake`. Replaces the manual two-step
`gh workflow run` chain.

```
eidolons release <eidolon> <version> [OPTIONS]
```

**Behaviour.**

1. Validates SemVer (`X.Y.Z[-pre][+build]`) and the `gh` CLI version
   (requires `gh >= 2.20.0` for `gh pr merge --auto` support).
2. Resolves the Eidolon from the roster; checks `gh auth` scope per repo
   (`Rynaro/<EIDOLON>` and `Rynaro/eidolons`); confirms the upstream
   `release.yml` workflow file exists.
3. Version-precedence guard: rejects when the requested version equals the
   roster `versions.latest` (use `--resume`) or is older (use `--force`).
4. Dispatches `Release <DISPLAY>` on the upstream repo via `gh workflow run`
   (skipped when `--resume` and the tag already exists).
5. Polls `gh release view v<version>` on the upstream repo until the tag
   appears or `--release-timeout` elapses.
6. Dispatches `Roster Intake` on `Rynaro/eidolons` with the resolved
   eidolon + version inputs.
7. Polls `gh pr list` for the resulting `codex/roster-<name>-<v>` branch
   until the PR opens or `--intake-timeout` elapses.
8. Prints the PR URL, auto-merge status, and a follow-up `gh pr checks`
   command. Hints the consumer to run `eidolons upgrade <name>`.

**Flags.**

| Flag | Default | Purpose |
|------|---------|---------|
| `--check` | — | Dry-run: validate plan only; print what would dispatch; no side effects. |
| `--resume` | — | Skip Release dispatch when the upstream tag already exists. Use after a partial completion. |
| `--force` | — | Allow version equal to or less than the current roster latest (intentional rollback path). |
| `--auto-merge` | — | Pass-through hint to Roster Intake (auto-merge is the default for routine bumps anyway). |
| `--yes`, `-y` | — | Skip the interactive confirmation prompt. Required with `--non-interactive` for mutating runs. |
| `--non-interactive` | — | Fail on prompts. Combine with `--yes` for unattended use (CI). |
| `--release-timeout=N` | 600 | Seconds to wait for the upstream tag to appear. |
| `--intake-timeout=N` | 300 | Seconds to wait for the Roster Intake PR to open. |
| `-h`, `--help` | — | Print usage and exit 0. |

**Safety properties.**

- Idempotent: re-running with `--resume` after a partial completion never
  re-dispatches a workflow that already produced its tag.
- No mutating action runs before validation completes (auth, version
  precedence, workflow existence).
- All log output to stderr; stdout reserved for capturable values
  (PR URL on success).
- Bash 3.2 safe.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Success — tag landed, intake dispatched, PR URL printed |
| 1 | Generic failure (details on stderr) |
| 2 | Usage error or validation failure (bad SemVer, unknown eidolon, version not ahead, missing flags) |
| 4 | Network/timeout — upstream tag never appeared, or intake PR never opened |
| 5 | Dispatch failure — `gh workflow run` returned non-zero |

**Examples.**

```bash
eidolons release atlas 1.4.0                         # interactive prompt
eidolons release atlas 1.4.0 --yes                   # skip prompt
eidolons release atlas 1.4.0 --check                 # dry-run
eidolons release atlas 1.4.0 --resume                # tag already landed
eidolons release atlas 1.4.0 --release-timeout=120   # short timeout
```

**Companion automation.** Routine roster bumps that pass attestation
verification + required status checks now auto-merge once Roster Intake
opens the PR. First-shipped Eidolon transitions stay DRAFT for explicit
review. See `docs/release-integrity.md` § "Auto-merge of routine roster
bumps".

---

## `eidolons mcp`

Unified MCP server store. See [`docs/mcp.md`](mcp.md) for the full reference.

```
eidolons mcp list                    # browse catalogue + installed status
eidolons mcp show <name>             # full detail for one MCP
eidolons mcp install <name>[@<ver>]  # install at pins.stable or explicit version
eidolons mcp refresh <name>          # re-fetch artefact (image pull / binary)
eidolons mcp uninstall <name>        # remove from this project
eidolons mcp upgrade [<name>|--all]  # upgrade to catalogue stable
eidolons mcp sync                    # reconcile eidolons.yaml mcps: block
eidolons mcp health [<name>|--all]   # run health probes; exit code always 0
eidolons mcp run <name> [<args>]     # pass-through to binary MCP (junction only in v1.3)
```

### Environment

| Variable | Purpose |
|---|---|
| `EIDOLONS_SUPPRESS_DEPRECATED=1` | Silence `DEPRECATED:` lines from legacy verbs |

### Deprecated aliases (removed in v3.0.0)

These still work but emit one `DEPRECATED:` line to stderr on every invocation.
Set `EIDOLONS_SUPPRESS_DEPRECATED=1` to suppress.

| Legacy verb | Replacement |
|---|---|
| `eidolons mcp atlas-aci [--force]` | `eidolons mcp install atlas-aci [--force]` |
| `eidolons mcp atlas-aci pull [...]` | `eidolons mcp refresh atlas-aci [...]` |
| `eidolons harness install [ver]` | `eidolons mcp install junction[@ver]` |
| `eidolons harness up` | `eidolons mcp health junction` |
| `eidolons harness verify [args]` | `eidolons mcp run junction verify [args]` |
| `eidolons harness uninstall` | `eidolons mcp uninstall junction` |

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

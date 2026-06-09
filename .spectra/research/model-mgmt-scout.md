# Scout Report — Model Management Feature
**MISSION-ID:** ATLAS-MODEL-MGMT-2026-06-09
**DECISION_TARGET:** Where models/model-tiers are referenced today and where the model management feature must hook in.

---

## Topology Summary

- `roster/routing.yaml` — per-Eidolon `model_tier` ∈ {speed-class, reasoning-class}; read by `cli/src/run.sh`.
- `schemas/routing.schema.json` — enforces the two-value enum on `model_tier`; `additionalProperties: true` so new fields are additive-safe.
- `cli/src/run.sh` — the jq kernel that reads `model_tier` from routing.yaml and surfaces `model_tier_per_step: [...]` in the `--json` routing artifact. Informational only; no concrete model name is ever resolved.
- Per-Eidolon `install.sh` (external repos, cached under `~/.eidolons/cache/<name>@<ver>/`) — the **sole writer** of `model:` in host agent files. Each Eidolon hard-codes its own value inline.
- `cli/src/sync.sh` — invokes `install.sh --hosts <CSV>` per member; does not touch `model:` itself.
- `eidolons.yaml` / `schemas/eidolons.yaml.schema.json` — no `model` field exists; member shape is `{name, version, source?, target?}`.
- `eidolons.lock` — no `model` field; member shape is `{name, version, resolved, commit, tree, archive_sha256, manifest_sha256, verification, target, hosts_wired, comm?}`.
- `cli/src/mcp_use.sh` + `cli/src/mcp.sh` — the `eidolons mcp use <name>@<ver>` UX precedent for per-project version switching.
- `methodology/prime-directives.md #162` — no vendor names in core methodology; capability classes only.
- `EIDOLONS.md:7,49,75,142` — explicitly says "no vendor model names", uses speed-class/reasoning-class only.

---

## Answer to DECISION_TARGET by Sub-Question

### SQ1 — Where does `model:` frontmatter get written?

**FINDING-01 (H):** `model:` is written exclusively by each Eidolon's own `install.sh` (external repo). The nexus CLI (`sync.sh`, `init.sh`, `lib_mcp_wiring.sh`, `lib.sh`) writes zero `model:` fields.

Evidence:
- `~/.eidolons/cache/spectra@4.8.0/install.sh:566-571` — heredoc `cat > ".claude/agents/${EIDOLON_NAME}.md"` with `model: opus` hard-coded inline.
- `~/.eidolons/cache/atlas@1.11.0/install.sh:611-616` — `AGENT_CONTENT` string has no `model:` line; ATLAS omits it entirely (host default applies).
- Installed evidence: `.claude/agents/spectra.md:4 model: opus`, `.claude/agents/apivr.md:6 model: sonnet`, `.claude/agents/idg.md:4 model: haiku`, `.claude/agents/kupo.md:4 model: haiku`, `.claude/agents/vigil.md:4 model: opus`. ATLAS and FORGE have no `model:` line.
- `cli/src/sync.sh:372-374` — only passes `--hosts "$HOSTS_CSV"` to `install.sh`; no model flag exists.

**FINDING-02 (H):** The model value is baked at Eidolon release time, not at consumer-project install time. There is no indirection layer between "what the Eidolon repo ships" and "what lands in `.claude/agents/<n>.md`".

**FINDING-03 (M):** Host coverage for `model:`:
- **claude-code** (`.claude/agents/<n>.md`): supports `model:` frontmatter. Currently set by 5/7 Eidolons.
- **codex** (`.codex/agents/<n>.md`): supports `model:` frontmatter (`~/.eidolons/cache/atlas@1.11.0/install.sh:694-695` notes `name, description required; tools, model optional`). Codex fixture in `mcp_wiring.bats:169` uses `model: gpt-5`.
- **opencode** (`.opencode/agents/<n>.md`): no `model:` in ATLAS's opencode agent template (`install.sh:660-677`); unclear if supported.
- **copilot** (`.github/instructions/<n>-<skill>.instructions.md`) and **cursor** (`.cursor/rules/*.mdc`): instruction-file format only; no per-agent model concept.

### SQ2 — `eidolons mcp use` end-to-end pattern

**FINDING-04 (H):** Dispatch chain: `cli/eidolons:228` allowlist `list|show|install|refresh|uninstall|upgrade|use|sync|health|run|pull|images` → `exec bash cli/src/mcp.sh "$mcp_sub" "$@"` → `cli/src/mcp.sh:56` `exec bash "$SELF_DIR/mcp_use.sh"`.

**FINDING-05 (H):** The `cli/eidolons` allowlist (`cli/eidolons:228`) and `cli/src/mcp.sh`'s case statement (`mcp.sh:49-62`) are identical in content but physically separate. Adding a new top-level verb (e.g. `model`) requires updating only `cli/eidolons`; `mcp.sh` is the sub-dispatcher that then branches to sub-scripts.

**FINDING-06 (H):** `mcp_use.sh` pattern:
1. `nexus_refresh` (cache refresh, non-fatal on network failure).
2. Parse `<name>@<ver>` (mandatory `@ver` suffix — bare names exit 2).
3. `mcp_assert_version_published "$name" "$ver"` — catalogue-only guard.
4. Idempotency no-op check: `mcp_lock_entry "$name" | jq -r '.version'` vs `$ver`.
5. Require already-installed (lock entry must exist).
6. Delegate to `mcp_install.sh "${name}@${ver}" --force`.
7. Lock is written by `mcp_install.sh` (not `mcp_use.sh`).

**FINDING-07 (H):** Version catalogue lives in `roster/mcps.yaml` under `versions.releases.<ver>`. Lock lives in `eidolons.mcp.lock` (`schemas/mcp-lockfile.schema.json`). The `eidolons mcp use` pattern is: catalogue-validated → lockfile-persisted → re-install under new version.

### SQ3 — Lockfile + per-project state

**FINDING-08 (H):** `schemas/eidolons.lock.schema.json` — member shape has no `model` or `model_tier` field. The lock records `name, version, resolved, commit, tree, archive_sha256, manifest_sha256, verification, target, hosts_wired, comm`. No model calibration state.

**FINDING-09 (H):** `eidolons.lock` is generated and owned by `cli/src/sync.sh` (the lock is written at the end of each sync run). `eidolons.mcp.lock` is generated by `cli/src/mcp_install.sh`.

**FINDING-10 (H):** A per-project model calibration would need either: (a) a new top-level `eidolons.lock` section (e.g. `model_overrides: [{name: spectra, model: sonnet}]`), or (b) a parallel `eidolons.models.lock` file mirroring the mcp-lockfile pattern. The schema uses `additionalProperties` omission (not `false`) in member items — additive fields are safe.

### SQ4 — Doctor gates touching model/tier/routing

**FINDING-11 (H):** Zero doctor gates touch model, model_tier, routing, or agent frontmatter `model:` field. The 8 deep gates (D1–D8) check: token budget (D1), outbound link resolution (D2, D3), manifest SHA (D4), host-vendor agent body contract (D5), skills SHA parity (D6), ACI boundary (D7), ECL receiver skill (D8). `cli/tests/doctor.bats` confirms: no `@test` names or assertions mention `model` or `tier`.

**FINDING-12 (M):** D5 checks that the agent body "references agent.md + SPEC.md, zero legacy refs" but does NOT verify the `model:` field value against the roster's `model_tier`. This is the natural home for a new gate: D9 — model field in agent file matches project's configured model for that capability class.

### SQ5 — Host model specification across vendors

**FINDING-13 (H):** Per-host model support:
- **claude-code**: `model:` in YAML frontmatter of `.claude/agents/<n>.md`. Fully supported; 5/7 Eidolons use it.
- **codex**: `model:` in YAML frontmatter of `.codex/agents/<n>.md`. Supported per EIIS v1.1 §4.5 contract and `install.sh:694-695`.
- **opencode**: `.opencode/agents/<n>.md` — ATLAS template omits `model:`. Format may support it but not currently used.
- **copilot** (`.github/instructions/*.instructions.md`): frontmatter is `applyTo`+`description` only (`install.sh:527`). No per-agent model concept.
- **cursor** (`.cursor/rules/*.mdc`): frontmatter is `description`+`alwaysApply` only (`install.sh:536`). No per-agent model concept.
- **raw** / `AGENTS.md` / `CLAUDE.md`: shared instruction surface, no per-agent model concept.

`detect_hosts` in `cli/src/lib.sh` sniffs for `CLAUDE.md`, `.claude/`, `.github/`, `.cursor/`, `.opencode/`. Registered in `sync.sh:91` via `HOSTS_CSV`.

**FINDING-14 (H):** Model management is therefore only actionable for claude-code and codex hosts. Copilot and cursor have no per-agent model field to write to.

### SQ6 — Relevant test files

**FINDING-15 (H):** Test files to extend:
- `cli/tests/run.bats` — tests `model_tier_per_step` in routing artifact (V1–V12 + tier tests). A model-resolution test would live here.
- `cli/tests/mcp_use.bats` — 15 tests covering bare-name rejection, unpublished-version gate, idempotency, no-op, downgrade allowed. Mirror for `eidolons model use`.
- `cli/tests/mcp_wiring.bats` — tests `tools:` frontmatter patching in agent files. A model-wiring gate would extend this file.
- `cli/tests/doctor.bats` — 40+ tests. New D9 gate test would go here.
- `cli/tests/cortex.bats:131` — `@test "cortex: EIDOLONS.md has no vendor model names"` — asserts no vendor names in cortex. Must NOT be broken by adding a model mapping file; the mapping belongs in a separate file (e.g. `roster/models.yaml`), not in `EIDOLONS.md`.
- `cli/tests/mcp_upgrade.bats` — analogous to a future `model upgrade` command.

### SQ7 — Cortex model-tier references

**FINDING-16 (H):**
- `EIDOLONS.md:7` — "No vendor model names appear here — capability classes only (speed-class, reasoning-class)."
- `EIDOLONS.md:49` — routing artifact field `model_tier_per_step: [speed-class | reasoning-class, ...]`.
- `EIDOLONS.md:75` — TRANCE grants "model-tier upgrade (lead = reasoning-class, workers = speed-class)".
- `EIDOLONS.md:142` — invariant I-C3: "Capability classes only: `speed-class`, `reasoning-class`. Never vendor names."
- `methodology/cortex/trance-matrix.md:27` — C2 rule: "lead = reasoning-class, workers = speed-class".

**FINDING-17 (M):** The vocabulary is currently two classes (speed-class, reasoning-class). A model management feature that introduces a three-tier vocabulary (e.g. haiku/sonnet/opus or fast/balanced/powerful) would need: (a) `routing.schema.json` enum expansion, (b) `routing.yaml` per-Eidolon update, (c) `EIDOLONS.md` I-C3 update, (d) `trance-matrix.md` C2 update. The cortex prose test in `cortex.bats:131` checks for vendor names — it would catch regression.

### SQ8 — Schema hook points

**FINDING-18 (H):**
- `schemas/roster-entry.schema.json` — no `model` or `suggested_model` field. Has `capability_class` (8 values). A new `models` object (e.g. `{suggested: "reasoning-class", default_concrete?: "claude-opus-4"}`) could be additive here.
- `schemas/eidolons.yaml.schema.json` — member items have `{name, version, source?, target?}`. A `model?` or `model_override?` per-member field would be additive.
- `schemas/eidolons.lock.schema.json` — member items have no model field. A `model_resolved?: string` would be additive.
- `schemas/routing.schema.json` — per-Eidolon shape has `model_tier: enum[speed-class, reasoning-class]`. A `suggested_model?: string` alongside `model_tier` would be additive (`additionalProperties: true` in current schema).

---

## Recommended Hook Points (by 4-layer position)

```
LAYER 1 — EIIS (install contract)
  → human: Decide whether EIIS v1.5 adds a contract clause: install.sh MUST accept
           --model <name> and substitute it into agent frontmatter.
           This is the cleanest boundary: Eidolons stay vendor-agnostic; the nexus
           passes the calibrated model down at sync time.

LAYER 2 — Eidolon repos (external)
  → SPECTRA: Spec the install.sh interface change: --model flag patches
             the `model:` line in the agent file being written; default
             falls back to the Eidolon's hardcoded value.
  → human: All 7 Eidolon repos need coordinated releases once the contract
           is specced. ATLAS and FORGE currently omit `model:` — they need
           a default added too.

LAYER 3 — Nexus (this repo) — primary implementation surface
  New file: roster/models.yaml
    Per-Eidolon suggested + default model by capability class.
    Schema: schemas/models.schema.json (new).
    Invariant: uses capability-class-scoped names (e.g. haiku, sonnet, opus)
    NOT vendor IDs, to preserve prime-directive #162.

  New file: eidolons.models.lock (or section in eidolons.lock)
    Per-project active model per Eidolon.
    Generated by 'eidolons model sync' (or folded into eidolons sync).

  Schema additions (additive, non-breaking):
    schemas/eidolons.yaml.schema.json — members[].model?: string
    schemas/eidolons.lock.schema.json — members[].model_resolved?: string
    schemas/roster-entry.schema.json — models?: {suggested, default_concrete?}
    schemas/routing.schema.json — per-eidolon suggested_model?: string

  New CLI surface (mirror mcp use pattern):
    cli/eidolons — add 'model' to top-level verb allowlist
    cli/src/model.sh — sub-dispatcher (list|show|set|use|reset|sync)
    cli/src/model_use.sh — switch model for one Eidolon per-project
      (reads roster/models.yaml catalogue; writes eidolons.lock model_resolved)
    cli/src/model_sync.sh — reapply all model_resolved values to agent files
      (called from sync.sh after per-Eidolon install.sh runs)

  sync.sh modification:
    After run_installer_captured, if model_resolved for member exists in lock,
    patch `model:` in the written agent file(s) in place.
    Pattern: same awk strategy as _mcp_wiring_patch_claude_code in lib_mcp_wiring.sh.

  doctor.sh addition:
    D9 — model field in .claude/agents/<n>.md matches eidolons.lock model_resolved.
    If eidolons.lock has no model_resolved, skip (Eidolon-default is authoritative).

LAYER 4 — Consumer project
  eidolons.yaml member shape gains optional 'model' field:
    members:
      - name: spectra
        version: ^4.8.0
        model: sonnet    # override: use sonnet instead of default opus
  eidolons.lock gains model_resolved per member.
  User-facing: 'eidolons model use spectra@sonnet' (analogous to mcp use).
```

---

## Risks and Gaps

**RISK-1 (H):** The `model:` field is baked into each Eidolon's `install.sh` as a hardcoded string. Without an EIIS contract change, the nexus can only patch it post-install (fragile awk surgery on agent files), not pass it cleanly at install time. EIIS contract change is the prerequisite.

**RISK-2 (M):** ATLAS and FORGE currently have no `model:` in their claude-code agent files (host default applies). Adding model management requires agreeing on a default for them too.

**RISK-3 (M):** opencode agent format support for `model:` is not confirmed by local evidence. opencode agent templates currently omit it. Needs a check against the opencode schema docs before adding wiring.

**RISK-4 (L):** copilot and cursor have no per-agent model concept. Model management will silently be a no-op for those hosts. This should be explicit in the feature spec.

**GAP-1:** Did not inspect `cli/src/run.sh` lines 130–220 (the full jq kernel) for any concrete model resolution logic beyond `model_tier_per_step`. Confidence H that none exists (all probes found only tier references), but the full jq program was not exhaustively read.

**GAP-2:** Did not inspect opencode's format spec to confirm whether it supports `model:` in agent frontmatter. Three-strike reached; marked L-confidence.

---

## Telemetry

```
phase: A  | tool_calls: 3
phase: T  | tool_calls: 6
phase: L  | tool_calls: 24
phase: S  | tool_calls: 1 (write)
total_tool_calls: 34
```

# SPEC: Model Management for the Eidolons nexus

- **Status:** decision-ready (SPECTRA, 2026-06-09)
- **Owner of decisions:** locked by orchestrator + FORGE decision record (this spec does not relitigate)
- **Implementer:** APIVR-Δ (coder), single track, sequenced work packages
- **Scope:** nexus only — roster data, schemas, `eidolons` CLI surface, sync-time frontmatter wiring, doctor gate, cortex vocabulary. **No EIIS contract change** (future follow-up).

> Anchors marked `[verify]` are from the ATLAS scout / task brief and MUST be re-confirmed against the tree at implement time.

---

## 0. Problem & shape

Today the routing kernel carries a **binary** `model_tier` (speed/reasoning) per Eidolon in `roster/routing.yaml`, consumed by `cli/src/run.sh`. There is no vendor-neutral abstraction, no consumer-side override, no way to switch providers, and no mechanism to write a concrete `model:` into host agent frontmatter. Vendor model strings would, if placed in routing/cortex, violate prime-directive #162 (no vendor model names in the always-loaded cortex) and break `cli/tests/cortex.bats` "EIDOLONS.md has no vendor model names".

**Solution (locked):** a vendor-neutral ordered tier ladder **`light < standard < deep`**; a NEW nexus file `roster/model-profiles.yaml` as the **sole** home for vendor model strings; named provider **profiles** mapping the three tiers → concrete models; per-Eidolon assignment is a **tier**, with a per-Eidolon **model pin** as the escape hatch. The nexus resolves an **effective model** per Eidolon and patches host agent frontmatter (claude-code, codex) at sync time via idempotent awk surgery — mirroring the MCP `tools:` wiring.

### 0.1 Vocabulary (binding)

| Term | Meaning |
|---|---|
| **tier** | ordered ladder member: `light` `<` `standard` `<` `deep`. The vendor-neutral unit of assignment. |
| **profile** | named provider mapping `{light,standard,deep} → model string`, declared in `roster/model-profiles.yaml`. Ships `anthropic` (default) + `openai`. |
| **suggested tier** | the tier a roster Eidolon ships with (shown in UX). At the tier layer, **suggested ≡ default**. |
| **calibration** | consumer-side per-tier model override **within** the active profile (`eidolons.yaml` → `models.calibration`). |
| **pin** | consumer-side per-Eidolon concrete model, ignores tiers/profile entirely (`models.members.<id>.model`). |
| **effective model** | fully resolved concrete model string per Eidolon; persisted in `eidolons.lock`; written to frontmatter. |

### 0.2 Resolution precedence (most-specific wins — binding)

```
1. per-Eidolon user model PIN           (eidolons.yaml models.members.<id>.model)
2. per-tier user CALIBRATION            (eidolons.yaml models.calibration.<tier>, within active profile)
3. active PROFILE selection             (eidolons.yaml models.profile, else roster default_profile)
4. per-Eidolon roster TIER override     (routing.yaml <id>.suggested_tier)
5. class suggested TIER                 (routing.yaml class default, when an Eidolon has none)
6. nexus default profile                (model-profiles.yaml default_profile) — fallback for profile only
```

Layers 3 and 6 select the *profile*; layers 1, 2, 4, 5 select the *tier-or-model*. The effective model = `pin` if present, else `profile[tier]` where `tier` resolves via 4→5 and `profile[tier]` honors calibration override at layer 2.

---

## 1. Data model / schema changes

### 1.1 NEW: `roster/model-profiles.yaml`

The **sole** home for vendor model strings. Vendor strings appear nowhere else in the nexus.

```yaml
# roster/model-profiles.yaml
# SOLE home for vendor model strings (prime-directive #162). Do not put model
# strings in routing.yaml, index.yaml, EIDOLONS.md, or any cortex file.
schema_version: 1
default_profile: anthropic

profiles:
  anthropic:
    description: "Anthropic Claude family"
    applies_to_hosts: [claude-code]
    tiers:
      light:    haiku
      standard: sonnet
      deep:     opus
  openai:
    description: "OpenAI GPT-5 family"
    applies_to_hosts: [codex]
    tiers:
      light:    gpt-5-mini
      standard: gpt-5
      deep:     gpt-5
```

**Extensibility proof (zero code change):** adding a `google` profile is pure data —

```yaml
  google:
    description: "Google Gemini family"
    applies_to_hosts: [claude-code]   # whichever hosts accept these strings
    tiers:
      light:    gemini-flash
      standard: gemini-pro
      deep:     gemini-ultra
```

The resolution lib (§2) reads `profiles.<name>.tiers.<tier>` by flat-key lookup; no enum of profile names is hardcoded.

**`applies_to_hosts` semantics:** the list of host environments for which this profile's model strings are valid identifiers. Used by the write-adapter (§4) to decide whether to write `model:` for a given (profile, host) pair. If the active profile does **not** apply to a wired host, the adapter **skips that host with a warning** (does NOT write an invalid model string).

### 1.2 NEW: `schemas/model-profiles.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://eidolons.dev/schemas/model-profiles.schema.json",
  "title": "Eidolons model profiles",
  "type": "object",
  "required": ["schema_version", "default_profile", "profiles"],
  "additionalProperties": false,
  "properties": {
    "schema_version": { "type": "integer", "const": 1 },
    "default_profile": { "type": "string", "minLength": 1 },
    "profiles": {
      "type": "object",
      "minProperties": 1,
      "patternProperties": {
        "^[a-z][a-z0-9-]*$": {
          "type": "object",
          "required": ["tiers"],
          "additionalProperties": false,
          "properties": {
            "description": { "type": "string" },
            "applies_to_hosts": {
              "type": "array",
              "items": { "type": "string", "enum": ["claude-code", "codex"] },
              "uniqueItems": true
            },
            "tiers": {
              "type": "object",
              "additionalProperties": false,
              "minProperties": 1,
              "properties": {
                "light":    { "type": "string", "minLength": 1 },
                "standard": { "type": "string", "minLength": 1 },
                "deep":     { "type": "string", "minLength": 1 }
              }
            }
          }
        }
      },
      "additionalProperties": false
    }
  }
}
```

> Note: a profile MAY omit a tier (e.g. only `standard`+`deep`). Resolution then **resolves UP** (§2.4). The schema permits `minProperties: 1` for `tiers`, not all three.

**Cross-check:** `default_profile` MUST name an existing key in `profiles`. JSON Schema can't express this; add a structural assertion to `make schema` (jq: assert `.profiles[.default_profile]` is non-null) and a `model-profiles.bats` test (§7).

### 1.3 `roster/routing.yaml` — MIGRATE `model_tier` → `suggested_tier`

**Decision: MIGRATE (rename), do not dual-carry.** Rationale:
- Dual-carrying (`model_tier` + `suggested_tier`) creates two sources of truth and a drift surface; the routing kernel must stay deterministic and minimal.
- `model_tier` is binary (speed/reasoning) and incompatible with the 3-way ladder; keeping it implies a mapping layer nobody wants.
- Blast radius is contained: the only consumer is `run.sh` (and any cortex/test references). The migration touches `run.sh`'s read of the field once.

Migration value map (binary → ladder), applied once during the roster edit:

| old `model_tier` | new `suggested_tier` |
|---|---|
| `reasoning-class` | `deep` |
| `speed-class` | `light` |
| (absent) | inherit class default |

After migration, **apply the FORGE criteria-derived defaults** (these are the authoritative per-Eidolon tiers, not a mechanical translation):

```yaml
# roster/routing.yaml  (illustrative shape — confirm existing structure)
eidolons:
  spectra:  { suggested_tier: deep }
  forge:    { suggested_tier: deep }
  vigil:    { suggested_tier: deep }
  atlas:    { suggested_tier: standard }
  apivr:    { suggested_tier: standard }   # coder; deep is benchmark-GATED (see loop_native hook)
  idg:      { suggested_tier: light }
  kupo:     { suggested_tier: light }

# class-level defaults (used when an Eidolon has no per-id suggested_tier)
classes:
  default: { suggested_tier: standard }    # new/unknown capability class
```

> NOTE: the existing routing.yaml carries `model_tier` *inside* each per-Eidolon entry alongside `capability_class`, `trigger_verbs`, etc. — keep that nesting; just rename the field and revalue. The `classes:` block is NEW (additive); place it as a sibling top-level key.

**Coder promotion hook (documented, not hardcoded):** APIVR-Δ ships at `standard`. Add an inert, documented marker so the deep promotion is a one-line data flip post-benchmark, never a code change:

```yaml
  apivr:
    suggested_tier: standard
    loop_native: false        # promotion hook: flip to deep is benchmark-GATED
                              # see project_coder_7_5_augmentation / project_apivr_overhaul
```

`loop_native` is advisory metadata for humans/UX (shown in `model show` as a note); the resolver ignores it. Do NOT wire it into resolution in this scope.

**`run.sh` change:** `run.sh` reads `.model_tier` in its jq kernel (the `model_tier_per_step` output, ~lines 133/187/197/207). Change those jq paths to `.suggested_tier`. The kernel only *passes through* the tier value into the routing artifact (`model_tier_per_step`) — it does not branch on the literal — so the migration is a field-name swap plus updating the emitted key name if desired (keep `model_tier_per_step` as the artifact key for back-compat, or rename to `suggested_tier_per_step` and update run.bats; RECOMMEND keep the artifact key name to minimize churn, only change the source field path). Keep `run.sh` reading the *tier* only — it must NOT learn about profiles or vendor strings.

### 1.4 `schemas/routing.schema.json` — field/enum update

- Rename the per-Eidolon property `model_tier` → `suggested_tier` (currently `required` with enum `["speed-class","reasoning-class"]`).
- Constrain: `"suggested_tier": { "type": "string", "enum": ["light", "standard", "deep"] }`.
- Add optional `"loop_native": { "type": "boolean" }` to the per-Eidolon properties.
- The eidolons object uses `additionalProperties: true`, so the additive `loop_native` is safe even if not declared; declare it anyway for documentation.

### 1.5 `schemas/eidolons.yaml.schema.json` — consumer `models:` block

New optional top-level `models` object:

```jsonc
"models": {
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "profile": { "type": "string", "minLength": 1 },        // active profile name
    "calibration": {                                         // per-tier override within active profile
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "light":    { "type": "string", "minLength": 1 },
        "standard": { "type": "string", "minLength": 1 },
        "deep":     { "type": "string", "minLength": 1 }
      }
    },
    "members": {                                             // per-member tier override and/or pin
      "type": "object",
      "patternProperties": {
        "^[a-z][a-z0-9-]*$": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "tier":  { "type": "string", "enum": ["light", "standard", "deep"] },
            "model": { "type": "string", "minLength": 1 }    // PIN (highest precedence)
          }
        }
      }
    }
  }
}
```

Example consumer `eidolons.yaml` excerpt:

```yaml
models:
  profile: anthropic
  calibration:
    deep: opus           # override the profile's deep mapping for THIS project
  members:
    spectra: { tier: deep }          # tier override (still resolves via profile/calibration)
    apivr:   { model: sonnet }       # PIN — ignores tier/profile/calibration entirely
```

### 1.6 `schemas/eidolons.lock.schema.json` — `effective_model` + provenance

Each per-member lock entry gains an optional `model` object recording the resolved outcome and how it was reached:

```jsonc
"model": {
  "type": "object",
  "additionalProperties": false,
  "required": ["effective_model", "tier", "profile", "source"],
  "properties": {
    "effective_model": { "type": "string", "minLength": 1 },
    "tier":            { "type": "string", "enum": ["light", "standard", "deep"] },
    "profile":         { "type": "string", "minLength": 1 },
    "source": {
      "type": "string",
      "enum": ["pin", "calibration", "profile", "roster-tier", "class-default"]
    }
  }
}
```

`source` mirrors the winning precedence layer (§0.2): `pin`(1) / `calibration`(2) / `profile`(3 base mapping) / `roster-tier`(4) / `class-default`(5). When a pin wins, `tier` records the tier the Eidolon would otherwise have had (informational); `effective_model` is the pinned string. The lock member items object must not be `additionalProperties:false` (it isn't today) so the field is additive-safe.

### 1.7 `schemas/roster-entry.schema.json` — SINGLE source of truth for tier

**Decision: the per-Eidolon suggested tier lives in `roster/routing.yaml`, NOT `roster/index.yaml`.** Justification:
- Routing already owns per-Eidolon dispatch metadata (`model_tier` today); tier is a routing concern, not an identity/version concern.
- `index.yaml` is the identity/versions/source-of-truth registry; adding a behavioral knob there splits ownership and forces both roster CI workflows to validate a duplicated field.
- One source of truth keeps the resolver and tests simple.

**Therefore: do NOT add a tier field to `roster-entry.schema.json`.** No change to `roster-entry.schema.json` in this scope. (Document this explicitly so a future contributor doesn't "helpfully" mirror it into `index.yaml`.)

---

## 2. Resolution algorithm (bash 3.2-safe)

Implemented in a new lib **`cli/src/lib_model_resolve.sh`** (sourced like `lib.sh`). **No `declare -A`, no `${var,,}`/`${var^^}`, no `readarray`/`mapfile`** (macOS bash 3.2 — see CLAUDE.md "Bash 3.2 compatibility"; commits `116df8f`/`6a5689a`).

### 2.1 Inputs (all via `yaml_to_json` → jq, the established pattern)

- `routing.json` ← `yaml_to_json roster/routing.yaml`
- `profiles.json` ← `yaml_to_json roster/model-profiles.yaml`
- `consumer.json` ← `yaml_to_json eidolons.yaml` (the `models` block)
- list of member ids ← `roster_list_names` / the consumer manifest members

### 2.2 Flat-key lookup strategy (NO associative arrays)

The profile→tier→model map is read **directly from JSON via jq** at each lookup — no in-shell map structure needed. This sidesteps bash 3.2 entirely:

```sh
# resolve a single (profile,tier) -> model string, with resolve-UP fallback
model_profile_lookup() {            # args: <profile> <tier>; reads $PROFILES_JSON
  _p="$1"; _t="$2"
  _m=$(printf '%s' "$PROFILES_JSON" | jq -r --arg p "$_p" --arg t "$_t" \
        '.profiles[$p].tiers[$t] // empty')
  if [ -n "$_m" ]; then printf '%s\n' "$_m"; return 0; fi
  # resolve-UP: light->standard->deep (over-provision; FORGE-approved)
  case "$_t" in
    light)    model_profile_lookup "$_p" standard; return $? ;;
    standard) model_profile_lookup "$_p" deep;     return $? ;;
    deep)     return 1 ;;   # nothing above deep -> hard miss
  esac
}
```

If even `deep` is absent (malformed profile), return non-zero → caller fails the resolve with a clear error (doctor/`model show` surface it).

### 2.3 Per-Eidolon resolution (precedence-ordered)

```sh
model_resolve_for() {               # arg: <eidolon-id>; echoes "model<TAB>tier<TAB>profile<TAB>source"
  _id="$1"

  # active profile (layer 3, else roster default = layer 6)
  _profile=$(printf '%s' "$CONSUMER_JSON" | jq -r '.models.profile // empty')
  [ -z "$_profile" ] && _profile=$(printf '%s' "$PROFILES_JSON" | jq -r '.default_profile')

  # 1. PIN
  _pin=$(printf '%s' "$CONSUMER_JSON" | jq -r --arg id "$_id" '.models.members[$id].model // empty')
  if [ -n "$_pin" ]; then
    _tier=$(model_tier_for "$_id")
    printf '%s\t%s\t%s\t%s\n' "$_pin" "$_tier" "$_profile" "pin"; return 0
  fi

  # tier (member tier override > roster tier > class default)
  _tier=$(model_tier_for "$_id")
  _src_tier=$(model_tier_source "$_id")            # roster-tier | class-default

  # 2. CALIBRATION (per-tier override within active profile)
  _cal=$(printf '%s' "$CONSUMER_JSON" | jq -r --arg t "$_tier" '.models.calibration[$t] // empty')
  if [ -n "$_cal" ]; then
    printf '%s\t%s\t%s\t%s\n' "$_cal" "$_tier" "$_profile" "calibration"; return 0
  fi

  # 3. PROFILE base mapping (with resolve-UP)
  if _m=$(model_profile_lookup "$_profile" "$_tier"); then
    printf '%s\t%s\t%s\t%s\n' "$_m" "$_tier" "$_profile" "$_src_tier"; return 0
  fi
  return 1   # hard miss -> caller errors
}
```

`model_tier_for` precedence for the **tier** value:

```sh
model_tier_for() {                  # arg: <id>
  _id="$1"
  _t=$(printf '%s' "$CONSUMER_JSON" | jq -r --arg id "$_id" '.models.members[$id].tier // empty')
  [ -n "$_t" ] && { printf '%s\n' "$_t"; return 0; }
  _t=$(printf '%s' "$ROUTING_JSON" | jq -r --arg id "$_id" '.eidolons[$id].suggested_tier // empty')
  [ -n "$_t" ] && { printf '%s\n' "$_t"; return 0; }
  printf '%s' "$ROUTING_JSON" | jq -r '.classes.default.suggested_tier // "standard"'
}
```

`model_tier_source` returns `roster-tier` when the routing per-id value won, else `class-default`.

### 2.4 Missing-tier behavior — **resolve UP (over-provision)** (FORGE-approved)

`light` missing → try `standard` → try `deep`. Never resolve DOWN. Hard miss only when `deep` itself is absent → error. Rationale: over-provisioning is a cost/latency penalty; under-provisioning is a *capability* failure; prefer the safe direction.

### 2.5 Host-applicability (profile vs wired host)

For each wired host (via `detect_hosts`/lock `hosts_wired`), the write-adapter (§4) checks `profiles.<active>.applies_to_hosts`. If the host is absent, the adapter **skips writing `model:` for that host's agent files and emits a warning**. *Resolution* still produces an effective model for the lock; only the **frontmatter write** is host-gated.

### 2.6 Determinism

Resolution is pure data → no randomness, no time dependence. Same inputs → same `effective_model`. Idempotency at the lock and frontmatter layers follows from this plus canonical serialization (§4.3).

---

## 3. CLI surface — `eidolons model`

### 3.1 Dispatch wiring (the dual-allowlist trap)

Mirror the `mcp` verb family precisely. **Two edits are required** (MEMORY: "`cli/eidolons` has a SEPARATE mcp-verb allowlist from `cli/src/mcp.sh`"):

1. **`cli/eidolons`** top-level verb allowlist: add `model` so it `exec`s `cli/src/model.sh`.
2. **NEW `cli/src/model.sh`** sub-dispatcher: parse the first arg into `list|show|use|reset|profile`, with a **bare** invocation (`eidolons model`) launching the interactive picker (§3.4). Source `cli/src/lib.sh` + `cli/src/lib_model_resolve.sh` + `cli/src/ui/prompt.sh`.

`cli/src/model.sh` MUST carry its **own** internal sub-verb allowlist (mirror `cli/src/mcp.sh`), so unknown subs fail with usage + exit 2.

### 3.2 Usage text

```
eidolons model                         Interactive guided picker (TTY) / usage (non-interactive)
eidolons model list                    List profiles (mark active) + tier ladder + vendor mappings
eidolons model show [<eidolon>]        Show resolved model(s): eidolon | tier | profile | source | effective
eidolons model use <eidolon>@<tier>    Set per-member tier override (consumer eidolons.yaml)
eidolons model use <eidolon>@<model>   Pin a concrete model for one eidolon (escape hatch)
eidolons model profile <name>          Set the active profile; re-resolve all; rewrite frontmatter
eidolons model reset [<eidolon>]       Clear member override/pin (all members if no arg)

Flags:
  --non-interactive   Never prompt; bare `model` prints usage and exits 0
  --json              (show/list) machine-readable output
  --dry-run           (use/profile/reset) resolve + print diff; do NOT write lock/frontmatter
```

### 3.3 Subcommand semantics, args, exit codes

**`model list`** — reads `model-profiles.yaml`; prints each profile (name, description, `applies_to_hosts`, tier→model rows), marking the active profile. `--json` emits the profiles object. Exit `0`; `1` profiles file missing/invalid.

**`model show [<eidolon>]`** — no arg: table for all roster members → `eidolon | suggested_tier | effective_tier | profile | source | effective_model` (+ `loop_native` note). With `<eidolon>`: single-row precedence trace. `--json` emits array. Exit `0`; `2` unknown eidolon; `1` resolve hard-miss.

**`model use <eidolon>@<tier|model>`** — parse `@`. RHS ∈ `{light,standard,deep}` → write `models.members.<id>.tier`; else → **model pin** → `models.members.<id>.model`. Update `eidolons.yaml` (jq/yq merge), re-resolve, update `eidolons.lock`, patch frontmatter (§4) for that member's wired host agent file(s). `--dry-run` prints diff, writes nothing. Exit `0`; `2` bad eidolon/`@arg`; `3` resolve produced no model; `4` frontmatter write failed.

**`model profile <name>`** — validate `<name>` exists (else exit 2). Set `eidolons.yaml models.profile`. Re-resolve **all** → rewrite lock → re-patch frontmatter (host-gated by `applies_to_hosts`). Exit `0`; `2` unknown profile; `4` write failure.

**`model reset [<eidolon>]`** — no arg: clear `models.members.*` AND `models.calibration` (profile selection retained). With `<eidolon>`: clear only that member's `tier`+`model`. Re-resolve + update lock + frontmatter. Exit `0`; `2` unknown eidolon.

### 3.4 Interactive guided picker (bare `eidolons model`)

Mirror `ui_pick_hosts` and the vendor-path picker in `cli/src/ui/prompt.sh`. Flow:

1. **Guard:** if `--non-interactive` OR not a TTY (`[ -t 0 ]`/`[ -t 1 ]`, mirror `ui_pick_hosts`) → print usage and **exit 0** (NEVER prompt).
2. Render the resolved table (same columns as `model show`).
3. Menu: `[1] Change an Eidolon's tier  [2] Pin a model  [3] Change active profile  [4] Reset overrides  [q] Quit`.
4. **Change tier:** pick Eidolon (numbered, mirror `ui_pick_hosts`), then pick tier. Apply == `model use <id>@<tier>`.
5. **Pin model:** pick Eidolon, then pick from active profile's tier values or free-text (validated non-empty). Apply == `model use <id>@<model>`.
6. **Change profile:** numbered list (mark active). Apply == `model profile <name>`.
7. **Reset:** confirm, then `model reset`.
8. After each apply, re-render the table. `q` exits 0. All prompts via `ui_*`; logs to **stderr**, machine output only on `--json`.

---

## 4. Frontmatter write-adapter

### 4.1 Location & trigger

- **NEW lib `cli/src/lib_model_wiring.sh`**, mirroring `cli/src/lib_mcp_wiring.sh` (`_mcp_wiring_patch_claude_code`). Functions: `model_wiring_patch_claude_code`, `model_wiring_patch_codex`, `model_wiring_noop_host`.
- **Invoked from `cli/src/sync.sh`** in the post-install/wiring phase (same point MCP `tools:` wiring runs). Also invoked directly by `model use`/`model profile`/`model reset` for immediate effect.
- **Host scoping:** patch only `claude-code` (`.claude/agents/<id>.md`) and `codex` (`.codex/agents/<id>.md`). **Explicit NO-OP for copilot & cursor.** `model_wiring_noop_host` logs `info` and returns 0.

### 4.2 The awk surgery (managed-key sentinel)

Insert/replace, inside the YAML frontmatter block, two managed lines:

```
# eidolons:managed model
model: <effective_model>
```

Rules (mirror `_mcp_wiring_patch_claude_code`): the sentinel comment is the idempotency anchor; if present, replace the following `model:` line in place; if absent, insert both lines immediately after the opening `---`. A `model:` without the sentinel = hand-authored (drift policy §4.4). awk operates only within the frontmatter fence (first `^---$` … next `^---$`); never touch the body. Write via temp file + atomic mv, preserving file mode.

Idempotent skeleton (bash 3.2 / awk, no GNU-isms):

```sh
model_wiring_patch_claude_code() {   # args: <agent-file> <effective_model>
  _f="$1"; _m="$2"
  awk -v model="$_m" '
    BEGIN { infm=0; seen_fence=0; done_key=0 }
    /^---[[:space:]]*$/ {
      if (seen_fence==0) { seen_fence=1; infm=1; print; next }
      else if (infm==1) {
        if (done_key==0) { print "# eidolons:managed model"; print "model: " model; done_key=1 }
        infm=0; print; next
      }
    }
    {
      if (infm==1 && $0=="# eidolons:managed model") {
        print; getline; print "model: " model; done_key=1; next
      }
      print
    }
  ' "$_f" > "$_f.tmp" && mv "$_f.tmp" "$_f"
}
```

> The coder MUST diff this against the real `_mcp_wiring_patch_claude_code` and adopt its exact fence-detection + temp/mv + permission-preserving idioms. Codex variant differs only in path — confirm codex frontmatter is YAML-fenced `---`; branch if not.

### 4.3 Canonical serialization (idempotency)

Managed lines written in fixed order at a fixed position. Re-running with the same effective model → byte-identical file → repeat `sync` is a no-op (satisfies the idempotency invariant + the "Second install run is idempotent" CI class). Compare-before-write: if the file already contains exactly the managed block with the same value, skip the write.

### 4.4 Conflict / drift policy — **warn-and-preserve on hand-edit; clobber-on-explicit-command**

- **Sync-time (`eidolons sync`):** a `model:` without the sentinel = hand-edit → **warn and preserve** (don't overwrite, don't fail sync). Matches MCP `tools:` wiring respecting user content.
- **Explicit command (`model use`/`profile`/`reset`):** the verb is consent → **clobber** any existing `model:` with the managed block.
- **Doctor (§5):** reports drift; does not auto-fix.

---

## 5. doctor gate — D-model

New gate in `cli/src/doctor.sh` (use the repo's actual next gate id).

**Scope:** runs only when a `models` block is present and non-trivial. Else **SKIP** (status `skip`).

**Check:** for each wired claude-code/codex member agent file, parse frontmatter `model:` (managed line) and compare to `eidolons.lock` `model.effective_model`.

**Semantics:**
- **PASS:** every applicable file's `model:` == lock `effective_model` (also pass when a profile doesn't apply to a host and the file correctly has no managed `model:`).
- **WARN:** hand-authored `model:` without sentinel, OR a host-inapplicable file unexpectedly carries a managed line. Non-fatal.
- **FAIL:** managed `model:` (sentinel present) ≠ lock `effective_model`. Fatal in `doctor --deep`.

Output mirrors existing gates; include in the `--deep` static suite.

---

## 6. Cortex updates

**Invariant I-C3 (binding):** no vendor model strings in `EIDOLONS.md` or any `methodology/cortex/*`. Vendor strings live ONLY in `roster/model-profiles.yaml`. Preserves `cli/tests/cortex.bats` "no vendor model names" + PD #162.

**`EIDOLONS.md`:** introduce the tier ladder vocabulary only — "Each Eidolon resolves to a tier `light < standard < deep`; the concrete model per tier is set by the active profile in `roster/model-profiles.yaml`." Mention `eidolons model`. Do NOT name haiku/sonnet/opus/gpt-5. Keep ≤900-token budget — one compact sentence + pointer. Change any binary speed/reasoning wording to the ladder term.

**`methodology/cortex/trance-matrix.md`:** replace binary `model_tier` references with the ladder. Add a short "Model tiers" subsection (ladder definition + FORGE per-class defaults by tier name only, NO vendor strings + precedence summary, pointing to this spec). Reference `eidolons model show`.

**Verify:** `cli/tests/cortex.bats` must still pass (no-vendor + token-budget). Extend it to assert the ladder words exist and no profile tier-value strings appear in the cortex.

---

## 7. Test plan (bats — mirror `mcp_use.bats`)

**`cli/tests/model_resolve.bats`** (new): default install resolves FORGE defaults (spectra/forge/vigil→deep, atlas/apivr→standard, idg/kupo→light); precedence pin>calibration>profile-base (toggle one layer at a time); resolve-UP on missing tier (standard+deep only → light resolves to standard; deep-only → all deep; missing deep → hard error); unknown class → standard; host-inapplicable profile still resolves (lock) but write skipped (warning, no file write).

**`cli/tests/model_cli.bats`** (new, mirror `mcp_use.bats`): `model list` shows both profiles+active; `model show` table+`--json`, unknown eidolon→2; `use spectra@standard` sets `members.spectra.tier`; `use apivr@<model>` sets pin, `source:pin`; `profile openai` re-resolves, unknown→2; `reset spectra`/`reset` clear; `--non-interactive` bare prints usage, exits 0, never blocks; `--dry-run` no mutation.

**`cli/tests/model_wiring.bats`** (new): `use spectra@standard` rewrites `.claude/agents/spectra.md` with sentinel + `model: sonnet`; idempotency (repeat = byte-identical, checksum); profile switch rewrites all; copilot-only project no-op exit 0; cursor no-op; codex `.codex/agents/<id>.md` gets managed block under openai; drift (hand-authored preserved on sync/warn; clobbered on explicit `use`).

**`cli/tests/doctor.bats`** (extend): D-model SKIP (no models block); PASS (match); FAIL (managed drift, `--deep`); WARN (hand-edit drift).

**`cli/tests/model_profiles.bats`** (new): `roster/model-profiles.yaml` validates vs schema (jq empty, matching `make schema`); `default_profile` exists; anthropic+openai with exact mappings; a `google` fixture validates with zero code change.

**`make schema` / schema checks** (extend): new schema lints; routing `suggested_tier` enum; eidolons.yaml/lock additive blocks validate.

**`cli/tests/cortex.bats`** (extend, don't break): "no vendor model names" still passes; add positive assertion ladder words present + no profile tier-value strings in cortex.

**`cli/tests/run.bats`** (extend): `run.sh` reads `suggested_tier`; ladder values accepted; binary values absent.

---

## 8. GIVEN / WHEN / THEN acceptance criteria

1. **Default resolution.** No `models` block, anthropic default, migrated tiers → `model show`: spectra/forge/vigil `deep→opus`, atlas/apivr `standard→sonnet`, idg/kupo `light→haiku`; lock `source: roster-tier` (or `class-default`).
2. **Tier override rewrites frontmatter.** claude-code wired, anthropic → `model use spectra@standard` → `eidolons.yaml` `models.members.spectra.tier: standard`, lock `effective_model == sonnet`, `.claude/agents/spectra.md` has sentinel + `model: sonnet`.
3. **Profile switch re-resolves all.** codex wired → `model profile openai` → all re-resolve to openai (deep/standard→gpt-5, light→gpt-5-mini), lock updates, `.codex/agents/*.md` get managed lines, `.claude/agents/*` skipped-with-warning (openai `applies_to_hosts` excludes claude-code).
4. **Pin overrides everything.** `model use apivr@sonnet` → lock `effective_model==sonnet`, `source:pin`, regardless of profile/calibration/tier.
5. **Calibration within profile.** `models.calibration.deep: opus` + openai active → `model show spectra` (deep) → `opus`, `source:calibration`.
6. **Resolve-UP on missing tier.** Profile with only standard+deep → idg (light) → resolves UP to standard; never down.
7. **Idempotent repeat.** Wiring applied → re-run `sync` unchanged → no file changes (byte-identical, lock unchanged).
8. **Copilot/cursor clean no-op.** copilot-only (or cursor) project → any `use`/`sync` → exit 0, info no-op log, NO frontmatter written.
9. **Doctor catches managed drift.** managed `model:` hand-mutated ≠ lock → `doctor --deep` FAILs (names file/expected/found).
10. **Doctor preserves hand-edit.** hand-authored `model:` no sentinel → `sync` preserves + warns; `doctor` WARNs.
11. **Non-interactive guard.** no TTY/`--non-interactive` → bare `eidolons model` prints usage, exit 0, no prompt.
12. **Cortex stays vendor-free.** `cortex.bats` after edits → "no vendor model names" passes; ladder words present.
13. **Extensibility, zero code.** add `google` profile to `model-profiles.yaml` only → `model profile google && model show` works, no code change.

---

## 9. Phased implementation (ordered, each independently testable)

- **WP1 — Schemas.** Add `schemas/model-profiles.schema.json`; update `routing.schema.json` (`suggested_tier` enum + `loop_native`); extend `eidolons.yaml.schema.json` (`models`) + `eidolons.lock.schema.json` (`model` provenance). `roster-entry.schema.json` unchanged (document). **Test:** `make schema`, `model_profiles.bats` validity.
- **WP2 — Roster data.** Create `roster/model-profiles.yaml` (anthropic+openai, `default_profile: anthropic`). Migrate `routing.yaml` `model_tier`→`suggested_tier`, apply FORGE defaults + `apivr.loop_native:false`, add `classes.default`. Update `run.sh`. **Test:** `model_profiles.bats`, `run.bats`.
- **WP3 — Resolution lib.** `cli/src/lib_model_resolve.sh`. **FLAG: jq flat-key lookup, NO `declare -A`, NO `${var,,}`.** **Test:** `model_resolve.bats`.
- **WP4 — CLI + picker.** `cli/src/model.sh` (`list|show|use|reset|profile` + bare→picker); add `model` to `cli/eidolons` allowlist AND `model.sh`'s sub-allowlist. Picker mirrors `ui_pick_hosts`. **Test:** `model_cli.bats`, non-interactive guard.
- **WP5 — Sync wiring.** `cli/src/lib_model_wiring.sh` (claude-code+codex patchers, copilot/cursor no-op), invoked from `sync.sh` + CLI verbs. Idempotent awk + canonical serialization + compare-before-write + drift policy. **Test:** `model_wiring.bats`.
- **WP6 — Doctor gate.** D-model in `doctor.sh`. **Test:** `doctor.bats`.
- **WP7 — Cortex.** `EIDOLONS.md` + `trance-matrix.md` (ladder vocab, vendor-free). **Test:** `cortex.bats`.
- **WP8 — Docs/CHANGELOG.** README/architecture note on `eidolons model`; `CHANGELOG.md`; nexus minor bump per release-nexus flow. Note EIIS follow-up.
- **WP9 — Full suite.** `make test`, `make schema`, `make lint` green; bash-3.2 (cli-tests macos-latest).

Deps: WP1→WP2→WP3→{WP4,WP5}→WP6; WP7/WP8 after WP2; WP9 last.

---

## 10. Complexity & out-of-scope

**Complexity: 5.5/10** — high mechanical breadth (2 new schemas, 1 roster file, 1 routing migration, 3 new libs, 1 CLI verb-family, sync/doctor/cortex edits), low design risk (mirrors MCP `use`/wiring + `ui_pick_hosts`). Real traps: bash-3.2 map, dual verb-allowlist, idempotency, cortex vendor-string invariant.

**Out of scope:** EIIS contract change (future follow-up); opencode model support (pending frontmatter-convention confirmation — treat as no-op); Google/Gemini profile (extensibility proven, not shipped); GAMBIT UI; per-tier cost/latency budgets/auto-tier/availability probing; APIVR-Δ deep promotion (benchmark-gated data flip).

See `model-management.acceptance.yaml` for the machine-readable acceptance block.

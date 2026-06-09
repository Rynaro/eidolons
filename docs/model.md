# `eidolons model` — vendor-neutral model management

> **See also:**
> - [`docs/architecture.md`](./architecture.md) — system layers and security model
> - [`EIDOLONS.md`](../EIDOLONS.md) — routing cortex and Eidolon tiers

---

## Overview

`eidolons model` is the management surface for binding each Eidolon to a concrete model. Eidolons themselves stay vendor-neutral — they are assigned a cognitive *tier* (`light`, `standard`, or `deep`), never a vendor model name (prime-directive #162: no vendor model names in any Eidolon methodology or the always-loaded cortex). The nexus owns the mapping from tier to model: it lives in `roster/model-profiles.yaml` as **profiles** (one per vendor), and the resolved model is written into the host agent's frontmatter as a managed block.

This decouples methodology from vendor choice — you can swap the active profile (e.g. Anthropic Claude → OpenAI) without touching any Eidolon's code or specification, and every member re-resolves in one command.

---

## Tier ladder

Eidolons resolve to three vendor-neutral tiers, ordered by cognitive demand:

| Tier | Cognitive load | Autonomy / loop-length | Failure cost |
|---|---|---|---|
| **light** | retrieval, parse, format | stateless / single-step | low |
| **standard** | planning, multi-step reasoning, tradeoffs | short loop, local retry | medium |
| **deep** | long-horizon synthesis, graph search, plan-revision | extended loop, re-scout | high |

The criteria: cognitive load + autonomy/loop-length + failure-cost push **up** the ladder; cost-sensitivity + throughput push **down**.

---

## Default tiers per Eidolon

The roster (`roster/routing.yaml`) assigns each Eidolon a **suggested tier**:

| Eidolon | Suggested tier | Rationale |
|---|---|---|
| **IDG** | light | documentation scriber; low load; cheap to re-run |
| **Kupo** | light | PROPOSE-only micro-task executor; high throughput |
| **ATLAS** | standard | read-only scout; bounded local reasoning |
| **APIVR-Δ** | standard | brownfield coder (deep is a benchmark-gated candidate — see `loop_native`) |
| **SPECTRA** | deep | spec composition; long reasoning; fans out to all downstream |
| **FORGE** | deep | structured deliberation; multi-hypothesis stress-testing |
| **VIGIL** | deep | root-cause graph search + counterfactual intervention |

A new/unknown capability class defaults to **standard**.

---

## Profiles

Vendor model strings live **only** in `roster/model-profiles.yaml` — the sole source of truth for concrete model identifiers (keeping the cortex and every Eidolon vendor-free). Each profile maps the three tiers to a vendor's lineup and declares which hosts its strings are valid for.

Two profiles ship by default (`default_profile: anthropic`):

```yaml
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

Adding another profile (e.g. Google Gemini) is **pure data** — a new entry in `roster/model-profiles.yaml`, no code change. The resolver reads `profiles.<name>.tiers.<tier>` by key; no profile names are hardcoded.

---

## Command surface

### `eidolons model` (interactive picker)

On a TTY with no arguments, opens a guided picker to change the active profile and per-member tiers/pins, re-rendering the resolved table after each change. When non-interactive (or no TTY), prints usage and exits 0 — it never blocks.

```bash
eidolons model
```

### `eidolons model list`

Shows the tier ladder, every profile (active one marked), and each profile's tier→model map.

```bash
eidolons model list
```

```
Tier ladder: light < standard < deep

Profiles:

  anthropic [active]
    Anthropic Claude family
    applies to: claude-code
    light       standard    deep
    haiku       sonnet      opus

  openai
    OpenAI GPT-5 family
    applies to: codex
    light       standard    deep
    gpt-5-mini  gpt-5       gpt-5
```

### `eidolons model show [<eidolon>]`

Tabulates every Eidolon (or one, if named): tier · profile · resolution source · effective model. `--json` for machine output.

```bash
eidolons model show
```

```
EIDOLON       TIER        PROFILE       SOURCE            EFFECTIVE MODEL
──────────────────────────────────────────────────────────────────────
apivr         standard    anthropic     roster-tier       sonnet
atlas         standard    anthropic     roster-tier       sonnet
forge         deep        anthropic     roster-tier       opus
idg           light       anthropic     roster-tier       haiku
kupo          light       anthropic     roster-tier       haiku
spectra       deep        anthropic     roster-tier       opus
vigil         deep        anthropic     roster-tier       opus
```

### `eidolons model use <eidolon>@<tier>`

Set a per-member tier override (`<tier>` ∈ `light` / `standard` / `deep`). Resolves through the active profile, writes `eidolons.yaml` + the lock, and patches frontmatter.

```bash
eidolons model use spectra@standard
```

```
✓ Set models.members.spectra.tier = standard
· Resolved: sonnet (tier=standard, profile=anthropic, source=roster-tier)
```

### `eidolons model use <eidolon>@<model>`

Pin a concrete model for one Eidolon — the escape hatch. Ignores tier, profile, and calibration; stored verbatim under `models.members.<id>.model`.

```bash
eidolons model use apivr@sonnet
```

```
✓ Set models.members.apivr.model = sonnet (PIN)
· Resolved: sonnet (tier=standard, profile=anthropic, source=pin)
```

### `eidolons model profile <name>`

Switch the active profile. All members re-resolve through the new profile and frontmatter is re-applied (host-gated — see below). Persisted under `models.profile`.

```bash
eidolons model profile openai
```

```
✓ Set models.profile = openai
✓ Re-applied model wiring for all members (profile=openai)
```

### `eidolons model reset [<eidolon>]`

Clear a member's tier override / pin. With no argument, clears **all** member overrides **and** per-tier calibration (the active profile selection is retained).

```bash
eidolons model reset spectra
eidolons model reset
```

### Flags & exit codes

- `--non-interactive` — never prompt; bare `model` prints usage and exits 0.
- `--json` — machine-readable output (`show` / `list`).
- `--dry-run` — resolve and print the diff without writing.

| Code | Meaning |
|---|---|
| 0 | success |
| 2 | bad arguments / unknown Eidolon or profile |
| 3 | resolve hard-miss (the active profile is missing the requested tier even after resolve-up) |
| 4 | frontmatter write failed |

---

## Resolution precedence

The **effective model** for an Eidolon is resolved most-specific-first.

1. **Per-member model PIN** (`models.members.<id>.model`) — wins outright; ignores everything below.

Otherwise a **tier** is determined (member tier override `models.members.<id>.tier` → roster `suggested_tier` → class default `standard`), then that tier is mapped to a model:

2. **Per-tier calibration** (`models.calibration.<tier>`) — overrides the profile's model for that tier, within the active profile.
3. **Active profile base mapping** (`models.profile`, else `roster/model-profiles.yaml` → `default_profile`) — the profile's `tiers.<tier>` value.

If a profile omits the requested tier, resolution **resolves up** (`light → standard → deep`) rather than down — over-provisioning is a cost penalty; under-provisioning is a capability failure.

### Terminology

- **Suggested tier** — the roster's recommended tier for an Eidolon; shown in `eidolons model show`.
- **Default** — what ships if you change nothing (suggested tier resolved through the default profile).
- **Effective model** — the fully resolved concrete model, persisted in `eidolons.lock` (`members[].model.effective_model`, with its `tier` / `profile` / `source`) and written to the agent frontmatter.

---

## How the model reaches the agent

The nexus patches a managed block into each host agent's frontmatter:

```
# eidolons:managed model
model: <effective_model>
```

The `# eidolons:managed model` sentinel marks the line the nexus owns. Writes are **idempotent** — `eidolons model …` and `eidolons sync` produce byte-identical output when nothing changed.

### Host behavior

- **`claude-code`** → writes `.claude/agents/<id>.md`.
- **`codex`** → writes `.codex/agents/<id>.md`.
- **`copilot`, `cursor`** → no per-agent model concept; model management is a clean **no-op** for these hosts.

### Profile host-gating

If the active profile does not apply to a wired host (e.g. the `openai` profile, which applies to `codex`, on a claude-code project), the writer **skips** that host rather than writing a model string the host can't use. The lock still records the resolved model; only the frontmatter write is gated.

---

## Drift & the `eidolons doctor` D9 gate

A hand-authored `model:` line **without** the sentinel is **preserved with a warning** during a passive `eidolons sync` — the nexus does not clobber user content. An explicit `eidolons model use` / `profile` / `reset` is treated as consent and **clobbers**.

`eidolons doctor --deep` runs the **D9** gate, comparing the managed `model:` against the lock's `effective_model`:

| Status | Meaning |
|---|---|
| **skip** | no `models` block configured, or no lock model entry yet (run `eidolons sync`) |
| **PASS** | managed `model:` matches the lock |
| **WARN** | hand-authored `model:` without the sentinel, or a managed line on a host the profile doesn't apply to |
| **FAIL** | managed `model:` (sentinel present) drifted from the lock — fatal under `--deep` |

D9 never auto-fixes; it reports and lets you re-run `eidolons model` or `eidolons sync`.

---

## Out of scope

- **EIIS install-contract extension** — having each Eidolon's own `install.sh` accept a `--model` flag is a cleaner long-term boundary, deferred to a future EIIS revision; today model wiring is a nexus-only, post-install concern.
- **opencode model wiring** — pending confirmation of opencode's per-agent frontmatter convention; treated as a no-op for now.
- **Additional vendor profiles** — Google Gemini and others are supported by the data model (and validate with zero code change) but are not shipped until a maintainer commits to keeping them current.

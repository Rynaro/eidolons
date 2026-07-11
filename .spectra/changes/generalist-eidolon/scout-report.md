# Scout Report — Covering the "general-purpose agent" class in the Eidolons roster

**Mission:** DECISION_TARGET — what would adding a NEW Eidolon+capability-class vs augmenting Kupo mechanically touch, and what precedent exists.
**Producer:** ATLAS (standard tier, sonnet) — 2026-07-10, campaign `generalist-eidolon`.

---

### 1. Capability-class machinery

- **FINDING-001** (H): `capability_class` is a **closed enum** with exactly 8 values: `["scout", "planner", "coder", "scriber", "reasoner", "debugger", "memory", "executor"]`. A brand-new class (e.g. `generalist`) requires editing this line.
  `schemas/roster-entry.schema.json:11`
- **FINDING-002** (H): `roster/routing.yaml`'s per-Eidolon `capability_class` field and its schema counterpart are **open strings**, not enums — `schemas/routing.schema.json:34` (`"type": "string"`). Routing has a `classes.default` fallback (`suggested_tier: standard`) that already covers "unknown / future capability classes" (`roster/routing.yaml:44-48`), so routing.yaml itself needs **no schema change** for a new class — only a new `eidolons.<name>` block + trigger/refuse verbs.
- **FINDING-003** (H): `roster/index.yaml` requires `capability_class` on every entry via `roster-entry.schema.json:7` (`required` array). `crystalium` (memory class) has no `working_set_tokens`/no host agent — capability classes don't strictly imply a dispatched agent (`roster/index.yaml:1340-1455`).
- **FINDING-004** (H): The `add-eidolon` skill explicitly documents the extension path: "If you need a new class, add it to `schemas/roster-entry.schema.json` `capability_class.enum`. This is backward-compatible; existing roster entries still validate." — `.claude/skills/add-eidolon/SKILL.md:58`.

### 2. Kupo's current contract

- **FINDING-005** (H): Kupo's roster entry — `capability_class: executor`, `status: shipped` (KEEP-cohort eval 36/36, pass³ 1.0), `handoffs.upstream: [spectra, vigil, forge, vivi, apivr, atlas]`, `downstream: []`, `lateral: []` (pure worker), `working_set_tokens.entry: 850 / target: 1800`, `security.writes_repo: false`. `roster/index.yaml:1456-1555`.
- **FINDING-006** (H): `routing.yaml` deliberately keeps Kupo **narrow-by-design**: trigger verbs are localized micro-task verbs only (rename, import fix, lockfile bump, lint autofix, one-line edit…); refuse_verbs explicitly include `design`, `cross-cutting refactor`, `plan`, `novel architecture`, `greenfield`, `open-ended`, `loop-native campaign`, `implement feature`. A `localized_micro_task` signal (+0.15) tiebreaks Kupo vs. the coder class, capped below the +0.5 named-dispatch bonus. `roster/routing.yaml:125-138,168-178`.
- **FINDING-007** (H): EIDOLONS.md frames Kupo as **orchestrator-dispatched, never a runtime router** ("subagents cannot spawn subagents… worker, never router") and PROPOSE-only (never commits, never applies). `EIDOLONS.md:27-29`.
- **FINDING-008** (H): `.claude/agents/kupo.md` frontmatter: `model: haiku`, narrow read+sandbox-only tool allowlist (`Read, Grep, Glob, Bash(eidolons sandbox:*)…`, no generic `Bash(*)`, no `Write`/`Edit`), `x-eidolons-mcp-wired: [atlas-aci, crystalium, tonberry]`. `.claude/agents/kupo.md:1-7`.
- **FINDING-009** (H): Kupo's 4 skills enforce the load-bearing constraints as mechanical phases: `kupo-keep-or-kick` (Phase K triage/refusal gate, "structurally non-negative"), `kupo-patch-verify` (Phase P+O sandbox+external-verifier loop, circuit-breaker), `kupo-esl-hop` (checker role, maker≠checker), `kupo-verify-incoming` (blocking ECL SHA-256 gate). `.claude/skills/kupo-{keep-or-kick,patch-verify,esl-hop,verify-incoming}/SKILL.md:1-9` each. The composition.md handoff table reinforces the ≤2-file / named-verifier scope textually in every `*→kupo`/`kupo→*` edge description. `methodology/composition.md:143-259`.

**Implication:** Kupo's contract is narrow *by explicit design* at multiple independent enforcement layers (routing refuse_verbs, tool allowlist, skill-level refusal gate, handoff role). "Promoting" Kupo into a general-purpose seat would mean overriding all four layers simultaneously — not a config tweak.

### 3. Dispatch fallthrough

- **FINDING-010** (H): Dispatch Protocol Step 2: "No Eidolon scores ≥ 0.6: emit `clarification_request` with 1–3 targeted questions. Do not dispatch." — there is **no catch-all/general-purpose route** today; every prompt either matches a specialist (or chain) or bounces to clarification. `EIDOLONS.md:42`.
- **FINDING-011** (H): Chain templates (8 total: `plan-before-build`, `decide-then-implement`, `audit-without-touching`, `ship-fast`, `forensic-then-fix`, `failed-attempt-recovery`, `decision-only`, `scout-then-spec`) all require ≥2 co-triggering **existing** capability classes (`requires_classes`); none reference a generalist fallback. `roster/routing.yaml:184-208`, `EIDOLONS.md:62-73`.
- **FINDING-012** (M): The only place "general-purpose" appears in-repo is as the **host's built-in Claude Code subagent type** (`Agent` tool, `general-purpose` type) used inside research artifacts (e.g. `.spectra/research/ramza-stage2/ac003/AB-H1-ramza-r2.out.md:610`) — a host-level fallback subagent, not a roster concept. There is no wiring today from a roster Eidolon into that slot.

### 4. Precedent: adding an Eidolon (Kupo as the exact prior new-class case)

- **FINDING-013** (H): Kupo introduced the `executor` capability class from scratch. Full commit chain: `40f89fb` "add Kupo — the low-effort executor Eidolon (in_construction v0.1.0)" (#290) → `09612b5` "Kupo KEEP-cohort eval, v0.1.1 applier-trust fix" (#292) → `8bd41f9` "Kupo → shipped (v1.0.0) — KEEP-cohort eval cleared (pass^3 1.0)" (#295) → `9c24a3a` "nexus v1.29.0 — ship Kupo (composition.md regen + version cut)" (#296) → `654d4c5` "re-scope Kupo to orchestrator-direct dispatch" (#375, a post-ship routing correction). This is the closest structural precedent for adding a generalist class.
- **FINDING-014** (H): `add-eidolon` SKILL.md enumerates the full checklist, split **[NEW]** vs **[BUMP]**: capability-class enum extension (B.1), roster entry (B.2), lateral-array wiring for lateral specialists (B.3), presets (B.5), release-integrity metadata (B.6), CI matrix `roster-health.yml` line ~209 (C.1), README table (C.2), MANIFESTO team table + pipeline phrase (C.3), `methodology/composition.md` (pipeline diagram, handoff table, consultation pattern, partial-configs table, shared-memory list) (C.4), CHANGELOG (C.5). `.claude/skills/add-eidolon/SKILL.md:33-247`.
- **FINDING-015** (H): The CI matrix is a hardcoded array — `eidolon: [atlas, spectra, ramza, apivr, vivi, idg, forge, vigil, kupo]`. `.github/workflows/roster-health.yml:210`.
- **FINDING-016** (M): ECL contracts (one YAML per directed edge) live **externally** in `Rynaro/eidolons-ecl` — the nexus's `methodology/composition.md` is auto-generated from those contracts and never hand-edited (per CLAUDE.md), meaning a new class also requires an upstream `eidolons-ecl` PR before `composition.md` regen. Not independently verified inside this repo checkout — **[GAP-001]**, confidence L without cloning eidolons-ecl.

### 5. Host wiring

- **FINDING-017** (H): `.claude/agents/` contains 7 files: `atlas.md, forge.md, idg.md, kupo.md, ramza.md, vigil.md, vivi.md` — no `spectra.md`/`apivr.md`/`crystalium.md` (opt-in/memory members aren't host-dispatched by default). No file represents or overrides Claude Code's built-in `general-purpose` subagent slot.
- **FINDING-018** (H): `detect_hosts()` in `cli/src/lib.sh:427-457` only *detects which host directories exist* (`.claude`, `.github`, `.codex`, `.cursor`, `.opencode`) to decide which host adapters `install.sh` wires — it has no concept of a catch-all/general-purpose agent slot.
- **GAP-002** (repo-silent): No mechanism found for wiring an Eidolon into a host's built-in general-purpose/catch-all agent identity (e.g. overriding Claude Code's default `general-purpose` Task-tool type). Each Eidolon gets its own **named** `.claude/agents/<name>.md`; the routing cortex decides *which* named Eidolon to dispatch, but nothing repositions an Eidolon as the host's fallback-when-nothing-matches agent. This is the crux gap for "Path B."

### 6. Cortex token budget headroom

- **FINDING-019** (H): `EIDOLONS.md` full file = 2,180 words / 15,629 chars. Just the **Roster Index table + Dispatch Protocol** sections (lines 15-58, the two explicitly named in CLAUDE.md's "≤900-token" description) = 628 words / 4,434 chars ≈ **800-1,100 tokens** — **already at or over the I-C4 ≤900-token ceiling** (`EIDOLONS.md:147`) before adding anything. Nearly every section in the file is labeled "(always-loaded)," which is inconsistent with I-C4's "deep tables load on demand" design — worth flagging, not fixing here.
- **Consequence:** Adding one more roster-index table row pushes the always-loaded section further over budget. A new class realistically forces **trimming an existing row/section** to stay under I-C4, not just appending.

---

## Touchpoint tables

### Path A — New Eidolon + new capability class (e.g. `generalist`)

| # | File / system | In-repo / external | Touch | Blast radius |
|---|---|---|---|---|
| A1 | `schemas/roster-entry.schema.json:11` | in-repo | Add value to `capability_class` enum | Small, backward-compatible |
| A2 | `roster/index.yaml` | in-repo | New `- name:` block (methodology, source, versions, install, handoffs, security, working_set_tokens) | Medium |
| A3 | `roster/routing.yaml` | in-repo | New `eidolons.<name>` block + trigger/refuse verbs; **no schema change needed** (FINDING-002) | Medium |
| A4 | `.github/workflows/roster-health.yml:210` | in-repo | Add name to hardcoded matrix array | Small |
| A5 | `EIDOLONS.md` | in-repo | New roster-index row + possibly a new chain template; **must fit ≤900-token always-loaded budget** (FINDING-019) — likely requires trimming elsewhere | Medium-High (budget-constrained) |
| A6 | `methodology/composition.md` | in-repo, **auto-generated from external eidolons-ecl contracts** — never hand-edit | Regenerate after upstream contract PRs | Medium, gated on external repo |
| A7 | `roster/index.yaml` presets | in-repo | Add to `full` preset (+ maybe a new named preset) | Small |
| A8 | `README.md` roster table, `MANIFESTO.md` team table + pipeline phrase | in-repo | New rows/phrase updates | Small |
| A9 | `CHANGELOG.md` | in-repo | Unreleased entry | Trivial |
| A10 | New Eidolon's **own repo** | external (`Rynaro/<Name>`) | Full EIIS-1.0 conformant repo: `AGENTS.md`, `CLAUDE.md`, `install.sh`, `agent.md`, methodology spec, skills, release workflow | Large — an entire new methodology to design/write |
| A11 | `Rynaro/eidolons-ecl` contracts | external | One YAML per new directed hand-off edge (upstream+downstream for every peer that talks to it) | Medium-Large, external repo PR |
| A12 | `Rynaro/eidolons-eiis` | external | Only if install-contract itself needs a new shape (usually not) | Unlikely |
| A13 | `.claude/agents/<name>.md` | in-repo (or written by installer per EIIS) | New agent frontmatter (model, tools) | Small |
| A14 | Eval/measurement gate | in-repo (`.spectra/` or evals) | Precedent (Kupo, RAMZA, Vivi) shows every new class went through a KEEP/measurement gate before `status: shipped` | Process cost, not a file touch |

### Path B — Augment Kupo (or another existing member) into a general-purpose seat

| # | File / system | In-repo / external | Touch | Blast radius |
|---|---|---|---|---|
| B1 | `roster/routing.yaml:125-138` | in-repo | Widen `trigger_verbs`, remove/relax `refuse_verbs` | High — reverses the deliberate narrow-by-design posture (FINDING-006) |
| B2 | `.claude/skills/kupo-keep-or-kick/SKILL.md` | in-repo | Rewrite the refusal/triage gate that currently makes Kupo "structurally non-negative" via cheap bounce | High — removes a core safety property |
| B3 | `.claude/agents/kupo.md:5` | in-repo | Broaden tool allowlist (currently no `Write`/`Edit`, sandboxed `Bash`) and likely bump `model: haiku` → a stronger tier | Medium-High |
| B4 | `EIDOLONS.md:27-29` | in-repo | Rewrite Kupo's descriptor row + the "orchestrator-dispatched executor" callout that defines worker-never-router | High — touches an explicit invariant description |
| B5 | `roster/index.yaml:1456-1555` (`handoffs`) | in-repo | Change `downstream: []` / `lateral: []` if Kupo starts routing/dispatching onward | High — conflicts with "subagents cannot spawn subagents" constraint |
| B6 | `methodology/composition.md` handoff edges | in-repo, external-contract-gated | Every `*→kupo` / `kupo→*` edge description reasserts ≤2-file, named-verifier scope — all would need rewriting | Medium, gated on eidolons-ecl |
| B7 | Kupo's own repo (`Rynaro/Kupo`) methodology/skills (K→U→P→O cycle) | external | The cycle itself is architected for micro-tasks, not open-ended design — a "generalist" mode is a different methodology, not a parameter | Large — effectively a new methodology inside the same name |
| B8 | Eval/measurement re-gate | process | Precedent shows any seat-widening claim needs a fresh A/B before `status` changes reflect it | Process cost |
| B9 | `schemas/roster-entry.schema.json` | in-repo | **No change needed** — `capability_class: executor` stays | None |
| B10 | `.github/workflows/roster-health.yml` | in-repo | **No change needed** — Kupo already in the matrix | None |

---

## Gaps

- **GAP-001** (L): Whether `methodology/composition.md`'s "auto-generated from eidolons-ecl, never hand-edited" claim is enforced by tooling in *this* checkout wasn't independently verified — the external `Rynaro/eidolons-ecl` repo wasn't cloned/inspected.
- **GAP-002** (repo-silent, confirmed via FINDING-017/018): No existing mechanism anywhere in the roster/CLI/cortex for wiring an Eidolon into a host's built-in general-purpose/catch-all agent slot. Any path that means literally becoming the host's fallback agent — rather than widening routing verbs — is unaddressed by current machinery.
- **GAP-003** (M): I-C4's ≤900-token ceiling for the "always-loaded" section already sits at or past budget with the current 9-member roster (FINDING-019); no mechanical token-budget gate exists in CI — an unenforced invariant today.

## Recommended next actions

- → **FORGE**: the trade-off (new class vs. augment Kupo vs. no-new-persona alternatives) is a genuine ambiguous decision — deliberate before committing.
- → **RAMZA**: spec the chosen path.
- → **human**: confirm whether "general-purpose" means (a) a new roster capability class dispatched like any other Eidolon, or (b) literally overriding the host's built-in fallback agent (GAP-002) — different blast radii.
- → **ATLAS** (follow-up): if Path A is chosen, scout `Rynaro/eidolons-ecl` + `Rynaro/eidolons-eiis` to close GAP-001.

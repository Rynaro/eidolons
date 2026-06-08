# Kupo Build Dossier

> Working dossier for constructing **Kupo** — a "little smart" low-effort executor Eidolon that
> other Eidolons delegate quick/cheap work to. Compiled 2026-06-08.
> Sections: (1) EIIS/ECL compliance contract, (2) ATLAS internal construction blueprint,
> (3) frontier research synthesis [appended when the research workflow lands],
> (4) open design decisions.

---

## 0. Identity (decided so far)

- **Name:** Kupo (Final Fantasy Moogle greeting — small helper; fits the FF-themed roster: Vivi, GAMBIT, MATERIA→GAMBIT).
- **Role:** small / cheap / low-latency executor; heavier Eidolons delegate micro-tasks to it to keep their own sessions efficient.
- **Tier:** `haiku` / `speed-class` (matches IDG — the closest existing template).
- **MCP:** must access `atlas-aci` (structural lookups); rides the **junction** transport bus.
- **Repo:** `Rynaro/Kupo` (canonical casing — identity key downstream).
- **Standards:** EIIS **1.4**, ECL **2.0**.

---

## 1. Compliance Contract — EIIS 1.4 + ECL 2.0

### EIIS 1.4 (install contract)

**Source repo root MUST have:** `agent.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `install.sh` (executable), `EIIS_VERSION` (`1.4`), `SPEC.md`. Optional: `skills/<skill>.md`, `templates/<artifact>.md`, `evals/`, `ECL_VERSION`.

**Install target `./.eidolons/kupo/` — strict §1.9 whitelist (only these allowed):**
| Path | role | status |
|---|---|---|
| `agent.md` | `agent-profile` | MUST (exactly one) |
| `SPEC.md` | `spec` | MUST (exactly one) |
| `install.manifest.json` | `manifest` | MUST |
| `ECL_VERSION` | `ecl-version` | MUST (source declares it) |
| `skills/<skill>.md` | `skill` | MAY |
| `templates/<artifact>.md` | `template` | MAY |
| `schemas/install.manifest.v1.json` | vendored schema | SHOULD |
| `schemas/<aux>.json` | other | MAY |

**Prohibited in target:** `AGENTS.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, root `SKILL.md`, `skills/<phase>/SKILL.md` subdirs, `hosts/`, `evals/`, `research/`, legacy slug-named spec files.

**install.sh flags (required):** `--target DIR` (default `./.eidolons/kupo`), `--hosts LIST` (claude-code,copilot,cursor,opencode,codex,all,auto,none), `--shared-dispatch`/`--no-shared-dispatch`, `--force`, `--dry-run`, `--non-interactive`, `--manifest-only`, `--version`, `-h/--help`.
**Exit codes:** 0 ok · 2 bad args · 3 already-installed (no --force) · **4 token budget exceeded**.

**install.manifest.json required fields:** `eidolon`(`^[a-z][a-z0-9-]*$`), `version`(semver), `methodology`, `installed_at`(RFC3339-UTC), `target`, `hosts_wired[]`, `files_written[]` (each `{path, sha256:64hex, role, mode}`). Optional: `token_budget`, `handoffs_declared`, `security`, `ecl_version_emitted`, `spec_file`, `canonical_inventory_strict`(default true), `skills[]`, `comm`.

**Canonical pairs:** exactly one `role:agent-profile` (agent.md) + one `role:spec` (SPEC.md).
**`canonical_inventory_sweep`:** runs after ALL writes, BEFORE writing manifest — deletes any file under target not in `FILES_WRITTEN_PATHS`, then removes empty dirs.
**agent.md token gate:** `AGENT_TOKENS = wc -w agent.md / 0.75`; if `>1000` and `--non-interactive` → **exit 4**. (CRYSTALIUM recall block must be a `SPEC.md §9` pointer, NOT inlined.)

**claude-code host dispatch file** `.claude/agents/kupo.md` (v1.4 body):
```markdown
---
name: kupo
description: <one-line>
model: haiku
---
You are KUPO. Read these two files in order at session start:
1. `./.eidolons/kupo/agent.md` — always-loaded P0 rules.
2. `./.eidolons/kupo/SPEC.md` — deep on-demand methodology spec.
Skills live at `./.eidolons/kupo/skills/<skill>.md` (load on demand).
```
Other host paths: `.github/instructions/kupo.instructions.md`, `.cursor/rules/kupo.mdc`, `.opencode/agents/kupo.md`, `.codex/agents/kupo.md`. Shared-dispatch files use markers `<!-- eidolon:kupo start --> … <!-- eidolon:kupo end -->`.

**Conformance check:** `bash <eiis>/conformance/check.sh <kupo-repo> [--json] [--level=MUST]` → exit 0 OK. IDs I1 (no non-whitelisted paths), I2 (one agent-profile + one spec), I3 (ECL_VERSION target==source), I4 (host refs use agent.md+SPEC.md, no legacy names), I5 (skill refs in agent.md resolve to files_written).
**Skeleton to scaffold from:** `github.com/Rynaro/eidolons-eiis/tree/main/templates/eidolon-skeleton`.

### ECL 2.0 (communication contract)

- `ECL_VERSION` file = `2.0` (root + installed target, byte-identical).
- **Envelope sidecar** `<payload>.envelope.json` (same dir as artifact): `envelope_version:"2.0"`, `message_id`(UUIDv7), `thread_id`, `parent_id`(null on first), `from:{eidolon:"kupo",version}`, `to:{eidolon|"orchestrator"|"human"}`, `performative`, `objective`(≤240 chars), `artifact:{kind,schema_version,path,sha256,size_bytes}`, `integrity:{method:"sha256",value:64hex}`, `trace:{ts,host,model,tier}`. Optional: `edge_origin`(roster|composition|implicit), `context_delta`, `constraints`, `expected_response`, `confidence`, `assumptions[]`, `ise`.
- **Closed 10 performatives:** REQUEST, INFORM, PROPOSE, CRITIQUE, DECIDE, DELEGATE, ACKNOWLEDGE, ESCALATE, RESUME, REFUSE.
- **verify-incoming receiver gate** (MUST, before processing inbound): failure codes INTEGRITY_MISMATCH, SCHEMA_INVALID, UNDECLARED_EDGE, PERFORMATIVE_NOT_ALLOWED, ARTIFACT_KIND_NOT_ALLOWED, CONTEXT_OVER_BUDGET, MISSING_REQUIRED_SECTION → emit `verify_fail`, do NOT process. `skills/verify-incoming.md` must contain blocking language (`REFUSE`, `SHALL NOT`, `Do not process`) and must NOT contain "process the payload anyway".
- **Trace:** append per-envelope JSONL to `.eidolons/.trace/<thread_id>.jsonl` (`verify_pass`/`verify_fail`).
- **Per-edge contract** `contracts/<from>→<to>.yaml`: `contract_version`, `from`, `to`, `edge_origin`, `performatives_allowed[]`, `artifacts[]{kind,schema_ref,required_sections?,evidence_anchor_required?}`, `context_delta?`, `trust_level?`, `notes?`. Undeclared edge = MUST-level fail (`UNDECLARED_EDGE`). Needed for EVERY edge Kupo touches (inbound + outbound), incl. `human-to-kupo.yaml` (humans limited to REQUEST/INFORM/CRITIQUE/REFUSE/ACKNOWLEDGE/ESCALATE).
- **Note (do not "fix"):** spec dir is `spec/ecl-1.0.md` / `ecl-2.0.md` but the wire `ECL_VERSION` stamp live Eidolons emit is `2.0`. Emit `2.0` to match; DO NOT unilaterally reconcile the spec-vs-wire ambiguity (breaks install.bats + desyncs roster — see memory `feedback_ecl_version_v3_overreach`).

---

## 2. ATLAS Internal Construction Blueprint

**Template = IDG** (haiku-tier). Installed layout (`.eidolons/idg/`): `agent.md`, `SPEC.md`, `ECL_VERSION`(2.0), `install.manifest.json`, `skills/{composition,verification,section-parallel,verify-incoming}.md`, `schemas/{ecl-envelope.v1,ecl-base-profile.v1,…}.json`, `templates/*.md`. Upstream (`~/.eidolons/cache/idg@1.7.0/`) adds: `install.sh`, `EIIS_VERSION`(1.4), `AGENTS.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `INSTALL.md`, `hosts/`, `.github/{copilot-instructions.md,workflows/release.yml}`, `evals/`, `tests/{helpers.bash,verify-incoming.bats}`.

**Key enforcement points (path:line):**
- agent.md token gate: `install.sh:679-724` (`wc -w / 0.75`, exit 4) + `roster-health.yml:344-360` (CI runs the gate per Eidolon).
- model tier written into `.claude/agents/<name>.md`: `install.sh:430` (`model: haiku`).
- CI matrix hardcode: `roster-health.yml:210` — `eidolon: [atlas, spectra, apivr, idg, forge, vigil]` → **add `kupo`**.
- IDG roster entry reference: `roster/index.yaml:536-691`.
- Junction transport: `roster/mcps.yaml:64-98` (`grants_to_eidolons: all`, `wiring_mode: transport`) + `cli/src/lib_mcp_wiring.sh:629-636` — **transport eligibility is automatic for every roster member; no per-Eidolon action**. Junction tools never enter any agent's `tools:` line.
- atlas-aci grant: `roster/mcps.yaml:21` `grants_to_eidolons:[atlas]` → **add `kupo`**. Wiring injects `tools: mcp__atlas_aci__*` (underscore glob) but **runtime tool calls use `mcp__atlas-aci__*` (hyphen)**.
- Cortex source of truth: `roster/index.yaml` (I-C7); cortex tables hand-synced.

**Construction checklist (condensed; full 19 steps in ATLAS report):**

*Upstream `Rynaro/Kupo` repo* — create: `agent.md` (≤1000 tok), `SPEC.md`, `ECL_VERSION`(2.0), `EIIS_VERSION`(1.4), `install.sh` (adapt IDG's: EIDOLON_NAME/SLUG/VERSION/METHODOLOGY, model haiku, keep sweep + token gate, bash 3.2), `skills/verify-incoming.md` (blocking) + ≥1 task skill, `schemas/{ecl-envelope.v1,ecl-base-profile.v1}.json` (copy from IDG) + `install.manifest.v1.json`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `INSTALL.md`, `hosts/claude-code.md`, `.github/workflows/release.yml` (release-asset contract: release-manifest.json + SHA256SUMS + attestation), `tests/verify-incoming.bats`, `evals/canary-missions.md`, `contracts/*.yaml` (ECL per-edge).

*Nexus edits:* (1) `schemas/roster-entry.schema.json` capability_class enum (if new class) → (2) `roster/index.yaml` Kupo entry + bump `updated_at` → (3) other Eidolons' handoffs (lateral/downstream) → (4) presets (`full` at least) → (5) `roster/mcps.yaml` atlas-aci grant += kupo → (6) `roster/routing.yaml` kupo descriptor → (7) `roster/ecl.yaml` class (if new) → (8) `roster/aci.yaml` class (if new) → (9) `roster-health.yml:210` matrix += kupo → (10) `EIDOLONS.md` roster table row → (11) `EIDOLONS.md` marker block → (12) `.eidolons/cortex/EIDOLONS.md` mirror (or `eidolons sync`) → (13) `handoff-graph.md` node → (14) `methodology/composition.md` → (15) `README.md` roster table → (16) nexus `CHANGELOG.md` → (17) Roster Intake workflow_dispatch (auto-fills releases.<v> + opens PR) → (18) verify (`jq empty schemas/*.json`, `yq eval roster/index.yaml`, `cli/eidolons list`, shellcheck, `make test`) → (19) PR `feat/roster-kupo-shipped`.

**Hard invariants:** canonical repo casing `Rynaro/Kupo`; bash 3.2 install.sh; verify-incoming must be blocking; do NOT pre-push tags / hand-edit `archive_sha256` (use Roster Intake); junction transport automatic; atlas-aci hyphen namespace at runtime.

---

## 3. Frontier Research Synthesis

> `kupo-frontier-research` (wf_cd259aac-60a): 24 agents · 3 rounds · 82 accepted claims · 0 authors blacklisted.
> R1=28 accepted, R2=26, R3 total=82. Every principle below is multi-source cited in the workflow result.

**Core thesis:** *Harness > model.* A haiku-class agent wins by owning a **fixed, minimal-autonomy
localize→edit→validate pipeline with external-only verification**, NOT an open-ended ReAct loop.
Haiku 4.5 = 73.3% SWE-bench Verified on a 2-tool surface — the lever is interface/harness design, not size.

**14 design principles:**
1. Fixed minimal-autonomy **localize→edit→validate** pipeline, not open-ended ReAct. (Agentless 27–32% SWE-Lite @ $0.34–0.70 vs ~$3.34/issue verbose; arxiv 2407.01489)
2. Canonical **gather→act→verify→repeat** loop with self-declared done-marker + hard step ceiling + per-cmd timeout. (mini-swe-agent >74% Verified bash-only)
3. **~4–5 consolidated tools** (read / edit / run-bash / grep-glob); whole prompt+tools <1000 tokens. Bloated tool sets = #1 failure mode; small models most sensitive. (pi, ghuntley, Cursor Composer, Anthropic)
4. **External-signal self-verification only** (tests/typecheck/lint/compile/diff). Intrinsic self-critique stays flat or DEGRADES (Huang ICLR'24, 2310.01798). LLM-as-judge least robust → worst at haiku.
5. **"Success silent, failures verbose"** + pre-completion verification gate + per-file loop detector. (harness swap Top-30→Top-5; +13.7pt build-verify loop, LangChain/Osmani/Fowler)
6. **Emit search/replace or whole-file edits + deterministic FUZZY applier**, never hand-apply diffs. (small models can't apply diffs — Qwen-7B 0.59 EM; disabling fuzzy apply = 9X errors; Aider/Diff-XYZ)
7. **Single-threaded inline writes**; delegate only read/retrieval, only when disjoint. (multi-agent ~15x tokens; "conflicting decisions carry bad results" — Cognition/Anthropic/philschmid)
8. **Context 40–60% utilization**, just-in-time retrieval-targeted, never pre-load whole files. (context rot; dynamic discovery −46.9% tokens — Anthropic/Cursor/HumanLayer)
9. **Keep failures/stack-traces in context** + recite objective (todo.md) vs goal drift. (Manus; ⚠ validated for capable models — haiku caveat)
10. **Escalate on structural/behavioral triggers** (stall, K=3 disagreement, circuit-breaker), NEVER verbalized confidence. (models "almost never abstain" — RiskEval 2601.07767)
11. **Gather-before-first-edit gate** (ρ=+0.68 w/ success), validate before done (ρ=+0.50), **budget by cost not steps** (winners often take MORE steps; 2604.02547).
12. **Kupo = cheap WORKER under a heavier planner**, never the router. Pair small-executor+strong-planner. Inline ONLY if pass-rate > cost-ratio (~20% Haiku→Opus). KV-cache append-only (10x lever — Manus/Madeyski/Anthropic Haiku 4.5).
13. **OS-sandbox blast radius** (cwd-write-only + proxied net) + circuit-breaker (STOP at 3-consecutive / 20-total denials). Maps to roster's 3-failures-then-STOP. (Anthropic sandboxing −84% prompts; auto-mode)
14. **Implement as a Claude Code subagent**: haiku frontmatter, allowlisted tools, isolated context returning a 1–2k-token summary; can't nest-delegate (structurally enforces worker role; mirrors built-in Explore=Haiku+read-only).

**Cycle implication:** intake/triage (keep-inline vs escalate) → gather/localize (just-in-time) → patch (minimal-tool edit + fuzzy apply) → observe/verify (external signals + pre-completion gate + circuit-breaker). Candidate naming **K→U→P→O** (Keep-or-Kick · Understand · Patch · Observe) — spells the name like FORGE/VIGIL/ATLAS.

**Top open risks (design must neutralize):**
- Small-model self-knowledge ceiling ⇒ Kupo-as-router unsafe → **worker-only**; escalation triggers must be structural not introspective.
- Untuned haiku capability ceiling (~7–14% full SWE-Lite; the 73.3% is *with* a strong harness) ⇒ **scope to quick/localized tasks, escalate hard ones hard**.
- **Net-negative-LOO risk** ⇒ Kupo must be shown additive (leave-one-out), eval-gated — consistent with frontier dossier "add ZERO new Eidolons" default.
- Edit-format token-vs-accuracy tension; "leave mistake in context" unvalidated at haiku; routing economics partly an un-run proposal (re-derive thresholds on Kupo's eval).
- **No measured outcome for Kupo yet ⇒ deployment-grade reliance GATED on a Kupo SWE-task eval** (borrowed numbers only; conf ~0.62 until harness ships).

---

## 4. Design Decisions — RESOLVED (FORGE @ opus/max-effort · global conf M-H 0.74)

1. **Capability class → NEW `executor`** [H 0.82]. Adds `executor` to `schemas/roster-entry.schema.json` enum + `roster/{aci,ecl,routing,mcps}.yaml`. `scriber` (IDG) is doc-synthesis; Kupo executes against a live repo w/ atlas-aci + sandbox — wrong class mis-gates every routing decision (paid forever vs enum-add paid once). Reversal: collapse to `scriber` if eval shows identical routing behavior.

2. **Write authority → PROPOSE-only at repo boundary + ephemeral cwd-write SCRATCH sandbox in-loop** [H 0.80] — **KEYSTONE**. Kupo emits search/replace or whole-file text; a deterministic **harness-owned fuzzy applier** applies it into a *throwaway* sandbox; Kupo runs external verifiers (test/lint/typecheck) against its own patch **before** emitting a *verified* ECL `PROPOSE`; the **PARENT commits to the real tree**. `security.reads_repo:true`, `writes_repo:false` (real tree); `aci.yaml writes_repo:sandbox`; `reads_network:true` (proxied, atlas-aci/junction). Emits `INFORM/PROPOSE/ESCALATE/REFUSE/ACKNOWLEDGE/RESUME`; **never** `DECIDE/DELEGATE/CRITIQUE/REQUEST`. Why: direct-write-sandboxed recreates the Vivi coder niche at a weaker tier (net-negative); read-only = a redundant weaker ATLAS; PROPOSE + scratch-sandbox = verification fidelity *without* blast radius and *without* Vivi overlap. Resolves the PROPOSE-vs-external-verify tension (applier+verifier run INSIDE Kupo's loop on the throwaway sandbox). Reversal: drop to read-only if in-loop verify gives <5% pass-lift or sandbox setup erodes the latency premise.

3. **Topology → pure downstream WORKER** [H 0.83]. `downstream:[]`, `lateral:[]`. Any planner `DELEGATE`s in; Kupo replies to that parent only. **12 ECL contracts** (6 in / 6 out); 2 gated on Vivi landing → **10 active now**: in+out for {spectra, vigil, forge, apivr, atlas} — `kupo→atlas` is `INFORM/ESCALATE/REFUSE/ACKNOWLEDGE` only (no PROPOSE to a read-only scout). Filter is task-class (phase K), NOT sender. (Also likely needed: `human→kupo` / `orchestrator→kupo` REQUEST edges — confirm at spec.) Reversal: gate one inbound edge if a parent's delegations run <20% pass-rate.

4. **Cycle → K→U→P→O** [M-H 0.76]:
   - **K — Keep-or-Kick** (runs once): triage vs scope taxonomy + **economic gate** — KEEP only if expected pass-rate > ~0.20 (Haiku→Opus cost ratio); else `REFUSE` cheaply (no context spent). *The additive-proof lives here.*
   - **U — Understand**: atlas-aci just-in-time gather, 40–60% ctx budget; **HARD exit gate** — no Patch until a concrete `path:line` edit-site anchor exists (gather-before-first-edit).
   - **P — Patch**: emit edit text → fuzzy applier → **sandbox** (never real tree); per-file loop detector.
   - **O — Observe**: **external verifiers only** (no self-critique / LLM-judge); "success silent, failures verbose"; circuit-breaker **3-consecutive / 20-total → ESCALATE**; step ceiling + timeout; **pre-completion gate** — emit PROPOSE-done only after ≥1 green external signal (defeats "never abstains").
   Reversal: if it thrashes (exits via step-ceiling more than it completes), raise K's KEEP bar — don't change the cycle.

5. **Scope guard (additive-proof)** [M 0.70]. KEEP iff ALL: localized (≤2 files, one coherent change) + a **NAMED external verifier** determines correctness + pass-rate > 0.20. KEEP classes: rename/symbol-move w/ compiler confirm, import/path fix, lockfile/dep-pin bump, config-key edit vs schema, mechanical fixture update, obvious one-line failing-assertion fix, lint/format autofix apply, template boilerplate, bounded grep-replace. REFUSE/ESCALATE: open-ended reasoning, cross-cutting refactor (>2 files), ambiguous spec, design/planning, **loop-native coding campaigns (→ Vivi/APIVR-Δ)**, or pass-rate ≤ 0.20. Proof: Kupo only attempts tasks with a cheap external verifier + EV-positive pass-rate; misfits bounce at K for ~1 triage cost → structurally can't be net-negative. KEEP predicate is **structural** (named-verifier-must-exist), not verbalized confidence. **MASTER eval-gate (ship-blocker): ship behind a periodic KEEP-cohort eval; if net-pass < cost-ratio → revert to read-only or remove. Do NOT ship Kupo without the eval-gate.**

6. **Tier → haiku** [H 0.85]. Sonnet destroys the cost-ratio premise (shrinks the net-positive task band) and overlaps Vivi. The harness is the lever, not the tier. Reversal: bump to sonnet ONLY if the harness is maximally tuned AND haiku still sub-threshold on a well-scoped KEEP set — and raise the KEEP bar simultaneously.

**Top risks neutralized:** R1 eval-harness-doesn't-exist → eval-gate as ship-blocker (caps global conf at 0.74); R2 Vivi collision → PROPOSE-not-commit + REFUSE loop-campaigns; R3 confidently-wrong output → green-signal pre-completion gate + in-loop sandbox verify; R4 scope creep → structural KEEP predicate + periodic eval; R5 tool bloat → atlas-aci grant capped to read/grep/glob, only mutation path is the harness fuzzy-applier, <1000-token surface.

## 5. Build phases (for the plan)
P1 Kupo upstream repo (`Rynaro/Kupo`, scaffold from IDG) · P2 local verify (shellcheck + install.sh smoke + EIIS conformance + token gate) · P3 nexus integration (schema enum, roster entry, aci/ecl/routing/mcps, roster-health matrix, cortex, README/CHANGELOG, presets) · P4 outward-facing (create repo, push, tag, Roster Intake, nexus PR) · P5 eval-gate (NEXT — the KEEP-cohort eval that gates `shipped`). Coder = APIVR-Δ (Vivi gated) @ xhigh; spec finalize = SPECTRA @ opus; parent handles commits/pushes/envelope-SHAs/repo-creation.

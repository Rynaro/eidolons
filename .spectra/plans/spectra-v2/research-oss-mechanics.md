# Research — OSS Planning Mechanics + MCP Ecosystem (mid-2026)

> SPECTRA v2 campaign · gathered 2026-07-04 by 3 parallel reverse-engineering agents (Sonnet), curated by Fable 5.
> These are source-level findings (file paths cited), not marketing. Verdicts in `CURATION.md`.

## 1. Cline — Plan/Act

- Gating is **tool-array manipulation in code**, both architecture generations: legacy mode-exclusive tools `plan_mode_respond`/`act_mode_respond` (`apps/vscode/src/shared/tools.ts:18-34`); live SDK engine adds `switch_to_act_mode` to the tool array only `if (mode === "plan")` and strips it in Act (`sdk-session-config-builder.ts`) [HIGH].
- Mode switch **rebuilds the session** (`togglePlanActMode()` → `rebuildSessionForMode()`); on Plan→Act a system-authored continuation is injected ("The user approved switching to act mode…") [HIGH].
- **Per-mode model binding is first-class**: `planModeApiModelId` / `actModeApiModelId` persist across the migration [HIGH].
- No plan file artifact — the plan lives only in conversation. Focus Chain (self-reported markdown todo, re-injected every ~6 messages) is **stubbed out in the live engine** ("focus chain removed") [HIGH stubbed / MED permanence]. It never mechanically verified anything — completion was always self-reported.

## 2. Roo Code — modes as declarative capability grammar

- `ModeConfig` (Zod): `slug, roleDefinition, whenToUse, groups, customInstructions`. Architect = `["read", ["edit", {fileRegex: "\\.md$"}], "mcp"]` [HIGH].
- **Enforcement is a thrown typed error**: `isToolAllowedForMode()` runs before every tool call; violations throw `FileRestrictionError` ("can only edit files matching pattern: \.md$") [HIGH].
- Boomerang/Orchestrator: `new_task` disposes the parent loop, persists `parentTaskId/childIds` lineage; completion returns as **free-text** `attempt_completion.result` — no structured handoff schema [HIGH].
- Sticky per-mode models (`modeApiConfigs`) swap provider/model on mode switch [HIGH].
- Only mechanical completion gate: `preventCompletionWithOpenTodos` — checklist-completeness, not semantic verification [HIGH].

## 3. Kilo Code

- Rewritten around a fork of the OpenCode engine; Cline/Roo modes survive only as a legacy migration layer. Plan mode = `plan-mode.txt` prompt (explore→design→review→write→`plan_exit`, read-only except a plan file) + OpenCode-native agents; generic `task` tool with `background: true` and `task_id` resume [HIGH/MED]. No scoring or acceptance-criteria system.

## 4. Aider — architect/editor (the two-model evidence)

- Hard code-path split: `ArchitectCoder.reply_completed()` instantiates a second `Coder` with `main_model = editor_model`, **`map_tokens=0` hardcoded** (executor starved of repo-map) and wiped message history — the editor sees only the proposal text [HIGH, source].
- Measured (website/_data/architect.yml): solo Sonnet 77.4% → Sonnet+Sonnet architect/editor 80.5%; new SOTA 85.0% for o1-preview+deepseek/whole and o1-preview+o1-mini/whole (prior solo SOTA 79.7%) [HIGH].
- Caveats from aider's own analysis: cheap editors can't reliably emit diffs — SOTA runs used the slow "whole-file" format ("probably not practical for interactive use"); gains are contingent on giving the weak executor a **low-ambiguity output contract** [HIGH].
- Repo-map: tree-sitter tags → `networkx` graph → personalized PageRank with deterministic weight multipliers (+10x mentioned, 50x already-in-chat, 0.1x high-fan-out), truncated by `--map-tokens` — zero LLM discretion [HIGH].

## 5. OpenHands

- Condensation is numerically gated code: `max_size` 240 events (subagents 80), `keep_first`, `minimum_progress=0.1` — a condensation forgetting <10% raises an exception; triggers classified HARD/SOFT; failed summarizer calls degrade-and-retry (5×, 0.8× shrink) [HIGH].
- Microagent injection = deterministic keyword/task-trigger string matching, not LLM relevance judgment [HIGH].
- No plan.md artifact; persisted state is an event-sourced `EventLog` [MED].

## 6. goose

- Recipes = serialized plans: builder-enforced required fields, typed parameters, `sub_recipes`, **`response.json_schema` validated against model output**; loadable from cwd/env-path/GitHub — plans as versioned, shareable files [HIGH].
- Subagents mechanically restricted to parent-session extensions (no privilege escalation); `max_turns` numeric cap per delegated task [HIGH field / MED loop-break].

## 7. opencode

- Agents defined with **glob-pattern permission rulesets** (allow/ask/deny, last-match-wins) enforced before tool execution. `plan` agent: `edit: {"*": "deny", ".opencode/plans/*.md": "allow", <data>/plans/*.md: "allow"}` — plan mode can write ONLY plan files [HIGH, source read directly].

## 8. Planning MCP ecosystem (white-space scan)

Inventory (tools exposed):
- **sequential-thinking** (Anthropic reference): one tool, in-turn scaffold, no persistence, advisory [HIGH].
- **software-planning-mcp** (393★, dormant): start_planning/add_todo/…, no ordering guarantee [MED].
- **shrimp-task-manager** (2.1k★): plan/analyze/reflect/split/execute/verify tools; ordering **recommended, not enforced** [MED].
- **claude-task-master** (27.8k★, active): parse_prd/next_task/expand_task/…, `tasks.json` + dependency graph but **no server-side rejection** of out-of-order status changes; `analyze_project_complexity` = single scalar, not multi-dim rubric [MED].
- **vibe-kanban** (27.3k★): execution orchestration (worktrees, kanban), not plan enforcement [MED].
- **spec-workflow-mcp** (4.3k★, active — closest analog): enforces Requirements→Design→Tasks with per-phase approval gate, dashboard + VS Code ext; approval is **binary human file-backed decision, no scoring** [MED-HIGH].
- **Beads**: git-friendly typed dependency-DAG issue graph for agents — strongest dependency primitive, no scoring/criteria formalism [MED].

Enforcement patterns that exist: (A) next-step-ID gate (server rejects out-of-sequence calls); (B) token messenger (server-issued step tokens, can carry payload hashes); (C) advisory-only (majority); (D) human approval-file gate. **Nobody does weighted multi-dimension scoring with a server-enforced threshold.**

Confirmed white space (searched directly, nothing found):
1. Rubric-arithmetic gate (multi-dim weighted score → mechanical pass/fail).
2. EARS grammar linter as a tool (Kiro/Spec Kit only *generate* EARS via prompting).
3. Cryptographic acceptance-criteria freeze + amend chain (Kiro is explicitly anti-freeze).
4. **Plan-vs-diff drift checker** (all existing "drift" tools are MCP schema drift, unrelated).
5. Graduated evidence-scored confidence gates with audit trail.
6. Maker≠checker enforcement at the MCP layer.

## Consolidated OSS lessons

1. The winning enforcement primitives are boring and portable: tool-array gating per phase (Cline), regex/glob write restrictions (Roo/opencode), fresh-context executor with starved context (Aider), numeric budget gates (OpenHands/goose), schema-validated outputs (goose).
2. Everyone binds models per mode/phase mechanically **except at the quality level** — no one verifies plan content by code; "done" is self-reported everywhere.
3. Aider is the only measured two-model split: real gains (+3-5pt same-model, up to SOTA with pairs), conditional on a low-ambiguity executor contract.
4. The entire mechanized-plan-quality surface (scoring, linting, freezing, drift, gates, maker≠checker) is **unclaimed** in the MCP ecosystem — first-mover space for an Eidolon MCP that composes with Junction (whose `harness_plan_from_prompt` is an explicit stub reserving the planner seat, and whose `harness_verify` already does L1-L4 envelope checks).

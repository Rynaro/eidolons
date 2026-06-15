# DOSSIER — Harness Mechanization: Making Eidolons a Mechanical Differentiator

**Date:** 2026-06-10
**Mission:** Determine how to make Eidolon routing + crystalium memory pre-flight *mechanically enforced* — not documentary prose — across every supported host harness (Claude Code, Codex CLI, GitHub Copilot, OpenCode, Cursor).
**Verdict confidence:** 0.85 (FORGE, deep deliberation, 3-pass stable)
**Evidence base:** 112 adversarially-verified capability rows (6 research angles, 18 agents) — `.spectra/tooling-audit-2026-06/harness-research-verified.json` · internal scout `.spectra/tooling-audit-2026-06/host-wiring-scout.md` · decision artifact `.spectra/tooling-audit-2026-06/forge-harness-decision.md`

---

## 1. Diagnosis — why prompting doesn't invoke Eidolons today

The routing mandate is **documentary, not mechanical**. Four compounding causes, all verified:

1. **Zero hook surfaces are written by the CLI today** (scout G7). No host executes anything per-prompt; routing competes as prose against each vendor's system prompt, which biases the model toward acting directly.
2. **The cortex's "always-loaded" assumption is false in practice.** Only CLAUDE.md/AGENTS.md-class files auto-load; the dispatch table lives in `EIDOLONS.md`, a pointer target. Cursor and OpenCode have **no cortex surface at all** (G4/G9). The CLAUDE.md footer even gates the pointer on "any prompt *that mentions an Eidolon*" — a self-inflicted lexical gate.
3. **Dispatch is lexically keyed.** The strongest confidence signal in the protocol is "+0.5 Eidolon named explicitly" — which is precisely the observed behavior: explicit mention works, implicit intent doesn't.
4. **Junction and crystalium are structurally invisible.** MCP tool schemas defer out of working attention; junction is transport-wired (never in any allowlist) so it only fires when chains fire; the crystalium pre-flight mandate lives in the unloaded file. Junction's silence is a *symptom* of routing not firing, not a separate failure.

This is the same root cause the Frontier dossier named ecosystem-wide: **documentary ≠ behavioral; the gap is the missing mechanical runtime.** The runtime half already exists — `eidolons run` is a deterministic, non-LLM routing kernel (`cli/src/run.sh` + `roster/routing.yaml`, `--json`, `--verify-block`). It is wired to nothing.

---

## 2. The market window — every vendor just shipped the missing primitive

Between September 2025 and March 2026, **all five supported harnesses converged on lifecycle hook systems with blocking semantics**. This is the load-bearing research finding: the mechanization layer Eidolons needs became installable everywhere, and almost no framework exploits it cross-vendor yet.

### Verified per-host mechanical surface matrix (2026-06-10)

| Capability | Claude Code | Codex CLI | Copilot (CLI/cloud) | OpenCode | Cursor |
|---|---|---|---|---|---|
| **Prompt-submit hook** | `UserPromptSubmit` — blocks + injects (GA) | `UserPromptSubmit` — blocks + injects, dual-mode confirmed (GA) | `userPromptSubmitted` (1 of **13** events, GA) | — (no sound prompt hook; `chat.system.transform` **broken**, #17100) | `beforeSubmitPrompt` — blocks only; bug: blocked msg persists in context; absent in cloud |
| **Session-start inject** | `SessionStart` additionalContext, 10k-char cap (GA) | `SessionStart` additionalContext (GA) | `sessionStart` (GA) | `session.created` event (plugin) | — (static rules only) |
| **Pre-tool block** | `PreToolUse` exit-2 / permissionDecision (GA) | `PreToolUse` blocks-only; no inject (#19385) | `preToolUse` **fail-closed**: crash/timeout = deny; cloud treats ask as deny | `tool.execute.before` throw-to-block, **subagent bypass #5894** | `preToolUse`, `beforeShellExecution`, `beforeMCPExecution`, `failClosed:true` (GA) |
| **Subagent files** | `.claude/agents/*.md`; `tools`/`disallowedTools` enforced; `maxTurns` NOT enforced (#41143) | `.codex/agents/*.toml` — **TOML only; our `.md` files are never read (G10)** | `.github/agents/*.agent.md` GA (ex-chatmode; org: `.github-private/agents/`) | `.opencode/agents/*.md` + `agent` key (singular); `permission.task` globs gate sub-dispatch (sound block) | No agent files; `/multitask` subagents; `subagentStart` hook |
| **Always-loaded prose** | CLAUDE.md | AGENTS.md (32 KiB combined cap) | copilot-instructions.md + `.instructions.md` applyTo (mechanically injected) | AGENTS.md project+global **concatenated** | `.cursor/rules/*.mdc` `alwaysApply` (3.0.16 silent-demotion regression) + AGENTS.md (CLI confirmed) |
| **Skills** | `.claude/skills` (GA; model-driven dispatch) | **Codex Skills** (custom prompts deprecated 2026-01-22) | `.instructions.md` | `commands/*.md` | rules `.mdc` |
| **MCP** | `.mcp.json`; tool-search deferral | `config.toml mcp_servers` | `.vscode/mcp.json` (`servers` key); sampling in CLI ≥1.0.13 | `opencode.json mcp`; `.well-known/opencode` org defaults | `.cursor/mcp.json` |

### Cross-cutting verdicts

- **MCP cannot be the chokepoint.** The protocol has **no required-first-tool primitive**; tool invocation is always model-chosen; sampling/elicitation can't force routing. Microsoft confirms the control-plane gap is structural. → junction stays **transport**, never router.
- **LLM-chosen handoffs are suggests-only everywhere** (OpenAI Agents SDK `transfer_to_*` included). What genuinely blocks: pre-execution guardrails, graph topology at the boundary, **hooks**.
- **Memory must be harness-injected, never model-requested.** Mem0 (platform-side automatic retrieval + injection) vs Letta/MemGPT (agent must remember to call memory tools — fails exactly like our cortex). The crystalium pre-flight must move into hooks.

---

## 3. FORGE verdict — Architecture A (kernel + thin adapters), inject-by-default

> Full deliberation: `.spectra/tooling-audit-2026-06/forge-harness-decision.md`. Composite scores: A=4.70, per-host-maximalism=3.10, documentary++=2.20, MCP-router=1.85, wrapper-CLI=1.85.

**Adopt: universal deterministic kernel (`eidolons run`) + thin per-host hook adapters, installed by a new idempotent `eidolons harness install` surface.** Documentary cortex remains the universal floor (T0); junction stays transport; ECL `verify-envelope --block` stays the integrity gate.

- **Adapters contain zero routing logic** — they are shims (bash, or JS for the OpenCode plugin) that shell out to `eidolons run --hook <host> --json` and emit the host's hook-output dialect. Routing semantics live once, in the kernel, table-driven from `roster/routing.yaml`. (Re-implementing routing five times in three languages was explicitly rejected — semantic-drift class of the tools-allowlist bug.)
- **INJECT is the default posture on every host; BLOCK is per-host opt-in strict tier, tool-boundary only.** Dispatch is model-executed on every host, so a prompt-boundary block can only enforce "stop", never "delegate correctly". Injection converts the failure mode from *recall-of-distant-prose* (measured failure) to *instruction-following on fresh, prompt-local, deterministically-computed routing artifacts*.
- **Memory pre-flight mechanized:** SessionStart-class hooks run `eidolons memory preflight` → crystalium recall → inject digest. TTL-cached, 1.5 s timeout → silent skip. **Never block on memory failure.**
- Rejected: **MCP-as-router** (no force primitive — would recreate the starvation pattern), **wrapper CLI owning the loop** (can't proxy Copilot cloud / Cursor GUI; vendor-churn treadmill), **documentary++** (is the measured status quo).

### Per-host enforcement ladder (achievable TODAY)

| Host | Tier | How | Hard caveats |
|---|---|---|---|
| **Claude Code** | **T3** full-route-inject | UserPromptSubmit injects routing artifact; SessionStart injects cortex digest + memory recall; strict: PreToolUse deny direct-edit, Stop gate | Never rely on `maxTurns` (#41143) |
| **Codex CLI** | **T3** full-route-inject | UserPromptSubmit dual-mode; SessionStart inject; strict: PreToolUse deny | **Prereq G10: write `.codex/agents/*.toml`** — current `.md` files are dead weight; AGENTS.md ≤32 KiB budget |
| **Copilot** | **T2** static-inject + gate (→T3 pending GAP-1) | copilot-instructions.md + applyTo instructions (mechanically injected); hooks for CLI+cloud | `preToolUse` is fail-closed → advisory hooks must be exit-0-hardened; prereq G3/G8: write `.github/agents/*.agent.md` |
| **Cursor** | **T2** static-inject + gate | `.cursor/rules/eidolons-cortex.mdc` `alwaysApply` **dual-written with AGENTS.md** (3.0.16 regression hedge); strict: preToolUse/beforeShellExecution/beforeMCPExecution | **REFUSE `beforeSubmitPrompt` blocking** (persist-in-context bug); prereq G1/G4 |
| **OpenCode** | **T1** gate-only + floor | AGENTS.md concatenation; `agent.permission.task` globs encode the hand-off graph (the one *sound* block); plugin shim for events | `chat.system.transform` broken (#17100); `tool.execute.before` advisory-only while #5894 (subagent bypass) open |

**Degradation rules:** tier failure → next tier down, terminating at T0 = status quo (never worse). `doctor --deep` probes report the *effective* tier per host. Advisory hooks never fail closed. Prompt path ≤300 ms pure bash. Strict tier recorded in `eidolons.lock`; CLI refuses to write the two known-buggy block surfaces even under `--strict`.

---

## 4. Why this is the differentiator

1. **First-mover on the hook convergence.** All five vendors shipped blocking hooks within ~6 months; no agent-team framework installs a *cross-vendor* mechanical routing layer today. "One brain (`eidolons run`), five sockets" is a defensible position: vendor-neutral methodology + per-host mechanical enforcement, degradable to prose on any host that breaks.
2. **The kernel is deterministic and non-LLM** — same prompt, same roster ⇒ same route (I-C6), auditable via `--explain`, integrity-gated via ECL. Competitors' routing (LLM-chosen handoffs) is exactly the suggests-only pattern the research refuted.
3. **Memory becomes a guarantee, not a hope.** Hook-injected crystalium recall puts Eidolons in the Mem0 architectural class (platform-owned recall) while staying vendor-neutral — no other coding-agent framework offers that across five harnesses.
4. **Already 70 % built.** `eidolons run`, `verify-envelope --block`, `sandbox loop`, junction, crystalium, marker-bounded idempotent writers, doctor gates — the campaign is adapters + one new CLI verb, not a new system.

---

## 5. Roadmap

**P0 — correctness fixes that land regardless (small, immediate):**
- **G10:** Codex agent files — emit `.codex/agents/*.toml` (the `.md` files are never read). Roster/installer + EIIS template change.
- **G3/G8:** Copilot custom agents — emit `.github/agents/<name>.agent.md` (format is GA).
- Fix the CLAUDE.md footer's lexical gate ("that mentions an Eidolon" → unconditional read-before-non-trivial).

**P1 — `eidolons harness install` + T3 hosts (Claude Code, Codex):**
- New CLI verb family: `harness install|remove|status` (idempotent; jq canonical-merge for JSON surfaces, markers elsewhere; opt-in; lockfile-recorded).
- `eidolons run --hook <host>` output contracts (per-host hook-dialect JSON).
- Claude Code adapter: settings.json hooks (UserPromptSubmit inject, SessionStart inject); Codex adapter: `[hooks]` config + agents-toml.
- `eidolons memory preflight` (crystalium recall via CLI/docker-exec entrypoint — GAP-2).

**P2 — T2 hosts (Cursor, Copilot):**
- Cursor: `.cursor/rules/eidolons-cortex.mdc` (closes G4) + `.cursor/mcp.json` writer (closes G1) + hooks.json adapter (no prompt-block).
- Copilot: hooks adapter (exit-0-hardened) + instructions injection; resolve **GAP-1** (does Copilot hook output inject context? → if yes, T3).
- `.codex/config.toml` MCP writer (closes G2).

**P3 — OpenCode + strict tier:**
- OpenCode plugin shim (thin kernel shim, zero logic) + `opencode.json` MCP/permission writer (closes G5/G9); encode hand-off graph as `permission.task` globs.
- Strict-tier recipes: delegate-or-deny PreToolUse on T3 hosts, crystalium tier-gates, ECL verify-block in chains.
- `doctor --deep` host-surface probes → effective-tier report; canary per host.

**Open gaps:** [GAP-1] Copilot hook-output injection unverified (ATLAS). [GAP-2] crystalium recall outside an MCP session needs a CLI entrypoint (additive crystalium change). [WATCH] Cursor 3.0.16 alwaysApply regression; OpenCode #5894/#17100; Claude #41143.

**Reversal conditions:** MCP ships a control-plane/first-tool primitive → revisit router-MCP. ≥2 vendors destabilize prompt hooks → revisit wrapper for terminal hosts. Advisory compliance <80 % measured on T3 hosts → escalate default to block. Host bug fixes re-grade tiers upward.

---

## 6. Provenance

- External research: workflow `wf_ffdd9c8d-ccc` (18 agents — Sonnet search/verify, Haiku extraction; 302 tool calls; 112 verified rows, 41 corrections, 9 refuted claims). Primary sources: code.claude.com/docs (hooks/sub-agents/skills/settings), developers.openai.com/codex (hooks/subagents/config-reference/agents-md), docs.github.com + GitHub changelog (hooks reference, custom agents, MCP), opencode.ai docs + sst/opencode issues, cursor.com docs + forum (hooks v1.7, rules), modelcontextprotocol.io spec (2025-06-18 + draft), vendor issue trackers for bug verification.
- Internal scout: ATLAS A→T→L→A→S, 47 evidence anchors, 9 gaps, all H-confidence.
- Decision: FORGE deep deliberation (5 hypotheses, 4 stress-test families, weighted rubric), crystalium-checkpointed (episodic `d9724b4d`, plan `5e4df716`).

**Hand-off:** → SPECTRA for the `harness install` + `run --hook` spec (P1 scope; G10/G3 may proceed immediately). → ATLAS for GAP-1/GAP-2 probes before P2 freeze.

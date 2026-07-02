# v2.0 Research — OSS Landscape & Threats to Differentiation (2026-07-02)

> Bounded single-pass research (Sonnet worker, ~24 web calls + GitHub API star
> verification). Persisted condensed; unverified claims flagged.

## Comparison snapshot (stars verified via GitHub API 2026-07-02)

| System | Install | Routing | Cross-host? | Stars/activity |
|---|---|---|---|---|
| claude-flow/ruflo | MCP + .claude/ + 27 hooks | **Adaptive/learned** (SONA "neural router", emergent swarms) | mainly Claude Code | 62,650 / very active |
| BMAD-METHOD | npx installer, 34+ workflows, 12+ personas | workflow/role, prose | CC, Cursor, web bundles | 50,015 / active |
| spec-kit | .specify/ templates | n/a (single-agent spec tool) | 30+ hosts | **117,458** / most active |
| OpenSpec | .openspec/ | n/a; explicitly **rejects** phase gates | 25+ tools | 58,400 / active |
| wshobson/agents | per-host plugin dirs compiled from one Markdown source | LLM-driven (no rule engine) | **6 hosts incl. Copilot + Gemini CLI** | 37,450 / active |
| Agent OS | .agent-os/ | prose | CC, Cursor, Antigravity | 5,001 / 2mo stale |
| **Microsoft Conductor** | CLI + YAML workflows | **Deterministic** (Jinja2 first-match-wins, zero-token layer, Pre/PostToolUse+Stop hooks) | only 2 hosts (Copilot SDK, Anthropic Agents SDK) | 295 / young, MSFT-backed, AAIF-adjacent |
| A2A protocol | wire protocol (JSON-RPC, AgentCard) | n/a (cross-org RPC) | network-level | 24,595 ("150+ orgs" UNVERIFIED) |
| Mem0 / basic-memory / Cognee | MCP memory servers | n/a | yes — cross-host memory is a solved market | basic-memory 3,359 / active |
| LangGraph/CrewAI/AG2/OpenAI SDK/smolagents/Mastra/Pydantic-AI | libraries, not repo installs | LangGraph deterministic edges; CrewAI LLM; OpenAI SDK **typed handoffs** (closest ECL analog); Mastra unified model router | no (build-with, not install-into) | — |

## Threats to differentiation

- **The bundle is still unique**: nobody combines deterministic hook-enforced routing +
  typed/hashed envelopes + mechanically-gated lifecycle + persistent cross-host memory +
  zero-dependency install.
- **wshobson/agents**: closest on host breadth (6 incl. Copilot + Gemini CLI); a
  components marketplace, not a contracted team — but README-skim-confusable.
- **Microsoft Conductor**: closest on the routing claim; tiny today but Microsoft-backed
  and Linux-Foundation-adjacent. Quarterly watch (host expansion + velocity).
- **claude-flow**: 62.6k stars on the OPPOSITE bet (emergent/learned routing) — proof
  the emergent camp is viable, not that mechanical is wrong; auditability is the moat.
- **spec-kit/OpenSpec/Kiro**: spec-driven development is mainstream; OpenSpec's explicit
  "no rigid gates" makes ESL's mechanical gate an articulable difference.
- **Memory is the weakest solo leg** — cross-host memory is commoditized (Mem0 et al.);
  crystalium's edge is only its wiring into routing+handoff contracts (tiers, ISE,
  verifier-gated skills), not memory-as-a-feature.
- Market direction favors the Eidolons bet: OpenAI SDK typed handoffs + Conductor's
  deterministic-runtime framing independently converge on what ECL/kernel already ship.

## Top-10 lessons (agent's classifications)

1. ADOPT — Conductor-grade legibility for routing semantics: publish the kernel's
   first-match/scoring rules as diffable documented behavior (provable, not asserted).
2. ADOPT — Terminal-Bench canary-string technique: fixture prompt with unique marker,
   assert it surfaces in the ECL envelope/trace in CI (proves hooks actually fire).
3. ADAPT — single-Markdown-source compiled to per-host formats (wshobson) — evaluate
   vs per-Eidolon install.sh drift risk at 5+ hosts.
4. ADAPT — Mastra's model-router config shape (naming/ergonomics only).
5. ADAPT — cite OpenAI SDK handoffs as external validation of ECL positioning.
6. WATCH — Microsoft Conductor + Agentic AI Foundation (quarterly).
7. WATCH — A2A (orthogonal today; pressure if it grows a local-handoff profile).
8. WATCH — AG2/AutoGen fork as upstream-risk precedent (validates vendoring stance).
9. REJECT — claude-flow-style learned routing (erases the differentiation).
10. REJECT — bench-scale per-PR self-eval; realistic = nightly non-blocking canary of
    ~10-20 fixed prompts against real hosts.

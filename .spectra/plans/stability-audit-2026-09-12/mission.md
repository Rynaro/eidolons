# Stability investigation — ATLAS mission 20260912-001

GOAL: Investigate reported integration defects and specify individual fixes, without implementing them.

DECISION_TARGET: Which evidenced defects block a stable Eidolons release, in what order should they be fixed, and what acceptance checks demonstrate each fix?

Sub-questions: MCP lifecycle/startup; MCP installation/grants/usage; Codex descriptors/model execution; canonical instructions/hooks; context cost and useful augments.

Scope: cli/**, roster/**, schemas/**, scripts/**, methodology/**, .eidolons/**, repository integration files, relevant tests and official host contracts. Exclude implementation edits, external writes, installs, live container changes and private credentials.

Budget: max_tool_calls=100 per branch; max_tokens_input=25000 per branch; max_wall_clock_s=1200; max_subagents=3; max_recursion_depth=1. Stop when every sub-question has evidence or an explicit gap. Escalate only if an essential check requires external mutation or unavailable private session evidence.

Structural map: MCP process lifecycle → mcp_run/lib_mcp/mcp_reap; installation and grants → mcp_install/mcp_sync/lib_mcp_wiring; host dispatch/models → lib/dispatch_eidolon/lib_model_*; canonical adapters/hooks → lib_eiis_v3/lib_eidolons_md/harness_*. More than 25 relevant source files; independent lifecycle, grants, and host-contract questions.

Routing: ATLAS scouting → SPECTRA specifications; VIGIL-style reproduction checks where feasible. Standard model tier per step; bounded parallel ATLAS probes per scatter rules. RAMZA absent locally, so installed SPECTRA is the explicit fallback. No implementation handoff.

Memory/tool gap: CRYSTALIUM, ATLAS-ACI, ATOMOS and Junction tools are not exposed in this session; use bounded local probes and record this limitation. Actual token/context meters are unavailable; do not invent readings.

Parent sign-off: scope and decision target accepted. Deliver concise Markdown specs plus a machine-readable index under this directory.

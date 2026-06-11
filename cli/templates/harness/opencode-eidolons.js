// Eidolons OpenCode advisory plugin — tool.execute.before
// =========================================================
// CAVEAT (#5894): OpenCode's tool.execute.before hook does NOT intercept
// tool calls spawned by subagent Task invocations. This plugin applies to
// PRIMARY-AGENT edit/write tool calls only (the main agent context).
// Subagents (spawned via the Task tool) bypass this hook entirely.
// This is an ADVISORY shim — not a hard security boundary.
//
// Written by: eidolons harness install --strict (opencode wired)
// Strict mode: advisory (strict:advisory in eidolons.lock)
// Reference: Eidolons Harness P3, R18, R-plugin (spec-p3.md §4 AC-R18-7)
//
// OpenCode plugin API: https://opencode.ai/docs/plugins
// Zero external dependencies. Plain JS, no build step.

/** @type {import("@opencode/plugin").Plugin} */
export default {
  name: "eidolons-strict-advisory",
  description:
    "Advisory gate for Eidolons strict tier. Surfaces a delegation reminder " +
    "when the primary agent attempts a direct edit/write. Subagent calls " +
    "are NOT intercepted (#5894 bypass — primary-agent-only advisory).",

  hooks: {
    /**
     * tool.execute.before fires before a tool runs in the primary agent context.
     * If the tool is an edit or write, throw to surface a delegation message.
     *
     * IMPORTANT: This hook does NOT fire for tools called inside subagent Tasks (#5894).
     * Use claude-code strict (delegate-or-deny via PreToolUse) for a sound block.
     */
    "tool.execute.before": async ({ tool }) => {
      const editTools = new Set([
        "edit_file",
        "write_file",
        "create_file",
        "str_replace",
        "str_replace_based_edit_tool",
        // opencode native edit tool names (exact set may vary by version)
        "write",
        "edit",
      ]);

      if (editTools.has(tool.name)) {
        throw new Error(
          "[Eidolons strict advisory] Direct edit/write from the primary agent is " +
          "advisory-blocked. Delegate this edit to a coder Eidolon (Vivi) per the " +
          "routing artifact. Note: this block applies to the primary agent only — " +
          "subagent-spawned tool calls are NOT intercepted (#5894)."
        );
      }
    },
  },
};

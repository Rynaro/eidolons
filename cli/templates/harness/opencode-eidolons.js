// Eidolons OpenCode plugin — strict advisory gate + ECM context adapter
// =========================================================
// TWO independent capabilities share this one file because OpenCode loads
// exactly one plugin file per project (.opencode/plugins/eidolons.js):
//
//   1. STRICT ADVISORY GATE (tool.execute.before) — written when
//      'eidolons harness install --strict' wires opencode's strict tier.
//      See CAVEAT (#5894) below.
//   2. ECM CONTEXT ADAPTER (experimental.chat.system.transform +
//      experimental.session.compacting) — written when 'context:' is on for
//      opencode (ECM P2 Track B). OpenCode's plugin-event surface gives ECM
//      exactly two channels here: a system-prompt transform (start + every
//      turn) and a session-compacting hook. There is NO per-tool /
//      tool-boundary channel for ECM on OpenCode — this file makes no such
//      claim; ECM's OpenCode tier is T1 (system-prompt), never full ladder.
//
// CAVEAT (#5894): OpenCode's tool.execute.before hook does NOT intercept
// tool calls spawned by subagent Task invocations. This plugin applies to
// PRIMARY-AGENT edit/write tool calls only (the main agent context).
// Subagents (spawned via the Task tool) bypass this hook entirely.
// This is an ADVISORY shim — not a hard security boundary.
//
// Written by: eidolons harness install --strict (opencode wired), and/or
//             eidolons harness install with 'context:' on (opencode wired)
// Strict mode: advisory (strict:advisory in eidolons.lock)
// ECM: system-prompt meter, tier T1 (docs/specs/ecm/spec.md, Track B)
// Reference: Eidolons Harness P3, R18, R-plugin (spec-p3.md §4 AC-R18-7)
//
// OpenCode plugin API: https://opencode.ai/docs/plugins
// [ASSUMPTION OC1]: the exact experimental.chat.system.transform /
// experimental.session.compacting payload shapes are inferred from
// OpenCode's plugin docs, not independently confirmed in-repo — mirrors
// [ASSUMPTION A1] (codex hooks.json) / [A-CODEX-CFG] (codex autocompact
// config) elsewhere in the harness. Every ECM hook below is wrapped in its
// own try/catch and fails open: never throws, never blocks the chat turn
// or the compaction, degrades silently to "no line added" on any error.
// Zero external dependencies. Plain JS (Node/Bun built-ins only), no build step.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

// ── ECM: read the live meter (Track B) ─────────────────────────────────────
// Prefer a fresh 'eidolons context status --json' read; fail open to the
// on-disk meter.json sidecar the harness hook shims already maintain for
// every other host. Never throws — returns null on any failure.
function _ecmReadMeter() {
  try {
    const raw = execFileSync("eidolons", ["context", "status", "--json"], {
      encoding: "utf8",
      timeout: 3000,
      stdio: ["ignore", "pipe", "ignore"],
    });
    const parsed = JSON.parse(raw);
    return { zone: parsed.zone || "unknown", utilization: parsed.utilization ?? null };
  } catch (_e) {
    try {
      const raw = readFileSync(".eidolons/.context/meter.json", "utf8");
      const parsed = JSON.parse(raw);
      return { zone: parsed.zone || "unknown", utilization: parsed.utilization ?? null };
    } catch (_e2) {
      return null;
    }
  }
}

// ── ECM: the SessionStart pin digest (start-of-session only, Track B) ──────
// Reuses the SAME host-agnostic SessionStart flow every other wired host
// gets — harness_hook.sh's session_start mode branches on hook_mode, not
// host string, so no new kernel code is needed. Extracts just the pins
// line so the system-prompt injection stays small. Fails open to null.
function _ecmReadPinDigest() {
  try {
    const raw = execFileSync(
      "eidolons",
      ["run", "--hook", "opencode", "--session-start"],
      { encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }
    );
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    const ctx =
      (parsed && parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext) || "";
    const m = ctx.match(/Pins \([^\n]*\n?[^\n]*/);
    return m ? m[0].trim() : null;
  } catch (_e) {
    return null;
  }
}

// Module-scoped: fires once per plugin lifetime (one opencode session), not
// on every turn — this is what makes the pin digest a "start" injection.
let _ecmStartDigestSent = false;

/** @type {import("@opencode/plugin").Plugin} */
export default {
  name: "eidolons-opencode-adapter",
  description:
    "Advisory gate for Eidolons strict tier PLUS the ECM P2 context adapter " +
    "(system-prompt meter + compaction externalize). Two independent " +
    "capabilities, each gated independently at install time.",

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

    /**
     * experimental.chat.system.transform fires on every turn, letting a
     * plugin mutate the outgoing system prompt (output.system) before the
     * model sees it. ECM uses this as its ONLY live channel on OpenCode: a
     * start-of-session pin digest (once) plus a per-turn meter line. Fails
     * open — any error here must never block the chat turn.
     */
    "experimental.chat.system.transform": async ({ output }) => {
      try {
        if (!output || typeof output !== "object") return;
        if (!Array.isArray(output.system)) {
          output.system =
            typeof output.system === "string" && output.system ? [output.system] : [];
        }
        if (!_ecmStartDigestSent) {
          _ecmStartDigestSent = true;
          const pinDigest = _ecmReadPinDigest();
          if (pinDigest) output.system.push(pinDigest);
        }
        const meter = _ecmReadMeter();
        if (meter) {
          const util = meter.utilization == null ? "unknown" : meter.utilization;
          output.system.push(`Context: zone=${meter.zone} util=${util}`);
        }
      } catch (_e) {
        // fail-open: never throw, never block the chat turn.
      }
    },

    /**
     * experimental.session.compacting fires when OpenCode is about to
     * compact the session. ECM externalizes state first (crystalium when
     * present, file-floor otherwise) so nothing is lost across the op.
     * Fails open — any error here must never block the compaction.
     */
    "experimental.session.compacting": async () => {
      try {
        execFileSync(
          "eidolons",
          ["context", "externalize", "--summary", "opencode session compacting"],
          { timeout: 5000, stdio: "ignore" }
        );
      } catch (_e) {
        // fail-open: never throw, never block the compaction.
      }
    },
  },
};

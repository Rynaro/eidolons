# Verify-fail attribution — AC-4 / AC-9 (2026-07-07)

**Verdict:** NOT a maker defect. Confirmed upstream capability gap
(pre-registered as GAP-D5-ingest in spec.yaml; FORGE D5 bounded the downside).

## Evidence

1. `eidolons canary --context-handoff` (worktree build, live crystalium 1.7.0):
   both legs fail at the **ingest** step — `crystalium_ingest did not succeed —
   cannot verify recall`. Recall was never reached; AC-9's printed
   quarantine diagnosis is downstream noise of the same ingest failure.
2. Structural probe against the pinned image
   (`ghcr.io/rynaro/crystalium@sha256:b6978817…`, v1.7.0):
   one-shot CLI commands = `canary commit doctor dream export forget index
   promote quarantine recall serve` — **`Error: No such command 'ingest'`**.
   `ingest` exists only on the MCP tool surface (9 tools).
3. Maker behavior per spec: `lib_context.sh:context_try_ingest` fails open
   (file floor), never fabricates success, never falls back to `commit`
   (AC-16 frozen constraint honored).

## Precedent

Identical shape to DOSSIER-HARNESS GAP-2: out-of-session `recall` → shipped as
crystalium 1.4.0; out-of-session `commit` → shipped as 1.7.0 ("write half…
unblocks the nexus round-trip memory canary"). `ingest` is the missing third
verb of the pairing.

## Required upstream (CRYSTALIUM → 1.8.0, additive)

- One-shot `ingest` CLI verb (ECL-envelope in, tier derivation + MIN-trust +
  `contains_tool_origin` provenance preserved — parity with the MCP tool).
- AC-9 companion: default recall (or a scoped flag usable by
  `memory preflight --query`) must surface `topic_key: session_handoff`
  records even when quarantined-flagged — per the pre-registered remedy:
  a scoped recall surface, NOT a commit-based persist switch (D5
  reversal-condition).

## Change disposition

`ecm-context-kernel` holds at `in_progress`: 15/17 ACs checker-verifiable now;
AC-4/AC-9 are live-verify blocked on the upstream verbs. Criteria remain frozen
(SHA `6e0b9b10…`) — no descoping; the change completes when crystalium 1.8
lands and the canary round-trip passes.

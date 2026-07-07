---
Title: Roster atomos as the 5th MCP
Version: 1.0.0
Date: 2026-07-07
Author: orchestrator (roster addition; scribed — tonberry container writes SELinux-blocked this session)
tier: lite
Target: roster/mcps.yaml, cli/templates/mcp/atomos.mcp.json.tmpl
---

# Roster atomos as the 5th MCP (LITE spec)

## Framing

`Rynaro/atomos` v0.1.0 shipped (the ECM compose/verify executor MCP — a Go stdio
server, the tonberry-analog for the context lifecycle). This change adds it to the
nexus MCP catalogue so `eidolons mcp install atomos` can wire it, making it the
**5th sibling MCP** (atlas-aci · junction · crystalium · tonberry · **atomos**).

Atomos is an **alternate surface** to the canonical `eidolons context` bash kernel:
same inputs ⇒ same bytes (T1 brief + T2 envelope byte-parity, CI drift-guarded).
The kernel verbs remain what Eidolons use; atomos is orchestrator/host-facing, so it
is rostered `wiring_mode: transport` (registered in `.mcp.json`, never injected into
an Eidolon's `tools:` allowlist — the same posture as junction).

## Scope / non-goals

- IN: the `atomos` catalogue entry in `roster/mcps.yaml` (source ghcr, versions with
  the v0.1.0 INDEX digest, `exposes_tools` = the closed 3-tool set, `install.template`)
  and the run template `cli/templates/mcp/atomos.mcp.json.tmpl`.
- OUT: `roster/index.yaml` (MCPs live in `mcps.yaml` only; crystalium is the special
  dual-tracked case — the skew guard is crystalium-specific and unaffected here);
  local install into THIS project (a separate `eidolons mcp install atomos`); any
  change to atomos itself (its own repo); nexus kernel edits.

## Design notes

- **Digest**: `sha256:ff2449e92cae030e8cb25796c2b9e06ad4814e59ac6db8fc19beffc5606d8a73`
  — the multi-arch INDEX digest captured by the atomos release workflow into
  `release-manifest.json` (v0.1.0, commit 5c10193, `github_attestation: true`).
- **Template**: mirrors `tonberry.mcp.json.tmpl` (both are workspace-mounting stateless
  executors). Mounts `__PROJECT_ROOT__:/workspace:z` — atomos writes the handoff
  sidecar pair under `.eidolons/.context/`; the `:z` SELinux relabel is carried over
  from the tonberry template fix (inert on non-SELinux hosts). `--cap-drop ALL` +
  `--security-opt no-new-privileges` matches atomos's capability-starvation fence
  (no network, no crystalium mount).
- **Tools**: `mcp__atomos__{compose_handoff,verify_envelope,verify_pins}` — the closed
  set enforced in atomos by a registry-exact + source deny-list fence.

## Acceptance checks

**AC-1 — atomos is in the catalogue.** `yq '.mcps[].name' roster/mcps.yaml` lists
five, ending in `atomos`; `eidolons mcp list` shows `atomos` at stable `0.1.0`.
- verify_method: observed 2026-07-07 (5 MCPs; `atomos … 0.1.0 install missing`).

**AC-2 — schema + guards clean.** The atomos entry is strictly schema-conformant and
the existing gates are unaffected.
- verify_method: `jsonschema` Draft7 → atomos (mcps[4]) 0 errors; `make schema` passes;
  `check_roster_mcp_skew` OK (crystalium 1.8.0 match).

**AC-3 — digest is the real, attested INDEX.** The pinned digest matches the v0.1.0
release-manifest.
- verify_method: `release-manifest.json` `manifest_sha256` == the rostered digest.

**AC-4 — template is valid + fenced.** `jq empty` the template; it mounts `:z` and
drops all capabilities.
- verify_method: `jq empty cli/templates/mcp/atomos.mcp.json.tmpl`; grep `:/workspace:z`
  + `--cap-drop ALL`.

## Notes for the executor

- Pure roster/data + one template; no CLI code path changes. `eidolons mcp install
  atomos` (generic driver) wires it — no per-MCP install code needed (unlike the
  bespoke `mcp_atlas_aci*` path, atomos is a plain oci-image executor like tonberry).

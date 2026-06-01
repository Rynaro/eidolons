# Cortex Deep — Hand-off Graph

> Load this file when composing a multi-Eidolon chain or auditing
> which edges are declared vs inferred. See `EIDOLONS.md` for the
> always-loaded routing cortex.

---

## Canonical Hand-off Graph

The cortex adopts the **union** of roster-declared edges and
`methodology/composition.md` prose-described edges, with origin labels.
Every chain step records `edge_origin: "roster" | "composition" | "implicit"`.

```
ATLAS  ──(roster:downstream)──▶  SPECTRA
ATLAS  ──(roster:downstream)──▶  APIVR-Δ        # documented bypass
SPECTRA ──(roster:downstream)──▶ APIVR-Δ
APIVR-Δ ──(roster:downstream)──▶ IDG
SPECTRA ──(composition.md)────▶  IDG            # plan-only docs
ATLAS  ──(composition.md)────▶  IDG            # read-only audits
VIGIL  ──(roster:lateral)──────▶ SPECTRA / IDG / FORGE / ATLAS / APIVR-Δ
FORGE  ──(composition.md:67-68)▶ <any caller>  # consultation return
ANY    ──(any)──▶  human                        # implicit terminal
```

Lateral edges are bidirectional; both directions are roster-declared via the lateral array
(`vigil.handoffs.lateral: [atlas, spectra, apivr, idg, forge]`). VIGIL→{atlas,spectra,apivr,idg,forge}
edges previously marked `[DISPUTED]` (OQ-3) are now confirmed roster-declared.

---

## Disambiguation Table

| Prompt class | Default route | Override condition |
|---|---|---|
| "Fix the bug" | APIVR-Δ standard | Prior attempt failed in this conversation OR stack trace + "flaky" → VIGIL |
| "Design X" | SPECTRA standard | Prompt also asks to write code → SPECTRA → APIVR-Δ chain |
| "Find and fix" | ATLAS → APIVR-Δ direct | Surface > complexity threshold OR "unclear requirements" → ATLAS → SPECTRA → APIVR-Δ |
| "Document this" | IDG | Prior artifact missing on disk → re-route ATLAS first (IDG refuses retrieval) |
| "Should we use X or Y?" | FORGE | Decision is also implementable → FORGE → SPECTRA chain |
| "Audit the auth flow" | ATLAS standard | Auditor wants written narrative → ATLAS → IDG |
| "Write a runbook" with no source artifacts | CLARIFY (IDG cannot retrieve) | User provides artifacts → IDG |

---

## Chain Template Justifications

| Template | Edge origins | Spec source |
|---|---|---|
| plan-before-build | roster (ATLAS→SPECTRA), roster (SPECTRA→APIVR-Δ), roster (APIVR-Δ→IDG) | MANIFESTO.md §"What you can do" row 1; composition.md |
| audit-without-touching | composition.md (ATLAS→IDG) | Preset `research`; MANIFESTO.md:79 |
| ship-fast | roster (SPECTRA→APIVR-Δ) | Preset `plan-and-build` |
| direct-implementation-bypass | roster (ATLAS→APIVR-Δ) | roster/index.yaml:60; spec §7.3 |
| decide-then-implement | composition.md (FORGE→caller), roster (SPECTRA→APIVR-Δ) | composition.md:60-69 |
| forensic-then-fix | composition.md (VIGIL→APIVR-Δ) | roster/index.yaml:298; composition.md:46-48 |
| failed-attempt-recovery | composition.md (APIVR-Δ failure → VIGIL) | apivr-failure-recovery/SKILL.md:14-27 |
| decision-only | (terminal FORGE) | composition.md:60-69 |

---

## Hand-off Transport Policy

When composing a multi-Eidolon chain, the physical transport for ECL envelopes
depends on whether junction is present in the project:

| Condition | Transport mechanism |
|---|---|
| `junction` installed + `.mcp.json` registered | Parent/orchestration layer dispatches ECL envelopes over the junction bus via `mcp__junction__*` tools |
| `junction` absent | ECL-on-disk sidecar (`ecl-envelope.json` adjacent to the artefact) is the fallback |

**Keystone rule:** junction's `grants_to_eidolons: all` in `roster/mcps.yaml` is
**transport-eligibility**, NOT allowlist-injection. Concretely:

- `mcp__junction__*` tools are registered in the project `.mcp.json` (a project-wide
  transport surface reachable by all hosts — claude-code, cursor, opencode).
- `mcp__junction__*` tools **never** appear in any agent's `tools:` allowlist line.
  They are not wired into ATLAS, SPECTRA, APIVR-Δ, IDG, FORGE, or VIGIL tool lists.
- `wiring_mode: transport` in the catalogue encodes this distinction explicitly.
  The `mcp_wiring_grant_targets` function short-circuits on this field, producing
  zero agent-file targets.

The parent (orchestration layer) reads the project `.mcp.json` to discover the
junction bus endpoint; individual Eidolons do not interact with junction directly.

---

## ATLAS MCP-first When atlas-aci Present

When `atlas-aci` is installed in the target project (i.e. `mcp__atlas_aci__*`
tools are wired into ATLAS's `tools:` allowlist), ATLAS applies MCP-first
precedence for structural reads:

| Structural task | Preferred | Fallback |
|---|---|---|
| View a file | `mcp__atlas_aci__view_file` | `Read` |
| Search symbol | `mcp__atlas_aci__search_symbol` | `Grep` / `rg` |
| Search text | `mcp__atlas_aci__search_text` | `Grep` / `rg` |
| List directory | `mcp__atlas_aci__list_dir` | `Glob` |
| Graph query | `mcp__atlas_aci__graph_query` | — (no native equivalent) |

This is the opposite of junction's transport model: `atlas-aci` is a genuine
**in-agent capability** that is injected into ATLAS's allowlist (the only Eidolon
it grants to, per `grants_to_eidolons: [atlas]`). MCP-first preference maximises
the structural intelligence of the graph backend while keeping native tools as a
reliable fallback when atlas-aci is absent.

---

## Open Questions Carried Forward

| ID | Assumption | Mitigation |
|---|---|---|
| OQ-3 | VIGIL lateral edges are roster-declared via `vigil.handoffs.lateral`. | Resolved 2026-05-08 — `[DISPUTED]` markers removed; lateral array is the authoritative roster declaration. |
| OQ-6 | Max 2 reroutes per turn is sufficient to prevent ping-pong. | Raise cap with explicit `[BLOCKED]` exit; never remove the cap. |

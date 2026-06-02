# Smoke Test — full setup & verification

A step-by-step install you can run end-to-end to confirm a healthy Eidolons
deployment, then five focused checks that the team behaves as designed:

1. Eidolons agents are defaulted in sessions
2. TRANCE (delegate-by-default) is applied
3. Junction acts as the communication layer
4. CRYSTALIUM memory is respected and used
5. ATLAS is efficient for the other Eidolons

> Targets **nexus v1.15.0**. Every command and PASS signal below is real for that
> release. See also [`getting-started.md`](getting-started.md), [`mcp.md`](mcp.md),
> and [`cli-reference.md`](cli-reference.md).

---

## Prerequisites

- `git`, `bash`, `curl` — the installer auto-installs `yq`/`jq` if missing.
- **Docker running** — required for CRYSTALIUM and atlas-aci (both are
  `oci-image` MCPs). Junction is a plain binary; no Docker needed for it.
- A host LLM with subagent support. These checks assume **Claude Code**
  (`claude`); the same shape applies to other hosts with per-agent files.

---

## Part A — Install the CLI (one-time, global)

```bash
# Pin to the released nexus so the smoke test is reproducible.
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | EIDOLONS_REF=v1.15.0 bash

# If `eidolons` isn't on PATH yet, the installer prints the bin dir — add it, then:
eidolons version          # ✅ EXPECT: eidolons 1.15.0
```

## Part B — Create a scratch project

```bash
mkdir ~/eidolons-smoketest && cd ~/eidolons-smoketest
git init -q               # some checks expect a repo; harmless either way
```

## Part C — Install the full roster

```bash
# Interactive (detects host, prompts):
eidolons init --preset full

# …or fully scripted / reproducible:
eidolons init --preset full --hosts claude-code --non-interactive
```

Installs all six Eidolons (`atlas, spectra, apivr, idg, forge, vigil`), writes the
always-loaded cortex `EIDOLONS.md`, per-agent files under `.claude/agents/`, and a
dispatch pointer into `CLAUDE.md`.

## Part D — Install the MCP layer

```bash
# 1) Junction — communication bus (binary, transport-only)
eidolons mcp install junction

# 2) CRYSTALIUM — shared memory (OCI image; pre-pull so the first session is fast)
docker pull ghcr.io/rynaro/crystalium:1.2.0
eidolons mcp install crystalium

# 3) (optional, for check #5) atlas-aci — ATLAS's structural-read MCP
docker pull ghcr.io/rynaro/atlas-aci:latest     # or the digest from: eidolons mcp show atlas-aci
eidolons mcp install atlas-aci
```

## Part E — Reconcile + health check

```bash
eidolons sync             # mirrors cortex into .eidolons/cortex/, reconciles state
eidolons doctor           # ✅ EXPECT: checks pass (Check 3 host wiring, Check 7 MCP servers)
eidolons mcp health --all # ✅ EXPECT: junction ok; crystalium image_local ok + docker daemon ok
```

---

## The five checks

Static checks run in your shell. **Behavioral** checks run inside a `claude`
session started **from the project dir** (`cd ~/eidolons-smoketest && claude`).

### 1. Eidolons agents are defaulted in sessions

**Static:**

```bash
ls .claude/agents/                              # ✅ atlas.md spectra.md apivr.md idg.md forge.md vigil.md
test -f EIDOLONS.md && echo "cortex present"    # ✅ always-loaded routing cortex
grep -c "Roster Index" EIDOLONS.md              # ✅ ≥1 (the descriptor table)
```

**Behavioral (in `claude`):** run `/agents` → ✅ the six Eidolons are listed as
available subagents. The cortex is auto-loaded, so the model knows the roster at
session start.

### 2. TRANCE is applied (delegate-by-default)

**Static** — confirm the v1.14.0 delegate-by-default mandate is wired:

```bash
grep -i "delegate by default\|mandatory-unless-trivial\|Default operating mode" EIDOLONS.md CLAUDE.md
# ✅ EXPECT: matches (the cortex routes non-trivial work through Eidolons by default)
```

**Behavioral:** give a **non-trivial** prompt, e.g. *"Add input validation to the
user signup flow."* → ✅ PASS if the session **routes to an Eidolon** (ATLAS to
scout → SPECTRA to spec → APIVR-Δ to build) instead of editing inline. A trivial
prompt (*"what's 2+2?"*, *"rename this variable"*) should **not** trigger
delegation — that is correct, not a failure.

> "TRANCE applied" here means work flows through the **delegation pipeline**. The
> gated cost-*tier* (also named TRANCE) stays off by default — don't expect a tier
> escalation unless a complexity flag **and** a stakes flag both fire.

### 3. Junction is the communication layer

**Static:**

```bash
jq '.mcpServers.junction' .mcp.json             # ✅ junction server entry present
# Transport-only by design — junction tools are NOT in agent allowlists:
grep -l "mcp__junction__" .claude/agents/*.md || echo "✅ correct: junction NOT injected (transport-only)"
eidolons mcp list | grep junction               # ✅ installed + healthy
```

**Behavioral:** run a **multi-Eidolon** task (*"scout this repo then plan a
refactor."*). The parent dispatches each hand-off **over the junction bus** (ECL
envelopes), with on-disk `*.envelope.json` sidecars as the fallback. ✅ PASS if
hand-offs carry ECL envelopes (you'll see `mcp__junction__harness_*` activity / a
junction trace) rather than only loose files.

### 4. CRYSTALIUM memory is respected and used

**Static** — the T1 unlock + per-agent wiring:

```bash
jq -r '.mcpServers.crystalium.args[]' .mcp.json | grep -E "CRYSTALIUM_CALLER_TIER=T1|/.crystalium/"
# ✅ EXPECT: CRYSTALIUM_CALLER_TIER=T1 present AND an absolute $HOME path (no literal __HOME__)
grep -l "mcp__crystalium__" .claude/agents/*.md  # ✅ injected into all six agents (allowlist)
```

**Behavioral — the real test (memory persists across sessions):**

1. Session 1: run a small task (*"document how config loading works."*). ✅ Watch
   for `mcp__crystalium__recall` at the start and `mcp__crystalium__ingest`
   (+ `session_end`) at the end of the Eidolon's run.
2. End the session.
3. Session 2 (new `claude`): *"What did we learn about config loading last time?"*
   → ✅ PASS if `recall` surfaces the prior crystal. Cross-session memory lives in
   `~/.crystalium/<project-slug>/` — confirm it grew: `ls -la ~/.crystalium/*/`.

### 5. ATLAS is efficient for the other Eidolons

Checks that ATLAS's scouting **accelerates** downstream members — its scout-report
lands in memory at T1, so SPECTRA/APIVR-Δ recall it instead of re-scouting — and,
if atlas-aci is installed, that ATLAS reads structurally rather than brute-force.

**Static (if atlas-aci installed):**

```bash
grep -l "mcp__atlas_aci__" .claude/agents/atlas.md   # ✅ ATLAS has structural-read tools
```

**Behavioral:** run a chained task (*"audit the auth module, then plan a change to
it."*).

- ✅ ATLAS scouts once and emits a scout-report; it is `ingest`ed to CRYSTALIUM at T1.
- ✅ When SPECTRA takes over, it **recalls ATLAS's findings** (you'll see a `recall`
  hit referencing the scout-report) rather than re-reading the whole module — that
  is the efficiency signal.
- ✅ With atlas-aci present, ATLAS uses `mcp__atlas_aci__*` for the structural map
  (codegraph-backed) instead of raw file sweeps.

---

## Pass / fail rollup

| # | One-line check | Pass signal |
|---|----------------|-------------|
| 1 | `ls .claude/agents/` + `/agents` | six agents present & listed |
| 2 | grep cortex + non-trivial prompt | routes to an Eidolon, not inline |
| 3 | `jq .mcpServers.junction .mcp.json` | entry present, NOT in agent tools, healthy |
| 4 | `grep CRYSTALIUM_CALLER_TIER=T1` + cross-session recall | T1 wired, recall returns prior crystal |
| 5 | chained audit→plan | downstream recalls ATLAS's report; atlas-aci structural reads |

**If something fails:** `eidolons doctor` is the first stop (host wiring, MCP
servers, drift). For MCP-specific issues, `eidolons mcp health --all`. For memory
not persisting, confirm the Docker daemon is up and `~/.crystalium/<project>/` is
writable.

## Two things that look like failures but aren't

- **Junction tools are deliberately absent from agent `tools:` lists.** That is the
  transport-only design (the parent dispatches over the bus), not a wiring bug.
  Only CRYSTALIUM and atlas-aci are injected into agents.
- **A trivial prompt not triggering delegation is correct** for check 2 — the
  delegate-by-default mandate is *mandatory-unless-trivial*.

# Harness Mechanization — `eidolons eval compliance` Spec (A/B routing-compliance instrument)

> SPECTRA planning artifact · 2026-06-11 · campaign `harness-mechanization`
> Intent: `REQUEST` · Complexity 9/12 (extended) · Confidence 88%
> Hand-off: → Vivi (coder, loop-native) — net-new bash module + suite + bats + docs + runbook.
> Sibling specs: `spec.md` (P1 harness), `spec-p2.md`, `spec-p3.md`, `spec-gap2.md`.

---

## 0. Framing

The FORGE harness decision (`DOSSIER-HARNESS-2026-06.md`) ships routing-context
injection as an **advisory** default (cortex digest + per-prompt route hint via
hooks) and reserves a **block** tier (`--strict` delegate-or-deny) behind opt-in.
The dossier records a reversal condition (line 106):

> "Advisory compliance <80 % measured on T3 hosts → escalate default to block."

That condition is **aspirational** — there is no instrument that measures whether
the advisory injection actually changes a host LLM's behaviour (does it delegate
to the routed Eidolon, or ignore the hint and act in the main loop?). This spec
builds that instrument: a two-arm A/B behavioral measurement that runs the same
prompt corpus through a real headless host (`claude -p`) with and without the
harness wired, parses the resulting tool-call stream for `Task(<eidolon>)`
dispatches, and reports the delegation-rate delta plus a GATE line vs the 80%
threshold.

**This is the first DELEGATION-behavioral Eidolons number.** Prior evals measure
the kernel (`eval routing`, deterministic), structural conformance (`eval
quality`, mechanical grep), or task-solving orchestration (`eval swe`, sandbox
loop). None measures *whether a host LLM obeys the route*. `eval compliance` is
that fourth mode — and unlike the others its headline number is **non-deterministic**
(a model is in the loop), so the Coder-7.5 `pass^k` discipline applies: k=1 is
noise for any headline claim.

**Adapter-not-engine stance (inherited from `eval_swe`).** The nexus owns the
HARNESS — fixture generation, the driver contract, stream parsing, metrics, gates,
the suite format. It embeds NO model. The model is supplied by the pluggable
`--driver` (default `claude -p`). The live driver is the **only** network/billed
path and fires only behind `--yes`. CI and bats never call a live model: they run
the entire pipeline against a FAKE driver that replays canned stream-json fixtures.

### The variable under test (the whole point of A/B)

| | ARM A (treatment) | ARM B (control) |
|---|---|---|
| Consumer wiring | full (`eidolons.yaml`/`.lock`, cortex, CLAUDE.md, agent stubs) | **identical** |
| `harness install` | YES — hooks live in `.claude/settings.json` | NO — documentary cortex only |
| What the host sees | SessionStart cortex digest + per-prompt UPS route hint | the cortex pointer in CLAUDE.md only |
| Measures | does the mechanical hook injection raise delegation? | baseline delegation from prose cortex alone |

The ONLY difference between the two fixtures is `harness install`. Everything else
is byte-identical, so the measured Δ(A−B) is attributable to the harness, not to
fixture noise. ARM A self-verifies its wiring before measuring (D-C8) — a broken
instrument must abort loudly, never produce a silently-vacuous arm.

---

## 1. Complexity Assessment (SPECTRA Scope)

| Dimension | Score /3 | Rationale |
|---|---|---|
| Scope breadth | 3 | Driver + offline fixture builder + stream parser + metrics + gates + suite YAML + bats + 3 doc surfaces + runbook. |
| Technical depth | 2 | Net-new headless-Claude integration (no prior art in-repo), stream-json parsing, Task-dispatch detection. Bounded by the verified driver contract. |
| Integration surface | 2 | New `eval compliance` mode in `eval.sh`; reuses `run.sh` (`--hook`, `--json`), `harness_install.sh`, cortex mirror, roster. No schema migration. |
| Ambiguity / rework risk | 2 | Orchestrator decisions D-C1..D-C8 retire most ambiguity; residual risk is the live stream-json shape (FAKE-driver-first dev de-risks it). |
| **Total** | **9/12** | **Extended thinking — 7–9 band.** Single-pass S→P→E→C→T→R→A (no TRANCE: stakes are real but this is one bounded module, not multi-service architecture). |

---

## 2. Requirements Index

| ID | Requirement | Files |
|---|---|---|
| **R30** | `eval_compliance.sh` (driver, fixture builder, parser, metrics, gates) + `eval.sh` dispatch + the suite YAML | `cli/src/eval_compliance.sh` (new), `cli/src/eval.sh`, `evals/compliance-suite.yaml` (new), `schemas/compliance-suite.schema.json` (new) |
| **R31** | Fake-driver smoke + bats coverage | `cli/tests/eval_compliance.bats` (new), `cli/tests/fixtures/compliance/*.jsonl` (new) |
| **R32** | Docs | `CHANGELOG.md`, `docs/cli-reference.md`, `docs/architecture.md` |
| **R33** | Live-run runbook | `.spectra/harness-mechanization/runbook-compliance.md` (new) |

The orchestrator decisions D-C1..D-C8 are mapped onto these requirements below and
referenced inline by tag.

---

# R30 — `eval_compliance.sh` + dispatch + suite (the instrument)

The bulk of the work. One new bash module, one new suite, one new schema, a 3-line
dispatch edit. Split into sub-requirements R30.1–R30.7 for review and sequencing.

## R30.0 — Module skeleton, flags, stderr discipline

`cli/src/eval_compliance.sh` follows the exact header/sourcing/flag-loop shape of
`eval_swe.sh` (the structural analogue). It is invoked as `eidolons eval
compliance [OPTIONS]`.

### Dispatch wiring (D-C1) — `cli/src/eval.sh`

`eval.sh` already routes its own subcommands internally (lines 59–65). `compliance`
is added there alongside `quality`/`swe` — **there is no second allowlist** (the
mcp-verb double-allowlist trap from memory does NOT apply here; `cli/eidolons`
dispatches `eval` → `eval.sh` and `eval.sh` owns the sub-verb). Two edits:

1. `case "$SUBCMD"` (line 59): add `compliance) exec bash "$SELF_DIR/eval_compliance.sh" "$@" ;;`
2. `usage()` (lines 28–56): add the `compliance` line to the mode list and to the
   `Usage: eidolons eval <routing|quality|swe|compliance>` synopsis.

> **TEST (R31):** `eidolons eval compliance --help` exits 0 and prints a help body;
> `eidolons eval --help` lists `compliance`.

### Flag contract (D-C3, D-C6, D-C7)

```
eidolons eval compliance [OPTIONS]

  --suite-file PATH    Suite YAML (default: evals/compliance-suite.yaml).
  --driver CMD         Driver command (default: built-in claude -p invocation).
                       Receives the prompt on argv ("$@") OR on stdin; emits
                       stream-json (one JSON object per line) to stdout.
  --model NAME         Model for the default claude driver (default: sonnet).
  --max-turns N        Per-session turn cap (default: 3 — we measure whether an
                       EARLY Task(eidolon) dispatch fires, not task completion).
  --k N                Repeat each (prompt × arm) N times (default: 1). Reports
                       pass^k-style per-prompt stability. k=1 is NOISE for a
                       headline claim (Coder-7.5 lesson) — the runner says so.
  --arm A|B|both       Which arm(s) to run (default: both).
  --smoke              Run the WHOLE pipeline against the FAKE driver (canned
                       fixtures). No model, no network. CI/bats path. Implies a
                       fixed deterministic driver; ignores --driver/--model.
  --dry-run            Build fixtures + print the session-count cost envelope and
                       exit 0 WITHOUT calling any driver.
  --yes                Confirm a LIVE billed run. REQUIRED for any non-smoke,
                       non-dry-run invocation that would call a real model.
  --keep               Keep the mktemp fixture projects (default: cleaned up).
  --min N              Exit 1 if ARM-A delegation_rate < N percent (the FORGE
                       gate; default threshold 80 when --gate is set).
  --gate               Print the explicit GATE line vs 80% and set exit policy
                       (exit 1 if arm-A correct_target_rate < 80).
  --json               Emit the scorecard as JSON (stdout). Default: text.
  -h, --help           Show this help.
```

**P0 discipline (HARD CONSTRAINTS):**
- bash 3.2: no `declare -A`, no `${var,,}`, no `readarray`/`mapfile`, no `&>>`.
  Lowercasing via `tr`; arrays are plain indexed; empty-array expansion is the
  `"${arr[@]+"${arr[@]}"}"` form already used in `eval_swe.sh:213`.
- **Stderr discipline:** every `say/ok/info/warn/die` to stderr; **stdout is the
  scorecard only** (text card or `--json`). The cost-envelope banner and the GATE
  line go to **stderr** unless `--json` (where the gate verdict is a JSON field).
- No `eval` of consumer config; fixtures are generated mechanically.
- `set -euo pipefail`.

### Argument validation (fail-fast, actionable)

- `--k`, `--max-turns` must be `>= 1` (mirror `eval_swe.sh:105-107`).
- `--arm` ∈ {A, B, both}.
- A non-smoke, non-dry-run run with neither `--yes` nor a `--driver` that the
  runner can confirm is offline → **abort** before any session with:
  `die "live run requires --yes (this calls a billed model; N sessions estimated). Use --smoke for the fake-driver pipeline or --dry-run to preview the cost."`
- `--smoke` and `--yes` together: `--smoke` wins (fake driver), warn that `--yes`
  is ignored under smoke.

> **TEST (R31):** unknown option dies non-zero with the option name; `--k 0` dies;
> live run without `--yes`/`--smoke`/`--dry-run` dies with the cost message.

### Risk tags
- **P0** stdout pollution would corrupt the JSON scorecard (every other eval mode
  pins this). Route ALL human output through stderr.
- **P1** a `--yes`-less live path that silently bills the user. The cost gate is
  the guardrail — test it.

---

## R30.1 — Offline deterministic fixture builder (D-C2)

The heart of the instrument's reproducibility. Two fixture projects are built into
mktemp dirs; they are **identical except for `harness install`**. Generation is
**OFFLINE** (no member fetch from GitHub) and **deterministic** (same checkout ⇒
byte-identical fixtures modulo the mktemp path).

### Fixture root layout (per arm)

```
<mktemp>/compliance-arm-<A|B>/
├── eidolons.yaml                 # minimal manifest (members from roster)
├── eidolons.lock                 # minimal lock (name/version/target/hosts_wired)
├── CLAUDE.md                     # standard cortex pointer block
├── .eidolons/
│   └── cortex/
│       └── EIDOLONS.md           # COPIED verbatim from the checkout
├── .claude/
│   ├── settings.json             # permissions allowlist (+ hooks in ARM A only)
│   └── agents/
│       ├── atlas.md              # stub: name/description/model only
│       ├── spectra.md
│       ├── vivi.md
│       ├── idg.md
│       ├── forge.md
│       ├── vigil.md
│       └── kupo.md
└── (ARM A only) .eidolons/harness/hooks/claude-code-*.sh   # via harness install
```

### Builder algorithm — `_build_fixture ARM DEST`

1. `mkdir -p "$DEST/.eidolons/cortex" "$DEST/.claude/agents"`.
2. **Cortex:** copy `$NEXUS/EIDOLONS.md` → `$DEST/.eidolons/cortex/EIDOLONS.md`.
   This is the same file the host reads at SessionStart. `[[ -f ]]` guard; die if
   absent (the nexus is broken — abort, do not measure).
3. **`eidolons.yaml`** (minimal, mirrors `helpers.bash::seed_manifest` shape but
   with all 7 roster members so every capability class is dispatchable):
   ```yaml
   version: 1
   hosts: { wire: [claude-code], shared_dispatch: true }
   members:
     - { name: <each roster name>, version: "0.0.0", source: github:<repo> }
   ```
   Member list + `source.repo` come from `roster_list_names` + `roster_get`. Version
   is a placeholder `0.0.0` — fixtures never fetch, so the version is inert.
4. **`eidolons.lock`** (minimal — enough for `harness install` to find
   `hosts_wired` and for `harness status` to verify; mirror `seed_lock` shape):
   one member entry per roster name with `target: ./.eidolons/<name>` and
   `hosts_wired: ["claude-code"]`, plus a top-level `hosts.wire: [claude-code]`.
   `harness_install.sh` reads `.harness` from this lock and rewrites it — that is
   expected (ARM A only).
5. **`CLAUDE.md`** — the standard cortex pointer block. Use the canonical pointer
   that `eidolons sync` writes so the host's reading behaviour matches production:
   ```markdown
   # CLAUDE.md
   <!-- eidolon:cortex start -->
   ## Eidolons routing cortex
   Read `.eidolons/cortex/EIDOLONS.md` at session start. For any non-trivial
   request, route through the Eidolons dispatch protocol: delegate to the
   indicated Eidolon via the Task tool (subagent_type = the Eidolon name) rather
   than acting in the main loop.
   <!-- eidolon:cortex end -->
   ```
   > **Decision [D-FIX-1]:** the pointer text is generated INLINE by the builder
   > (a heredoc constant), NOT sourced from the live consumer `CLAUDE.md` — the
   > fixture must be self-contained and offline. The text is a faithful paraphrase
   > of the production cortex pointer; if the production pointer wording changes
   > materially, update the heredoc (a test asserts the block markers exist).
6. **Agent stubs** — one `.claude/agents/<name>.md` per roster member, generated
   from `roster/index.yaml` (D-C2: name/description/model ONLY; **no member
   fetch**). Frontmatter:
   ```markdown
   ---
   name: <name>
   description: "<methodology.summary from roster, truncated to ~200 chars>"
   model: <model from model-profiles via suggested_tier→tier→string, default sonnet>
   tools: Read, Grep, Glob
   ---
   You are <DISPLAY_NAME>. (compliance-eval stub — full methodology not installed.)
   When dispatched, acknowledge the route and stop.
   ```
   The stub body is intentionally minimal: the experiment measures *whether the
   main loop dispatches a `Task(<name>)`*, NOT what the subagent does. A real
   subagent would fetch its methodology; the stub just needs to EXIST so the
   `Task` tool has a valid `subagent_type` target (verified scout fact).
   > **Decision [D-FIX-2]:** `model` resolution reads `roster/model-profiles.yaml`
   > active profile (`anthropic`) mapping the member's `suggested_tier` (from
   > `roster/routing.yaml`) → concrete string. If resolution fails, default
   > `sonnet`. The model field is advisory metadata for the host; it does not
   > affect detection (we parse `subagent_type`, not the subagent's model).
7. **`.claude/settings.json`** — permissions allowlist (next sub-section).
8. **ARM A only:** run `eidolons harness install --hosts claude-code
   --non-interactive` *with `$DEST` as cwd* (the installer writes to cwd only —
   architecture invariant). This wires the hooks into `.claude/settings.json` and
   writes the shim scripts + lock `harness:` block. ARM B skips this entirely.

### `.claude/settings.json` permissions (D-C2 — spec the EXACT allowlist)

The headless session must never hang on an interactive permission prompt. The
allowlist grants exactly what the experiment needs:

```json
{
  "permissions": {
    "allow": [
      "Task",
      "Read",
      "Grep",
      "Glob"
    ],
    "deny": [],
    "defaultMode": "acceptEdits"
  }
}
```

- **`Task`** — the dispatch we measure. MUST be allowed or the host cannot delegate.
- **`Read/Grep/Glob`** — the main loop may inspect the cortex/agents before routing;
  allowed so it does not stall asking.
- **No `Bash`, `Write`, `Edit`** — the experiment is read-and-route only; omitting
  write tools keeps the session bounded and cheap.
- `defaultMode: acceptEdits` — belt-and-braces against any residual prompt; with no
  write tools allowed there is nothing to accept, but it guarantees non-interactivity.

> **Realism trade-off (DOCUMENT in the runbook + a code comment):** restricting
> tools to Task/Read/Grep/Glob makes the fixture a *cleaner* discriminator (the
> only "productive" action available besides reading is to dispatch a Task), which
> may **inflate** the absolute delegation rate vs a fully-tooled production session
> where the main loop could also just Edit the file directly. **The A/B Δ is robust
> to this** because BOTH arms share the identical restriction — the bias is common-
> mode and cancels in Δ(A−B). The absolute arm-A rate vs the 80% gate is the part
> sensitive to the restriction; the runbook calls this out so the first measurement
> is interpreted as "Δ is the harness effect; absolute-rate-vs-gate is a *floor*
> estimate under a read-only tool surface." A follow-up may add a `--tools` flag to
> widen the surface; out of scope for R30.

> **Decision [D-FIX-3]:** ARM A's `harness install` MERGES its hooks block into
> this same `settings.json` (the installer's surgical-append path,
> `harness_install.sh:497-562`). So ARM A's settings.json = permissions allowlist
> + hooks; ARM B's = permissions allowlist only. The builder writes the permissions
> file FIRST, then (ARM A) runs `harness install` to merge hooks on top. This is the
> production order and exercises the real installer.

### Determinism guarantee

Same checkout ⇒ identical fixtures except the mktemp path and the (deterministic)
`generated_at` timestamps in lock/manifest. A test asserts the two arms' trees are
identical *except* `.claude/settings.json` (hooks), the lock `harness:` block, and
`.eidolons/harness/`.

> **TEST (R31 — fixture build determinism):** build arm A and arm B into temp dirs;
> assert (a) cortex EIDOLONS.md is byte-identical to the checkout's; (b) all 7 agent
> stubs exist with valid frontmatter (`name:` matches filename); (c) arm A's
> settings.json has a `hooks` block, arm B's does not; (d) arm A has executable
> shims under `.eidolons/harness/hooks/`, arm B has none; (e) the two CLAUDE.md
> files are byte-identical.

### Risk tags
- **P0** non-offline fixture (accidental `fetch_eidolon`) would make the instrument
  network-dependent and slow. The builder must NEVER call `fetch_eidolon`/`git
  clone`; assert this in code review and via a test that runs the builder with
  network-blocking env (`EIDOLONS_SKIP_REFRESH=1`, no clone log entries).
- **P1** agent stub missing → `Task(<name>)` would target a non-existent agent and
  the host might refuse to dispatch, depressing the rate spuriously. Generate ALL
  roster members.

---

## R30.2 — ARM-A wiring self-check (D-C8 — no vacuous arms)

Before ARM A measures, it verifies the instrument itself is wired. This campaign's
recurring lesson (canary confound, fitpass-needs-verification, capture-live-before-
parsing) is *verify the real exit gate, not just that the harness ran*. Three checks,
all run with `$DEST_A` as cwd:

1. **Hooks present in settings.json:**
   `jq -e '.hooks.UserPromptSubmit and .hooks.SessionStart' .claude/settings.json`
   → must be true.
2. **Shims executable:**
   `.eidolons/harness/hooks/claude-code-UserPromptSubmit.sh` and `-SessionStart.sh`
   exist and are `-x`.
3. **Kernel returns a route for a probe prompt:**
   ```bash
   echo '{"prompt":"map the auth flow"}' \
     | eidolons run --hook claude-code --stdin
   ```
   → stdout MUST be non-empty JSON containing `.hookSpecificOutput.additionalContext`
   with a `Route:` substring (VERIFIED live in scout — the probe returns
   `{"hookSpecificOutput":{...,"additionalContext":"Route: atlas  Tier: standard ..."}}`).
   This proves the wired kernel actually injects a route, not just that files exist.

If ANY check fails → **abort the whole run** (not just arm A) with diagnostics:
`die "ARM-A wiring self-check failed: <which check>. The instrument is broken; refusing to report a vacuous comparison. Run 'eidolons harness status' in the fixture or 'eidolons doctor'."` Print the failing check to stderr.

> **Decision [D-SC-1]:** the self-check runs even in `--smoke` mode (the fixture
> builder + harness install run identically; only the *driver* is faked). This
> means the smoke path also exercises the self-check, so bats covers it for free.
> The kernel-probe check uses the REAL `eidolons run` (deterministic, no model) in
> all modes — it is never faked.

> **TEST (R31 — arm wiring self-check):** (a) happy path: smoke run completes, no
> abort. (b) sabotage: delete arm A's UserPromptSubmit shim before the self-check
> (via a test seam — `--keep` + a pre-staged broken fixture, OR an injected
> `EIDOLONS_COMPLIANCE_SABOTAGE=1` that skips `harness install`) and assert the run
> aborts non-zero with "wiring self-check failed".

### Risk tags
- **P0** a vacuous arm A (hooks silently not wired) would report Δ≈0 and falsely
  "prove" the harness does nothing — the exact confound the campaign keeps hitting.
  The self-check is the guardrail; it is non-skippable.

---

## R30.3 — The driver contract (D-C3) + claude-absent handling

The driver is **pluggable**. It is a command that accepts the prompt and emits
**stream-json** (one JSON object per line) to stdout. Two built-in shapes plus the
user `--driver`:

### Driver invocation protocol

```
DRIVER_CMD <prompt-on-argv>        # default: prompt passed as the last argv
# OR, if the driver reads stdin (heuristic: --driver author's choice), the prompt
# is ALSO piped on stdin. The runner passes BOTH (argv + stdin) so either style
# works — eval_swe's --fix-hook is the structural analogue (it reads an env var).
```

> **Decision [D-DRV-1]:** the runner passes the prompt on argv AND on stdin, and
> exports `EIDOLONS_COMPLIANCE_PROMPT` and `EIDOLONS_COMPLIANCE_CWD`. A driver may
> consume whichever it prefers. The default claude driver uses argv. The fake
> driver uses an env var to select the canned fixture. This maximises pluggability
> for other hosts/CIs without prescribing a single calling convention.

### Default `claude -p` driver (live path — D-C3)

Built inline (a bash function `_default_claude_driver`), invoked **with the fixture
dir as cwd** so the host reads that project's CLAUDE.md/cortex/settings:

```bash
claude -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --max-turns "$MAX_TURNS" \
  --model "$MODEL"
```

(`--verbose` is required by Claude Code for `stream-json` to emit the full event
stream including tool_use events — VERIFY in the runbook's first dry contact; if the
flag name differs in the installed version, the runbook records the correction. The
spec pins the *contract* — "emit one JSON object per line including Task tool_use
events" — not the exact CLI surface, which is host-version-dependent.)

### claude-absent handling (D-C3 — actionable, never hang)

Before the FIRST live driver call (not in smoke/dry-run):
```bash
command -v claude >/dev/null 2>&1 || die \
  "the default driver needs the 'claude' binary on PATH and it is absent.
   Install Claude Code, or pass --driver <cmd> to substitute another host,
   or run --smoke for the fake-driver pipeline."
```
This fails FAST with a fix, never hangs.

> **TEST (R31 — claude-absent):** with `PATH` scrubbed of `claude` (or via a
> `--driver /nonexistent` probe), a non-smoke run dies non-zero with the
> "needs the 'claude' binary" / "Install Claude Code" message. (bats can't install
> claude; this path is tested by asserting the guard fires, not by running claude.)

### Per-session driver harness

For each (prompt, arm, k-index):
1. `cd "$FIXTURE_DIR_<arm>"` (subshell — never leak cwd).
2. capture: `stream="$(_run_driver "$prompt" 2>/dev/null)"` with a per-session
   timeout via `with_timeout` (lib.sh) — default 120s, env-tunable
   `EIDOLONS_COMPLIANCE_SESSION_TIMEOUT`. A timed-out session = `delegated_any:false`
   recorded with `error: timeout` (never aborts the whole suite).
3. parse the stream (R30.4).

### Risk tags
- **P1** a hung session blocking the whole suite — bounded by `with_timeout` +
  fixture permission allowlist (no interactive prompts).
- **P2** stream-json CLI flag drift across Claude Code versions — pin the *contract*
  in the spec; the runbook's first contact verifies/corrects the exact flags.

---

## R30.4 — Stream parser: Task-dispatch detection (D-C4)

Parse the driver's stream-json (newline-delimited JSON objects) for **Task tool_use
events**. Per the verified scout fact: a `Task` tool_use appears in the stream with
`subagent_type` naming the `.claude/agents` agent.

### Detection algorithm — `_parse_stream STREAM`

Stream events are NDJSON. The relevant event is an assistant message containing a
`tool_use` content block with `name == "Task"` and `input.subagent_type` set. The
robust jq extraction (tolerant of the exact envelope shape):

```bash
# Collect every Task dispatch as {subagent_type, turn} in stream order.
printf '%s\n' "$STREAM" | jq -c -R '
  fromjson? // empty
' | jq -s -c '
  [ to_entries[]
    | .key as $turn
    | .value as $ev
    # tool_use blocks may live at .message.content[] (assistant turns) or top-level
    | ( ($ev.message.content // $ev.content // []) | if type=="array" then . else [] end )[]
    | select((.type? == "tool_use") and (.name? == "Task"))
    | { subagent_type: (.input.subagent_type // .input.subagentType // null),
        turn: $turn }
  ]'
```

> **Decision [D-PARSE-1]:** parse defensively — `fromjson? // empty` drops non-JSON
> lines (banners, partial chunks); both `.message.content` and `.content` envelope
> shapes are tried; both `subagent_type` and `subagentType` key spellings are tried.
> The exact shape is host-version-dependent; the FAKE fixtures (R31) are authored
> from a VERBATIM live capture (campaign lesson: capture-live-before-parsing — do
> NOT fabricate the fixture shape). The runbook's first contact saves a real stream
> to `cli/tests/fixtures/compliance/live-sample.jsonl` and the parser is reconciled
> against it before any headline run.

### Per-prompt compliance scoring (D-C4)

Given the kernel's ground truth (R30.5) and the parsed Task list:

| Prompt class | `correct` definition |
|---|---|
| **routed** (kernel decision ∈ {dispatch, chain, refusal_reroute}) | `delegated_any` = ≥1 Task to ANY roster Eidolon within max-turns; `delegated_correct` = the FIRST dispatched `subagent_type` ∈ the kernel's `selected` set (for chain: the first step; the head of the chain is the correct first dispatch) |
| **control** (kernel decision == clarify / no-route) | **INVERTED:** `correct` = NO Task dispatch fired (the host correctly declined to route a trivial/ambiguous prompt) |

- `delegated_any` (routed): boolean — did the host delegate at all?
- `delegated_correct` (routed): boolean — did it delegate to the RIGHT Eidolon?
  Uses the FIRST Task in stream order (we measure whether the EARLY dispatch is
  correct, per D-C3's max-turns rationale).
- For a **chain** ground truth (e.g. `[spectra, vivi]`), the correct first dispatch
  is the chain head (`spectra`). A host that dispatches the head is `delegated_correct`;
  the runner records the full observed sequence for diagnostics but scores on the head.
- For **control** prompts, `delegated_correct` = `delegated_any == false`.

> **Decision [D-PARSE-2]:** "within max-turns" is satisfied automatically because the
> driver runs with `--max-turns N`; any Task in the captured stream is within the cap
> by construction. The `turn` index is recorded for diagnostics (how early did it
> route?) but is not a separate gate — the cap is enforced upstream by the driver.

### Risk tags
- **P0** parsing the WRONG envelope shape → all dispatches missed → vacuous 0% (the
  capture-live-before-parsing trap). Mandate the verbatim live-sample fixture FIRST;
  the parser's bats tests assert against it.
- **P1** counting a self-dispatch or a non-roster Task as a delegation — filter
  `subagent_type ∈ roster_list_names` for `delegated_any` on routed prompts.

---

## R30.5 — Ground truth computed LIVE (D-C4)

The expected target per prompt is **NOT hardcoded** — it is computed at suite-run
time by the deterministic kernel, keeping the suite in sync with `routing.yaml`:

```bash
gt="$(eidolons run "$prompt" ${ctx_flags[@]+"${ctx_flags[@]}"} --json 2>/dev/null)"
gt_decision="$(printf '%s' "$gt" | jq -r '.decision')"
gt_selected="$(printf '%s' "$gt" | jq -c '.selected')"   # array
```

- `ctx_flags` come from the suite task's optional `ctx` block (same `--surface-modules`/
  `--trance`/`--prior-failure` mapping as `eval.sh:130-133`).
- A task is a **control** when `gt_decision == "clarify"` OR the suite marks
  `control: true` explicitly. (Both signals are honoured; an explicit `control: true`
  in the suite is authoritative and is also self-checked against the kernel — if the
  suite says control but the kernel routes it, that's a suite defect surfaced by
  `--validate-suite`.)
- The ground truth is computed ONCE per prompt (not per k, not per arm) — it is
  deterministic, so caching it is correct and cheap.

> VERIFIED live: `eidolons run "spec out the new caching layer" --json` →
> `{"decision":"dispatch","selected":["spectra"],"tier":"standard"}`. The kernel
> is the authority for "what SHOULD the host have done."

### Risk tags
- **P1** suite drift vs routing.yaml — eliminated by computing GT live. A `--validate-suite`
  cross-check (R30.7) flags any suite `control:` flag that disagrees with the kernel.

---

## R30.6 — Metrics, scorecard, GATE (D-C6)

### Per-arm aggregate metrics

For each arm (A, B):
- **`delegation_rate`** = (# routed prompts with `delegated_any` over the BEST of k
  runs) / (# routed prompts). Per-prompt: a prompt counts as delegated if it
  delegated in ≥1 of its k runs (pass@1 semantics for "did it ever route").
- **`correct_target_rate`** = (# routed prompts with `delegated_correct` in ≥1 of k) /
  (# routed prompts).
- **`control_pass_rate`** = (# control prompts that correctly did NOT route in ALL k) /
  (# control prompts). (Controls use pass^k — a control that routes even once is a
  failure; the host should NEVER route a trivial prompt.)
- **`pass_k_stability`** (per prompt): for routed prompts, the fraction of k runs
  that were `delegated_correct` — surfaced per-prompt so the human sees flakiness.
  A per-arm `stability_passk` = (# routed prompts `delegated_correct` in ALL k) /
  (# routed prompts) is the pass^k headline (the Coder-7.5 metric).
- **per-class breakdown:** `delegation_rate` and `correct_target_rate` grouped by
  the suite task's `class` (one of the 8 capability classes).

### Δ and GATE

- **`delta`** = `{ delegation_rate: A.delegation_rate - B.delegation_rate,
  correct_target_rate: A.correct_target_rate - B.correct_target_rate }`.
- **GATE line** (the FORGE reversal condition operationalised):
  ```
  GATE (FORGE reversal, dossier:106): arm-A correct_target_rate = <X>%
    threshold = 80%  →  PASS (advisory sufficient)  |  FAIL (escalate default to block)
  ```
  - When `--gate` (or `--min N`): exit 1 if arm-A `correct_target_rate` < threshold
    (default 80). This is the CI/decision gate. **Decision [D-GATE-1]:** the gate is
    on `correct_target_rate` (delegating to the RIGHT Eidolon), not bare
    `delegation_rate` — "delegated to the wrong agent" is not compliance. The dossier
    phrase "advisory compliance" = correct routing under advisory injection.

### Scorecard JSON shape (`--json`)

```json
{
  "compliance_version": "1.0",
  "mode": "smoke | live",
  "driver": "claude -p --model sonnet | <custom> | fake",
  "model": "sonnet",
  "max_turns": 3,
  "k": 2,
  "suite": "evals/compliance-suite.yaml",
  "n_prompts": 14,
  "n_routed": 11,
  "n_control": 3,
  "sessions_run": 56,
  "arms": {
    "A": { "harness": true,
           "delegation_rate": 0.91, "correct_target_rate": 0.82,
           "control_pass_rate": 1.0, "stability_passk": 0.73,
           "by_class": [ { "class": "scout", "delegation_rate": 1.0, "correct_target_rate": 1.0 }, ... ],
           "per_prompt": [ { "id": "C-001", "class": "scout", "control": false,
                             "ground_truth": ["atlas"], "delegated_any": true,
                             "delegated_correct": true, "passk_correct": "2/2",
                             "observed": [ { "subagent_type": "atlas", "turn": 1 } ] }, ... ] },
    "B": { "harness": false, "delegation_rate": 0.55, "correct_target_rate": 0.45, ... }
  },
  "delta": { "delegation_rate": 0.36, "correct_target_rate": 0.37 },
  "gate": { "metric": "A.correct_target_rate", "value": 0.82, "threshold": 0.80,
            "verdict": "PASS", "reversal_action": "advisory default retained" },
  "scope_note": "Non-deterministic (model in loop); k=<K>. k=1 is noise for a headline claim. Tool surface restricted to Task/Read/Grep/Glob — the A−B delta is the harness effect (common-mode bias cancels); absolute arm-A rate is a floor under a read-only surface."
}
```

### Text scorecard (stdout when not `--json`)

Mirror the `eval_swe` / `eval routing` card style: per-arm rates, the per-class
table, the Δ block, then the GATE line. The `scope_note` (non-determinism + k=1
caveat + tool-restriction caveat) prints as a `⚠` banner like `eval_swe`'s honest-
scope line. **All of this is stderr-safe except the JSON; the text card is stdout**
(matching `eval routing`/`eval_swe` which print their text card to stdout).

> **Decision [D-MET-1]:** stdout = the scorecard (text card OR `--json`), consistent
> with the sibling modes. The cost-envelope confirmation banner (R30.7) and the
> wiring-self-check diagnostics go to STDERR (they are not the scorecard). This keeps
> `eidolons eval compliance --json | jq` clean.

> **TEST (R31 — scorecard math):** feed a hand-built set of parsed results (3 routed
> + 1 control, known dispatches) through the metric aggregation and assert
> `delegation_rate`, `correct_target_rate`, `control_pass_rate`, `delta`, and the
> gate `verdict` are arithmetically correct. (Exercise via `--smoke` with fixtures
> engineered to produce known rates — see R31 fixture design.)

### Risk tags
- **P1** gate on the wrong metric (bare delegation vs correct target) would mis-fire
  the reversal decision. Pin it to `correct_target_rate` (D-GATE-1).
- **P2** integer-vs-float jq rate formatting (the `eval_quality.sh:158` lesson — use
  jq division, not awk `%.2f`, to avoid jq 1.7 number-literal preservation). Use
  `jq -n '$p/$k'` style throughout.

---

## R30.7 — Cost discipline, `--dry-run`, `--smoke`, `--validate-suite` (D-C7)

### Cost-envelope banner (before any live session)

Before the first live driver call, print to **stderr** and require `--yes`:
```
COST: <N_prompts> prompts × <arms> arm(s) × k=<K> = <SESSIONS> live sessions
      driver=claude -p  model=<MODEL>  max-turns=<MAX>
      This calls a BILLED model. Re-run with --yes to proceed, --dry-run to preview,
      or --smoke for the fake-driver pipeline.
```
`SESSIONS = N_prompts × (1 if arm∈{A,B} else 2) × K`. Without `--yes` → exit 0 after
printing (a preview), or exit non-zero if invoked in a context expecting execution —
**Decision [D-COST-1]:** absent `--yes`/`--smoke`/`--dry-run`, **die non-zero** (do
not silently no-op) so a CI mis-wire is loud. `--dry-run` prints the banner and exits
**0** (explicit preview, success).

### `--smoke` (the FAKE driver — also the bats path)

`--smoke` swaps `_run_driver` for `_fake_driver`, which `cat`s a canned NDJSON
fixture selected by the prompt (via `EIDOLONS_COMPLIANCE_PROMPT` → a fixture map).
The fixtures live at `cli/tests/fixtures/compliance/<scenario>.jsonl`. Smoke runs
the ENTIRE pipeline (fixture build → harness install → self-check → driver → parse →
metrics → gate) with zero network and zero model. This is exactly what CI and bats
invoke; CI NEVER calls a live model.

> **Decision [D-SMOKE-1]:** the fake-driver fixture set is authored to cover the
> parser's branch table: (a) a correct early dispatch (`Task(atlas)` turn 1);
> (b) a wrong-target dispatch (`Task(vivi)` when GT=atlas); (c) NO Task at all (the
> host ignored the route — the arm-B-ish baseline and the routed-miss case);
> (d) a control prompt with no dispatch (correct control); (e) a control prompt
> that WRONGLY dispatches (control failure). The smoke suite's prompts map to these
> fixtures so the bats scorecard-math test has known inputs.

### `--validate-suite` (the harness's own self-test — mirror `eval routing`)

`eidolons eval compliance --validate-suite` checks the suite shape WITHOUT running
the driver (mirror `eval.sh:90-118` / `eval_swe.sh:114-142`):
- every task has `id`, `prompt`, `class`;
- no duplicate ids; no duplicate prompts;
- `class` ∈ the 8 capability classes (scout, planner, coder, scriber, reasoner,
  debugger, executor) + `control` is allowed as a class label for controls;
- for each task, compute the kernel GT and assert the suite's `control:` flag (if
  present) agrees with `gt_decision=="clarify"` (cross-check — catches a mislabeled
  control). Coverage assertion: ≥1 task per capability class present + ≥2 controls.

> **TEST (R31):** `--validate-suite` passes on the shipped suite; a deliberately
> broken suite (dup id, missing class, mislabeled control) fails non-zero with the
> defect listed.

### Risk tags
- **P0** a billed run firing without `--yes` (the user's bill). The cost gate +
  die-non-zero-without-confirmation is the guardrail; test it.
- **P1** a smoke run accidentally hitting the network (e.g. `harness install` trying
  to refresh) — set `EIDOLONS_SKIP_REFRESH=1` in the builder's env and pass
  `--non-interactive` everywhere.

---

# R31 — Fake-driver smoke + bats coverage

`cli/tests/eval_compliance.bats` (load `helpers`). Pure sh/coreutils/git/jq — NO
model, NO network, NO Docker (mirror `eval_swe.bats`). The fixture NDJSON files live
under `cli/tests/fixtures/compliance/`.

### Fixture NDJSON files (authored from the live-sample shape — D-PARSE-1)

| File | Scenario |
|---|---|
| `dispatch-correct.jsonl` | one `Task` tool_use, `subagent_type:"atlas"`, turn 1 |
| `dispatch-wrong.jsonl` | one `Task`, `subagent_type:"vivi"` (wrong when GT=atlas) |
| `no-task.jsonl` | assistant text only, NO Task tool_use (host ignored the route) |
| `chain-head.jsonl` | `Task` `subagent_type:"spectra"` (chain head correct) |
| `control-clean.jsonl` | assistant text only (correct: control did not route) |
| `control-routed.jsonl` | a `Task` dispatch on a control prompt (control failure) |
| `live-sample.jsonl` | the VERBATIM first-contact capture (committed in R33; the parser is reconciled against THIS) |

> These fixtures encode the REAL stream-json envelope shape. Until `live-sample.jsonl`
> is captured (R33 first contact), the other fixtures are authored to a best-effort
> shape and reconciled the moment the live sample lands. **Do not ship the headline
> run before reconciliation** (campaign lesson).

### Test list (≥16 cases)

| # | Test | Asserts |
|---|---|---|
| 1 | `--help` exits 0 | help body present; `eval --help` lists `compliance` |
| 2 | unknown option dies | non-zero + option name |
| 3 | `--k 0` dies; `--max-turns 0` dies | arg validation |
| 4 | fixture build determinism | cortex byte-identical; 7 stubs valid; arm A hooks present, arm B absent; shims -x in A only; CLAUDE.md identical across arms |
| 5 | offline guarantee | builder run with network-block leaves no clone-log entry; no `fetch_eidolon` call |
| 6 | arm-A self-check happy path | smoke run completes, no abort |
| 7 | arm-A self-check sabotage | broken fixture (no harness install) → run aborts non-zero with "wiring self-check failed" |
| 8 | parse: correct early dispatch | `dispatch-correct.jsonl` → `delegated_any:true, delegated_correct:true` |
| 9 | parse: wrong target | `dispatch-wrong.jsonl` (GT=atlas) → `delegated_any:true, delegated_correct:false` |
| 10 | parse: no Task | `no-task.jsonl` → `delegated_any:false, delegated_correct:false` |
| 11 | parse: chain head | `chain-head.jsonl` (GT=[spectra,vivi]) → correct (head=spectra) |
| 12 | control inversion (clean) | `control-clean.jsonl` on a clarify-GT prompt → `correct:true` |
| 13 | control inversion (routed) | `control-routed.jsonl` on a clarify-GT prompt → `correct:false` |
| 14 | scorecard math | engineered smoke run → known `delegation_rate`/`correct_target_rate`/`control_pass_rate`/`delta`/gate verdict |
| 15 | `--smoke` end-to-end both arms | full pipeline, JSON scorecard valid, `arms.A`/`arms.B`/`delta`/`gate` present, `mode=="smoke"`, `sessions_run` correct |
| 16 | claude-absent error | non-smoke run with no `claude` on PATH (or `--driver /nonexistent`) dies with "Install Claude Code"/"needs the 'claude' binary" |
| 17 | `--validate-suite` passes | shipped suite valid; broken suite fails with defect list |
| 18 | `--dry-run` cost envelope | prints `COST:` banner + session count, exits 0, calls no driver |
| 19 | live-run-without-confirmation guard | non-smoke, non-dry, no `--yes` → dies with the cost/`--yes` message |
| 20 | determinism of smoke scorecard | two `--smoke --json` runs byte-identical (fake driver is deterministic) |
| 21 | stdout discipline | `--smoke --json` stdout is valid JSON only (no log lines); diagnostics on stderr |

> **Decision [D-TEST-1]:** the sabotage seam (test 7) is an env var
> `EIDOLONS_COMPLIANCE_SABOTAGE=skip-harness` that makes the builder skip ARM A's
> `harness install`, so the self-check fires its abort. This is test-only plumbing,
> documented as such, never a production path.

### Risk tags
- **P0** tests that pass vacuously on darwin but fail on ubuntu (the obsolete-probe /
  timestamp-coincidence campaign lessons). Canonicalize JSON comparisons (`jq -cS`),
  sort arrays, and run determinism asserts. Trust ubuntu CI.
- **P1** fixtures fabricated to the wrong shape (capture-live-before-parsing) — gate
  the headline run on `live-sample.jsonl` reconciliation (R33).

---

# R32 — Docs

### `CHANGELOG.md` (Unreleased)

```
### Added
- `eidolons eval compliance` — A/B behavioral measurement of routing compliance
  on real hosts. Two isolated, offline-built fixture projects (identical except
  `harness install`) run a prompt corpus through a pluggable headless driver
  (default `claude -p`); the stream is parsed for Task(<eidolon>) dispatches and
  scored against the live kernel ground truth. Reports per-arm delegation_rate,
  correct_target_rate, Δ(A−B), per-class breakdown, pass^k stability, and an
  explicit GATE line vs the 80% FORGE reversal threshold (dossier:106). --smoke
  runs the whole pipeline against a fake driver (CI never calls a live model);
  live runs are gated behind --yes.
```

### `docs/cli-reference.md` — `eidolons eval` section

Add a `compliance` subsection alongside `routing`/`quality`/`swe`: the flag table
(R30.0), the A/B explanation, the smoke-vs-live distinction, the cost gate, and a
worked `--json` scorecard excerpt. State the honest scope (non-deterministic;
k=1 is noise; tool-restriction common-mode caveat).

### `docs/architecture.md` — one paragraph tying it to the FORGE gate

A paragraph in the harness/eval section: `eval compliance` operationalises the FORGE
harness reversal condition ("advisory compliance <80% on T3 hosts → escalate default
to block"). It is the only Eidolons eval whose headline is non-deterministic (a model
is in the loop), so it reports `pass^k`. The A/B design isolates the harness effect:
both arms share identical fixtures except `harness install`, so Δ(A−B) is the
mechanical injection's contribution and the absolute arm-A rate vs 80% is the gate
input. Cross-reference `DOSSIER-HARNESS-2026-06.md:106`.

> **TEST (R31, light):** a doc-presence assertion is optional; the campaign convention
> is to assert CHANGELOG has the entry only if a release-stamp gate requires it. No
> hard test mandated for R32 beyond the changelog line existing.

### Risk tags
- **P2** CHANGELOG drift vs the release-stamp gate — add the Unreleased entry; the
  release cut moves it under the version header.

---

# R33 — Live-run runbook (the first measurement)

`.spectra/harness-mechanization/runbook-compliance.md` — exact commands for the FIRST
real measurement. Results-artifact convention (D-C6, kupo-eval-results.md): the
runner PRINTS; the human/orchestrator COMMITS the scorecard to `.spectra/research/`.

### Runbook contents (spec the structure; the executor writes the file)

1. **Pre-flight — verify the instrument under smoke FIRST:**
   ```bash
   eidolons eval compliance --smoke --json | jq .
   eidolons eval compliance --validate-suite
   ```
   Both must be green before spending a token.
2. **First contact — capture the real stream shape (the capture-live-before-parsing
   gate):**
   ```bash
   # one prompt, one arm, k=1, --keep to inspect the fixture; save the raw stream
   eidolons eval compliance --arm A --k 1 --keep --yes \
     --suite-file /tmp/one-prompt-suite.yaml 2>stream.err
   # extract the raw NDJSON the driver emitted (the runner logs it under --keep to
   # the fixture dir at .eidolons/compliance/last-stream.jsonl) and commit it as
   cp <fixture>/.eidolons/compliance/last-stream.jsonl \
      cli/tests/fixtures/compliance/live-sample.jsonl
   ```
   > The runner MUST, under `--keep`, persist each session's raw stream to
   > `<fixture>/.eidolons/compliance/last-stream.jsonl` so first-contact can harvest
   > the verbatim shape. **Add this as a sub-requirement of R30.3** (a `--keep`-gated
   > stream dump). Reconcile the parser + fixtures against this sample; re-run smoke.
3. **The headline measurement — sonnet, k=2, both arms (the spec's mandated first run):**
   ```bash
   eidolons eval compliance --model sonnet --k 2 --arm both --gate --json --yes \
     | tee compliance-2026-06-XX.json
   ```
   - **Expected cost envelope:** N_prompts (~14) × 2 arms × k=2 = ~56 sessions,
     each ≤3 turns at sonnet. The runbook states the order-of-magnitude token/$
     estimate (the runner's `COST:` banner is the source of truth at run time).
   - k=2 is the MINIMUM for a stability signal (k=1 is noise — Coder-7.5). The
     runbook notes that a defensible headline wants k≥3; k=2 is the first-pass floor.
4. **Where to commit:** `.spectra/research/compliance-eval-results.md` — a results
   artifact in the kupo-eval-results.md style (instrument, run date, the scorecard
   table, the GATE verdict, honest scope, and the reversal-decision recommendation).
   The orchestrator commits it; the runner never writes it.
5. **Decision rule (operationalising dossier:106):** if arm-A `correct_target_rate`
   < 80% AND the Δ(A−B) shows the harness is NOT closing the gap → recommend
   escalating the advisory default to block (or making `--strict` the default on
   T3). If arm-A ≥ 80% → advisory default retained. Either way the number, not a
   guess, drives it.

### Risk tags
- **P0** spending tokens before smoke + live-sample reconciliation are green. The
  runbook ORDERS the steps: smoke → first-contact capture → reconcile → headline.
- **P1** committing a headline run authored against a fabricated stream shape. Gate
  on `live-sample.jsonl`.

---

## 3. Dependency & Sequencing

```
R30.0 (skeleton + dispatch + flags)
  └─→ R30.1 (fixture builder)           ← reuses harness_install.sh, cortex, roster
        └─→ R30.2 (arm-A self-check)    ← reuses run.sh --hook --stdin (VERIFIED)
              └─→ R30.3 (driver + claude-absent + --keep stream dump)
                    └─→ R30.4 (stream parser)   ← FAKE fixtures first
                          └─→ R30.5 (live ground truth)  ← reuses run.sh --json (VERIFIED)
                                └─→ R30.6 (metrics + GATE)
                                      └─→ R30.7 (cost/smoke/validate-suite)
R31 (bats + fixtures)  ── developed ALONGSIDE R30.4–R30.7 (smoke-first TDD)
R32 (docs)             ── after R30 lands
R33 (runbook)          ── after R31 green; first contact captures live-sample.jsonl,
                          which feeds back into R30.4/R31 reconciliation BEFORE headline
```

**Build order for the executor:** R30.0 → R30.1 → R30.2 → R30.4 (parser, against
authored fixtures) → R30.3 (driver, fake first) → R30.5 → R30.6 → R30.7, writing the
matching bats case in R31 as each piece lands (smoke-first TDD — the whole pipeline is
exercisable under `--smoke` before any model contact). R32 docs, then R33 runbook +
first-contact capture + reconcile.

**Critical feedback loop:** R33 step 2 (live-sample capture) may force a parser
correction in R30.4 and a fixture update in R31. The spec mandates this loop
explicitly — the headline run (R33 step 3) is BLOCKED until smoke is green against
the reconciled live sample.

---

## 4. Acceptance Criteria (consolidated, GIVEN/WHEN/THEN)

### AC-1 — dispatch (R30.0)
GIVEN the nexus CLI WHEN `eidolons eval compliance --help` runs THEN it exits 0 with
a help body AND `eidolons eval --help` lists `compliance` among the modes.

### AC-2 — offline deterministic fixtures (R30.1)
GIVEN a clean checkout WHEN the builder runs for arm A and arm B with the network
blocked THEN both fixtures are created with no `git clone`/`fetch_eidolon` call, the
cortex `EIDOLONS.md` is byte-identical to the checkout's, all 7 roster agent stubs
exist with valid frontmatter, and the two arms differ ONLY in `.claude/settings.json`
hooks + the lock `harness:` block + `.eidolons/harness/`.

### AC-3 — wiring self-check (R30.2, D-C8)
GIVEN arm A WHEN its hooks/shims/kernel-probe self-check runs THEN a wired fixture
passes silently AND a sabotaged fixture (no `harness install`) aborts the WHOLE run
non-zero with "wiring self-check failed" diagnostics on stderr.

### AC-4 — driver contract + claude-absent (R30.3, D-C3)
GIVEN `--driver` is pluggable WHEN a non-smoke run finds no `claude` on PATH THEN it
dies non-zero with an actionable "Install Claude Code / pass --driver / use --smoke"
message (never hangs) AND under `--keep` each session's raw stream is persisted to
`<fixture>/.eidolons/compliance/last-stream.jsonl`.

### AC-5 — detection + scoring (R30.4, R30.5, D-C4)
GIVEN a parsed stream and the LIVE kernel ground truth WHEN scored THEN a routed
prompt is `delegated_correct` iff its FIRST Task `subagent_type` ∈ the kernel's
`selected` (chain → head), a routed prompt with no Task is `delegated_any:false`, and
a control prompt (kernel `clarify`) is `correct` iff NO Task fired (inversion).

### AC-6 — metrics + GATE (R30.6, D-C6)
GIVEN both arms ran WHEN the scorecard is emitted THEN it carries per-arm
`delegation_rate`/`correct_target_rate`/`control_pass_rate`/`stability_passk`, a
per-class breakdown, `delta`, and a `gate` block comparing arm-A `correct_target_rate`
to 80% with a PASS/FAIL verdict; `--gate`/`--min` exits 1 below threshold.

### AC-7 — cost discipline + smoke (R30.7, D-C7)
GIVEN a non-smoke, non-dry, `--yes`-less invocation WHEN run THEN it dies non-zero
after printing the `COST:` session-count banner; `--dry-run` prints the banner and
exits 0; `--smoke` runs the FULL pipeline against the fake driver with zero network/
model and is what bats/CI invoke.

### AC-8 — stdout discipline (P0)
GIVEN `--smoke --json` WHEN run THEN stdout is a single valid JSON scorecard with NO
log lines; all `say/ok/info/warn`, the cost banner, and self-check diagnostics are on
stderr.

### AC-9 — tests green (R31)
GIVEN `cli/tests/eval_compliance.bats` WHEN `make test-file F=cli/tests/eval_compliance.bats`
runs THEN all ≥16 cases pass under bash 3.2 with no network/model/Docker.

### AC-10 — docs + runbook (R32, R33)
GIVEN the change WHEN reviewed THEN CHANGELOG has the Unreleased entry, cli-reference
documents the mode + flags + honest scope, architecture ties it to dossier:106, and
the runbook spells out smoke → first-contact-capture → reconcile → headline
(sonnet/k=2/both arms) with the cost envelope and the `.spectra/research/` commit
target.

---

## 5. Test Verification (SPECTRA T-phase, 6 layers)

| Layer | Result |
|---|---|
| **Structural** | Hierarchy R30→R33 intact; R30 decomposed into 8 atomic sub-reqs; no orphaned tasks; every D-Cn decision mapped to a sub-req. |
| **Self-consistency** | Three decompositions (by-file, by-pipeline-stage, by-decision) converge on the same 8 R30 pieces (≥70% overlap). The pipeline-stage view (fixture→self-check→driver→parse→GT→metrics→cost) is the load-bearing order and matches the dependency DAG. |
| **Dependency** | All touch-points validated against the live tree: `eval.sh:59-65` dispatch, `run.sh --hook/--stdin/--json` (probed live), `harness_install.sh` (cwd-only writes), `EIDOLONS.md` cortex (present), `roster_list_names`/`roster_get`/model-profiles (present), `with_timeout`/`yaml_to_json` (lib.sh). No schema migration; new `compliance-suite.schema.json` is additive. |
| **Constraint** | bash 3.2 (no assoc arrays/`${var,,}`/readarray); stdout=scorecard; offline fixtures; `--yes`-gated billing; idempotent fixture build; CI never bills (smoke/fake). All HARD CONSTRAINTS satisfied. |
| **Process reward** | Smoke-first TDD means the whole pipeline is exercisable before any token spend; the live-sample reconciliation loop prevents the campaign's recurring fabricated-fixture trap; the wiring self-check prevents the vacuous-arm trap. Each step reduces a known risk. |
| **Adversarial** | (a) *Vacuous arm A* → D-C8 self-check aborts. (b) *Fabricated stream shape* → live-sample-first gate. (c) *Billed run with no consent* → cost gate dies non-zero. (d) *Tool-restriction inflates absolute rate* → documented common-mode bias; Δ is robust, absolute is a floor. (e) *Suite drift vs routing.yaml* → live ground truth + validate-suite cross-check. (f) *stdout pollution* → stderr discipline pinned. (g) *darwin-green/ubuntu-red tests* → canonical jq compare + determinism asserts. (h) *gate on wrong metric* → pinned to correct_target_rate. |

**Adversarial residue (the 12% uncertainty):** the EXACT `claude -p` stream-json
envelope shape and the precise CLI flags (`--verbose`?, `--output-format
stream-json` field names) are host-version-dependent and not verifiable offline in
this read-only planning pass. The spec mitigates by (1) pinning the *contract* not
the surface, (2) defensive multi-shape parsing (D-PARSE-1), and (3) mandating the
first-contact live-sample capture + reconciliation BEFORE any headline run (R33).
This is a known, bounded, explicitly-sequenced unknown — not a planning gap.

---

## 6. Confidence Report

**Overall: 88% — AUTO_PROCEED.**

| Factor (25% each) | Score | Note |
|---|---|---|
| Pattern match | 90% | `eval_swe.sh` is a near-exact structural template (mktemp fixtures, pluggable hook, suite YAML, --validate-suite, --json, --min gate, honest-scope banner, pass^k). ADAPT strategy. |
| Requirement clarity | 92% | D-C1..D-C8 retire nearly all ambiguity; flag contract, fixture layout, permissions, gate metric, and sequencing are all pinned. |
| Decomposition stability | 88% | 8 R30 sub-reqs are atomic and converge across three decomposition views; the dependency DAG is unambiguous. |
| Constraint compliance | 82% | All HARD CONSTRAINTS provably satisfied; the −18% is the offline-unverifiable live stream-json shape, explicitly fenced by the first-contact gate. |

The single largest residual risk (live stream shape) is **structurally contained**:
the instrument is fully developable and testable under `--smoke` with zero model
contact, and the spec forbids the headline run until the live sample is captured and
the parser reconciled. That sequencing is the difference between an 88% spec and a
guess.

---

## 7. Rejected Alternatives

| Alternative | Why rejected |
|---|---|
| **Extend `canary.sh`** (human-in-the-loop) for compliance | D-C1 keeps canary human-in-the-loop and untouched. Compliance is automatable end-to-end (headless driver + mechanical parse); forcing it through canary's print-mission/grade-output flow would lose the A/B automation and the cost gate. |
| **Hardcode expected targets in the suite** | D-C4: drifts from `routing.yaml` the moment a trigger verb changes. Computing GT live via the deterministic kernel keeps the suite self-synchronising and lets `--validate-suite` cross-check. |
| **Single arm (measure ARM A only)** | Without the control arm there is no baseline — a high ARM-A rate could be the model's prior, not the harness. The Δ(A−B) is the whole scientific claim; common-mode biases (tool restriction) only cancel in the difference. |
| **Reuse `eval routing`'s grading loop** | That loop grades the DETERMINISTIC kernel against static ground truth — no model, no sessions, no pass^k. Compliance needs a live driver, NDJSON parsing, non-deterministic pass^k, and a two-arm fixture — a different engine that only shares the suite-validate and --json/--min conventions. |
| **Fixtures that `eidolons init`/`sync` a real project** | Would fetch members from GitHub (network, slow, non-deterministic, version-coupled). D-C2 mandates an OFFLINE mechanical builder; agent stubs from roster metadata suffice because we measure dispatch, not subagent execution. |
| **Make `--strict`/block the default now** | Premature — the dossier's reversal is *conditional on measurement*. This spec builds the measurement so the decision is evidence-driven, not asserted. |
| **TRANCE parallel-spec mode** | Stakes are real but this is one bounded CLI module, not multi-service architecture with high rework risk. Single-pass S→P→E→C→T→R→A is the correct tier (complexity 9, not 10–12). |

---

## 8. Hand-off

**→ Vivi** (default coder, loop-native). This is net-new bash with a clean
smoke-first TDD loop — ideal for the edit-run-test cycle. Brief Vivi:
- Build under `--smoke` end-to-end FIRST (no model contact); every R30 piece has a
  matching R31 bats case.
- The live stream-json shape is UNVERIFIED offline — author fake fixtures to a
  best-effort shape, then RECONCILE against the first-contact `live-sample.jsonl`
  (R33 step 2) before declaring done. Do NOT fabricate-and-ship.
- bash 3.2 only; stdout = scorecard; `--yes`-gate all billing; CI never bills.
- Mirror `eval_swe.sh` structure (header, flag loop, mktemp+trap cleanup, jq metric
  aggregation, honest-scope banner, --json/--min gate).
- The agent-handoff YAML (`spec-compliance.yaml`) carries the per-story timeboxes,
  agent hints, and validation gates.

Parent commits + pushes (Vivi has no Bash-git in some host configs; per memory,
SPECTRA/IDG/Vivi tool gaps mean the parent handles git). Run
`make test-file F=cli/tests/eval_compliance.bats` and `make lint` (shellcheck -x)
before any PR.

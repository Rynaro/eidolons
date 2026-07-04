# Runbook — `eidolons eval compliance` live measurement (GAP, FORGE reversal gate)

This is the human-driven procedure for the **only** billed path of the routing-compliance
instrument. CI and `make test` never reach it — `eval_compliance.sh` refuses the default
`claude` driver whenever `EIDOLONS_COMPLIANCE_NO_LIVE=1` is set, and the bats suite exports
that variable in `setup()`. A live run is a deliberate, supervised act.

> **What this measures.** Whether the advisory harness injection (ARM A: `harness install`
> wired) actually changes a host LLM's delegation behaviour versus prose-cortex-only
> (ARM B). The gate metric is **`A.correct_target_rate`** against the 80% threshold in the
> FORGE decision (`DOSSIER-HARNESS-2026-06.md:106`): below 80% → the reversal action
> recommends escalating the default posture from inject to block.

## 0. Cost envelope — read before running

```
sessions = n_prompts × arms × k
```

The shipped suite is 14 prompts. The headline run (both arms, k=2) is **14 × 2 × 2 = 56
billed `claude -p` sessions**, each capped at `--max-turns 3`. Budget accordingly. Every
invocation prints this count and requires `--yes`; `--dry-run` prints it and stops.

## 1. Smoke first (free, no model)

Prove the pipeline, fixtures, parser, and gate math before spending anything:

```bash
eidolons eval compliance --smoke --json | jq .
```

Expect a complete scorecard. ARM A == ARM B with zero delta is correct here — the fake
driver does not differentiate arms; smoke validates machinery, not behaviour.

## 2. Capture a first-contact stream sample (1 billed session) — MANDATORY

The exact `--output-format stream-json` envelope shape is host-version-dependent. Before
trusting any headline number, capture one real stream and reconcile the parser against it.
This is the campaign's hardest-won lesson (fabricated fixtures pass vacuously):

```bash
EIDOLONS_COMPLIANCE_NO_LIVE= \
  eidolons eval compliance --arm A --k 1 --yes --keep --capture-sample \
    --suite-file evals/compliance-suite.yaml
# Find the saved raw stream under the kept fixture:
#   <fixture>/.eidolons/compliance/last-stream.jsonl
```

Open it and confirm the parser's Task-detection path (`_parse_stream` in
`cli/src/eval_compliance.sh`) matches the real envelope: `tool_use` blocks with `name:"Task"`
and an `input.subagent_type`, under either `.message.content[]` or `.content[]`. If the live
shape differs, fix the parser and re-capture **before** step 3. Replace the placeholder
`cli/tests/fixtures/compliance/live-sample.jsonl` with this verbatim capture and add/adjust a
parser test so the real shape is locked.

> `EIDOLONS_COMPLIANCE_NO_LIVE=` (empty) in front of the command clears the safety net for
> that single invocation. Never export it cleared in a shell you also run `make test` in.

## 3. Headline run (56 billed sessions)

```bash
EIDOLONS_COMPLIANCE_NO_LIVE= \
  eidolons eval compliance --arm both --k 2 --model sonnet --yes --json \
    --suite-file evals/compliance-suite.yaml \
    > /tmp/compliance-scorecard.json
jq '{gate, armA: .arms.A.correct_target_rate, armB: .arms.B.correct_target_rate, delta}' \
  /tmp/compliance-scorecard.json
```

`--k 2` is the floor for a headline claim: k=1 is noise (the Coder-7.5 lesson). Read the
per-class breakdown and `stability_passk` to see which capability classes the host routes
reliably versus flakily.

## 4. Interpreting the result

- **`gate.verdict`** is computed against `A.correct_target_rate` vs 80%. PASS → the
  inject-default posture is empirically justified on this host. FAIL → the reversal action
  (`ESCALATE: recommend block default`) applies; open the discussion to flip the T3 default
  to the strict tier.
- **`delta.correct_target_rate` (A − B)** isolates the *harness effect*: a positive delta is
  the evidence that mechanical injection beats documentary prose. A near-zero delta with a
  high absolute rate means the host already routes well without the harness; a near-zero
  delta with a low rate means the injection is not landing (investigate the hook wiring via
  `eidolons harness status` and `eidolons doctor --deep`).
- **Realism caveat.** Fixture sessions run under a read-only tool allowlist (Task + read
  tools), common to both arms — so the delta is robust but the absolute arm-A rate is a
  *floor* under a constrained surface. Note this when quoting the number.

## 4b. Closing the SessionStart-only floor (`--driver claude-headless-ups`)

The 2026-06-12 headline (66.7%, GATE FAIL) was explicitly a **floor** for a second reason:
Claude Code **2.1.175**'s headless `claude -p` fired only `SessionStart` hooks, **not**
`UserPromptSubmit` — the primary T3 per-prompt injection. That measured the always-loaded
cortex digest, not the per-prompt "Route: <eidolon>" nudge the 80% gate was written about.

**That floor is now closable.** On Claude Code **>= 2.1.200**, headless `claude -p` fires
`UserPromptSubmit` (verified 2026-07 with a $0 hook-marker probe: a scratch project whose
UPS hook `touch`es a marker, run under a dead `ANTHROPIC_BASE_URL` so the model call fails
connection-refused before any tokens are sent — both the marker and a stream
`hook_event:"UserPromptSubmit"` appeared). Use the built-in `claude-headless-ups` driver to
rerun with the mechanism live **and certified**:

```bash
EIDOLONS_COMPLIANCE_NO_LIVE= \
  eidolons eval compliance --arm both --k 2 --model sonnet --yes --json \
    --driver claude-headless-ups \
    --suite-file evals/compliance-suite.yaml \
    > /tmp/compliance-scorecard-ups.json
jq '{ups_fired, gate, armA: .arms.A.correct_target_rate, delta}' \
  /tmp/compliance-scorecard-ups.json
```

- `--driver claude-headless-ups` is a **reserved built-in name** (not a shell command): it
  runs the same `claude -p` path plus `--include-hook-events`, then records **`ups_fired`**
  in the scorecard — `"true"` = every ARM-A session fired `UserPromptSubmit` (mechanism
  live); `"false"` = it did not (the floor persists — check `eidolons harness status` /
  `eidolons doctor --deep`); `"unknown"` = not certified (default/custom/fake driver).
- **Confirm `ups_fired == "true"` before trusting the headline.** If it is `"false"` or
  `"unknown"`, the number is still a SessionStart-only floor and the June caveat stands.
  Before concluding the mechanism is dead on a `"false"`, check the run log for session
  timeouts: prior to the partial-stream fix (post-1.49.0), any timed-out ARM-A session
  counted as never-fired (the 2026-07-03 run reported `"false"` from 5 timeouts while a
  $0 dead-URL probe in the identical fixture proved UPS fired). On current code a
  timed-out session's already-emitted events still count; a `"false"` now means at least
  one ARM-A session genuinely produced no UPS event.
- **Version gate.** The driver refuses to run below Claude Code `2.1.200` with an actionable
  error (2.1.175 provably fired SessionStart only). Override the floor with
  `EIDOLONS_COMPLIANCE_UPS_VERSION_FLOOR=<ver>` if a lower version is known to fire UPS —
  `ups_fired` remains the per-run ground truth regardless.
- The old SessionStart-only default driver still works and reports `ups_fired: "unknown"`;
  prefer `claude-headless-ups` for any headline that quotes the absolute arm-A rate against
  the 80% gate.

## 5. Record the result

Commit the scorecard and a short interpretation to `.spectra/research/` following the
`kupo-eval-results.md` convention, e.g. `.spectra/research/compliance-eval-<date>.md`, and
cross-link it from `project_harness_mechanization` memory. If the gate FAILs, that artifact
is the input to the inject-vs-block default decision.

## Driver substitution (other hosts / CI)

`--driver '<cmd>'` replaces the default `claude -p` invocation; the command receives the
prompt on argv and stdin and must emit the host's stream on stdout. This is how Codex,
OpenCode, or a future CI harness measure the same suite without the Claude binary. A custom
driver bypasses the `NO_LIVE` net (it only guards the default-claude path), so a CI that sets
a real `--driver` is responsible for its own cost gating.

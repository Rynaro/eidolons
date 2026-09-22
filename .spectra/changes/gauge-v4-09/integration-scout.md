# V4-09 integration scout

Static source: original main `1a4697e2101f5c588dcf3632c6823e7b73c86d58`. Authority: supplied `/private/tmp/gauge-v4-09-requirements.md` and FORGE decision. Read source and test definitions only; no evaluations, host/model/network calls, private logs, or moving V4-06 worktree inspection. Scratch report is the only write. CRYSTALIUM unavailable. Confidence H means directly anchored source behavior, not live qualification.

## Capability versus evidence

- `roster/host-capabilities.json:1–17` contains only schema version plus Claude capability-class → tool-name mappings. `_eiis_v3_claude_tools` consumes it to generate descriptor tool lists (`cli/src/lib_eiis_v3.sh:31–40`). It is policy/configuration data, not a host/version/method/billing qualification catalogue. H.
- `harness check` verifies lock-to-file registration, executable bits and shell syntax (`cli/src/harness_check.sh:8–10,20–59`). It proves neither execution, cancellation, child visibility nor hard caps. H.
- `readiness --live` calls that registration checker, records `host_version:"unknown"`, and derives `enforceable` from lock membership (`cli/src/readiness.sh:55–67`). Never upgrade this receipt's `live_probe`/`passed` labels into V4-09 qualification. H.
- Compliance has a useful empirical hook-event parser: `_stream_ups_fired` detects UserPromptSubmit lifecycle events (`cli/src/eval_compliance.sh:656–670`). Its version gate proceeds on unparseable version and permits an environment floor override (`:225–243`); it is not a fail-closed exact tuple qualification. A detected hook event proves that event, not every required capability. H.

## Native/original-v3 and shadow seams

- H-WIN arms are `bare-standard`/sonnet and `system-light`/haiku, both passed through the same `eval_swe.sh` and sandbox loop (`evals/arms/h-win.json:3–21`; `cli/src/eval_swe.sh:149–180,437–445`). Neither is an untouched native control or the supplied pinned original-v3 commit. Preserve the supplied original-v3 SHA as an explicit baseline-manifest input; do not reinterpret these labels. H.
- The bare hook still edits through a supplied prompt, a timeout and `claude -p --permission-mode acceptEdits` (`evals/hooks/keep-bare.sh:40–78`). The system hook may read the first installed Kupo cache SPEC or use a static fallback (`evals/hooks/keep-system.sh:37–74`). Exact prompts/cache inputs therefore need freezing; same arm label alone does not establish the same treatment. H.
- `harness_hook.sh` actively emits delegation instructions and model-tier guidance (`cli/src/harness_hook.sh:564–604`). It is an intervention, not a shadow observer. Retain its behavior for the appropriate baseline; observation on/off must not add or remove these instructions. H.
- The existing observational seam is optional telemetry stamping, described as leaving routing output byte-identical (`cli/src/run.sh:564–568`). Existing fixture `cli/tests/telemetry_identity.bats:80–137` is a starting compatibility control, not full prompt/tool/model-setting equivalence proof. H.

## Recorder, protocol and environment gaps

- Matrix arms accept arbitrary environment entries and command-string hooks; schema records labels/hook/env/control but no baseline, qualification or frozen protocol identity (`schemas/eval-arms.schema.json:14–38`; `cli/src/eval_swe.sh:157–180`). First control wins; missing control merely skips comparison (`:134,238`). H.
- Single-arm evaluation materializes shell setup, discarding its failure status, then invokes the bounded loop (`cli/src/eval_swe.sh:399–445`). It preserves each repeated run's final string and includes failed runs in k, but matrix scorecards discard final strings and retain only resolved/pass/attempt counts (`:446–457,185–200`). `attempts` means k independent runs, not every repair attempt (`schemas/eval-scorecard.schema.json:25–35`). H.
- The lower sandbox records test exit/duration/output details (`cli/src/sandbox.sh:262–326`), but those durations are test-command elapsed time, not complete setup/inference/environment/human resource coverage. Raw output tails are not safe automatic inputs to V4-08's metadata-only recorder. H.
- Model-driven scorecard token totals are null, smoke totals zero (`cli/src/eval_swe.sh:471–482`). Preserve that honest distinction; do not fabricate complete cost from these cards. No existing fields supply V4-09's common all-attempt native/v3 resource record (`schemas/eval-scorecard.schema.json:7–48`). H.
- Matrix records a wall-clock start and nexus version, writes `<date>-<suite>-<label>` directly, and overwrites same-day runs (`cli/src/eval_swe.sh:129–134,185–205`; `evals/results/README.md:31–34`). This is not append-only prospective freeze. H.
- Baseline comparison selects date/label files and compares rates/task IDs; it does not verify protocol, baseline implementation or environment equality (`cli/src/eval_baseline.sh:91–141`). H.
- Existing isolation is a `--via` command string or explicit unsafe-host option, with smoke allowed on host (`cli/src/eval_swe.sh:378–390`). It is not a typed CPU/memory/network/dependency/cache/timeout guarantee. The scorecard loses even the single-arm isolation label during matrix projection (`:185–200,478–482`). H.
- Existing holdout support passes an inline command to the loop (`cli/src/eval_swe.sh:414–424`); absence from task-workdir files is not a qualified evaluator ownership/access boundary. No protected-oracle claim follows. H.

## Live workflow and billing boundaries

- Scheduled workflow always uses smoke. Manual live selection uses a repository variable plus API-key presence (`.github/workflows/live-eval.yml:74–99`), then installs unpinned Claude CLI (`:130–137`). These are legacy CI gates, not V4-07 authorization or a qualified spending-mode tuple. H.
- As written, the live invocation supplies neither `--via` nor `--allow-unsafe-host` (`live-eval.yml:140`), so the existing non-smoke isolation refusal applies (`eval_swe.sh:378–388`). This is a static integration finding; no live run attempted. H.
- Workflow smoke fallback is explicitly labelled plumbing-only (`live-eval.yml:8–22`), and stored results document the same distinction (`evals/results/README.md:43–54`). For V4-09, a missing required live criterion still needs a separate blocked state; smoke success cannot satisfy it. H.

## Safe fixture reuse and acceptance mapping

→ APIVR-Δ: Reuse deterministic task bodies/reference fixes from `evals/swe-suite.yaml:26–46` as synthetic known outcomes only; do not use bundled reference-fix rates as live effectiveness evidence.

→ APIVR-Δ: Reuse isolated result-store setup and fake arm shape from `cli/tests/eval_matrix.bats:7–29`; preserve smoke tagging, no-store, duplicate-label rejection and explicit missing-driver/model guards (`:58,91,136,251–286`). Its “schema-valid” helper is a jq shape assertion, not full JSON Schema validation (`:33–55`).

→ APIVR-Δ: Reuse compliance fixture-building/engineered stream patterns (`cli/src/eval_compliance.sh:333–359,632–670`; `cli/tests/eval_compliance.bats:3–27`). Tests set `EIDOLONS_COMPLIANCE_NO_LIVE=1`, but that guard blocks only the default Claude path, not custom commands (`eval_compliance.sh:793–815`). V4-09 blocked-path tests need an injected transport counter that covers every adapter, including API fallback; do not rely on PATH or this flag alone.

→ VIGIL/checker: Preserve unfixable-task failure, require-red, genuine-fix and visible-only-fix controls (`cli/tests/eval_swe.bats:57,123–159`). Add the FORGE-required identical native/v3 recorder arithmetic, all failed/cancelled/abandoned attempts, repeated acceptance deduplication, unknown-cost totals, and zero-accepted undefined ratio. No baseline card already supplies those guarantees.

→ VIGIL/checker: Add exact-tuple drift/billing rejection; fake-not-live qualification; prefreeze/forged-time/changed-manifest/wrong-protocol rejection; environment mismatch or declared stratification; shadow request equality; unavailable-arm eligibility without fabricated attempts. These are new fixture contracts from the supplied decision, not claims about existing implementation.

Implementation waits for accepted V4-06–08 interfaces. Reuse the existing fixture vocabulary and legacy compatibility tests; do not reuse daily scorecards as canonical records, CI credentials as allowance, host registrations as execution proof, or H-WIN labels as native/original-v3 controls. No live qualification or performance evidence established.

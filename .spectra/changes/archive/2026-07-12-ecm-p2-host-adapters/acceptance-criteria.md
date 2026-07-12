# ECM P2 — Acceptance Criteria (EARS)

## Track A — Codex adapter (full ladder)

### AC-CDX-1 (event-driven)
GIVEN eidolons.yaml declares a `context:` block AND codex ∈ hosts.wire
WHEN `eidolons harness install` runs
THEN `.eidolons/harness/hooks/codex-PostToolUse.sh` is written invoking `run --hook codex --post-tool-use`
VERIFY: bats — file exists; `grep -q 'run --hook codex --post-tool-use' codex-PostToolUse.sh`

### AC-CDX-2 (event-driven)
GIVEN codex wired with ECM on
WHEN `eidolons harness install` runs
THEN `.codex/hooks.json` `.hooks.PostToolUse[]` contains the codex PostToolUse shim command
VERIFY: bats — `jq -e '.hooks.PostToolUse[].command | select(endswith("codex-PostToolUse.sh"))' .codex/hooks.json`

### AC-CDX-3 (event-driven)
GIVEN a meter zone transition on stdin
WHEN `eidolons run --hook codex --post-tool-use` is driven
THEN stdout is a `hookSpecificOutput.hookEventName=="PostToolUse"` object carrying `additionalContext`
VERIFY: bats parity test mirroring harness.bats:1655 — assert same envelope shape as claude-code

### AC-CDX-4 (event-driven)
GIVEN ECM on for codex
WHEN `eidolons run --hook codex` handles a UserPromptSubmit firing
THEN the injected `additionalContext` contains a `Context: zone=… util=… policy=…` line
VERIFY: bats — `additionalContext` matches `Context: zone=`

### AC-CDX-5 (event-driven)
GIVEN ECM on for codex
WHEN `eidolons run --hook codex --session-start` runs
THEN `additionalContext` contains the `## Context policy` pins-and-handoff block
VERIFY: bats — `additionalContext` matches `Pins (must survive`

### AC-CDX-6 (event-driven)
GIVEN the codex config has no `model_auto_compact_token_limit` key
WHEN `eidolons harness install` runs for codex with ECM on
THEN `model_auto_compact_token_limit` is written to the codex config
VERIFY: bats — `grep -q '^model_auto_compact_token_limit' .codex/config.toml`

### AC-CDX-7 (unwanted-behavior)
IF the codex config already sets `model_auto_compact_token_limit` to a foreign value
WHEN `eidolons harness install` runs
THEN the existing value is left byte-unchanged (don't-clobber)
VERIFY: bats — seed foreign value; assert file unchanged; assert lock `codex_autocompact_managed=false`

## Track B — OpenCode adapter (start + per-prompt system-prompt)

### AC-OC-1 (event-driven)
GIVEN opencode ∈ hosts.wire AND ECM on
WHEN `eidolons harness install` runs
THEN the opencode plugin registers an `experimental.chat.system.transform` hook
VERIFY: bats — `grep -q 'experimental' && grep -q "chat.system.transform" .opencode/plugins/eidolons.js`

### AC-OC-2 (event-driven)
GIVEN the ECM opencode plugin is installed
WHEN the system transform fires
THEN it appends a live meter line to `output.system`
VERIFY: bats — `grep -q 'output.system' .opencode/plugins/eidolons.js`; node smoke-run asserts a `zone=` line appended

### AC-OC-3 (event-driven)
GIVEN opencode wired with ECM on
WHEN `eidolons harness install` runs
THEN the plugin registers an `experimental.session.compacting` externalize hook
VERIFY: bats — `grep -q 'session.compacting' .opencode/plugins/eidolons.js`

### AC-OC-4 (unwanted-behavior)
IF a reader inspects the opencode ECM plugin
WHEN searching for a per-tool AI-visible injection claim
THEN no PostToolUse or per-tool inject path is present
VERIFY: bats — `! grep -qi 'PostToolUse\|per-tool inject' .opencode/plugins/eidolons.js`

## Track C — Copilot adapter (start-only static file)

### AC-CP-1 (event-driven)
GIVEN copilot ∈ hosts.wire AND ECM on
WHEN `eidolons harness install` runs
THEN a `<!-- eidolon:ecm-context start -->` marker block is upserted into `.github/copilot-instructions.md`
VERIFY: bats — `grep -qF '<!-- eidolon:ecm-context start -->' .github/copilot-instructions.md`

### AC-CP-2 (state-driven)
WHILE the copilot ECM block is present
WHEN its body is inspected
THEN it contains the pin digest plus the handoff digest
VERIFY: bats — block interior matches `Pins:` plus `Prior session handoff`

### AC-CP-3 (unwanted-behavior)
IF the copilot ECM block is inspected for a live-refresh promise
WHEN searching its text
THEN no live-meter or per-prompt-refresh claim is present
VERIFY: bats — `! grep -qi 'live meter\|per-prompt refresh\|updated each turn'` within the marker block

### AC-CP-4 (event-driven)
GIVEN a prior install
WHEN `eidolons harness install` runs a second time
THEN the copilot ECM block is byte-identical
VERIFY: bats — capture block; re-run; `diff` is empty

## Track D — Cursor adapter (static documentary floor)

### AC-CR-1 (event-driven)
GIVEN cursor ∈ hosts.wire AND ECM on
WHEN `eidolons harness install` runs
THEN a marker-bounded ECM floor is written to `.cursor/rules/eidolons-context.mdc`
VERIFY: bats — file exists; `grep -qF '<!-- eidolon:ecm-context start -->' .cursor/rules/eidolons-context.mdc`

### AC-CR-2 (ubiquitous)
GIVEN the cursor ECM `.mdc` floor is written
THEN the file text documents its static-only limitation
VERIFY: bats — `grep -qi 'static' .cursor/rules/eidolons-context.mdc`

### AC-CR-3 (unwanted-behavior)
IF the cursor ECM `.mdc` is inspected for a runtime-injection promise
WHEN searching its text
THEN no live-injection or meter-refresh claim is present
VERIFY: bats — `! grep -qi 'meter refresh\|per-prompt\|live inject' .cursor/rules/eidolons-context.mdc`

### AC-CR-4 (event-driven)
GIVEN a prior install
WHEN `eidolons harness install` runs a second time
THEN `.cursor/rules/eidolons-context.mdc` is byte-identical
VERIFY: bats — `diff` of before/after is empty

## Track E — Removal parity

### AC-RM-1 (event-driven)
GIVEN ECM wrote `compactThreshold` into `.claude/settings.json`
WHEN `eidolons harness remove` runs
THEN the `compactThreshold` key is absent from `.claude/settings.json`
VERIFY: bats — `jq -e 'has("compactThreshold") | not' .claude/settings.json`

### AC-RM-2 (event-driven)
GIVEN eidolons.lock carries a `context:` block
WHEN `eidolons harness remove` runs
THEN the `context:` top-level key is absent from eidolons.lock
VERIFY: bats — `! grep -q '^context:' eidolons.lock`

### AC-RM-3 (event-driven)
GIVEN ECM managed `model_auto_compact_token_limit` in the codex config
WHEN `eidolons harness remove` runs
THEN the managed `model_auto_compact_token_limit` line is stripped from the codex config
VERIFY: bats — `! grep -q '^model_auto_compact_token_limit' .codex/config.toml` when managed=true

### AC-RM-4 (event-driven)
GIVEN the copilot ECM marker block exists with sibling content around it
WHEN `eidolons harness remove` runs
THEN the ECM marker block is gone while sibling content is preserved byte-identically
VERIFY: bats — marker absent; a seeded sibling line still present

### AC-RM-5 (event-driven)
GIVEN `.cursor/rules/eidolons-context.mdc` exists
WHEN `eidolons harness remove` runs
THEN the cursor ECM `.mdc` floor is removed
VERIFY: bats — file absent

### AC-RM-6 (event-driven)
GIVEN a full multi-host ECM install
WHEN install→remove→install is run
THEN `.claude/settings.json` is byte-identical across the two installs
VERIFY: bats — `jq -cS .` byte-compare of both installs

## Track F — Fail-open invariant (P0)

### AC-FO-1 (unwanted-behavior)
IF a wired host exposes no reliable live channel (cursor)
WHEN `eidolons harness install` runs
THEN the process exits 0 after writing the documentary floor
VERIFY: bats — `status -eq 0`; `.cursor/rules/eidolons-context.mdc` present

### AC-FO-2 (unwanted-behavior)
IF the meter zone is `unknown`
WHEN `eidolons context policy --json` is evaluated for any host
THEN the operation resolves to `continue`
VERIFY: bats — seed meter zone=unknown; `jq -e '.operation=="continue"'`

### AC-FO-3 (unwanted-behavior)
IF the codex config file is unwritable or not valid TOML for our append
WHEN `eidolons harness install` runs
THEN the process warns and exits 0 with the other hosts still wired
VERIFY: bats — chmod 0444 config; `status -eq 0`; claude-code shim still written

## Track G — Lock + schema

### AC-LK-1 (event-driven)
GIVEN a multi-host wire with ECM on
WHEN `eidolons harness install` runs
THEN `eidolons.lock` `context.per_host` records each wired host's effective ECM tier
VERIFY: bats — `jq -e '.context.per_host.codex.tier=="T3"' <(yaml_to_json eidolons.lock)`

### AC-LK-2 (event-driven)
GIVEN codex ECM install wrote the auto-compact knob
WHEN the lock is written
THEN `context.codex_autocompact_managed` is recorded as a boolean
VERIFY: bats — `jq -e '.context.codex_autocompact_managed | type=="boolean"'`

### AC-LK-3 (ubiquitous)
GIVEN a P1 lock fixture and a P2 augmented lock fixture
THEN `eidolons.lock.schema.json` validates both
VERIFY: CI — `jq empty schemas/eidolons.lock.schema.json`; validate P1 + P2 lock fixtures pass

## Track H — Atomos tripwire (P2-exit gate)

### AC-TW-1 (event-driven)
GIVEN every wired host has run `eidolons canary --context-handoff`
WHEN all hosts PASS the round-trip via kernel+hooks alone at P2 exit
THEN the atomos P3 roadmap line is absent from `docs/specs/ecm/spec.md` §8
VERIFY: gate — canary all-PASS triggers an ESL edit; `! grep -qi 'atomos' spec.md §8` post-edit

### AC-TW-2 (unwanted-behavior)
IF a host fails the context-handoff canary for an injection-surface reason
WHEN the P2-exit gate classifies the failure
THEN the failure routes to a host plugin/shim remedy (H4), never an atomos green-light
VERIFY: gate — classifier maps injection-surface failure to H4; assert no atomos roadmap re-entry

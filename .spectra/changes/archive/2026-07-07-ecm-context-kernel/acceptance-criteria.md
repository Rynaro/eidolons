# ECM P1 — Frozen Acceptance Criteria (EARS, lintable)

### AC-1 (event-driven)
GIVEN a session with a readable transcript or host telemetry
WHEN `eidolons context status` runs
THEN the kernel SHALL write .eidolons/.context/meter.json carrying a zone field, exiting 0
VERIFY: bats: cli/tests/context.bats#status_writes_meter_and_zone

### AC-2 (event-driven)
GIVEN a fixed meter.json input
WHEN `eidolons context policy --json` evaluates roster/context-policy.yaml
THEN the same meter input SHALL yield the identical operation verdict on repeat runs
VERIFY: bats: cli/tests/context.bats#policy_is_deterministic

### AC-3 (unwanted-behavior)
GIVEN crystalium is not installed
WHEN `eidolons context externalize` runs
THEN the kernel SHALL write the file-floor manifest .eidolons/.context/externalized-<ts>.json without blocking
VERIFY: bats: cli/tests/context.bats#externalize_file_floor_when_crystalium_absent

### AC-4 (event-driven)
GIVEN a handoff brief committed via crystalium_ingest in session N
WHEN session N+1 memory pre-flight recalls session_handoff
THEN the brief SHALL be recalled matching session N by envelope SHA-256
VERIFY: canary: eidolons canary --context-handoff round-trip

### AC-5 (event-driven)
GIVEN a Claude Code project already harness-installed
WHEN `eidolons harness install` runs a second time
THEN the generated hook shims plus settings SHALL be byte-identical to the first run
VERIFY: bats: cli/tests/context.bats#harness_install_idempotent

### AC-6 (state-driven)
GIVEN a host exposing exact context telemetry (Claude Code statusline used_percentage)
THEN the meter SHALL record estimate_source=host rather than a bytes/4 estimate
VERIFY: bats: cli/tests/context.bats#meter_prefers_host_telemetry

### AC-7 (unwanted-behavior)
GIVEN neither host telemetry nor a readable transcript file exists
WHEN the meter is computed
THEN the zone SHALL be "unknown" so the policy resolves to continue
VERIFY: bats: cli/tests/context.bats#meter_fail_open_unknown

### AC-8 (event-driven)
GIVEN a handoff brief whose composed size exceeds the 1500-token advisory target
WHEN the composer finalizes the brief
THEN the composer SHALL record the oversize to the policy log without truncating the artifact
VERIFY: bats: cli/tests/context.bats#brief_advisory_target_never_truncates

### AC-9 (unwanted-behavior)
GIVEN a handoff brief flagged contains_tool_origin=true
WHEN the round-trip canary recalls session_handoff in the successor session
THEN the flagged brief SHALL still surface on default recall (quarantine-vs-recall regression)
VERIFY: canary: eidolons canary --context-handoff tool-origin

### AC-10 (unwanted-behavior)
GIVEN .claude/settings.json already sets compactThreshold to a value other than 75
WHEN `eidolons harness install` runs
THEN the existing value SHALL be preserved, recorded as managed=false in the lock
VERIFY: bats: cli/tests/context.bats#compactthreshold_dont_clobber

### AC-11 (event-driven)
GIVEN a Claude Code project with no prior compactThreshold setting
WHEN `eidolons harness install` runs
THEN it SHALL write compactThreshold=75, recording managed=true in the eidolons.lock context block
VERIFY: bats: cli/tests/context.bats#compactthreshold_written_when_absent

### AC-12 (event-driven)
GIVEN a UserPromptSubmit hook firing with an ECM meter digest
WHEN the shim emits additionalContext
THEN the injected artifact SHALL be at most 200 tokens
VERIFY: bats: cli/tests/context.bats#ups_inject_within_200_tokens

### AC-13 (state-driven)
GIVEN the kernel is running inside a subagent session
THEN a handoff_fresh policy verdict SHALL remap to finish_and_return
VERIFY: bats: cli/tests/context.bats#subagent_remaps_handoff_fresh

### AC-14 (state-driven)
GIVEN multiple concurrent sessions writing budget records
THEN the budget-ledger SHALL be appended as JSONL rather than rewritten in place
VERIFY: bats: cli/tests/context.bats#budget_ledger_is_append_only

### AC-15 (optional-feature)
GIVEN an eidolons.yaml with no context block
THEN ECM SHALL be treated as disabled with no schema validation error
VERIFY: bats: cli/tests/context.bats#ecm_opt_in_absent_block

### AC-16 (event-driven)
GIVEN crystalium is installed with an ECL envelope for the handoff brief
WHEN `eidolons context handoff` persists the brief
THEN the canonical persist path SHALL be crystalium_ingest of the envelope with no commit fallback branch
VERIFY: bats: cli/tests/context.bats#handoff_ingest_is_canonical

### AC-17 (event-driven)
GIVEN the eidolons.lock gains a context block
WHEN `make schema` validates the lock schema
THEN the schema validation SHALL pass with the context key covered
VERIFY: bats: cli/tests/context.bats#lock_schema_covers_context

# Scout: crystalium 1.8.0 — one-shot `ingest` + `topic_key: session_handoff` recall surfacing

**REV 2 (rescout).** Origin fetched over HTTPS; delta range `8a785e7..b6adf99`
(v1.5.1 → v1.7.0, two commits: `6379ab9` = 1.6.0 diagnosability wave, `b6adf99` =
1.7.0 commit verb + version stamp). Local working tree is still the stale/dirty
1.5.1 checkout — all 1.7.0 anchors below were read via
`git -C /home/rynaro/workspace/oss/agents/crystalium show origin/main:<path>` /
`diff 8a785e7 b6adf99`. FINDING-000 (staleness caveat) is RESOLVED and removed;
carried-forward findings are tagged **[CARRIED]** (verified unchanged at 1.7.0),
flipped ones **[FLIPPED]**.

## 1. THE TEMPLATE — one-shot `commit` verb (1.7.0, PR #30)

**FINDING-100.** Single file: `mcp-server/src/crystalium/__main__.py`, new
`@cli.command() commit` inserted between `recall` and `export` (~L373-575 at
`b6adf99`). **Arg shape: flags only — no stdin, no file paths.**
`--summary` (required) | `--content` (default: the summary text) |
`--scope-project` (required) | `--scope-visibility` | `--source
human|verified_agent|unverified_agent|environment` (default `environment`) |
`--author-agent` (default `crystalium-cli`) | `--task-id` | `--format json|text`
(default json) | `--config`. Data-dir bootstrap: `Config.from_yaml(config_path)
if exists else Config.from_env()` (same idiom as recall/export). Output contract:
stdout = exactly one JSON doc (`json.dumps(result, default=str)` of the raw
`episodic.commit` dict: status/id/layer/validation_state/importance/content_ref);
`--format text` = just the crystal id. structlog rebound to `sys.__stderr__`.
Exit 0 success; any rejection → `click.ClickException` = exit 1, no stdout JSON.
Code sharing: **does NOT call `_handle_commit`** — builds
`BlobStore+RelationalStore+Enforcement+Redactor+EpisodicLayer(vector_store=None,
graph_store=None)` inline (index()'s pattern) and calls `episodic.commit()`
directly. Caller tier: `CRYSTALIUM_CALLER_TIER` env, **default T0** (asymmetric
vs recall's T1; inline comment explains it only affects the stamped trust_tier +
T3-quarantine, since episodic ceiling is T3/universally writable).
Tests: new `mcp-server/tests/test_commit_cli.py` (325 lines, real tmp-dir stores,
no mocks): happy-path commit→recall BM25 round-trip, poor-summary exit 1,
machine-label summary exit 1, missing required flags, `--format text` = bare
UUID line, source default/override persisted, `commit --help` pulls no heavy deps.

**FINDING-101.** Hard-vs-soft gate split: the v1.6 summary-quality gate
(`quality.py`: `is_poor_summary` = <24 chars stripped OR <3 alpha words OR
`^[a-z_]+:[0-9a-f-]+$`) is a **HARD reject (exit 1) on the CLI commit verb**,
but soft/advisory (`summary_quality:"poor"`) on the MCP commit tool — rationale
documented in the `--summary` help text: no in-session agent to read an advisory
back. The MCP **ingest** path has **no summary gate at all** (1.7.0
`_handle_ingest` diff adds only scope normalization). RAMZA must decide which
posture the CLI `ingest` verb takes (its summary is server-composed from
`kind: objective`, not caller-typed — soft/none is defensible).

**FINDING-107.** Asymmetry to resolve in the 1.8 spec: **the CLI commit verb
does NOT apply v1.6 canonical scope normalization** (calls `episodic.commit`
directly; `normalize_write_scope` lives only in `_handle_commit`/
`_handle_ingest`/execution.checkpoint) — it stores `--scope-project` verbatim,
test-locked by `test_commit_cli.py`'s round-trip using the verbatim key. A CLI
`ingest` verb reusing `_handle_ingest` (recommended) will normalize —
MCP-consistent, CLI-commit-inconsistent. Flag, don't silently inherit.

## 2. Carried / flipped findings vs REV 1

**[CARRIED] FINDING-002/003/004** (recall/export/index verb patterns) — recall
gains `--explain` flag + `model_dump(exclude_none=True)`; discipline otherwise
unchanged.

**[CARRIED, signature changed] FINDING-005.** `_handle_ingest` is still a free
function and still the ideal CLI reuse point, but 1.6.0 added a positional:
now `_handle_ingest(args, episodic, semantic, procedural, execution, config,
recall_cache=None)` (`server.py:1141-1148` at b6adf99). Tests thread it as
`enforcement.config` (`test_ingest_handler.py:46-48`).

**[CARRIED] FINDING-006** (11-field envelope validation + G7 raw-byte hash check
at `server.py:~1190`) and **FINDING-007** (MIN-trust `resolve_caller_tier`;
`ingest_adapter.py` has **zero diff** in the range) — unchanged.

**[FLIPPED] FINDING-008 → FINDING-102.** At 1.5.1 ingest stored
`scope.project = thread_id` (recall had to know the thread). At 1.6.0+,
`_handle_ingest` **normalizes `scope.project` to
`canonical_project_key(config.data_dir)`** = basename of `CRYSTALIUM_DATA_DIR`
(`scope.py:34-43`; `server.py:1206-1213`); the thread_id survives verbatim in
new optional `scope.project_raw` (`schemas.py Scope`, `crystal.v1.json`) and in
`provenance.task_id`; result carries `scope_normalized: true`.
`test_roundtrip_handoff.py` now recalls by the canonical key and asserts
`project_raw == thread_id`. **Nexus implication (good news):** the nexus mounts
`CRYSTALIUM_DATA_DIR=/root/.crystalium/__PROJECT_SLUG__`
(`nexus:cli/templates/mcp/crystalium.mcp.json.tmpl`), so canonical key ==
`memory_probe_project_slug` == exactly what `memory preflight` already passes as
`--scope-project`. An ingested `session_handoff` brief is therefore recallable by
the successor session's default preflight scoping with **no envelope
thread_id coordination needed**.

**[CARRIED — AC-9 answer re-verified at 1.7.0] FINDING-010/FINDING-103.**
The 1.6.0 retrieve.py diff refactors the post-fusion filter into an
explain-countered waterfall (`retrieve.py:406-428` at b6adf99) but the filters
are still exactly two: `_scope_matches` + `_is_active` (status/temporal only,
behind `recall_active_only`). **Still no `validation_state` filter anywhere in
recall; quarantined crystals still surface.** Export-only quarantine exclusion
(`relational.list_for_export/count_for_export`) also unchanged. AC-9 verdict
stands: no recall-side change needed.

**[CARRIED] GAP-001** — still no `contains_tool_origin` field anywhere at 1.7.0;
tier-derived quarantine remains the only structural tool-origin signal.

**[CARRIED] GAP-002** — still no `topic_key` anywhere at 1.7.0; FTS still
indexes `summary` only; `map_envelope_to_crystal` still folds `artifact.kind`
into the summary prefix + `tags[0]` (adapter untouched). The
`kind="session_handoff"` → FTS-indexed-summary path remains viable; the
underscore-tokenization question remains open for Vivi's canary.

**[CARRIED] GAP-003** — `--envelope <json-string>` vs `--envelope-file`: the
1.7.0 commit verb confirms the house style is flags-with-inline-values (proven
through the nexus `%q` docker quoting for `--summary`), so the nexus's guessed
contract (`--envelope <json> --payload <text> --payload-encoding utf8 --format
json`) is stylistically compatible and `--payload-encoding` matches the MCP arg
name. A `--envelope-file`/`--payload-file` companion is still worth specifying
for multi-KB envelopes (joint RAMZA/nexus decision).

**[RESOLVED] GAP-004 → FINDING-105.** Version stamping is now single-sourced.
Mechanism (1.7.0 `install.sh:43-76`): `CRYSTALIUM_VERSION` is grepped at run
time from `[project].version` — probing `<repo>/mcp-server/pyproject.toml`
(checkout layout) then `<repo>/pyproject.toml` (container /app layout) — with a
hardcoded fallback literal (`"1.7.0"`) only for missing/unreadable file;
`SCRIPT_DIR` resolution moved above arg parsing so `--version` works under
`set -u`. `__init__.py` similarly single-sources via
`importlib.metadata.version("crystalium")` with `_FALLBACK_VERSION = "1.7.0"`;
`server.py` passes `Server("crystalium", version=__version__)` so MCP
serverInfo is correct. `test_install_manifest.py` now asserts against
pyproject, not a literal. **A 1.8.0 bump touches exactly:** (1)
`mcp-server/pyproject.toml [project].version` (the SSOT), (2) the two fallback
literals (`__init__.py _FALLBACK_VERSION`, `install.sh` fallback — both
comment-mandated "kept in sync"), (3) `CHANGELOG.md` (Keep-a-Changelog), plus
tag/image. Note: 1.7.0's CHANGELOG **pre-defers a `consolidate` batch verb to
1.8** — RAMZA should scope-fence ingest-verb 1.8.0 against that ledger entry.

## 3. New 1.6/1.7 machinery constraining the ingest verb / recallability

**FINDING-104.** For an ingested `session_handoff` crystal to be recallable by
`memory preflight --query`: (a) scope is now automatic (FINDING-102 — canonical
key); (b) the FTS-findable text is `summary = f"{artifact.kind}: {objective}"`
(`ingest_adapter.py:164`, unchanged) — **the envelope `objective` must carry the
query-matchable words**; the nexus's preflight query should target tokens the
brief's objective is guaranteed to contain (e.g. "session handoff brief").
No quality gate blocks ingest (FINDING-101). (c) `recall --explain` (v1.6:
CLI flag + MCP arg; `retrieve.py` explain object with
candidates_prefilter/filtered_by_scope/filtered_by_status/arms/store/
project_keys_present; cache-bypassing) plus `doctor`'s new memory-diagnostics
block (`__main__.py` doctor + `relational.diagnostics_summary()`) are the
purpose-built debug surfaces for the AC-9 round-trip canary — Vivi should wire
`--explain` into the canary's failure path.

## 4. Tests / run (updated)

1.7.0 adds `test_commit_cli.py` (the direct model for a new
`test_ingest_cli.py`) and `test_diagnosability.py` (628 lines, v1.6 wave).
`test_ingest_handler.py`/`test_roundtrip_handoff.py` updated for the `config`
param + canonical-key recall — extend these for the CLI verb's round-trip.
Container-first unchanged: `make test` / `make test-fast`
(`CRYSTALIUM_SKIP_SLOW=1`); host-side pytest banned (MISSION.md:113-117).

## 5. Guardrails (unchanged, re-verified against 1.7.0 diffs)

MISSION.md P0s hold: T3→Episodic-quarantine-only (rule 2, MISSION.md:41-42),
bi-temporal never-hard-delete (rule 5, MISSION.md:48-50; the 1.6 additions
`project_raw`/`explain` were both additive-optional — the precedent to follow
for any `topic_key` field), MIN-trust no-laundering (rule 6, MISSION.md:51-53;
re-asserted by the updated roundtrip tests). `forget` remains the sole
sanctioned hard-delete. New since REV 1: the v1.6 "never auto-deprecate the
last active checkpoint" Dream guard and canonical-scope normalization are
themselves now invariants — an ingest verb must not bypass
`normalize_write_scope` if it claims MCP parity.

## Handoffs

**→ RAMZA (spec 1.8.0):** (1) `ingest` verb = FINDING-100's flag style +
FINDING-005's `_handle_ingest(args, ep, se, pr, ex, config)` reuse (build via
`_build_components` or index()'s None-store stack) — envelope/tier/hash/scope
normalization all inherited; (2) AC-9: no recall change needed (FINDING-103) —
spec the round-trip canary on `recall --explain` instead (FINDING-104c);
(3) decide: summary-gate posture for ingest (FINDING-101), `--envelope-file`
companion (GAP-003), `contains_tool_origin` explicit field vs tier-inferred
(GAP-001), `topic_key` real field vs `artifact.kind`-in-summary convention
(GAP-002), and the FINDING-107 normalization asymmetry; (4) version bump per
FINDING-105 (SSOT + two sync'd fallbacks); scope-fence vs the pre-deferred
`consolidate` verb.

**→ Vivi (implementation):** model the verb + tests on
`test_commit_cli.py`/`commit` verbatim (stderr routing, lazy imports,
`--format json|text`, ClickException exit 1); pass `enforcement.config` (or
`Config` directly) as `_handle_ingest`'s 6th arg; assert
`scope_normalized`/`project_raw` behavior in the CLI round-trip test; verify
GAP-002's underscore FTS tokenization empirically; wire `--explain` into the
AC-9 canary failure diagnostics.

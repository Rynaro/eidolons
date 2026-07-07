---
artifact: acceptance-criteria
plan: spec-crystalium-1.8
change: ecm-context-kernel
target_repo: crystalium (origin/main b6adf99 = v1.7.0)
created_at: 2026-07-07
---

# Acceptance Criteria — crystalium 1.8.0: one-shot `ingest` CLI verb

All tests live in `mcp-server/tests/test_ingest_cli.py` (new file, modeled on
`mcp-server/tests/test_commit_cli.py`), run container-first:
`docker compose run --rm crystalium pytest mcp-server/tests/test_ingest_cli.py -v`.

### AC-101 (event-driven)
GIVEN a fresh CRYSTALIUM_DATA_DIR and a valid ECL v1.0 envelope whose artifact.sha256 matches the UTF-8 payload bytes
WHEN  `crystalium ingest --envelope <json> --payload <text> --payload-encoding utf8 --format json` runs
THEN  the process SHALL exit 0 with stdout carrying exactly one JSON document whose "status" field is "ingested"
VERIFY: test: test_ingest_cli.py::test_ingest_happy_path_single_json_doc

### AC-102 (event-driven)
GIVEN an ingested envelope with artifact.kind "session_handoff" whose objective carries a distinctive token
WHEN  `crystalium recall --query "session_handoff <token>" --scope-project <canonical-key>` runs one-shot in the same data dir
THEN  the ingested crystal id SHALL appear in the recall result's records[]
VERIFY: test: test_ingest_cli.py::test_session_handoff_roundtrip_recall_by_kind_and_token

### AC-103 (event-driven)
GIVEN an envelope with from.eidolon "eidolons-context-kernel" (not in _ROSTER_EIDOLONS) plus trace.tier "standard"
WHEN  it is ingested via the CLI verb
THEN  the result SHALL report trust_tier "T3" with validation_state "quarantined"
VERIFY: test: test_ingest_cli.py::test_tool_origin_envelope_lands_t3_quarantined

### AC-104 (event-driven)
GIVEN the quarantined session_handoff crystal produced by AC-103's envelope shape
WHEN  one-shot recall runs with the same query/scope as AC-102
THEN  the quarantined crystal id SHALL appear in records[] (quarantine MUST NOT exclude it from default recall)
VERIFY: test: test_ingest_cli.py::test_quarantined_session_handoff_still_surfaces_on_recall

### AC-105 (unwanted-behavior)
GIVEN an envelope that is internally consistent (integrity.value == artifact.sha256)
WHEN  the actual --payload bytes do not hash to the declared artifact.sha256
THEN  the process SHALL exit 1 with no JSON document on stdout (G7 binding preserved)
VERIFY: test: test_ingest_cli.py::test_payload_hash_mismatch_exits_1

### AC-106 (unwanted-behavior)
GIVEN an envelope missing a required ECL field (e.g. no "integrity")
WHEN  ingest runs
THEN  the process SHALL exit 1 with no JSON document on stdout
VERIFY: test: test_ingest_cli.py::test_missing_envelope_field_exits_1

### AC-107 (unwanted-behavior)
GIVEN an envelope declaring envelope_version "3.0"
WHEN  ingest runs
THEN  the process SHALL exit 1 with no JSON document on stdout
VERIFY: test: test_ingest_cli.py::test_unsupported_envelope_version_exits_1

### AC-108 (unwanted-behavior)
GIVEN an --envelope argument that is not parseable JSON
WHEN  ingest runs
THEN  the process SHALL exit 1 with a clear message on stderr, never a Python traceback
VERIFY: test: test_ingest_cli.py::test_envelope_parse_error_exits_1

### AC-109 (event-driven)
GIVEN an envelope mirroring the nexus composer exactly — kind "ecm/handoff-brief@0.1" plus extra top-level fields topic_key "session_handoff" as well as contains_tool_origin true
WHEN  ingest runs
THEN  the process SHALL exit 0 (extra envelope fields are tolerated, required-fields-only validation)
VERIFY: test: test_ingest_cli.py::test_nexus_envelope_shape_extra_fields_tolerated

### AC-110 (event-driven)
GIVEN an envelope with thread_id "thread-X" ingested via the CLI verb
WHEN  the result JSON is inspected
THEN  it SHALL carry scope_normalized true with the stored crystal's scope.project equal to canonical_project_key(CRYSTALIUM_DATA_DIR)
VERIFY: test: test_ingest_cli.py::test_scope_normalized_to_canonical_key

### AC-111 (event-driven)
GIVEN the same envelope as AC-110
WHEN  the stored crystal is recalled by the canonical project key
THEN  its scope.project_raw SHALL preserve "thread-X" verbatim
VERIFY: test: test_ingest_cli.py::test_thread_id_preserved_in_project_raw

### AC-112 (event-driven)
GIVEN a valid envelope/payload pair
WHEN  `crystalium ingest ... --format text` succeeds
THEN  stdout SHALL be exactly the new crystal id on a single line
VERIFY: test: test_ingest_cli.py::test_format_text_prints_only_id

### AC-113 (event-driven)
GIVEN a valid envelope whose objective is empty (server-composed summary degenerates to the bare kind)
WHEN  ingest runs
THEN  the process SHALL exit 0 (NO summary-quality gate on the ingest path — MCP crystalium.ingest parity, unlike the commit CLI's hard reject)
VERIFY: test: test_ingest_cli.py::test_no_summary_gate_on_ingest_path

### AC-114 (ubiquitous)
THEN  `crystalium ingest --help` SHALL never import torch, lancedb, or kuzu (lazy imports inside the function body)
VERIFY: test: test_ingest_cli.py::test_ingest_help_no_heavy_imports

### AC-115 (ubiquitous)
THEN  the MCP tool surface SHALL stay at exactly 9 tools (ingest ships CLI-side only)
VERIFY: test: test_ingest_cli.py::test_mcp_tool_surface_unchanged_9_tools (len(build_tool_manifest()) == 9)

### AC-116 (event-driven)
GIVEN an envelope resolving to tier T3 by identity (unknown from.eidolon)
WHEN  ingest runs with environment CRYSTALIUM_CALLER_TIER=T0 set
THEN  the result SHALL still report trust_tier "T3" (tier is envelope-derived MIN-trust; the env var is never read on the ingest path)
VERIFY: test: test_ingest_cli.py::test_caller_tier_env_ignored_tier_is_envelope_derived

### AC-117 (ubiquitous)
THEN  mcp-server/pyproject.toml [project].version SHALL equal "1.8.0" (the SSOT)
VERIFY: command: grep -m1 '^version' mcp-server/pyproject.toml | grep -q '"1.8.0"'

### AC-118 (ubiquitous)
THEN  both sync'd fallback literals (__init__.py _FALLBACK_VERSION; install.sh CRYSTALIUM_VERSION fallback) SHALL equal "1.8.0"
VERIFY: command: grep -q '_FALLBACK_VERSION = "1.8.0"' mcp-server/src/crystalium/__init__.py && grep -q 'CRYSTALIUM_VERSION="1.8.0"' install.sh

### AC-119 (ubiquitous)
THEN  CHANGELOG.md SHALL open with a Keep-a-Changelog "[1.8.0]" entry that re-states the `consolidate` verb as deferred (now to 1.9)
VERIFY: command: grep -q '^## \[1.8.0\]' CHANGELOG.md && grep -qi 'consolidate' CHANGELOG.md

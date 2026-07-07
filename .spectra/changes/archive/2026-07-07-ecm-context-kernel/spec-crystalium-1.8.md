---
eidolon: ramza
kind: spec
version: 1.0.0
created_at: 2026-07-07
plan: spec-crystalium-1.8
change: ecm-context-kernel
target_repo: /home/rynaro/workspace/oss/agents/crystalium
target_baseline: origin/main b6adf99 (= v1.7.0; working tree is STALE+DIRTY — all anchors read via `git show origin/main:<path>`)
tier: lite (rightsize score 3; complexity 6/12 standard)
maker: vivi
checker: kupo
criteria_sha256: 62ce0fd819eb4bb1b42dc13aaa9508ff24374365a26cd181593790813cfcbd8c
---

# Spec — crystalium 1.8.0: one-shot `ingest` CLI verb (+ session_handoff recallability locks)

> The `## Approach` section below settles the six decisions the task ordered (D-1…D-5 + fence).

Upstream remedy for the nexus change `ecm-context-kernel`'s AC-4/AC-9 verify-fail
(`verify-fail-upstream.md`): the pinned 1.7.0 image has one-shot `recall` and
`commit` but **no `ingest`** — `crystalium_ingest` exists only on the MCP tool
surface, so `eidolons canary --context-handoff` fails at the ingest step on both
legs. `ingest` is the missing third verb of the out-of-session CLI pairing
(precedent: recall → 1.4.0, commit → 1.7.0).

## Scope

**In:** one new `@cli.command() ingest` in `mcp-server/src/crystalium/__main__.py`
reusing the existing `_handle_ingest` free function (server.py:1141) unchanged; a
new CLI test file `mcp-server/tests/test_ingest_cli.py`; the 1.8.0 version bump
(SSOT + two sync'd fallback literals); a CHANGELOG entry.

**Out (SCOPE FENCE — explicit):**
- **`consolidate` is OUT.** 1.7.0's CHANGELOG (CHANGELOG.md:55-66) pre-defers the
  `consolidate` batch verb to 1.8; this change ships **ingest only**. The 1.8.0
  CHANGELOG entry re-states the deferral (now to 1.9 / the ROADMAP-POST-1.0.md
  ledger). `dream` remains the sole consolidation entry point.
- **No schema migrations, no new columns.** GAP-001 (`contains_tool_origin` field)
  and GAP-002 (`topic_key` field) stay convention-over-schema: tier-derived
  quarantine remains the structural tool-origin signal; `artifact.kind` folded
  into the FTS summary prefix (ingest_adapter.py:164) remains the topic signal.
  The 1.6 precedent for additive-optional fields (`project_raw`, `explain`) is
  noted for a future revision, not exercised here.
- **No recall filter changes.** FINDING-103 re-verified at 1.7.0: recall's
  post-fusion filters are exactly `_scope_matches` + `_is_active`
  (retrieve.py:406-428) — no `validation_state` filter; quarantined crystals
  surface. AC-104 locks this as a regression test; nothing in recall changes.
- **No MCP surface changes.** Verified at b6adf99: `build_tool_manifest()`
  (server.py:172-437) registers **exactly 9 tools** (recall, commit, ingest,
  update, skill_invoke, plan_checkpoint, plan_replan, session_end, graph_export).
  Nexus `roster/mcps.yaml` release comments track "9 tools" per release (its
  `exposes_tools.list` enumerates 8 — `graph_export` is missing from the list but
  covered by the `mcp__crystalium__*` glob; nexus-side cosmetic, out of this
  fence). **Invariant: tool count stays 9 at 1.8.0; `ingest` ships CLI-side only**
  (AC-115).
- **No changes to `server.py`, `ingest_adapter.py`, `scope.py`, `ecl.py`,
  `quality.py`** — the entire parity core is reused, not touched.
- **No trust-table edits.** `eidolons-context-kernel` is deliberately NOT added to
  `_ROSTER_EIDOLONS` (ingest_adapter.py:46-51): the nexus composer is mechanical
  environment-adjacent machinery; T3 + episodic-quarantine + recall-surfacing is
  the designed conservative posture (D5), not a defect.

## Approach

### D-1 — Verb contract: flags-only, exactly the nexus's guessed shape

House style confirmed by the 1.7.0 `commit` verb (FINDING-100: flags only, no
stdin, no file paths). The contract:

```
crystalium ingest
  --envelope <json-string>              required; inbound ECL envelope (v1.x/v2.x), parsed with json.loads
  --payload <text>                      required; artifact payload string (G7: raw UTF-8 bytes must hash to artifact.sha256 when declared)
  --payload-encoding utf8|base64|json   default utf8 (matches the MCP arg name)
  --format json|text                    default json; text prints just the new crystal id
  --config <path>                       default: Config.from_env() (same idiom as recall/commit/export)
```

Exit 0 = success, stdout exactly one JSON document (`json.dumps(result,
default=str)` of `_handle_ingest`'s dict: status/id/layer/trust_tier/
validation_state/source_eidolon/artifact_kind/envelope_version/commit_status
[+scope_normalized]). Any rejection → `click.ClickException` → exit 1, no stdout
JSON. structlog rebound to `sys.__stderr__` (commit's discipline, __main__.py:492-499).

**Nexus verdict: the guessed shape works AS-IS.** `lib_context.sh:context_try_ingest`
(worktree, :161) emits `ingest --envelope <json> --payload <text>
--payload-encoding utf8 --format json` — byte-compatible with this contract.
**No lib_context.sh adjustment. Zero cross-repo churn on the verb call.**
`--envelope-file`/`--payload-file` companions (GAP-003) are REJECTED for 1.8.0 —
see Rejected Alternatives.

### D-2 — Parity source: reuse `_handle_ingest`, light one-shot stack (hyp-A, explore 84.5)

Lazy `from crystalium.server import _handle_ingest` inside the command body and
call it with the 1.6.0+ signature (FINDING-005):
`_handle_ingest({"envelope": env, "payload": payload, "payload_encoding": enc},
episodic, semantic, procedural, execution, config, recall_cache=None)`.
Everything below is **inherited, not re-implemented**:

- **Envelope validation:** 11 required fields + artifact/integrity/from-to
  sub-fields + version tolerance (1.x/2.x) — ecl.py:313-380
  (`validate_envelope`, `validate_inbound_envelope`,
  `_SUPPORTED_INBOUND_MAJORS`). Validation is **required-fields-only: extra
  top-level fields pass** — verified at b6adf99 (`missing = _REQUIRED_FIELDS -
  set(keys)`; no unknown-field rejection). The nexus envelope's extra
  `topic_key` + `contains_tool_origin` fields are therefore accepted (AC-109
  locks this so it stays true).
- **G7 integrity binding:** raw payload bytes must hash to declared
  artifact.sha256 — server.py:1191-1199 (`INGEST_PAYLOAD_HASH_MISMATCH`).
- **Tier derivation:** `resolve_caller_tier(envelope)` — ingest_adapter.py:67-95.
  MIN-trust clamp `max(declared, identity)`; identity from `from.eidolon`
  (`_ROSTER_EIDOLONS`/`_HOST_EIDOLONS`, ingest_adapter.py:46-52); a non-tier
  `trace.tier` token ("standard") falls back to identity. **The CLI ingest verb
  does NOT read `CRYSTALIUM_CALLER_TIER`** — tier is envelope-derived (AC-116).
  This is a deliberate, documented asymmetry vs `commit` (T0 default,
  __main__.py:545-556) and `recall` (T1 default, __main__.py:361): ingest's
  trust anchor is the envelope's source identity, and an env override would be
  a laundering vector.
- **Quarantine on tool-origin:** T3 → episodic lands `validation_state:
  "quarantined"` (only layer accepting T3; ingest_adapter.py:23-28 default
  episodic, `_KIND_TO_LAYER` empty at 1.7.0).
- **Scope canonicalization (v1.6, FINDING-102):** `normalize_write_scope(...,
  canonical_project_key(config.data_dir))` — server.py:1209-1213, scope.py:34-68.
  `thread_id` survives verbatim in `scope.project_raw`; result carries
  `scope_normalized: true`. **FINDING-107 asymmetry, flagged not inherited
  silently:** the CLI `commit` verb does NOT normalize (calls `episodic.commit`
  directly; test-locked); the CLI `ingest` verb WILL (MCP-consistent,
  CLI-commit-inconsistent). The CHANGELOG entry and the `--envelope` help text
  must state this explicitly.

**Construction (one-shot light stack, commit-verb precedent __main__.py:388-571):**
lazy imports in the function body; `Config.from_yaml(config_path) if exists else
Config.from_env()`; `BlobStore + RelationalStore + Enforcement + Redactor +
_select_importance_fn(config)` (__main__.py:35-46);
`EpisodicLayer(vector_store=None, graph_store=None)`;
`gate = PromotionGate(config, relational, enforcement)`;
`SemanticLayer(vector_store=None, graph_store=None, gate=gate, ...)`;
`ProceduralLayer(gate=gate, data_dir=config.data_dir, ...)`;
`ExecutionLayer(aetheryte=None, recall_cache=None, recall_prefetch=False)` —
default-safe: `aetheryte: Any = None` with a None-guard (execution.py:91,119).
Only episodic is reachable at 1.8.0 (empty `_KIND_TO_LAYER`), but real instances
of all four layers preserve exact `_handle_ingest` parity if the kind table ever
gains entries. `import crystalium.server` at invoke time is verified light:
storage/vector.py defers lancedb to instantiation ("LanceDB and numpy are heavy;
only import when the store is instantiated", vector.py:27) and None-stores mean
no instantiation; `ingest --help` never imports server at all (AC-114).

### D-3 — Summary-quality gate posture: NONE (MCP-ingest parity, justified)

The v1.6 gate is a HARD reject on the `commit` CLI verb, soft-advisory on the MCP
commit tool, and **absent from the MCP ingest path** (FINDING-101; the 1.7.0
`_handle_ingest` diff adds only scope normalization). The CLI `ingest` verb takes
the MCP-ingest posture: **no gate, no advisory** (AC-113). Justification:

1. The commit CLI's hard reject defends against a **caller-typed** summary that
   no FTS query could find. Ingest's summary is **server-composed** —
   `f"{kind}: {objective}"` (ingest_adapter.py:164) — mechanical, not caller prose.
2. `_handle_ingest` is reused verbatim; bolting a pre-gate onto the CLI wrapper
   would make the CLI verb REJECT envelopes the MCP tool ACCEPTS — the exact
   parity break this design exists to avoid.
3. Nexus CC2 (fail-open) context: a hard reject at critical-zone emergency
   handoff would discard the brief at the single most valuable moment; the
   recallability contract lives on the envelope `objective` content instead
   (D-4), which the nexus controls.

### D-4 — session_handoff recallability + the acceptance round-trip

**Mechanism is sufficient — with one nexus-side obligation.** The FTS chain at
b6adf99: FTS5 indexes `summary` ONLY (relational.py:75); `_fts5_query` extracts
`\w+` tokens and quotes each as a literal term with **implicit-AND** semantics
(relational.py:186-202). `"session_handoff"` survives as one `\w+` token, is
quoted, and FTS5 query-tokenizes the quoted term into the phrase
`"session handoff"` (unicode61 splits `_` at index time too) — which phrase-matches
summaries shaped `session_handoff: <objective>` AND ALSO the nexus's real
`ecm/handoff-brief@0.1: Session handoff brief …` summary. So
`memory preflight --query "session_handoff <token>"` recall works **iff every
query token hits the summary** — including `<token>`.

**[GAP-NEXUS-OBJECTIVE] — REQUIRED nexus-side companion (NOT in this fence, flag
to the ecm-context-kernel maker):** `context_handoff.sh` composes a **static**
objective ("Session handoff brief for context-lifecycle succession (ECM P1).",
context_handoff.sh:215) while the canary's per-run token lives in `--task-state`
→ brief body → `encoding_context.native_artifact` — **not FTS-indexed**. Under
implicit-AND, `--query "session_handoff ${token}"` (canary.sh:928-930) returns 0
records, and the preflight digest is `[layer/tier] summary` lines only — the
token cannot appear. **The canary will fail at the recall leg even after 1.8.0
ships, unless the nexus folds distinctive task-state content (head of
`--task-state`) into the envelope `objective`.** One-line jq change in
context_handoff.sh; the crystalium-side alternative (folding payload into the
summary) would break the adapter's generic/verbatim mapping and is rejected.
AC-102's fixture defines the working contract: objective carries the token.

**Quarantine leg (AC-9 mirror).** With the nexus's real envelope, BOTH canary
legs land T3-quarantined (from.eidolon `eidolons-context-kernel` ∉
`_ROSTER_EIDOLONS` → identity T3; trace.tier "standard" is a non-tier token →
identity wins). So AC-103/AC-104 are doubly load-bearing: they lock that a
quarantined session_handoff crystal (i) lands quarantined and (ii) **still
surfaces on default one-shot recall** — the FINDING-103 behavior that must STAY
true. If a future crystalium adds a validation_state recall filter, AC-104 is
the tripwire; the pre-registered remedy is a scoped recall flag, never a
commit-based persist switch (D5 reversal-condition).

### D-5 — Version bump 1.8.0 (FINDING-105 mechanism intact)

Single-sourcing stays: `[project].version` in mcp-server/pyproject.toml:8 is the
SSOT (grepped at run time by install.sh:66-75; `importlib.metadata` in
__init__.py:13-19). The bump touches exactly:
1. `mcp-server/pyproject.toml:8` — `version = "1.8.0"` (SSOT)
2. `mcp-server/src/crystalium/__init__.py:8` — `_FALLBACK_VERSION = "1.8.0"` (comment-mandated sync)
3. `install.sh:75` — `[ -z "${CRYSTALIUM_VERSION}" ] && CRYSTALIUM_VERSION="1.8.0"` (fallback only)
4. `CHANGELOG.md` — new `## [1.8.0]` entry under the header (Keep-a-Changelog):
   Added = ingest verb (contract, parity source, no-summary-gate posture, the
   FINDING-107 normalization asymmetry note); Deferred = `consolidate` re-deferred.
No other version literals exist (test_install_manifest.py asserts against
pyproject, not a literal). Plus tag `v1.8.0` + image publish (release mechanics,
not spec'd files).

## Per-file plan (drift fence = exactly these 6 paths)

| # | File | 1.7.0 anchor | Change |
|---|------|--------------|--------|
| 1 | `mcp-server/src/crystalium/__main__.py` | docstring :1-16; commit verb :388-571; export :579 | Add `ingest` line to the docstring subcommand list. Insert `@cli.command() ingest` between `commit` (ends :571) and `export` (:579) per D-1/D-2/D-3. Help text documents: envelope-derived tier (no CRYSTALIUM_CALLER_TIER), scope canonicalization (vs commit's verbatim scope — FINDING-107), no summary gate (MCP parity). |
| 2 | `mcp-server/tests/test_ingest_cli.py` | NEW — model: test_commit_cli.py (325 lines, real tmp-dir stores, no mocks; `_invoke`/`_find_json_line` helpers) | Implements AC-101…AC-116 (see criteria file). Fixture builder mirrors test_ingest_handler.py's `_envelope()` (:30-44) plus a nexus-exact fixture (kind `ecm/handoff-brief@0.1`, `topic_key`, `contains_tool_origin`, from.eidolon `eidolons-context-kernel`, trace.tier `standard`). Round-trips use the one-shot `recall` verb (BM25 fast path) with the canonical project key per test_roundtrip_handoff.py's 1.6 update. |
| 3 | `mcp-server/pyproject.toml` | :8 | `version = "1.8.0"` |
| 4 | `mcp-server/src/crystalium/__init__.py` | :8 | `_FALLBACK_VERSION = "1.8.0"` |
| 5 | `install.sh` | :75 | fallback literal → `"1.8.0"` |
| 6 | `CHANGELOG.md` | :7 (`## [Unreleased]`) | Insert `## [1.8.0] — <date>` entry per D-5 |

Any diff outside these six paths is DRIFT (ramza-drift check against the
crystalium repo with `--repo /home/rynaro/workspace/oss/agents/crystalium`).

## Stories

**S-1 — `ingest` verb (maker: vivi, timebox 1d).** Implement per D-1/D-2/D-3.
Executor hints: copy the `commit` verb block as scaffold; keep every import
inside the function body; do NOT touch server.py/ingest_adapter.py — if
`_handle_ingest` seems to need a change, STOP and escalate (fence violation).
Output contract: `git diff` confined to file 1; `ingest --help` clean under
`python -m crystalium`.

**S-2 — test file (maker: vivi, timebox 1d).** Implements the 16 test-backed ACs
(AC-101…AC-116). Container-first: `make test` / `make test-fast`
(`CRYSTALIUM_SKIP_SLOW=1`); host-side pytest is banned (MISSION.md:113-117).
While writing AC-102: empirically record the underscore-tokenization result
(GAP-002 probe) in the test's docstring — expected: quoted `"session_handoff"`
phrase-matches `Session handoff …` summaries.

**S-3 — version bump + CHANGELOG (maker: vivi, timebox 0.5d).** Files 3-6 per
D-5; AC-117…AC-119.

**S-4 — verification (checker: kupo — maker≠checker enforced).** Run the frozen
criteria set (SHA below) mechanically; then the cross-repo canary:
`eidolons canary --context-handoff` against the 1.8.0 image. Expected: ingest
legs now succeed; the recall leg PASSES only once [GAP-NEXUS-OBJECTIVE] is fixed
nexus-side — a recall-leg failure with `ingest_ok=true` attributes there, wire
`recall --explain` (FINDING-104c) into the diagnosis before blaming crystalium.

## Acceptance Criteria

Frozen at `spec-crystalium-1.8.criteria.md` — 19 EARS-linted criteria
(AC-101…AC-119: 16 pytest-backed, 3 grep/command-backed).
**criteria_sha256 = `62ce0fd819eb4bb1b42dc13aaa9508ff24374365a26cd181593790813cfcbd8c`**
(recorded in `spec-crystalium-1.8.state.json`; rides the envelope as
`x_ramza_acceptance_criteria`). Edits after freeze without `ramza-freeze --amend`
are tamper evidence.

## Test plan

1. `docker compose run --rm crystalium pytest mcp-server/tests/test_ingest_cli.py -v` — AC-101…AC-116.
2. `make test` (full container suite) — existing suites must stay green; notably
   test_commit_cli.py (verbatim-scope lock, FINDING-107), test_ingest_handler.py,
   test_roundtrip_handoff.py (canonical-key recall), test_install_manifest.py
   (version single-sourcing).
3. Grep gates AC-117…AC-119 (mechanical, CI-friendly).
4. Cross-repo (post-release, kupo): pin 1.8.0 digest in nexus `roster/mcps.yaml`,
   run `eidolons canary --memory` (1.7.0 behavior intact) and
   `eidolons canary --context-handoff` (ingest legs green; recall leg per
   [GAP-NEXUS-OBJECTIVE]).

## Rejected Alternatives

- **hyp-B (explore 72.5): reuse `_build_components(config)` wholesale**
  (test_ingest_handler.py's fixture, server.py:438). Full-parity and test-proven,
  but constructs VectorStore/GraphStore/Aetheryte/DreamScheduler in a one-shot —
  the cold-start weight recall's `--full` flag exists to opt INTO, against a
  nexus-side 1.5s timeout (`ECM_MEMORY_TIMEOUT_S`, lib_context.sh:34). Kept as
  the documented fallback if the light stack hits a constructor incompatibility.
- **hyp-C (explore 59.5, weak): standalone inline ingest logic** (commit-verb
  style, no `_handle_ingest` import). Duplicates envelope validation, G7 binding,
  MIN-trust and normalization — parity by copy, drifts by default. Rejected.
- **`--envelope-file` / `--payload-file` companions (GAP-003).** Deferred, not
  shipped: the nexus's proven `%q`-quoted inline path handles the brief's
  advisory ~1.5k-token size with orders of magnitude of ARG_MAX headroom, and the
  nexus caller (the only known consumer) already emits inline flags.
  Reversal condition: canary evidence of quoting/size failure on real briefs.
- **Hard/soft summary gate on ingest** — rejected per D-3.
- **Adding `eidolons-context-kernel` to `_ROSTER_EIDOLONS`** (would lift briefs
  to T1, un-quarantined) — rejected: trust elevation of a mechanical composer,
  out of scope, and D5's design leans on quarantine-surviving recall instead.

## Risks

- **[RISK-1] Canary recall leg fails post-1.8.0 for a nexus-side reason**
  ([GAP-NEXUS-OBJECTIVE], D-4). Mitigation: AC-102 proves the crystalium half
  end-to-end; the verify-fail attribution playbook in S-4 separates the halves.
- **[RISK-2] Light-stack constructor drift** (SemanticLayer/ProceduralLayer
  kwargs differ from assumed). Mitigation: constructors read at b6adf99
  (_build_components server.py:456-560); fallback = hyp-B, in-fence (file 1 only).
- **[RISK-3] One-shot latency vs the nexus 1.5s `with_timeout`.** The proven
  recall one-shot (same interpreter startup + lighter stack) passes today;
  ingest adds SQLite writes only. If it times out, the nexus tunes
  `ECM_MEMORY_TIMEOUT_S` (env-overridable constant) — no crystalium change.
- **[RISK-4] FTS phrase-match assumption** (quoted `session_handoff` →
  adjacent-phrase semantics). Checked from tokenizer rules, not yet executed.
  AC-102 falsifies it in CI before release if wrong; remedy stays in-fence
  (adjust the test's query contract, document in help text).

## Rollback

Additive CLI verb, zero schema/data migration: rollback = repin the nexus
`roster/mcps.yaml` to the 1.7.0 digest
(`sha256:b6978817f06706c23a7b9134bb235a57ccc2f5c0bdafd318b2a6b41fc6719b07`).
Crystals written by 1.8.0's ingest are ordinary episodic crystals fully readable
by 1.7.0 (bi-temporal store, P0-5 no-hard-delete unaffected). The nexus's
`context_try_ingest` fails open to the file floor against a 1.7.0 image — the
exact pre-1.8.0 behavior.

## Confidence

`ramza-score --rubric confidence` (computed, recorded in state):
pattern_match 92 (commit verb + `_handle_ingest` + test_commit_cli are ≥85%
templates), requirement_clarity 90 (REV-2 rescout, 1.7.0-verified findings),
decomposition_stability 85, constraint_compliance 88 (fence, P0s re-checked) —
see state file for the tool verdict. Escalation path: RISK-2/RISK-4 falsify
in-fence; only [GAP-NEXUS-OBJECTIVE] needs a cross-repo decision, and it is
flagged, not assumed away.

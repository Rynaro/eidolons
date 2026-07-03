# v2.0 Audit — Spec Repos, Junction, tonberry, CRYSTALIUM (2026-07-02)

> Fan-out audit agent report, persisted near-verbatim. Cross-cutting headline:
> **all three specs and both MCPs are opt-in; nothing in this layer hard-refuses work
> today.** Conformance is advisory-by-default with dated promotion windows. That is both
> the campaign's biggest lever and biggest risk.

## 1. ECL v2.0.2 (wire format)

- MUSTs are genuinely mechanical in `conformance/check.sh` + libs: 11 required envelope
  fields; closed 10-performative set; hand-off contract match (performative ∈ allowed,
  artifact.kind, token budget, **undeclared edge = MUST-fail**); SHA-256 recompute.
- v2.0 added the **ISE block**: S-1 `assertion_grade ∈ unverified|self-attested|
  validated|human-reviewed` (MUST when present), S-2 `receiver_authorization` boolean
  shape (MUST), S-3 ise-required-at-high (SHOULD/warn). I-5 hmac-at-high SHOULD.
  S-3 and I-5 are `[PROMOTION-CANDIDATE]` → MUST at v2.1 contingent ≥3/6 Eidolons adopting.
- 45 directed-edge contracts; JSON schemas v1+v2; bash/TS/Python SDKs; exit 0/2/3/4.
- Adoption: nexus vendors + runs checker in sync; Junction vendors contracts; crystalium
  emits ECL v2.0 sidecars on every tool result (G7).
- **Spec bug:** §6.5.3 references performatives `COMMIT`/`REJECT` that are not in the
  closed set (spec/ecl-2.0.md:616-618 vs 215-231).
- v2.0 opportunities: promote S-3/I-5 to MUST; verifier attestation via `assertion_grade`
  so a downstream weaker model can mechanically refuse un-validated inputs.

## 2. ESL v1.0 (lifecycle grammar)

- Six MUST checks C1–C6 + advisory C7, all deterministic bash 3.2: C4 = **maker≠checker**
  identity-inequality on the verify envelope; C5 drift-before-archive; C6 sidecar
  performative in closed set. Right-sizing gate §4 is mechanical by construction.
- Spec already embeds v1.1-additive content (EARS acceptance form §2.5, C7 EARS lint)
  while stamped 1.0 — stamp lags content.
- §6 maps lifecycle → CRYSTALIUM: in-flight spec ⇒ Execution plan_checkpoint/replan;
  spec-of-record ⇒ Semantic promotion; revision ⇒ bi-temporal update; drift_check
  re-derives acceptance vs promoted Semantic spec.
- Escalation warn→block recorded nexus-side in eidolons.mcp.lock, not in spec.
- v2.0 opportunities: memory-preflight gate at proposed-entry; bump stamp to 1.1;
  require checker run in fresh context, attested via ECL ise.

## 3. EIIS v1.4 (install contract)

- v1.4 gates I1–I5 (inventory whitelist, agent.md+SPEC.md canonical pair, ECL_VERSION
  copy, host-vendor body contract, manifest cleanup sweep) — MUST when self-declared
  ≥1.4, warn-only ≤1.3 until 2027-04-24.
- **Gap:** EIIS governs installed files but has NO hook/preflight role — SessionStart
  memory-preflight wiring has no install-contract home. Nexus writes it out-of-contract.
- v2.0 opportunities: add hooks/preflight manifest role; flip external conformance CI
  jobs from continue-on-error to blocking.

## 4. Junction v0.3.0 (bus MCP, Go)

- `harness.run` IMPLEMENTED (plan.json → schema-validated chain dispatch, container or
  shell executors). `harness.verify` IMPLEMENTED (L1 schema, L2 sha256, L3 edge, L4
  performative; exit 65-68). `plan_from_prompt` STUB by design (host LLM is planner).
  **`harness.inject` STUB** — the unbuilt human-in-the-loop typed-envelope injection and
  §5.7/§6.5 enforcement seam.
- Trace journal: append-only fsync JSONL at `.junction/threads/<thread_id>/trace.jsonl`.
  **Divergence: ECL §5 mandates `.eidolons/.trace/<thread_id>.jsonl`** — two trace
  conventions don't coincide.
- v0.2 reasoning seam: host-LLM step between assemble and package via MCP
  `sampling/createMessage` (providers: mcp-sampling, canned, shellout, none).
- Tool descriptions still say "v0.1" (stale copy).
- v2.0 opportunities: build inject with ISE/receiver_authorization enforcement;
  memory-preflight dispatch step; reconcile trace root.

## 5. tonberry v0.4.0 (ESL MCP, Go)

- 11 tools (8 lifecycle + list/status/assess). Byte-parity-locked to the vendored bash
  checker (parity CI; "bash checker is authoritative").
- References CRYSTALIUM Semantic at archive (promotion-intent envelope) but **never
  calls crystalium** — loop open by design.
- v2.0 opportunities: close archive→CRYSTALIUM loop; use `assess` escalation to force
  block-mode on weaker-model projects.

## 6. CRYSTALIUM (deep)

- **Version muddle:** SPEC says v0.1.0, pyproject 1.5.1, `__init__.__version__` 1.0.0
  (what serverInfo reports). Fix.
- Storage: BlobStore (content-addressed) + SQLite FTS5/BM25 + LanceDB (bge-m3) +
  KuzuDB graph; heavy stores degrade to **Null stubs when deps absent** (explains
  embedding_ref=null in live stores).
- Four layers with tier ceilings: episodic (T3, quarantine), semantic (T1, k=3
  corroboration + human window), procedural (T2→candidate; verifier-gated to shared),
  execution (T1, TTL 24h default — plan checkpoints). No separate plan type.
- Trust: T0 human > T1 verified agent > T2 unverified (default) > T3 environment.
  Final tier = max(declared, identity); MIN-trust on consolidation; frozen D1
  tier×layer×operation matrix (MappingProxyType).
- **Nine MCP tools** (docs say 7 — drift): recall, commit, ingest, update, skill_invoke,
  plan_checkpoint, plan_replan, session_end, graph_export. Every result emits ECL v2.0
  sidecar (G7).
- **GAP-2 recall CLI EXISTS**: `python -m crystalium recall --query … --scope-project …`
  (__main__.py:200-363) — read-only, BM25 fast path, lazy heavy imports, built exactly
  for bash SessionStart hooks. CHANGELOG confirms. Missing piece is contract-tracked
  wiring, not the tool.
- **skill system is real**: procedural crystals with language, inputs, verifier script;
  sandboxed invoke (30s timeout, 8KB caps, path-escape guard); T2 lands candidate,
  T0/T1 + passing verifier → shared. Strongest existing weak-model lever.
- Graph export: KuzuDB LINKS_TO/CITES + derived SUPERSEDES/MERGED_FROM/CONFLICTS_WITH;
  json/graphml/cytoscape; ≤10000 nodes.
- Recall pipeline: BM25+dense+graph, RRF k=60, optional decaying-walk completion (ON);
  **`recall_active_only` default ON drops status≠active or superseded** (explains the
  deprecated-checkpoint invisibility in the live-store audit); Composer hard cap 3500
  tokens with slot budgets; EVB ranking default ON; FSRS decay default OFF; redaction
  at output. Discipline: faculties ship OFF unless confound-free A/B earns ON.
- Housekeeping: version strings, "7 tools" docs, FTS5 raw-query injection (G1.2),
  unpopulated tool_calls audit (G1.3).

## Cross-repo summary

| Campaign goal | Mechanical hook exists | Missing |
|---|---|---|
| Stronger typed handoffs | ECL ise block, 45 contracts, ESL grammar | ISE gates SHOULD not MUST; no COMMIT/REJECT; Junction inject unbuilt |
| Mechanical memory preflight | crystalium recall CLI (GAP-2 closed); ESL §6 mapping | no EIIS hook role; no ESL preflight gate at proposed-entry |
| Fresh-context verification | ESL C4 maker≠checker; bi-temporal update; Junction reasoning seam | no attestation binding verify result → ECL ise; inject stub |
| Weaker-model support | tier matrix + verifier-gated skills; tonberry assess lever | tiers/skills not surfaced to handoff layer; escalation flip manual |

Highest-leverage v2.0 move: make the already-mechanical pieces (ISE gates, memory
preflight, maker≠checker) **binding** via existing promotion-candidate paths + EIIS.

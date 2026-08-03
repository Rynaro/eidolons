# Scout report — Rynaro/crystalium#36 (recall starvation / importance-dominates ranking)

Repo: `/home/rynaro/workspace/oss/agents/crystalium`, branch `main`, commit `af24493`
(confirmed via `git log -1`). All paths below are absolute under that checkout.
Version at this commit: `crystalium 1.8.1` (see Q8).

---

## SYNTHESIS (load-bearing facts)

1. **`Aetheryte.recall()` never truncates to `k`.** `k` only sizes the per-layer
   candidate fetch (`candidate_k = max(k*3, 10)`, `retrieve.py:258`) and the
   graph-expand seed set (`seed_ids = dense_ranking[:k]`, `retrieve.py:297`).
   Every scope/status-filtered candidate — regardless of how many — is handed
   to `Composer.compose()` (`retrieve.py:488-492,500`), and nothing after that
   slices the result to `k` (`composer.compose()` has no `k` parameter at all,
   `composer.py:179`). "Exactly one record regardless of k=3..15" is explained
   by the composer's slot eviction (fact 2), not by `k`.

2. **The composer discards query relevance entirely and ranks eviction survival
   by `(importance↑, last_access↑, id↑)` only.** `_eviction_key()`
   (`composer.py:122-134`) is the sole ordering key for both per-slot eviction
   (`composer.py:216-245`) and the global cap-reconciliation pass
   (`composer.py:249-263`, triggered whenever slot totals overflow the 3500
   hard cap — the slot caps intentionally sum to 3800). The BM25/dense/graph
   RRF fusion order computed upstream (`retrieve.py:339` `rrf_merge()`) is used
   only to decide which candidates get *fetched* into `all_candidates` /
   `filtered_ids` — it never participates in eviction or the returned order.
   So "importance dominates and query relevance contributes ~nothing" is
   **verified true**: once eviction fires (the common case — a fresh crystal's
   layer is almost never the sole occupant of its slot), a topically-unrelated
   but higher-importance record always outlives a topically-relevant
   importance-0.0 record, exactly matching the issue's symptom.

3. **Importance is hardcoded to `0.0` at commit time and never computed from
   `importance_fn` at write time**, even though every layer receives
   `importance_fn` in its constructor (`episodic.py:65`,
   `procedural.py:64`, `semantic.py:73`). Commit paths write
   `"importance": 0.0` literally (`episodic.py:176,191,262`,
   `procedural.py:149,193`, `semantic.py:233,287,380`). Only `execution.py`
   commits use `0.5` (`execution.py:226,368`).

4. **There is a bootstrap ("rich get richer") trap with no cold-start floor.**
   A crystal's importance only moves off `0.0` via (a) `Aetheryte.recall()`'s
   post-composition access event (`retrieve.py:516-553`), which recomputes
   `memory_dynamics.evb` **only for records already in `composed.records`** —
   i.e. only for records that *already survived* eviction — or (b)
   `DreamWorker`'s periodic consolidation sweep
   (`dream/worker.py:836-843`), which touches every active row but only runs
   when `now - last_activity >= idle_threshold_s` (300s) **and**
   `now - last_dream >= min_dream_gap_s` (1800s)
   (`dream/scheduler.py:9-10,269,278`). A freshly-committed, never-yet-surfaced
   crystal has no path to a nonzero importance until Dream eventually sweeps
   it — and by definition it can never win the eviction race that would let
   path (a) fire, since path (a) requires having already won. This is why
   "freshly committed crystals always have importance 0.0 and are never
   returned."

5. **`CrystalSummary.score` is structurally always `None`.** The field is
   declared `Optional[float] = None` (`schemas.py:222`) and the single
   construction site (`retrieve.py:562-571`) never passes `score=`. There is
   no code path anywhere in the repo that sets it — confirmed by grep (only
   the class definition and the one construction site reference
   `CrystalSummary(`).

Net: the four items above compose into one causal chain — every candidate
(not just top-k) reaches the composer, the composer ranks strictly by
importance/recency/id and ignores BM25+dense+graph relevance, importance is
frozen at 0.0 for anything not already reinforced, so recall degenerates to
"return whichever old, already-popular record has nonzero importance,"
independent of the query.

---

## 1. RECALL PIPELINE (tool entry -> response)

- MCP tool dispatch: `crystalium.recall` tool descriptor —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/server.py:179-223`.
  Routed to handler at `server.py:730-731`
  (`if name == "crystalium.recall": result = _handle_recall(...)`).
- Handler: `_handle_recall()` —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/server.py:947-987`.
  Normalizes scope (canonical project default), clamps `k` to a non-negative
  int (`server.py:970-973`), calls `aetheryte.recall(...)` (`server.py:977-984`),
  returns `result.model_dump(exclude_none=True)`.
- Core pipeline: `Aetheryte.recall()` —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/aetheryte/retrieve.py:173-656`.
  Documented 9-step order in the docstring (`retrieve.py:184-193`):
  rate-limit -> tier check -> hybrid retrieve -> RRF fusion -> (disabled)
  reranker -> scope filter -> `composer.compose()` -> redactor -> return.
  - **Sparse/BM25 arm**: `self.relational.bm25_search(...)` called per layer,
    `retrieve.py:262-264`; implementation
    `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/storage/relational.py:493-541`
    (SQLite FTS5, `ORDER BY bm25(crystals_fts)`).
  - **Dense/embedding arm**: `self.vector_store.embed(query)` then
    `self.vector_store.dense_search(...)`, `retrieve.py:272-294`;
    implementation
    `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/storage/vector.py:103-125` (embed, sentence-transformers, in-process cache)
    and `vector.py:174-206` (dense_search, LanceDB cosine ANN).
  - **Graph arm**: `self.graph_store.neighbor_expand(seed_ids=dense_ranking[:k], depth=1)`,
    `retrieve.py:296-311`.
  - **RRF fusion**: `rrf_merge()`, pure function,
    `retrieve.py:53-80` (sum of `1/(k_rrf+rank)` across the ranked lists,
    `k_rrf=60`); called at `retrieve.py:339`.
  - **Optional W5 pattern completion** (decaying multi-hop graph walk,
    `Config.recall_completion`, default **True**, `config.py:199`):
    `retrieve.py:313-333`, becomes a 4th ranked list fused in via the same
    `rrf_merge` call.
  - **Optional W5 context-match re-rank** (`Config.recall_context_match`,
    default False, `config.py:202`): `retrieve.py:341-360`, a stable
    post-RRF sort by encoding-context overlap — off by default, so it is not
    implicated in this issue by default config.
  - **Reranker**: stubbed/commented out, never executes
    (`retrieve.py:362-367`).
  - **Scope filter**: `_scope_matches()` closure, `retrieve.py:370-389`.
  - **Active-only filter** (`Config.recall_active_only`, default **True**,
    `config.py:215`): `_is_active()` closure, `retrieve.py:395-407`.
  - **Composer**: `Composer.compose()`,
    `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/composer.py:179-279`
    (see §2/§4 below).
  - **Redactor**: `self.redactor.redact(rec.summary, rec.scope_sensitivity_tag)`
    per surviving record, `retrieve.py:557-560`; implementation
    `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/aetheryte/redact.py`.
  - **Response assembly**: `RecallResult(...)`, `retrieve.py:605-618`.

## 2. RANKING FORMULA

There is **no single weighted-sum ranking formula** combining relevance +
importance + recency + layer. Instead there are two disjoint mechanisms:

- **Candidate selection/order** (relevance-driven): `rrf_merge()`,
  `retrieve.py:53-80`:
  ```python
  score(id) = sum( 1 / (k_rrf + rank_i(id)) )   for each list i where id appears
  ```
  This determines `fused_ids` order, i.e. which records are fetched and in
  what relevance order they enter `all_candidates`/`filtered_ids`.

- **Slot survival/eviction order** (importance-driven, and the one that
  actually determines the returned set + its order): `_eviction_key()`,
  `composer.py:122-134`:
  ```python
  def _eviction_key(rec):
      return (rec.importance, last_access, rec.id)   # ascending; lowest = evicted first
  ```
  Used at `composer.py:234` (per-slot eviction) and `composer.py:256`
  (global cap reconciliation, sorts the ENTIRE surviving set by this key and
  pops the lowest off the front until `total_tokens <= total_cap`). Neither
  step consults BM25/dense/RRF rank or query relevance in any form — `rec`
  (`_ComposerRecord`) doesn't even carry a relevance/rank field. **Confirmed
  plausible and verified against the issue's symptom**: importance
  dominates and query relevance contributes literally nothing to which
  records survive or their final order, because relevance information is
  structurally absent from `_eviction_key` and from `_ComposerRecord`
  entirely.

- `importance` itself, when computed (see §3), is `evb = gain(record) * need(record)`
  (`/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/evb.py:140-151`)
  or the legacy `importance_score()` D6 formula
  (`/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/importance.py:65-109`,
  `raw = 0.25*af + 0.30*recency + 0.25*outcome_success + 0.20*novelty`).
  Both are pure functions of the record's own history — neither takes the
  query as an argument in the eviction/Dream call sites (`query_ctx` in
  `evb.need()` defaults to a neutral 0.5 prior when absent,
  `evb.py:105-123,126-137`, and neither `retrieve.py:550` nor
  `dream/worker.py:837` passes `query_ctx`).

## 3. IMPORTANCE LIFECYCLE

- **Init at commit — hardcoded 0.0**, never computed via `importance_fn`
  despite it being injected as a constructor param:
  - `episodic.py:176,191,262` (`"importance": 0.0` — dedup-merge return, main
    utility stub, and one more path)
  - `procedural.py:149,193`
  - `semantic.py:233,287,380` (line `527` is a read-path fallback:
    `crystal.get("utility", {}).get("importance") or 0.0`)
  - `execution.py:226,368` uses `0.5` instead (execution entries are "currently
    active work" per the inline comment).
- **`importance_fn` is stored but dead at commit time** — `self.importance_fn`
  is set in every layer's `__init__` (`episodic.py:65`, `procedural.py:64`,
  `semantic.py:73`) but grepping `importance_fn(` across `layers/*.py` finds
  **zero call sites**; it is only ever invoked from:
  - `dream/worker.py:837` — `score = self.importance_fn(rec_stub, now=now)`,
    inside the periodic consolidation/prune sweep, for every active row of a
    layer (`dream/worker.py:814-819`), persisted to `memory_dynamics.evb` at
    `dream/worker.py:842-843` when `persist_dynamics` is True.
  - `retrieve.py:550` — inside `Aetheryte.recall()`'s post-composition access
    loop, **only for records already in `composed.records`**
    (`retrieve.py:520`), i.e. only for records that already survived
    eviction.
- **Recompute/reinforcement triggers**:
  - Recall-time: `self.relational.record_access(rec.id, now=now)`
    (`retrieve.py:544`; impl `storage/relational.py:402-422`, bumps
    `utility.access_count` and `utility.last_access`) runs unconditionally for
    every surfaced record; the EVB recompute+persist at `retrieve.py:545-551`
    is gated by `self.persist_dynamics` which is wired from
    `config.evb_enabled` (`server.py:536,568`), and `evb_enabled` defaults to
    **True** (`config.py:160`) — so in the default config this fires whenever
    a record makes it through composition.
  - Dream-time: `dream/worker.py:800-843`, gated by the scheduler's idle/gap
    predicate — `idle_threshold_s=300` and `min_dream_gap_s=1800`
    (`config.py:110-111`; predicate at `dream/scheduler.py:9-10,173,269,278`).
  - `evaluate importance value` reads (used for the composer's eviction key,
    `retrieve.py:461-473`): prefers `memory_dynamics.evb` if present, else
    falls back to `utility.importance` (0.0 at commit). So a crystal's
    effective importance is 0.0 until *either* Dream sweeps it or it wins a
    composer round on its own (impossible from 0.0 against any nonzero rival)
    — a closed loop with no external forcing function for records that never
    get initially surfaced.
- **Recency boost / cold-start floor**: none found. Recency (`0.5 **
  (days_elapsed/14.0)`, `importance.py:98`, mirrored in `evb.py:73-81`) is
  only ever one *weighted component inside* the importance/EVB formula, not
  an independent boost applied at recall time, and it only matters once the
  formula is actually evaluated for that record (see above — it isn't, for a
  never-surfaced fresh crystal). There is no separate "new crystal" floor or
  grace-period logic anywhere in `composer.py`, `retrieve.py`, or
  `importance.py`/`evb.py`.

## 4. TOKEN BUDGET / SLOTS

- **Budget is fixed, not derived from `k`.** `Config.total_cap = 3500`
  (`config.py:141`) and `Config.slots` (`config.py:131-140`):
  `executive=300, procedural=600, semantic=800, episodic=800, execution=1000,
  buffer=300` (sum = 3800, intentionally over-subscribed per the comment at
  `composer.py:249-253`). Neither `total_cap` nor `slots` reference `k`
  anywhere; `Composer.compose(records)` takes no `k` argument
  (`composer.py:179`).
- **Why ~500-720 tokens / one record fits**: because nothing limits candidate
  count to `k` before the composer (fact 1 above), and because eviction is
  importance-driven not relevance-driven (fact 2), the observed behavior
  (one record, ~500-720 tokens) is consistent with: many candidates flood the
  `episodic` slot (default layer for most commits — see `_LAYER_SLOT`,
  `composer.py:152-157`), the vast majority carry `importance=0.0` (fact 3/4),
  so Pass-1 per-slot eviction (`composer.py:223-245`) evicts everything
  ascending by `(importance, last_access, id)` until only the one (or few)
  nonzero-importance record(s) remain under the 800-token episodic cap. A
  procedural crystal that "closely matches" but has `importance=0.0` and
  shares the episodic-vs-procedural slot boundary would be evicted the same
  way if it lands in a slot with other, more-"important" competitors, or
  never survives the earlier scope/status/candidate-fetch stages at all
  (this repo does not show conclusive evidence either way for the specific
  procedural-crystal claim — flagged as an open question below).
- **`slot_breakdown` allocation**: `SlotBreakdown(...)` built directly from
  `composed.slot_tokens` per named slot, `retrieve.py:607-614`; the dict is
  populated in `Composer.compose()` as `slot_token_totals`
  (`composer.py:221,230,245,260`) — one entry per slot in `Config.slots`,
  decremented on both per-slot (Pass 1) and global (Pass 2) eviction. If a
  slot never receives a record with that `layer` (routing: `_route()`,
  `composer.py:285-296`, mapping `_LAYER_SLOT` at `composer.py:152-157` plus
  the `slot_override=="executive"` special case), or if every candidate
  routed to it gets evicted, its total is 0 — this is how `procedural` can
  show 0 even when a matching procedural crystal exists in the store, if
  that crystal either never reached the composer or lost the eviction race
  entirely (evicted to 0 tokens remaining, `composer.py:236-239`, which is
  possible even as the sole occupant of its slot if its own token count alone
  exceeds the slot cap, or if further candidates in that slot outrank it).
- **`evicted_count`**: accumulated in `Composer.compose()` at
  `composer.py:239` (per-slot Pass 1) and `composer.py:261` (global Pass 2
  reconciliation), summed into `ComposedSet.evicted_count`
  (`composer.py:274-279`), surfaced verbatim as `RecallResult.evicted_count`
  (`retrieve.py:616`, schema field `schemas.py:246`).

## 5. SCORE FIELD

- Declared: `score: Optional[float] = None` —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/schemas.py:222`
  (on `CrystalSummary`, `schemas.py:209-222`).
- Left null: the only construction site,
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/aetheryte/retrieve.py:561-572`,
  builds `CrystalSummary(id=..., layer=..., summary=redacted_summary,
  trust_tier=..., validation_state=..., importance=rec.importance,
  last_access=..., content_ref=...)` — **no `score=` kwarg anywhere**. Grep
  across the whole `mcp-server/src/crystalium` tree for `CrystalSummary(`
  returns exactly this one call site plus the class definition, confirming
  `score` is null on every recall response, unconditionally, by construction
  (not a bug in one code path — the field is simply never wired to anything,
  e.g. the RRF score or the eviction-key importance value).

## 6. SMALLER ITEMS

**(a) `provenance.source` enum + commit-side coercion (commit `92fb32a`)**

- Enum literal (schema of record): `Literal["human", "verified_agent",
  "unverified_agent", "environment"]` —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/schemas.py:28`
  (`Provenance.source`).
- Runtime valid-set + coercion helper (added by `92fb32a`, "fix(commit):
  coerce non-enum provenance.source instead of hard-failing", 2026-06-29):
  `_VALID_PROVENANCE_SOURCES = frozenset({"human", "verified_agent",
  "unverified_agent", "environment"})` —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/server.py:994-996`;
  `_coerce_provenance_source()` — `server.py:999-1014`; invoked from
  `_handle_commit` at `server.py:1077` (`final_source, source_coerced =
  _coerce_provenance_source(raw_source, caller_tier)`), with a
  `provenance_coercion` advisory attached to the result when a coercion fires
  (`server.py:1117-1127`).
- **Does the MCP tool description list the enum values?** **No.** The
  `crystalium.commit` tool manifest's `payload.provenance` description reads
  only `"Provenance dict: {source, author_agent, task_id, created_at}"`
  (`server.py:248-251`) — the four valid `source` literals are not named
  anywhere in the tool-surface description a caller/LLM would see. (This is
  the exact gap `92fb32a`'s fix works around at runtime by coercing instead
  of hard-failing, rather than by documenting the enum.)

**(b) `TIER_VIOLATION` advice string**

- Raised by `TierViolation`,
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/enforcement.py:89-111`.
  For a T2 caller attempting a Semantic commit (T2 is not permitted for
  Semantic — commit tool description: "T1/T0: Semantic, Procedural, Execution
  allowed", `server.py:230`), the exact advice string constructed is:
  ```python
  advice=f"Use a lower-trust layer or escalate caller identity above {tier}."
  ```
  (`enforcement.py:110`) — this is a generic, tier-parameterized string, not
  layer-specific; it doesn't name "Episodic" or "Semantic" explicitly, just
  "a lower-trust layer." `reason_code = "TIER_VIOLATION"` (`enforcement.py:95`),
  also enumerated as a `CommitResultRejected.reason_code` literal at
  `schemas.py:296`.

## 7. TESTS / EVALS

- **Runner**: pytest, run container-first via `docker compose run --rm
  crystalium pytest ...` (see module docstrings, e.g.
  `mcp-server/tests/test_composer.py:1-9`, `test_rrf.py:1-5`). Makefile
  targets (`/home/rynaro/workspace/oss/agents/crystalium/Makefile`):
  `make test` -> `$(RUN) pytest mcp-server/tests/ -v` (`Makefile:27-28`);
  `make test-fast` -> same with `CRYSTALIUM_SKIP_SLOW=1 -m "not slow"`
  (`Makefile:30-31`); no single dedicated `make test-recall` target exists —
  narrowest built-in target is `make test-w1` (schemas/storage/importance
  only, `Makefile:44-52`), which does **not** include `test_aetheryte.py` or
  `test_composer.py`. To run just the recall-relevant files:
  ```
  docker compose run --rm crystalium pytest \
    mcp-server/tests/test_aetheryte.py \
    mcp-server/tests/test_composer.py \
    mcp-server/tests/test_rrf.py \
    mcp-server/tests/test_recall_cli.py \
    mcp-server/tests/test_recall_active_only.py \
    mcp-server/tests/test_importance.py \
    mcp-server/tests/test_evb.py \
    -v
  ```
- **`mcp-server/tests/test_aetheryte.py`** (372 lines) — the only file that
  integration-tests `Aetheryte.recall()` end-to-end. Four test classes only:
  `TestAetheryteBm25Recall` (single-hit relevance + empty store + default
  all-layers), `TestScopeFilter` (cross-project / agent_class_visibility),
  `TestRedactorApplied` (SSN redaction), `TestRateLimit`
  (`test_aetheryte.py:159-372`). **Gap**: no test seeds multiple candidates
  with varying importance to check whether eviction starves relevant, fresh
  (importance-0.0) crystals in favor of irrelevant, high-importance ones, and
  no test asserts `len(records) <= k` or `k` truncation.
- **`mcp-server/tests/test_composer.py`** — unit tests the eviction key and
  slot-cap behavior in isolation (`_eviction_key`, `Composer`) using hand-built
  `_Rec` stubs, not real `Aetheryte.recall()` candidates — so it verifies the
  eviction ORDER is correct by its own (importance-only) spec, but can't catch
  that the spec itself discards relevance.
- **`mcp-server/tests/test_rrf.py`** — pure unit tests of `rrf_merge()` in
  isolation; doesn't touch the composer, so can't catch that RRF's output is
  discarded downstream.
- **`mcp-server/tests/test_importance.py`, `test_evb.py`** — unit-test the two
  scoring formulas in isolation (given `access_count`, `last_access`, etc.).
  Neither tests that a freshly-committed crystal (importance 0.0, never
  recalled) has any path to a non-zero score within a single session.
- **`mcp-server/tests/test_recall_cli.py`**, **`test_recall_active_only.py`**
  — CLI-level recall tests + the W6 active-only filter; not focused on
  ranking/budget.
- **`evals/retrieval_gate.py`** (+ `mcp-server/tests/test_retrieval_gate.py`,
  invoked via `python -m evals retrieval-gate`,
  `/home/rynaro/workspace/oss/agents/crystalium/evals/__main__.py:88-89,177-178`)
  — measures multi-hop completion / context-match **recall/F1 lift**
  (graph-reachable relevance), a different concern (W5 pattern completion
  ablation) from this issue's importance-vs-relevance starvation; it does not
  exercise the token-budget/eviction path or importance dynamics at all.
- No eval or test in the repo currently exercises: (1) `k` truncation
  behavior, (2) composer eviction discarding RRF order, or (3) the
  cold-start/never-surfaced-crystal importance trap — these are exactly the
  three mechanisms behind #36 and are the gaps a fix's regression test should
  close.

## 8. VERSION / RELEASE SURFACE

- `pyproject.toml` version: `"1.8.1"` —
  `/home/rynaro/workspace/oss/agents/crystalium/mcp-server/pyproject.toml:9`.
- `CHANGELOG.md` top entry: `## [1.8.1] — 2026-07-17` (Unreleased section
  above it is empty) —
  `/home/rynaro/workspace/oss/agents/crystalium/CHANGELOG.md:7-23`. Notably,
  1.8.1's own fix was *also* a recall-crash defense-in-depth fix (tiktoken
  special-token crash) referencing issue `#32` — i.e. the composer/tokenizer
  path has recent prior-art fragility.
- Latest git tag: `v1.8.1` (`git tag --sort=-creatordate` -> `v1.8.1, v1.8.0,
  v1.7.0, v1.6.0, v1.5.1, ...`), matching `af24493`/HEAD.
- Version stamping: `install.sh` single-sources `CRYSTALIUM_VERSION` from
  `mcp-server/pyproject.toml` at
  `/home/rynaro/workspace/oss/agents/crystalium/install.sh:71-75`
  (`grep -m1 '^version' ... | cut -d'"' -f2`, hardcoded fallback `"1.8.0"` if
  the grep fails), printed via `--version`
  (`install.sh:132`) and in the install banner (`install.sh:299`). No
  `crystalium/__init__.py` `__version__` stamp was found to grep-match (a
  comment at `install.sh:54` references "staleness crystalium/__init__.py's
  __version__ fix (v1.6, single-sourced via ...)" implying `__init__.py` used
  to hardcode its own version and was fixed to read from `pyproject.toml`
  instead — did not independently verify `__init__.py`'s current contents,
  see Open Questions).

---

## OPEN QUESTIONS

- **Whether the "procedural gets 0 slots despite a close match" symptom is
  caused by (a) the crystal never reaching `all_candidates`/`filtered_ids` in
  the first place (e.g. BM25/dense simply not surfacing it within
  `candidate_k = max(k*3,10)` per layer), vs (b) it reaching the composer and
  losing the procedural-slot eviction race outright.** Both are structurally
  possible from what's traced above; distinguishing them needs either a
  reproduction with `explain=True` (the `explain` diagnostic object at
  `retrieve.py:576-603` reports `candidates_prefilter`, `filtered_by_status`,
  `filtered_by_scope`, and arm status, which would disambiguate this) or a
  live repro against the reporter's store. I did not have a live repro
  environment as part of this read-only scout.
- **Whether `Config.evb_enabled=True` (default) or a legacy `importance_fn=
  importance_score` (evb disabled) config is in play for the reporting user.**
  The lifecycle differs slightly in numeric detail (EVB's `gain*need` product
  vs the D6 weighted sum) though the structural bug (frozen 0.0 until first
  Dream sweep or first composer win) is identical either way per `server.py:
  477-485` and `481-484`.
- **Whether `Config.recall_prefetch` (the `RecallCache`, default False,
  `config.py:205`) is enabled for the reporter.** If so, a stale cached
  result (keyed by `_cache_ctx`, `retrieve.py:161-171`) could compound the
  "same unrelated record every time" symptom independently of the eviction
  bug; the cache key includes `k`/`layers`/`visibility`/`sensitivity`/`tier`
  but not the query text's semantic content beyond the literal query string
  passed to `RecallCache.get/put` (`retrieve.py:241-245,634-638`) — did not
  read `aetheryte/cache.py`'s key-hashing internals in enough depth to rule
  in/out a query-collision confound. `recall_prefetch` defaults to False, so
  this is unlikely to be in play unless the reporter has non-default config.
- **Did not independently confirm `crystalium/__init__.py`'s current
  `__version__` value** (only inferred its existence/history from an
  `install.sh` comment) — flagged rather than asserted in §8.
- **Whether the harness recall caller sets `explain=True`** and what a real
  `explain` object from a reproduction looks like — would directly confirm
  or refute the `all_candidates` vs `filtered_ids` vs composer-eviction
  attribution above. Recommend the planner request this from the reporter
  or reproduce it.

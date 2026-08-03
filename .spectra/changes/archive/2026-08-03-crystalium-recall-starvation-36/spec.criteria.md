# Acceptance criteria — crystalium-recall-starvation-36 (frozen, amended)

Frozen sibling of `spec.md` revision 2.1.0. Amended once, legally, via
`ramza-freeze --amend --reason` after vigil's VERIFIED-with-notes attestation at
HEAD 323229f, per FORGE rulings DP-R1/DP-R2/DP-R3 and condition C-13.
`spec.md` §Acceptance Criteria is the same 32 blocks verbatim; §Amendment record
lists exactly what changed. A further change requires another
`ramza-freeze --amend --reason "<why>"` — a silent edit is tamper evidence.

change_id:  crystalium-recall-starvation-36
target:     Rynaro/crystalium @ af24493 (v1.8.1) -> 1.9.0
maker:      vivi   checker: vigil
criteria:   32  (rev 2.0.0 had 30; AC-007/016/017 strengthened, AC-031/032 added)
supersedes: sha256 8fd32daf09b7d500913fe9f46c1647b0bc5fd0ee53b3660e6bd36b314279f577

### AC-001 (event-driven)
GIVEN a store holding four high-importance crystals whose summaries do not contain the query tokens, plus one freshly committed crystal whose summary contains three distinctive low-frequency tokens, with `Config.slots["episodic"]` reduced so the candidate set overflows the slot
WHEN  `Aetheryte.recall()` is called with the same scope and a query composed of those three distinctive tokens
THEN  the system shall include the freshly committed crystal's id in `result.records`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestIssue36Regression::test_fresh_distinctive_crystal_is_returned` — C-5 RED-first at `af24493`.

### AC-002 (event-driven)
GIVEN a store holding eight crystals that all match the query, whose summaries fit within the slot budget
WHEN  `Aetheryte.recall()` is called with `k=5`
THEN  the system shall return exactly five records
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestKIsACap::test_k5_returns_five_when_five_fit` — C-5 RED-first at `af24493`.

### AC-003 (state-driven)
WHILE `Config.recall_relevance_primary` is enabled
WHEN  `Aetheryte.recall()` returns for any store or query
THEN  the system shall satisfy `len(result.records) <= k`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestKIsACap::test_never_exceeds_k` parameterised over `k in (1,3,5,10,15)`.

### AC-004 (event-driven)
GIVEN a store holding one irrelevant crystal at `utility.importance = 0.9` plus one query-relevant crystal at `utility.importance = 0.0`, with a slot cap admitting only one of them
WHEN  `Aetheryte.recall()` is called with a query matching only the relevant crystal
THEN  the system shall return the relevant crystal rather than the high-importance one
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestRelevanceBeatsImportance::test_relevant_zero_importance_survives_eviction` — C-5 RED-first; provable only under DP-1 O1.

### AC-005 (ubiquitous)
GIVEN any non-empty recall result in the default configuration
WHEN  the caller inspects any returned `CrystalSummary`
THEN  the system shall expose a non-null `score`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestScorePopulated::test_score_is_not_none` — C-5 RED-first at `af24493`.

### AC-006 (optional-feature)
WHERE `Config.recall_relevance_primary` is set to `False`
WHEN  `Aetheryte.recall()` returns a non-empty result
THEN  the system shall still expose a non-null `score` on every record
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestScorePopulated::test_score_populated_when_flag_off` — DP-5 "both modes".

### AC-007 (event-driven)
GIVEN a default-configuration fixture of four candidate records carrying relevance 0.9, 0.5, 0.1 and 0.05, routed to one slot whose cap is small enough to force at least one eviction
WHEN  `Aetheryte.recall()` returns the surviving records
THEN  the system shall emit them in non-increasing `score` order
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestOrdering::test_evicting_slot_emits_descending_score` — DP-6; **strengthened per DP-R2/C-13**. The fixture MUST evict: Pass 1 reassembles an evicting slot from `remaining`, which is sorted *ascending* by eviction key, so without seam 5 an evicting slot emits worst-relevance-first. Gate proof: attack E (delete the seam-5 output sort) must turn this node **RED** — it stayed green against the previous non-evicting fixture (`verification.md` F-V2).

### AC-008 (optional-feature)
WHERE `Config.recall_relevance_primary` is set to `False`
WHEN  `Aetheryte.recall()` runs against a fixture that overflows a slot
THEN  the system shall reproduce the pre-fix composition result set
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestLegacyPath::test_flag_off_restores_prefix_behaviour` — C-1; load-bearing because DP-2 landed B.

### AC-009 (optional-feature)
WHERE `Config.recall_relevance_primary` is set to `False`
WHEN  `Aetheryte.recall()` is called with a `k` smaller than the candidate count
THEN  the system shall return more than `k` records
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestLegacyPath::test_flag_off_does_not_cap_at_k` — pins C-1's "seam 3 is inside the flag" boundary.

### AC-010 (event-driven)
GIVEN a caller committing a well-formed crystal under the default `evb_enabled=True` configuration
WHEN  `crystalium.commit` returns successfully
THEN  the system shall report an `importance` strictly greater than 0.0
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestColdStartImportance::test_commit_importance_nonzero` parameterised over `episodic`, `procedural`, `semantic` — C-5 RED-first; DP-4c.

### AC-011 (state-driven)
WHILE `evb_enabled` is set to `False` so the legacy scorer is active
WHEN  a caller commits a well-formed crystal
THEN  the system shall report an `importance` no greater than 0.30
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestColdStartImportance::test_legacy_scorer_clamped_to_ceiling` — C-3; the clamp that makes DP-4=C differ from bare A.

### AC-012 (state-driven)
WHILE `evb_enabled` is set to `True` so the EVB scorer is active
WHEN  a caller commits a crystal with `novelty_at_write = 0.5`
THEN  the system shall report an `importance` equal to the unclamped `importance_fn` value
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestColdStartImportance::test_evb_path_unclamped` — C-3; proves the ceiling never binds on the default path.

### AC-013 (unwanted-behavior)
GIVEN a caller writing an execution-layer checkpoint
WHEN  the checkpoint is persisted
THEN  the system shall leave its `importance` at 0.5
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestColdStartImportance::test_execution_layer_importance_unchanged` — DP-4d.

### AC-014 (event-driven)
GIVEN a crystal committed in-session that has been surfaced by one recall
WHEN  a second recall for the same query runs
THEN  the system shall report a `utility.access_count` of at least 1 for that crystal
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestColdStartImportance::test_in_session_reinforcement_closes_the_loop` — asserts the existing loop at `retrieve.py:544-551` now fires for a fresh crystal.

### AC-015 (ubiquitous)
GIVEN any recall result in any configuration
WHEN  the caller reads the response
THEN  the system shall expose `result.budget` carrying `total_cap`, `slots`, `k_requested`, `k_applied`, `truncated_count`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestBudgetSurfaced::test_budget_object_present_with_five_fields` — DP-3c; always-on, both modes.

### AC-016 (event-driven)
GIVEN a store whose filtered candidate count exceeds `k` in the default configuration
WHEN  `Aetheryte.recall()` returns
THEN  the system shall report `budget.truncated_count` equal to the count of candidates actually removed by the `k` slice
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestBudgetSurfaced::test_truncated_count_derived_from_real_slice` — DP-7; **strengthened per DP-R3/C-14**. The oracle asserts the identity `len(result.records) + budget.truncated_count == <filtered candidate count before the slice>`, so a counter derived from pre-slice intent cannot pass: under attack D (delete `filtered_ids = filtered_ids[:k]`, keep the counter) the shipped object reported five drops that never happened while the old arithmetic oracle stayed green (`verification.md` F-V3). Attack D must turn this node **RED**.

### AC-017 (unwanted-behavior)
GIVEN any recall in any configuration
WHEN  the `budget` object is assembled
THEN  the system shall report a `budget.k_applied` no greater than `budget.k_requested`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestBudgetSurfaced::test_k_applied_never_exceeds_k_requested` — **strengthened per DP-R3/C-14**; `k_applied = min(k_requested, len(before))` makes this true by construction. Under attack D the shipped object reported `k_requested=15, k_applied=20` while every oracle stayed green (`verification.md` F-V3). Attack D must turn this node **RED**. The `evicted_count` field-meaning pin previously carried by this ID is preserved verbatim as **AC-032**.

### AC-018 (event-driven)
GIVEN a caller passing `explain=true`
WHEN  `Aetheryte.recall()` returns
THEN  the system shall include `k_applied` together with `truncated_by_k` in `result.explain`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestBudgetSurfaced::test_explain_carries_k_keys` — DP-3c.

### AC-019 (ubiquitous)
GIVEN any recall result
WHEN  the composer has assembled the working set
THEN  the system shall satisfy `result.total_tokens <= 3500`
VERIFY: `pytest mcp-server/tests/test_composer.py::TestTotalCap` (existing, unmodified) plus `pytest mcp-server/tests/test_recall_starvation.py::TestBudgetSurfaced::test_total_cap_invariant_holds` — DP-3b, P0-9.

### AC-020 (unwanted-behavior)
GIVEN a caller passing a numeric `k` outside the range 1 to 100
WHEN  the recall request is normalised
THEN  the system shall clamp `k` into the range 1 to 100
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestKClamp::test_numeric_k_clamped` parameterised over `0`, `-3`, `500` at both `server._handle_recall` and the CLI verb — DP-3d.

### AC-021 (unwanted-behavior)
GIVEN a caller passing a non-coercible `k` such as the string `"garbage"`
WHEN  the recall request is normalised
THEN  the system shall fall back to the default `k` of 10 without raising
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestKClamp::test_non_coercible_k_falls_back_to_default` — C-11.

### AC-022 (event-driven)
GIVEN a caller committing a crystal whose summary tokenises above the destination layer's slot cap
WHEN  `crystalium.commit` returns successfully
THEN  the system shall attach a `summary_size` advisory naming the token count together with the slot cap
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestOversizedSummary::test_oversized_summary_advisory` — DP-8.

### AC-023 (unwanted-behavior)
GIVEN a caller committing a crystal whose summary fits its destination slot
WHEN  `crystalium.commit` returns successfully
THEN  the system shall omit the `summary_size` advisory from the result dict
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestOversizedSummary::test_fitting_summary_has_no_advisory` plus the existing `test_diagnosability.py::TestSummaryQualityGate::test_commit_good_summary_no_advisory` — DP-8 clean-path byte-identity.

### AC-024 (unwanted-behavior)
GIVEN a tokenizer that raises on the supplied summary
WHEN  `crystalium.commit` processes that summary
THEN  the system shall complete the commit without an error
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestOversizedSummary::test_tokenizer_exception_skips_advisory` with a monkeypatched raising tokenizer — C-4.

### AC-025 (ubiquitous)
GIVEN the `crystalium.commit` tool manifest
WHEN  a client reads the `provenance` property description
THEN  the system shall name every member of `server._VALID_PROVENANCE_SOURCES`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestDX::test_commit_description_lists_provenance_sources` — asserts against the runtime frozenset, so the test cannot pass by matching a list the implementation also hardcodes.

### AC-026 (event-driven)
GIVEN a T2 caller attempting a semantic commit
WHEN  `TierViolation` is raised
THEN  the system shall include the string `procedural` in the advice
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestDX::test_tier_violation_advice_names_procedural_fallback` — DX-2.

### AC-027 (unwanted-behavior)
GIVEN a T2 caller attempting a semantic commit
WHEN  `TierViolation` is raised
THEN  the system shall omit any claim that a procedural candidate is promoted to semantic
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestDX::test_advice_makes_no_promotion_promise` asserting the advice contains neither `promoted to semantic` nor `auto-promot` — C-9, mission P0-4.

### AC-028 (ubiquitous)
GIVEN a live `RecallResult` produced by `Aetheryte.recall()`
WHEN  its `model_dump` is validated against `schemas/recall-result.v1.json`
THEN  the system shall produce a document that satisfies the published schema
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestSchemaRoundTrip::test_plain_result_validates` — DP-X, C-7; imports `jsonschema` unconditionally, never `pytest.skip`.

### AC-029 (event-driven)
GIVEN a live `RecallResult` produced with `explain=true`
WHEN  its `model_dump` is validated against `schemas/recall-result.v1.json`
THEN  the system shall produce a document that satisfies the published schema
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestSchemaRoundTrip::test_explain_result_validates` — DP-X, C-7.

### AC-030 (state-driven)
WHILE the full pytest suite runs against the fixed build
WHEN  the suite completes
THEN  the system shall report zero failures
VERIFY: `make test` (`docker compose run --rm crystalium pytest mcp-server/tests/ -v`) exits 0.

### AC-031 (event-driven)
GIVEN a store holding topically-unrelated crystals plus one freshly committed crystal carrying three distinctive low-frequency tokens, with `Config.recall_relevance_primary` enabled
WHEN  `Aetheryte.recall()` is called with `k=3` and a query composed of those three distinctive tokens
THEN  the system shall include the freshly committed crystal's id in `result.records`
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestSmallKFetchWidth::test_fresh_crystal_returned_at_k3` — **new per DP-R1/C-12**; pins seam 3b (`fetch_width = max(k, FETCH_WIDTH_FLOOR)`). Demonstrated RED at `323229f` before the seam-3b commit. The flag-off column of the four-cell probe is unchanged (AC-009 still holds).

### AC-032 (unwanted-behavior)
GIVEN a recall whose candidates are dropped only by the `k` slice rather than by the token budget
WHEN  the result is assembled
THEN  the system shall leave `evicted_count` at 0
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py::TestBudgetSurfaced::test_evicted_count_excludes_k_truncation` — DP-7; relocated verbatim from revision 2.0.0's AC-017 when that ID took the `k_applied` invariant. Pins `evicted_count`'s existing meaning (token-budget evictions only).

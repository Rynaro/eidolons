# Critique — crystalium-recall-starvation-36 (spec revision 2.0.0)

critic:   vigil (independent; plan author: ramza; maker: vivi)
date:     2026-08-02
inputs:   spec.md (rev 2.0.0, bound-pending-critique) · spec.criteria.md (frozen,
          sha256 8fd32daf09b7d500913fe9f46c1647b0bc5fd0ee53b3660e6bd36b314279f577 —
          re-hashed, matches) · crystalium-recall-starvation-36.state.json
target:   /home/rynaro/workspace/oss/agents/crystalium @ af24493 (tag v1.8.1, clean — verified)

**Verdict:** ramza-lint clean (exit 0, full tier) · ramza-ears-lint clean (30/30, exit 0) ·
refine rubric: **pass** (cycle 1, dims clarity 4 / completeness 4 / actionability 4 /
efficiency 5 / testability 3 — all ≥ 3; computed by `ramza-score --rubric refine`,
appended to state.gates[] and ramza-calibration.jsonl at 2026-08-02T23:55:58Z)

**Overall: PASS with findings.** No blocking defect. Three MAJOR-nonblocking findings
(F1–F3) carry mandatory prescriptions the maker should treat as merge-relevant even
though the gate opens; four MINOR findings (F4–F7).

## Anchor verification (what was independently checked, not trusted)

Every load-bearing `file:line` anchor was re-read at af24493. Confirmed exact:
`rrf_merge` retrieve.py:53-80 (scores computed and discarded) and its call at :339;
`candidate_k = max(k*3, 10)` :258; graph seed :297; `filtered_ids` :415-428;
compose call :500 inside try/except :499-514; unconditional `record_access` :544 +
`persist_dynamics` gate :545-551; score-less `CrystalSummary(...)` :561-572;
`_ComposerRecord.__slots__` :691-706 + `__init__` :708-720; `_eviction_key`
composer.py:122-134 used at :234 and :256; Pass-1 slot order :223-245; P0-9 assert
:269-272; module-level tokenizer :99/:171-177; `Composer.__init__` :159-165;
`score: Optional[float] = None` schemas.py:222; `extra="forbid"` :212; Provenance
Literal :28; TIER_VIOLATION literal :296; k clamp `max(0, int(k))` server.py:970-973
(garbage→10 already present there) and `__main__.py:363` (no try/except — see F7 note);
`exclude_none` dump server.py:986-987; `_VALID_PROVENANCE_SOURCES` :994-996 + coercion
:999-1014 invoked at :1077; commit provenance description :248-251 (literals absent);
caller identity from env :102-122 (process-level, not per-call); `persist_dynamics=
config.evb_enabled` wiring :536; advisory pattern :1129-1137; CLI hard-reject
`__main__.py:503-513`; advice f-string enforcement.py:110 verbatim; G2 "T2 ALWAYS
stays candidate" gate.py:228 + procedural.py:126-135; Dream anchors worker.py:440-442,
:547-552, :836-843; config slots/total_cap :131-141, evb_enabled :160,
idle/gap :110-111, recall_completion rationale :199; recall-result.v1.json:
`additionalProperties: false`, NO `explain` property, `score` description quoted
verbatim, `total_tokens` maximum 3500 — DP-X premise confirmed; skip-on-ImportError
helper test_schemas.py:63-77 verbatim (C-7 hazard is real); jsonschema>=4.21 at
pyproject.toml:45 (dev extra); four `Config.__new__` helpers at exactly the four
cited files/lines (C-8); **23 `.recall(` call sites across exactly 7 test files**
(9+2+1+8+1+1+1 — the spec's count is exact); TestG6EvictionDeterministic :113,
TestTotalCap :271, `_Rec` :35; retrieval_gate fixture/recall/predicate anchors within
±2 lines; install.sh:71-75 grep + "1.8.0" fallback; CHANGELOG.md:7-9; nexus roster
anchors index.yaml:1353-1373 and mcps.yaml:150-160/:164-173 exact (8 exposed tools ✓).

Empirical cold-start numbers re-measured by importing `crystalium.evb` /
`crystalium.importance` at af24493: fresh evb 0.240 (novelty 0.5), 0.258 (0.6),
legacy 0.525, 14-day 0.140, 30-day 0.085 — **all five reproduce to 3 decimals**.
The sixth does not — see F6.

Flag-scope leak check (gated seams 3+4+5 vs ungated everything-else): **clean**.
The split is consistent across §D1 flag table, DP table, C-1, and the criteria:
AC-003/016/017 presuppose flag-on where the k gate exists; AC-006/008/009 pin the
flag-off boundary; AC-015 (budget any-config) and AC-020/021 (clamp) match their
ungated status; D3 score is both-modes everywhere it is mentioned. No gated item
leaked into an ungated section or vice versa.

## Findings (severity-tagged)

### F1 — MAJOR (nonblocking): AC-001/AC-004 cannot go RED at af24493 under the Test Plan's prescribed harness
Anchors: spec.md §Test Plan ("MagicMock vector store with `embed.return_value = []`");
AC-001/AC-004 VERIFY ("C-5 RED-first at af24493"); retrieve.py:262-269 (BM25 arm is
query-filtered), :272-294 (`if query_vec:` — an empty embed return kills the dense arm
entirely), :296-299 (graph seeds come from dense hits).
Under the prescribed mocks, `all_candidates` contains **only BM25 matches**. AC-001's
four high-importance crystals ("summaries do not contain the query tokens") and
AC-004's irrelevant crystal ("query matching only the relevant crystal") therefore
never become candidates, never reach the composer, never contest the slot — both tests
return the fresh/relevant crystal at af24493 and are **GREEN on the broken build**,
which contradicts their own C-5 RED-first VERIFY clauses. The criteria are satisfiable
without amendment, but only by deviating from the harness prescription for these two
tests (a dense-arm mock returning a non-empty `query_vec` plus `dense_search` hits that
surface the competitors — the realistic "dense arm surfaces topically-weak neighbours"
mechanism §D1 itself describes). The spec never says this; a maker following §Test Plan
verbatim discovers C-5 is undischargeable and must improvise the one piece of fixture
mechanics the plan needed to bind. Sub-trap: RRF ties — a rank-1-in-one-arm competitor
ties a rank-1-in-another-arm fresh crystal at exactly 1/61, and the seam-4 key then
falls through to importance, evicting the fresh crystal **even post-fix**; the fixture
must give the target crystal multi-arm presence or rank asymmetry.

### F2 — MAJOR (nonblocking): "six sites" vs eight anchors in §D4, and the two extra sites are behaviorally different
Anchors: spec.md §D4 / §S-6 / DP-4 row ("six call sites"); the anchor list
episodic.py:176,191,262; procedural.py:149,193; semantic.py:233,287,380 = **eight**.
Source has exactly eight `"importance": 0.0` literals, and they split three ways:
3 utility storage writes (episodic:191, procedural:149, semantic:287 — the actual fix),
3 committed-result echoes (episodic:262, procedural:193, semantic:380 — DP-4c/AC-010's
surface), and 2 **dedup-merge result echoes** (episodic:176, semantic:233 — the
`status: "merged"` return path). Calling `initial_importance()` at the merge echoes
would be wrong: a merged-into crystal has its own stored importance, and echoing a
fresh cold-start value would misreport it. The count word and the anchor list cannot
both be right, and no AC covers the merged-status result path (AC-010's fixtures will
not dedup), so a wrong choice there ships green.

### F3 — MAJOR (nonblocking): C-6's own command block cannot discharge C-6
Anchors: spec.md §Conditions C-6 ("`evb_gate`, `forgetting_gate`, `dream_gate`
re-run"); §Exact pytest invocations "Slow eval gates (C-6…)" block, which runs
test_retrieval_gate, test_evb_gate, test_forgetting_gate, **test_prefetch_gate** —
and omits **test_dream_gate.py**, which exists at mcp-server/tests/test_dream_gate.py.
A maker who runs the printed command verbatim silently skips a binding condition
(and runs one gate C-6 never asked for). This is the "gate that cannot fail on the
defect it names" species: the checklist item reads discharged while the named gate
never ran.

### F4 — MINOR: AC-008's oracle is capture-tautology-prone
Anchors: AC-008 THEN ("reproduce the pre-fix composition result set"); §D4(b)
(cold-start importance is **ungated**); §Rollback ("importance values written by 1.9.0
commits persist").
With the flag off, seams 3/4/5 revert — but D4 does not. Crystals committed through
the API under the new build carry importance ≈0.24–0.30 where af24493 wrote 0.0, so
the legacy `(importance, last_access, id)` key can order the same fixture differently
than the true pre-fix build. An expected set captured from the new build makes the
test tautological ("pre-fix" silently becomes "whatever flag-off does"). The honest
fixture must pin `utility.importance` via direct insertion (as test_composer's stubs
do) or derive the expectation from the legacy algorithm, and the spec does not say so.

### F5 — MINOR: AC-014 asserts a surface the recall response does not expose
Anchors: AC-014 THEN ("the system shall report a `utility.access_count` of at least
1"); schemas.py:214-222 (CrystalSummary has no access_count field).
The value is only observable via direct store inspection (`relational.get_crystal`),
not via any recall response field. Testable, but the THEN names no observable response
surface — the test's oracle lives outside the API the criterion appears to describe.

### F6 — MINOR: the 0.403 "proven-useful" figure does not reproduce
Anchors: spec.md §Problem Statement / §D4 ceiling derivation ("5 accesses,
outcome_success=0.9, 7 days old scores evb = 0.403").
The literal stub measures **0.386** at af24493 (variants: 0.486 with last_access=now;
0.272 with the `outcome_success_score` attribute name). The other five quoted numbers
reproduce exactly. The design conclusion is unaffected (0.30 < 0.386 either way), but
this figure is destined for the COLD_START_IMPORTANCE_CEILING code comment, and the
§Test Plan repro snippet does not cover this case — an unreproducible derived number
should not reach shipped source (repo memory: recompute derived numbers).

### F7 — MINOR: small anchor drift (none load-bearing)
`version = "1.8.1"` is pyproject.toml:**8**, not :9 (§Release Plan "Edit
mcp-server/pyproject.toml:9"); `total_tokens` Field is schemas.py:**245**, not :242;
Makefile test recipe is :26-27, not :27-28; `completion_ok` is
evals/retrieval_gate.py:**153** (and reads `_gt(comp["f1"], flat["f1"])` — the spec's
`comp.f1 > flat.f1` is a paraphrase); S-2's "from_yaml/from_env/from_dict plumbing in
the style of config.py:196-217" points at the flag-declaration block — the factories
are from_yaml:254 / from_env:260, and the dict path is the private `_from_dict`.
Also noted: at __main__.py:363 there is no try/except today, but the CLI `k` arrives
through click's int typing, so AC-021's CLI-side "non-coercible" case may be
click-rejected before the new fallback code can run — the AC names no entry point, so
this is a fixture-design note, not a defect.

## Per-dimension findings (refine rubric, cycle 1)

- clarity (4/5): outstanding overall — the flag-scope table and per-DP operative
  instructions leave no decision open; docked for F2 (the six-vs-eight contradiction
  sits inside the core §D4 instruction the maker executes).
- completeness (4/5): blast radius is close to exhaustive (23 recall call sites exact,
  four Config helpers exact, roster anchors exact); gaps are F2's unspecified
  merge-echo behavior and F1's unstated harness deviation.
- actionability (4/5): every story unblocked, exact commands given; docked because two
  of those exact artifacts misdirect a verbatim executor (F1 harness, F3 command).
- efficiency (5/5): strictly additive, minimal contract growth, schema grows by the
  minimum, no gold-plating; the dual-mode cost is FORGE-ruled and test-pinned.
- testability (3/5): 30 lint-clean criteria with named test nodes and genuine
  anti-vacuity guards (AC-025's runtime-frozenset trick, C-7's no-skip rule) — but the
  two headline eviction criteria cannot go RED under the prescribed harness (F1),
  AC-008 risks a tautological oracle (F4), and AC-014's THEN names an unexposed
  surface (F5).

## Prescriptions (for the maker's implementation pass / author's next Refine)

1. §Test Plan (harness note) — add: "AC-001 and AC-004 fixtures MUST wire the mock
   vector store with a non-empty `embed.return_value` and a `dense_search` return that
   surfaces the non-query-matching competitor crystals (dense is the only path into
   `all_candidates` for them — retrieve.py:278); give the target crystal multi-arm
   presence (BM25 + dense) or rank asymmetry so its RRF score strictly exceeds the
   competitors' (two single-arm rank-1 entries tie at exactly 1/61 and the seam-4 key
   falls through to importance). Record the C-5 RED run only after confirming the test
   is red for the right reason (composer eviction, not candidate absence)."
2. §D4/§S-6/DP-4 row — replace "six call sites" with the split: "call
   `initial_importance()` at the 3 utility-write sites (episodic.py:191,
   procedural.py:149, semantic.py:287); echo the computed value at the 3
   committed-result sites (episodic.py:262, procedural.py:193, semantic.py:380);
   leave the 2 dedup-merge echoes (episodic.py:176, semantic.py:233) at their current
   behavior [or: echo the merged-into crystal's stored importance], explicitly out of
   AC-010's scope."
3. §Exact pytest invocations, slow-gate block — add `mcp-server/tests/test_dream_gate.py`
   (C-6 names it); keep or drop test_prefetch_gate.py deliberately, but say which.
4. AC-008 test note (§Test Plan) — require the fixture to pin `utility.importance` by
   direct `relational.insert_crystal` (never via the commit API, which D4 changes
   ungated), or to compute the expected set from the legacy key algorithm; forbid
   capturing the expectation from the new build.
5. §Test Plan (TestColdStartImportance note) — state that AC-014's oracle is
   `relational.get_crystal(id)["utility"]["access_count"]`, not a recall-response field.
6. §D4 ceiling comment — re-measure the proven-useful evb figure with a printed-inputs
   snippet before embedding it in the COLD_START_IMPORTANCE_CEILING comment (measured
   0.386 at af24493 for the literal stub; spec says 0.403).
7. §Release Plan — pyproject version line is 8, not 9 (trivial; fix on next touch).

## Gate record (this critique)

| Step | Command | Result |
|---|---|---|
| Structural lint | `ramza-lint --plan spec.md --state …state.json` | PASS, exit 0 ("plan passes structural lint (tier: full)") |
| EARS lint | `ramza-ears-lint spec.criteria.md` | PASS, exit 0 ("30 criteria pass EARS lint") |
| Criteria integrity | `sha256sum spec.criteria.md` | 8fd32daf…f577 — matches state.criteria_sha256 |
| Refine rubric | `echo '{"clarity":4,"completeness":4,"actionability":4,"efficiency":5,"testability":3}' \| ramza-score --rubric refine --state … --cycle 1` | **pass** (cycle 1, min 3), appended to gates[] at 2026-08-02T23:55:58Z |
| Critic record | `ramza-gate critic --state … --author ramza --checker vigil` | OK, exit 0 ("critic recorded (author: ramza, checker: vigil)") |
| Advance | `ramza-gate advance --to A --state …` | OK, exit 0 ("T -> A"); status now phase A, next DONE, criteria_frozen true |

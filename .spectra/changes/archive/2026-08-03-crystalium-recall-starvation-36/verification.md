# Verification — crystalium-recall-starvation-36

## Fresh-context attestation

| Field | Value |
|---|---|
| checker | `vigil` (fresh context; authored none of spec/critique/impl/evidence) |
| maker | `vivi` |
| date | 2026-08-02 |
| target | `/home/rynaro/workspace/oss/agents/crystalium` |
| branch | `fix/recall-starvation-36` |
| HEAD verified | `323229fc1e14e167d3774d68db63236f9b7c2027` |
| baseline | `af24493ff235ff1ccbedbeacddb5a445efb326c6` (tag v1.8.1) |
| criteria integrity | `sha256sum spec.criteria.md` = `8fd32daf09b7d500913fe9f46c1647b0bc5fd0ee53b3660e6bd36b314279f577` — **matches the frozen hash**; no criterion text edited |
| **verdict** | **VERIFIED-with-notes** |

**What I re-ran myself (nothing below is taken from the maker's transcript):**

- The RED-state at `af24493` in a scratch `git worktree`, carrying only
  `test_recall_starvation.py` from `3fd0c5e` — both the collection-error form and,
  with symbol-only shims, the behavioural form.
- The full suite (`make test`) on the branch, start to finish.
- All 30 frozen `VERIFY` commands as an explicit batch (42 named pytest nodes).
- Six gate attacks: induced defect → observed the named test go red → restored →
  proved `git status --porcelain` empty. Two of the six are my own, beyond the
  mandated four.
- Two direct composer/recall probes (not via pytest) to test claims the suite
  does not reach.
- `python -m evals retrieval-gate` on the branch.

`shasum` is not present on this host; `sha256sum` was used (same digest).

---

## Step 1 — RED-evidence authenticity

Scratch worktree at `af24493` (`--detach`), tracked diff empty, then
`git show 3fd0c5e:mcp-server/tests/test_recall_starvation.py` copied in.
Byte-identity of the copied file confirmed against the committed blob
(`sha256 34ee7157…1ca1d`, both sides). Isolated compose project (`-p redwt36`,
own volume) so the target repo's runner was untouched.

**Part 1 (as committed) — reproduced exactly:**

```
collected 0 items / 1 error
E   ImportError: cannot import name 'COLD_START_IMPORTANCE_CEILING'
    from 'crystalium.importance'
Interrupted: 1 error during collection
```

This is real but weak evidence — a missing symbol, not a behavioural defect. The
maker says so himself in `red-evidence.txt` and supplies a Part 2. I did not take
Part 2 on trust; I reconstructed it.

**Part 2 (my own reconstruction) — symbol-only shims at `af24493`**
(`COLD_START_IMPORTANCE_CEILING`, `normalize_k`, and `**_ignored` kwarg tolerance on
`Composer.__init__` / `Aetheryte.__init__`; no ranking, `k`, score or importance
logic touched). Result: **29 failed, 9 passed**. Every C-5-mandated AC failed on its
**own** assertion, for the semantically correct reason:

| AC | observed failure at `af24493` |
|---|---|
| AC-001 | `assert 'target' in {'comp-3'}` — composer evicted the fresh crystal |
| AC-002 | `assert 8 == 5` — `k` never applied as a cap |
| AC-003 | `assert 20 <= 10`, `assert 20 <= 15`, … (all 5 params) |
| AC-004 | `assert 'relevant' in {'irrelevant'}` — starvation inversion |
| AC-005/006 | `assert None is not None` — `score` never populated |
| AC-010 | `assert 0.0 > 0.0` × episodic/procedural/semantic |
| AC-011/012 | `assert 0.0 > 0.0`; `assert 0.0 == 0.24 ± 1e-9` |
| AC-015..018 | `AttributeError: 'RecallResult' object has no attribute 'budget'`; `'k_applied' not in explain` |

`red-evidence.txt`'s claims are **authentic**. Critique F1's concern (red for the
*right* reason, not candidate-absence) is genuinely discharged — the AC-001/AC-004
fixtures do wire a live dense arm (`_build_aetheryte_with_dense`, non-empty
`embed.return_value`, competitors surfaced via `dense_search`), exactly per
prescription 1. Worktree and its volume removed; `git worktree list` shows only the
main checkout.

## Step 2 — Full suite, my own run

```
docker compose run --rm crystalium pytest mcp-server/tests/ -v
896 passed, 2 skipped, 40 warnings in 789.46s (0:13:09)   EXIT=0
```

Zero failures. The only skips are the two pre-existing root-permission ones:
`test_cli.py::test_doctor_readonly_data_dir_nonzero` and
`test_cli.py::test_doctor_fail_shows_fail_marker` (`skipif os.getuid() == 0`,
`test_cli.py:104`). **AC-030 satisfied.**

C-6's four named slow gates all ran and passed inside this run —
`test_retrieval_gate`, `test_evb_gate`, `test_forgetting_gate`, `test_dream_gate`
(plus `test_prefetch_gate`). Note that the *spec's* printed slow-gate command block
(`spec.md:857-862`) still omits `test_dream_gate.py` — critique F3 was never folded
back into the frozen spec — but `make test` covers it, so C-6 is discharged in fact.

## Step 3 — Frozen-criteria conformance

Every `VERIFY` node from `spec.criteria.md`, run as one batch:

```
pytest mcp-server/tests/test_recall_starvation.py \
       mcp-server/tests/test_composer.py::TestTotalCap \
       mcp-server/tests/test_diagnosability.py::TestSummaryQualityGate::test_commit_good_summary_no_advisory
42 passed in 79.27s
```

**30/30 criteria conform** (AC-001..029 by named node, AC-030 by the suite above).
AC-028's no-skip requirement holds structurally: `import jsonschema` /
`from jsonschema import Draft202012Validator` sit unconditionally at module top
(`test_recall_starvation.py:42-43`); the `test_schemas.py:63-77` skip-on-ImportError
helper is **not** used. Criteria file hash re-verified — unchanged.

## Step 4 — Gate attacks

Six attacks. Each: induce → run → `git checkout -- .` → prove
`git status --porcelain` empty and `HEAD == 323229f`.

| # | Defect induced | Named gate | Result | Restored clean |
|---|---|---|---|---|
| **A** | delete the `budget` property definition from `schemas/recall-result.v1.json` | AC-028, AC-029 | **RED** — `ValidationError: Additional properties are not allowed ('budget' was unexpected)`. A real failure, **not a skip**. Control AC-015 stayed green. | ✅ |
| **B** | `_eviction_key`: `if relevance_primary:` → `if False:` — legacy `(importance, last_access, id)` key restored while the flag stays `True` | AC-004 | **RED** — `assert 'relevant' in {'irrelevant'}`. Also red: AC-001, `test_composer::TestRelevancePrimaryEviction::test_eviction_evicts_least_relevant_first`. Controls AC-002/003 and AC-008/009 green. | ✅ |
| **C1** | `initial_importance()` → `return 0.0` | AC-010 | **RED** ×3 (`assert 0.0 > 0.0`, episodic/procedural/semantic). Also red: AC-011, AC-012. Controls AC-013 (execution 0.5) and AC-014 green. | ✅ |
| **C2** | drop the `min(…, COLD_START_IMPORTANCE_CEILING)` clamp | AC-011 | **RED** — `assert 0.525 <= 0.3`. 0.525 is exactly the legacy-scorer cold-start value the critic measured independently. AC-012 stayed green ⇒ the clamp never binds on the default EVB path. | ✅ |
| **D** | delete `filtered_ids = filtered_ids[:k]` | AC-002, AC-003 | **RED** — AC-002 plus all 5 AC-003 parametrisations (`assert 20 <= 10`, …). Controls AC-008/009 green. Side finding — see F-V3. | ✅ |
| **E** *(mine)* | delete the seam-5 descending-relevance output sort | AC-007 | ⚠️ **GREEN — the gate did not fire.** See F-V2. | ✅ |
| **F** *(mine)* | delete `score=rec.relevance_score` | AC-005, AC-006 | **RED** both (`assert None is not None`); AC-007 also red (`TypeError` comparing `None`s). | ✅ |

Attacks B and D double as flag-scope proofs: reverting seam 4 / disabling seam 3 left
the flag-**off** tests (AC-008/AC-009) untouched, because flag-off *already is* that
code path.

## Step 5 — Flag-off fidelity

Static audit — `grep -rn 'recall_relevance_primary' mcp-server/src/` gives exactly
four read sites, and they are exactly the three declared seams:

- seam 3 — `retrieve.py:505` (`filtered_ids[:k]`)
- seam 4 — `composer.py:280`, `:303` (both `_eviction_key` call sites)
- seam 5 — `composer.py:318` (output ordering)

Nothing else is behind the flag. `score` population (`retrieve.py:667`), the `budget`
object (`:738`), `explain.k_applied`/`truncated_by_k` (`:703-704`), `normalize_k`, and
cold-start `initial_importance` are all **ungated** — matching the frozen split
(AC-015 "any configuration", AC-005/006 "both modes", AC-020/021). No gated item
leaked out and no ungated item leaked in. The flag is wired from `Config` at both
production construction sites (`server.py:480`+`:569`, `__main__.py:318`+`:352`), which
`grep` confirms are the *only* `Composer(` / `Aetheryte(` sites in `src/`.

Empirical (my own probe, real embedding stack, `_build_components`): with
`recall_relevance_primary=False`, `budget` is present, every `score` is non-null, and
`k=3` returns 6 records — **`k` is not a cap**, matching AC-009 and pre-1.9.0
behaviour. AC-008's fixture correctly pins `utility.importance` by direct
`relational.insert_crystal` rather than through the commit API (prescription 4
followed), so the oracle is not the tautology F4 warned about.

The `k` value participates in the recall-cache key (`_cache_ctx`, `retrieve.py:194-203`),
so AC-003's cap cannot be bypassed by a cached result computed under a different `k`.

## Step 6 — Issue #36 end-to-end

Driven through the **real** `commit → recall` path (`_build_components`, real
sentence-transformers dense arm, real graph store) rather than the unit fixtures:
6 topically-unrelated crystals committed, then one carrying three distinctive
low-frequency tokens.

At the **default `k=10`** (the value both the MCP manifest and the CLI default to),
flag on:

```
commit importance      = 0.24  (stored 0.24 — no longer 0.0)
fresh crystal returned = True, position 0 (top), score 0.032787
scores all non-null    = True
budget present         = True
```

The reported defect is fixed on the default path: a freshly committed crystal is
retrievable, ranks first, carries a non-null `score`, and `k` is honoured.
`CrystalSummary.score` is non-null in **both** flag modes.

At small `k` the picture is different — see **F-V1**, the headline note.

## Step 7 — Eval honesty

`docker compose run --rm crystalium python -m evals retrieval-gate`, my own run on
the branch:

| axis | eval-after.json (maker) | my re-run | match |
|---|---|---|---|
| `multihop_f1.flat` | 0.30769230769230765 | 0.30769230769230765 | ✅ exact |
| `multihop_f1.completion` | 0.4615384615384615 | 0.4615384615384615 | ✅ exact |
| `multihop_f1.both` | 0.4615384615384615 | 0.4615384615384615 | ✅ exact |
| `context_rank.flat / context` | 2 / 2 | 2 / 2 | ✅ |
| `context_rank.both` | 4 | **5** | ⚠️ F-V6 |
| `graph_ok` | true | true | ✅ |
| `completion_pass` | true | true | ✅ |
| `context_pass` | false | false | ✅ |
| `gate_pass` | true | true | ✅ |

**No silent predicate flip.** `git diff af24493 HEAD -- evals/retrieval_gate.py` is
**empty** — the gate's own predicates (`completion_ok = _gt(comp["f1"], flat["f1"])`,
`context_ok = _lt(ctx["ctx_rank"], flat["ctx_rank"])`) are provably unmodified by this
change, and my after-run's three pass values are identical to `eval-before.json`'s.
I did not independently re-run the eval at `af24493`; the unmodified-predicate proof
plus the matching pass values discharge the requirement.

## Step 8 — CHANGELOG, version, DX text

- `mcp-server/pyproject.toml:8` → `version = "1.9.0"` ✅ (spec §Release Plan says
  pyproject is the single source `install.sh:71-75` greps; its `"1.8.0"` grep-failure
  fallback was explicitly to be left alone, and was.)
- `CHANGELOG.md` top entry `## [1.9.0] — 2026-08-02`, above `## [1.8.1]` ✅, and it
  matches the shipped behaviour verbatim against the spec's sketch — names
  `recall_relevance_primary` (×2), `CrystalSummary.score`, `RecallResult.budget`,
  the `[1, 100]` clamp with fallback-to-10, the 0.30 cold-start ceiling, and the
  `summary_size` advisory. ✅
- AC-027 DX advice, checked mechanically against the source string: contains
  `procedural` ✅; contains neither `promoted to semantic` ✅ nor `auto-promot` ✅.
  The advice actively *denies* promotion ("it stays candidate; promotion to a
  validated/semantic record requires a T1/T0 proposer through the corroboration
  gate") — consistent with gate.py's G2 rule. **No T2→semantic promotion promise.**

---

## Deviation adjudications

### D1 — dedup-merge echoes report the merged-into crystal's stored importance — **ACCEPT**

This is exactly the alternative critique F2 itself prescribed
("[or: echo the merged-into crystal's stored importance]"), and it is the
semantically correct one: a merged-into crystal has earned its own importance, so
echoing a cold-start value would misreport it. Correctly scoped — the three
*utility-write* sites call `initial_importance()`, the three *committed-result*
echoes mirror the computed value, and only the two merge echoes
(`episodic.py:176`, `semantic.py:233`) take the stored value, with a `0.0` fallback
on lookup failure so the commit can never be broken by the new read. Out of AC-010's
scope, as F2 said. **Caveat:** no test asserts the merged echo's `importance` —
`test_dedup_merge.py:80` and `test_write_conflict.py:98` assert only
`status == "merged"`. The path is exercised (a crash would surface) but the *value*
is unasserted, so F2's "a wrong choice there ships green" remains structurally true.
Recommend one assertion; not a blocker.

### D2 — CLI `--k` changed from `click type=int` to `type=str` — **ACCEPT**

This is what makes C-11/AC-021 true at the CLI entry point, which the AC's
"at both `server._handle_recall` and the CLI verb" language demands; critique F7
flagged precisely this hazard ("click's int typing … may be click-rejected before
the new fallback code can run"). `normalize_k` is a genuine single source of truth
shared by both entries (`__main__.py` imports it from `server`), and
`test_normalize_k_never_raises` proves it degrades on `None`, `[]`, `{}`, `object()`.
Verified green: AC-020's CLI arm (`--k 0/-3/500` → `1 ≤ k ≤ 100`, exit 0) and AC-021.
Behaviour for a legitimate integer is unchanged; only the `--help` default renders
as a string.

### D3 — `Composer.recall_relevance_primary` an explicit kwarg, not a `self.config` read — **ACCEPT (with note)**

No live divergence: `grep` proves the only two `Composer(` sites in `src/`
(`server.py:480`, `__main__.py:318`) both pass
`recall_relevance_primary=config.recall_relevance_primary`, and the symmetry claim
holds — `Aetheryte` threads the same kwarg the same way. The stated rationale (a bare
`Composer(config)` in a pre-existing test still gets the new default) is real and is
what keeps `test_composer.py`'s untouched stubs meaningful.
**Note:** it is a latent trap, not a defect. A future third construction site that
forgets the kwarg gets seams 4+5 ON while Aetheryte's seam 3 is OFF — a half-gated
mode no AC covers, and `Config.recall_relevance_primary=False` would be silently
ignored there. A `None` sentinel defaulting to `config.recall_relevance_primary`
would close it without losing the stated benefit.

### D4 — `crystalium/__init__.py:_FALLBACK_VERSION` left at `"1.8.0"` — **ACCEPT**

**Pre-existing, not introduced.** `git show af24493:…/__init__.py` has
`_FALLBACK_VERSION = "1.8.0"` while `af24493:pyproject.toml` already read
`version = "1.8.1"` — the value was one release stale *before* this change. The
spec's §Release Plan names `pyproject.toml` as the single edit and explicitly
scopes the other hardcoded fallback out. The constant is only reached on
`PackageNotFoundError`; in the installed container `__version__` resolves to
1.9.0 (and `test_ecl_envelope.py:126-130` pins the ECL envelope to `__version__`,
which passes). Out of scope for this change; worth a one-line cleanup on the next
touch of that file.

---

## Findings

### F-V1 — MAJOR (does not fail any frozen criterion): at small `k`, the default configuration is *worse* than `af24493` at retrieving the fresh crystal

Reproduced on fresh stores (one per cell, no cross-measurement state — my first
attempt interleaved recalls in one store and was invalid; these numbers are the
clean re-run), real embedding + graph arms, `commit → recall`, query =
the three distinctive tokens:

| `k` | flag ON (shipped default) | flag OFF (= pre-1.9.0) |
|---|---|---|
| 1 | fresh **NOT returned** | fresh returned (pos 5 of 6) |
| 3 | fresh **NOT returned** | fresh returned (pos 3 of 6) |
| 5 | fresh returned, pos 1 | fresh returned, pos 1 |
| 10 (default) | fresh returned, **pos 0** | fresh returned, pos 0 |

Mechanism — and note the root is **pre-existing code the fix did not touch**:
`seed_ids = dense_ranking[:k]` (`retrieve.py:355`) makes the graph and completion
arms' membership depend on the caller's `k`. At small `k` the walk from the fresh
crystal hands its topically-unrelated neighbours a third and fourth arm, so RRF —
which fuses arms unweighted — scores them ~3 × 1/62 ≈ 0.048 against the exact
lexical match's 2 × 1/61 = 0.0328. The fresh crystal is genuinely ranked below them.

Pre-fix that cost it *position*; post-fix seam 3 converts "ranked 4th" into
"not returned at all". So for a caller passing `k=3`, v1.9.0 regresses the exact
capability #36 exists to restore.

**Why this is not a REJECT:** no frozen criterion is violated. AC-001's GIVEN
specifies four competitors, a reduced `episodic` slot, and its test uses `k=10`;
my scenario is a different, harder one that no AC describes. The shipped default
`k` (MCP manifest and CLI both = 10) is correct. But the maintainer should see this
before release — the honest options are weighting the sparse/exact arm, decoupling
the graph seed size from `k`, or documenting that small `k` trades recall for
precision.

### F-V2 — MAJOR: AC-007's gate cannot fail on the defect it names

Deleting seam 5 — the *only* code that guarantees descending-`score` output —
leaves `test_records_ordered_by_descending_score` **green** (attack E: 8 passed).

Seam 5 is nonetheless load-bearing. Direct composer probe, slot cap forcing one
eviction, four records at relevance 0.9/0.5/0.1/0.05:

```
HEAD                : ids ['a','b','c']  scores [0.9, 0.5, 0.1]   (descending ✓)
seam-5 removed      : ids ['c','b','a']  scores [0.1, 0.5, 0.9]   (ASCENDING ✗)
```

Pass-1 reassembles a slot from `remaining`, which is sorted *ascending* by eviction
key; without seam 5 any evicting slot emits worst-relevance-first. AC-007's fixture
(3 short records, 800-token slot) never evicts, so insertion order is already
descending and the assertion passes either way. The behaviour is **correct as
shipped** (verified green at HEAD) — the gate is what is weak. A future refactor that
drops seam 5 would ship green. Fix: add an eviction-forcing fixture to AC-007's test.

### F-V3 — MINOR: `budget.truncated_count` is computed independently of the truncation actually happening

`truncated_by_k_count = max(0, len(filtered_ids) - k)` is computed *before* the
slice, so the counter and the act are only coincidentally consistent. Under attack D
(slice deleted, counter kept) the shipped result object reported
`k_requested=15, k_applied=20, truncated_count=5` — five drops that never occurred,
and `k_applied > k_requested` — while AC-016 and AC-017 both stayed **green**. Their
oracles check arithmetic (`8 - 3`) and `evicted_count == 0`, never that the returned
set actually shrank. Same species as F-V2, milder. Suggest asserting
`len(records) + truncated_count == candidates` or `k_applied <= k_requested`.

### F-V4 — MINOR: the seam-3 comment states an invariant the code above it can break

`retrieve.py:495-497` asserts "`filtered_ids` is already in descending-RRF order".
That is false whenever `context_match` is on: `fused_ids` is re-sorted by context
overlap at `:425` before the scope filter builds `filtered_ids`. The k-gate then
selects the top-`k` by *context-overlap-then-RRF*, not by relevance — silently giving
`context_match` membership power it did not have pre-1.9.0. AC-003 and AC-007 still
hold (seam 5 re-sorts the survivors by raw RRF), and `recall_context_match` is
default-OFF and gate-recommended to stay off (`context_pass: false`), so nothing
ships broken. But the comment should say "descending-RRF order unless `context_match`
re-ranked it", or the capture should move.

### F-V5 — MINOR: AC-015's "any configuration" is only tested in one configuration

`test_budget_object_present_with_five_fields` runs solely with the flag on; the
criterion says "any recall result in any configuration". I verified flag-off
independently (my e2e probe: `budget present = True` with all five fields, both
modes), so the behaviour is right — the gate is just narrower than its criterion.

### F-V6 — MINOR: one BENCH-NOTES figure does not reproduce

`evals/BENCH-NOTES.md` records `context_rank (flat/context/both) = 2 / 2 / 4` for the
after-run; my re-run measured **2 / 2 / 5**, and `eval-after.json` also says 4. The
`both` arm feeds no pass predicate (`completion_ok` uses `comp` vs `flat`,
`context_ok` uses `ctx` vs `flat`), so no verdict is affected — but a
non-reproducible number is now in a committed document, which is the same class of
defect critique F6 raised about the 0.403 figure (that one *was* fixed: the shipped
`COLD_START_IMPORTANCE_CEILING` comment correctly carries the re-measured 0.386).
Either re-measure or mark the axis as run-varying.

### F-V7 — NOTE: the test file was amended after the RED commit

`git diff 3fd0c5e HEAD -- test_recall_starvation.py` is +25/−4. The change is
confined to AC-007's `TestOrdering` fixture (the original assumed FTS5 `MATCH` was
OR-semantics; it is implicit-AND, so only one crystal would have become a candidate
and `assert len(records) >= 2` could not pass). **No assertion was weakened**, and the
five C-5-mandated AC bodies are byte-identical between `3fd0c5e` and HEAD — I
diffed them. `red-evidence.txt`'s "PART 1 — OFFICIAL RUN (exact committed test file)"
is therefore against a file that now differs by that one fixture; the ImportError
claim is unaffected (whole-module collection failure). Honest, but the evidence file
should say so.

### F-V8 — NOTE: pre-existing stale `_FALLBACK_VERSION` — see D4.

### F-V9 — NOTE: a pre-existing stash entry survives in the target repo

`stash@{0}: On fix/recall-tiktoken-special-token-32: vivi: pre-merge stash of
unrelated nexus sync drift`. It predates this change (that branch is the #32/#34
work merged as `af24493`) and was **not** created by this verification — every
restore here used `git checkout -- .`. Flagged only so it is not mistaken for
verification residue.

---

## Verdict

**VERIFIED-with-notes.**

All 30 frozen acceptance criteria pass under my own runs; the full suite is
896 passed / 2 pre-existing skips / 0 failed; the RED-first evidence is authentic
and reproduced independently in both its forms; the flag genuinely gates seams 3+4+5
as one unit with no leakage in either direction; the eval numbers reproduce exactly
and no gate predicate was touched; version, CHANGELOG and the AC-027 DX text are
correct. Five of six gate attacks made the named gate go red on the defect it names,
and the tree was restored clean after every one.

Two MAJOR findings are recorded rather than blocking, and I want the maker and the
maintainer to weigh them explicitly before merge:

- **F-V1** — the fix's headline promise does not hold at small `k` in the default
  configuration, and is a regression against `af24493` there. It violates no frozen
  criterion (AC-001's GIVEN is a different scenario, and the shipped default `k=10`
  behaves correctly), and its root cause — `seed_ids = dense_ranking[:k]` plus
  unweighted RRF — is pre-existing code this change did not touch. But the change
  makes it bite harder than before.
- **F-V2** — AC-007's gate cannot fail on the defect it names. The behaviour is
  correct as shipped; the test is not a gate.

Neither is a criterion or invariant failure, so REJECT is not warranted. F-V1 in
particular is a scope judgement the maintainer owns, not a verification failure.

**Tree left exactly as found:** branch `fix/recall-starvation-36`, HEAD
`323229fc1e14e167d3774d68db63236f9b7c2027`, `git status --porcelain` empty,
`git status --untracked-files=all` empty, `git diff 323229f` empty, one worktree
(the main checkout), no stash created.

---

## Final pre-tag attestation (2026-08-03, vigil, fresh context)

Second attestation, appended per **DP-R4(ii) / C-15**. Fresh context, no reuse of the
323229f pass above; every number below is my own run. The prior attestation's text is
unmodified — this section only adds.

| item | value |
|---|---|
| target | `Rynaro/crystalium`, branch `fix/recall-starvation-36` |
| HEAD verified | `351ba22d619d02d815e015822b2dc54ad4b161de` (7 commits off `af24493` / v1.8.1) |
| tree at start | `git status --porcelain` empty; one worktree (the main checkout) |
| criteria file | `spec.criteria.md` rev 2.1.0, **32** criteria |
| criteria sha256 | `487058986ff25ac9e9a4d286e73019e79c2284fae1f14c777f9629e05a861d36` — recomputed, **matches** the amended hash |
| amend chain | `supersedes: 8fd32daf…f577` — that is exactly the rev-2.0.0 hash recorded in *this file* (§Fresh-context attestation) and in `critique.md:6,204`. The C-13 amend is hash-chained to the artefact I previously attested, not to an unverifiable ancestor. |
| `change.json` | `maker: vivi`, `checker: vigil` — **maker ≠ checker** holds; `acceptance_checks` regenerated, 32 entries, AC-001…AC-032 with no gaps |

### R1 — Full suite, my own run (DP-R4(ii).1)

```
docker compose run --rm crystalium pytest mcp-server/tests/ -v
902 collected
900 passed, 2 skipped, 40 warnings in 778.42s (0:12:58)   EXIT=0
```

**Zero failures, zero errors.** The only two skips are the pre-existing
root-permission ones (`test_cli.py::test_doctor_readonly_data_dir_nonzero`,
`test_cli.py::test_doctor_fail_shows_fail_marker`, `skipif os.getuid() == 0`) —
identical to the 323229f run. Collection went 898 → 902, matching exactly the four
nodes this patch round adds (AC-031, the new AC-017 node, and the two D1 merged-echo
assertions). **AC-030 satisfied.**

### R2 — The 32 frozen criteria (DP-R4(ii).2)

Verified against criteria sha256 `487058986ff2…a861d36` (recomputed, above).

```
docker compose run --rm crystalium pytest \
  mcp-server/tests/test_recall_starvation.py \
  mcp-server/tests/test_composer.py::TestTotalCap \
  mcp-server/tests/test_diagnosability.py::TestSummaryQualityGate::test_commit_good_summary_no_advisory -v
44 passed in 75.28s   EXIT=0
```

Every `VERIFY` node named by the amended file is present in that run and **green** —
AC-001…AC-032, including all parametrisations (AC-003 ×5, AC-010 ×3, AC-020 ×3) and
the two auxiliary nodes (`TestTotalCap` ×3 for AC-019, the diagnosability node for
AC-023). Node-by-node: 44 results, 0 failed, 0 skipped. **32/32 criteria conform.**
AC-028's no-skip requirement still holds structurally (`import jsonschema` remains
unconditional at module top).

### R3 — ATTACK E repeated (DP-R4(ii).3) — **the gate now fires**

Induced: delete the seam-5 output sort (`composer.py`, the
`if self.recall_relevance_primary: kept_records.sort(...)` block).

```
FAILED test_recall_starvation.py::TestOrdering::test_evicting_slot_emits_descending_score
E   AssertionError: expected non-increasing score order,
    got [0.015873015873015872, 0.016129032258064516, 0.01639344262295082]
1 failed, 39 passed in 71.78s
```

The observed order is **strictly ascending** — precisely the worst-first inversion my
direct composer probe predicted at 323229f (F-V2). **F-V2 is closed:** the strengthened
eviction-forcing fixture turns the one attack that previously left AC-007 green into a
RED. Exactly one node failed, so the fixture is specific, not blast-radius noise.
Restored with `git checkout --`; `git status --porcelain` empty.

### R4 — ATTACK D repeated (DP-R4(ii).4)

Induced: delete `filtered_ids = filtered_ids[:k]`, keep every counter exactly as shipped.

```
8 failed, 32 passed in 72.29s
FAILED …TestKIsACap::test_k5_returns_five_when_five_fit          (assert 8 == 5)
FAILED …TestKIsACap::test_never_exceeds_k[1|3|5|10|15]           (assert 10 <= 1, …, 20 <= 15)
FAILED …TestBudgetSurfaced::test_truncated_count_derived_from_real_slice
        E  AssertionError: assert 0 == (8 - 3)
        E   where 0 = Budget(…, k_requested=3, k_applied=3, truncated_count=0).truncated_count
FAILED …TestBudgetSurfaced::test_evicted_count_excludes_k_truncation
        E  AssertionError: assert 0 > 0        (the fixture's truncation precondition)
PASSED …TestBudgetSurfaced::test_k_applied_never_exceeds_k_requested
```

- **AC-016 → RED, as mandated.** And note *what* it now reports: `truncated_count=0`,
  not the phantom `5`. The F-V3 defect is gone at the source — the counter tells the
  truth about a slice that did not happen, and the strengthened oracle catches the
  missing slice instead of being fooled by it.
- **AC-032 → RED, on its `truncated_count > 0` precondition, not on its pin.**
  DP-R4(ii) expected AC-032 to stay green; it does not, and the reason is benign:
  attack D removes the very truncation the fixture needs, so assertion 1 (the guard
  that stops the `evicted_count == 0` pin from passing *vacuously*) trips first. The
  pinned value itself was never violated — `evicted_count` is 0 throughout. A guard
  that refuses to certify a pin it could not actually exercise is the correct
  behaviour; I record the deviation from the expectation rather than the reverse.
- **AC-017 → GREEN**, as DP-R3's by-construction design predicts. Adjudicated below.

**Attack D′ (mine, added).** Because "AC-017 stays green" is indistinguishable from
"AC-017 cannot fail", I re-ran the *original* F-V3 defect shape — slice deleted **and**
`k_applied_count` reverted from `min(k, before)` to the intent-derived `len(filtered_ids)`:

```
FAILED …TestBudgetSurfaced::test_k_applied_never_exceeds_k_requested
E   AssertionError: k_applied=8 > k_requested=1 at k=1
E   assert 8 <= 1
3 failed, 3 passed in 3.53s
```

AC-017 **does** fire on the defect it names. It is a live gate, not a tautology.

Restored after each attack with `git checkout --`; re-ran `TestBudgetSurfaced` +
`TestOrdering` + `TestKIsACap` → **13 passed in 4.28s**, `git status --porcelain` empty,
HEAD still `351ba22`.

#### Attack table

| # | Defect induced | Named gate | Mandated | Observed | Restored |
|---|---|---|---|---|---|
| **E** | delete seam-5 output sort (`composer.py`) | AC-007 | RED | **RED** — ascending score order; 1 failed / 39 passed | ✅ |
| **D** | delete `filtered_ids[:k]`, keep counters | AC-016 | RED | **RED** — `assert 0 == (8-3)` | ✅ |
| **D** | (same run) | AC-017 | green *(by construction)* | **GREEN** | ✅ |
| **D** | (same run) | AC-032 | green | **RED on its precondition** (`assert 0 > 0`); the `evicted_count == 0` pin itself never violated — see above | ✅ |
| **D** | (same run) | AC-002, AC-003 ×5 | — | RED (unchanged from 323229f) | ✅ |
| **D′** | slice deleted **+** `k_applied` reverted to intent-derived | AC-017 | — *(mine)* | **RED** — `k_applied=8 > k_requested=1` | ✅ |

### R5 — F-V1 four-cell probe, re-run (DP-R4(ii).5)

Real `commit → recall` stack (`server._build_components`, real sentence-transformers
dense arm, real Kuzu graph arm), one **fresh data dir per cell**, 6 topically-unrelated
crystals + 1 fresh crystal carrying three distinctive low-frequency tokens, query = those
three tokens. Run **twice per revision** — because a single run cannot distinguish a fix
from a lucky draw. `order` is the returned sequence, `F` = the fresh crystal, digits =
fixture index.

**Flag ON (the shipped default):**

| `k` | 323229f source (`89c23d9`) run 1 | run 2 | **351ba22** run 1 | run 2 |
|---|---|---|---|---|
| 1 | fresh **NOT returned** `[2]` | fresh **NOT returned** `[5]` | **fresh pos 0** `[F]` | **fresh pos 0** `[F]` |
| 3 | fresh **NOT returned** `[3,4,1]` | fresh pos 1 `[1,F,0]` | **fresh pos 0** `[F,2,5]` | **fresh pos 0** `[F,2,5]` |
| 5 | fresh pos 1 `[1,F,4,2,5]` | fresh pos 2 `[4,1,F,2,5]` | **fresh pos 0** `[F,2,5,0,3]` | **fresh pos 0** `[F,2,5,0,3]` |
| 10 | fresh pos 0 `[F,2,5,0,3,4,1]` | fresh pos 0, same order | **fresh pos 0**, same order | **fresh pos 0**, same order |

**Flag OFF:**

| `k` | 323229f source run 1 / run 2 | 351ba22 run 1 / run 2 |
|---|---|---|
| 1 | n=7, fresh pos 5 | n=7, fresh pos 5 |
| 3 | n=7, fresh pos 3 / pos 3 | n=7, fresh pos 3 / pos 3 |
| 5 | n=7, fresh pos 2 / pos 1 | n=7, fresh pos 0 / pos 1 |
| 10 | n=7, fresh pos 0, order `[F,2,5,0,3,4,1]` | n=7, fresh pos 0, order `[F,2,5,0,3,4,1]` |

Three things this establishes, none of which the unit fixture could:

1. **The acceptance test passes.** Flag-on returns the fresh crystal at `k ∈ {1,3,5,10}`,
   at **position 0** in every cell, reproducibly. The k=1 starvation cell — the worst cell
   in the original F-V1 table — is fixed.
2. **F-V1 is independently reproduced at the pre-fix commit** (fresh absent at k=1 in
   both runs; absent at k=3 in one). I did not take the maker's word that there was
   something to fix; I measured it at `89c23d9` myself.
3. **Seam 3b does what DP-R1 claimed it would do.** Post-fix, the small-`k` result is an
   exact *prefix* of the k=10 ranking (`[F]` ⊂ `[F,2,5]` ⊂ `[F,2,5,0,3]` ⊂
   `[F,2,5,0,3,4,1]`) and is byte-stable across runs. Pre-fix, each `k` produced a
   *different* ranking and the small-`k` cells were not even run-stable. The ranking
   universe is now genuinely `k`-independent — "strictly variance-reducing" was not
   rhetoric.

### R6 — Flag-scope audit, seam 3b included (DP-R4(ii).6)

`grep -rn recall_relevance_primary mcp-server/src/` — **exactly five production read
sites**, exactly the four declared seams:

| site | seam |
|---|---|
| `retrieve.py:374` | **3b** — `fetch_width = max(k, FETCH_WIDTH_FLOOR) if self.recall_relevance_primary else k` |
| `retrieve.py:535` | 3 — `filtered_ids[:k]` |
| `composer.py:294`, `:317` | 4 — both `_eviction_key` call sites |
| `composer.py:332` | 5 — output ordering |

Everything else is an assignment, a comment, or the `Config` field itself. **Nothing
gated leaked ungated and nothing ungated leaked in:** `score` population, the `budget`
object, `explain.k_applied` / `truncated_by_k`, `normalize_k` and cold-start
`initial_importance` all remain unconditional, matching the frozen split (AC-015 "any
configuration", AC-005/006 "both modes", AC-020/021). `FETCH_WIDTH_FLOOR = 10` is a
named module constant whose comment ties it to the existing `candidate_k = max(k*3, 10)`
floor and the shipped default `k` — per C-12, not a new magic number. Both arm-seeding
slices (`seed_ids`, `completion_seeds`) now read `fetch_width`; `grep` confirms
`filtered_ids[:k]` is the **only** remaining consumer of raw caller `k`.

**C-16 (D3 sentinel) — verified at runtime, not by reading:**

```
C16 config=True  default=True  explicitTrue=True explicitFalse=False
C16 config=False default=False explicitTrue=True explicitFalse=False
```

A bare `Composer(config)` now follows `config.recall_relevance_primary` in **both**
directions — the half-gated mode (seams 4+5 on while seam 3/3b is off) is no longer
reachable by forgetting a kwarg. Explicit kwargs still win, and `grep` shows exactly two
`Composer(` construction sites in `src/` (`server.py:480`, `__main__.py:318`) and two
`Aetheryte(` sites (`server.py:548`→`:569`, `__main__.py:340`→`:352`), **all four passing
the flag explicitly** — so behaviour at every production site is byte-identical to
before the sentinel. **C-16 discharged.**

### R7 — Flag-off fidelity (DP-R4(ii).7)

- AC-008 (`test_flag_off_restores_prefix_behaviour`) and AC-009
  (`test_flag_off_does_not_cap_at_k`) — **green** in R2.
- **Code proof:** with the flag off, `fetch_width = k` exactly, so `seed_ids =
  dense_ranking[:k]` and `completion_seeds = seed_ids or sparse_ranking[:k]` are
  character-for-character the 323229f expressions. The seam-3b widening is entirely
  inside the flag gate.
- **Empirical proof (R5, flag-off column):** result-set *size* is `n=7` at every `k` —
  `k` is not a cap, AC-009's boundary intact — and the deterministic anchor cell
  (`k=10`) returns the identical order `[F,2,5,0,3,4,1]` at both revisions across all
  four runs.
- **One honest correction to my own first reading.** A single-run comparison appeared to
  show the flag-off column changing at `k=3` between revisions. Repeating the probe
  twice per revision showed the flag-off ordering is **run-to-run non-deterministic at
  both revisions** (`89c23d9` k=5: pos 2 then pos 1; `351ba22` k=5: pos 0 then pos 1) —
  the apparent difference was noise in the narrow-seed graph arm, not a behaviour change.
  Pre-existing, unchanged by this patch, and *reduced* by it (the flag-on column became
  deterministic). Recorded as **F-V11** below rather than asserted as a regression.

### R8 — Release surface (DP-R4(ii).8)

- `mcp-server/pyproject.toml:8` → `version = "1.9.0"` ✅ (the root `pyproject.toml` is
  the tooling stub and carries no version, as designed).
- `CHANGELOG.md` `## [1.9.0] — 2026-08-02`, above `## [1.8.1]` ✅. The 1.9.0 block now
  carries the **fetch-width line** ("The retrieval arms' seed width no longer follows
  the caller's `k`… Arm seeding now uses `max(k, 10)`; the `k` slice remains the only
  consumer of the caller's `k`") ✅, names the flag `recall_relevance_primary` ×2 ✅,
  and covers the budget surface (`RecallResult.budget`, `evicted_count`'s preserved
  meaning), the score surface (`CrystalSummary.score`, "populated in both ranking
  modes") and the importance surface (non-zero cold start, 0.30 ceiling, no migration) ✅.
- **No T2→semantic promotion promise anywhere.** AC-027's node is green, and the
  `TierViolation` advice string actively *denies* promotion ("it stays candidate;
  promotion to a validated/semantic record requires a T1/T0 proposer through the
  corroboration gate"). `grep -rni "promot" mcp-server/src/` surfaces only the
  `PromotionGate` class, the `promote` CLI verb, and `ingest_adapter.py`'s two
  "never auto-promotes" comments. ✅

### R9 — AC-031 RED evidence, authenticated

`red-evidence.txt` claims AC-031 was RED at `89c23d9`. I did not take that on faith:

- `git diff 323229f 89c23d9 --stat` → **one file**, `test_recall_starvation.py`,
  `+82/−0`. The commit is test-only, exactly as claimed.
- The `TestSmallKFetchWidth` class body is **byte-identical** at `89c23d9` and
  `351ba22` (sha256 `132f63fb…f185c5` at both) — the red run and the green run test the
  same code, so the transition is the implementation's doing, not a rewritten oracle.
- Worktree at `89c23d9`, my own run:
  ```
  FAILED …TestSmallKFetchWidth::test_fresh_crystal_returned_at_k3
  1 failed in 3.14s
  captured: recall_ok  after_compose=3 candidates=5 evicted=0 filtered=3 k=3
  ```
  RED, and red for the right reason — `candidates=5` proves the fresh crystal *was* a
  real candidate that the k-gate truncated out, not a setup artefact. The captured
  counters match `red-evidence.txt` line-for-line. Worktree removed afterwards.

---

### Adjudication — AC-017 under attack D

**The documentation exists.** `spec.criteria.md` AC-017's VERIFY text states
`k_applied = min(k_requested, len(before))` "makes this true by construction", and
`spec.md` §Amendment record records AC-017 as "Strengthened / re-subjected. Now pins
`k_applied <= k_requested` by construction".

**I accept the rationale**, with one correction to the criteria text.

*Why I accept it.* DP-R3 chose to make the invariant unfalsifiable-by-that-mutation on
purpose, and that is the stronger engineering answer. The F-V3 defect was a receipt
derived from intent rather than from the act; the fix derives both fields from the
performed slice, which means the specific failure mode (`k_applied=20`,
`k_requested=15`) can no longer be *produced* by deleting the slice. Demanding that
attack D still turn AC-017 red would amount to demanding the bug remain reachable.
AC-016 carries the slice-deletion detection for the pair, and it fires.

*And I verified the gate is not hollow.* The doctrine here is that a gate which cannot
fail on the defect it names is not a gate — so I did not accept "green" as proof of
"by construction". Attack D′ reverted `k_applied` to the intent-derived form and AC-017
went **RED** with `k_applied=8 > k_requested=1`, the exact F-V3 signature. AC-017 gates
the arithmetic it claims to gate; what it no longer gates is the *slice*, which was
never its job.

*The correction (non-blocking).* AC-017's VERIFY text asserts both "true by
construction" **and** "Attack D must turn this node **RED**". Those cannot both hold, and
the shipped, ruled-correct design makes the second false — as R4 measured. The sentence
is a residue of the DP-R3 drafting, not a live obligation, and it misdescribes the gate
for the next reader. It does not affect conformance: the criterion's THEN
(`k_applied <= k_requested`) is satisfied and its node is green. **Recorded as F-V12; a
text-only fix for the next legal amend, not a release blocker.** I am flagging the
criteria file's prose, not the implementation.

---

### New findings (this round)

#### F-V10 — NOTE: with the flag **off**, `budget.k_applied` is the one field still derived from intent

Flag-off returns 7 records while reporting `k_applied = 1` at `k=1` (R5). No slice runs
in that mode, so `min(k, len(before))` describes the `k` that *would* have applied, not
the act — mild irony in the release whose DP-R3 ruling is "derive from the act".

Not a defect and not a criterion failure: frozen **AC-017 binds "any recall in any
configuration"**, and the pre-patch flag-off value (`k_applied = 7 > k_requested = 1`,
which I measured at `89c23d9` in R5) *violated* it. The current value is what AC-017
requires. AC-008 pins the composition *result set*, not the diagnostics, and `budget`
did not exist pre-1.9.0 at all. Recording it so nobody later reads flag-off `k_applied`
as a record count. `truncated_count` is honest in both modes (0 when no slice runs).

#### F-V11 — NOTE: flag-off recall ordering is run-to-run non-deterministic (pre-existing, reduced by this change)

Repeated probes give different orderings for the same store and query under flag-off, at
**both** `89c23d9` and `351ba22` (R5/R7). Source is the narrow-seed graph arm: with
`seed_ids = dense_ranking[:k]` a small `k` concentrates the walk, and the Kuzu expansion
is itself flaky (`neighbor_expand_error: No more tuples in QueryResult` observed
repeatedly, caught and logged as a warning by design). Pre-existing, untouched by this
patch, violates no criterion — and seam 3b *removes* it from the default path, where the
flag-on column is now bit-stable across runs. Worth an issue alongside the unweighted-RRF
follow-up DP-R1 already ordered; not release-blocking.

#### F-V12 — NOTE: AC-017's VERIFY prose contradicts its own by-construction design

See the adjudication above. Text-only; fix at the next legal amend.

*(Carried forward, unchanged: F-V4, F-V5 — AC-015's fixture uses an empty store, so
`k_applied == len(records)` is trivially satisfied there; F-V7; F-V8; F-V9 — the
pre-existing stash on an unrelated branch is still present and is not mine.)*

---

### Verdict — **RELEASE-CLEARED**

Every element of the DP-R4(ii) mandate ran and passed on the final pre-tag HEAD:

- Full suite **900 passed / 2 pre-existing skips / 0 failed**, my own run. ✅
- **32/32** frozen criteria green against recomputed hash `487058986ff2…a861d36`. ✅
- **Attack E fires** — AC-007 RED where it was green at 323229f. **F-V2 closed.** ✅
- **Attack D fires on AC-016** — and the shipped counter now reports the truth (0)
  instead of five phantom drops. **F-V3 closed.** ✅
- **AC-017 accepted as by-construction**, and proven a live gate by attack D′. ✅
- **F-V1's k=1/k=3 starvation is fixed and stays fixed across repeats**, with the
  pre-fix regression independently reproduced by me at `89c23d9`. **F-V1 closed on the
  default path.** ✅
- Flag scope is exactly the five declared reads; C-16's sentinel verified at runtime;
  flag-off fidelity holds by code *and* by measurement. ✅
- Release surface correct: 1.9.0, CHANGELOG complete including the fetch-width line, no
  promotion promise. ✅
- The RED-first evidence for AC-031 is authentic — test-only commit, byte-identical test
  body, reproduced RED by me. ✅

The three MAJOR/MINOR gate-strength findings from the 323229f attestation (F-V2, F-V3)
and the MAJOR behavioural finding (F-V1) are all discharged with evidence, not with
prose. The three new items (F-V10, F-V11, F-V12) are NOTE-level: one is *mandated* by a
frozen criterion, one is pre-existing and reduced by this change, one is a sentence in a
criteria file. None is a criterion failure or an invariant breach, so none blocks the tag.

**Cleared to tag v1.9.0 from `351ba22d619d02d815e015822b2dc54ad4b161de`.**

**Tree left exactly as found:** branch `fix/recall-starvation-36`, HEAD
`351ba22d619d02d815e015822b2dc54ad4b161de`, `git status --porcelain` empty,
`git status --untracked-files=all --porcelain` empty, `git diff 351ba22` empty,
`git worktree list` shows only the main checkout (the `89c23d9` worktree used for R5/R9
was removed and pruned), no stash created by me — `stash@{0}` is the pre-existing entry
already recorded as F-V9.

## Delta-discipline addendum — DP-R5 guards (2026-08-03, orchestrator)

Per deliberation DP-R5 ruling R5-2 (delta discipline, no full re-attestation), covering the change from the attested HEAD `351ba22` to the pre-tag merge ref `07d3af6` (= 351ba22 + squash-merged PR #40 pin + merge bookkeeping):

- **Guard 1 (diff exactness): PASS.** `git diff 351ba22..07d3af6 --stat` = 2 files: `mcp-server/pyproject.toml` (1 line: `"mcp>=1.2.0"` → `"mcp>=1.2.0,<2"`) and `CHANGELOG.md` (+4: the pin bullet relocated into 1.9.0 ### Fixed during conflict resolution). Nothing else.
- **Guard 2 (full CI on the merge ref): PASS.** PR #37 @ 07d3af6 — pytest (container), JSON schema validation, conformance suite (G1-G8 + invariants), install.sh idempotency all green on both event runs (runs 30784798019 / 30784799506). The container pytest job that failed pre-pin (mcp==2.0.0) is green post-pin.
- **Guard 3a (asserted runtime, CI): PASS.** Build log of job 91596212540 records `+ mcp==1.29.0` (<2). The environment claim is asserted from the log, not assumed.
- **Guard 3b (asserted runtime, release image): PENDING — blocks roster entry.** The v1.9.0 OCI image will be probed for `mcp.__version__` < 2 after the release workflow publishes it and BEFORE its digest is recorded in the nexus roster. Result to be appended below.
- **Guard 4 (local fast AC-batch on merge ref): PASS.** 44 passed, 0 failed (75.48s) — the full frozen-criteria node batch (AC-001..AC-032 coverage set).

Context for the record: pin PR #40 ran the same CI fresh-build on plain main + pin only (zero #36 code) — all green with `+ mcp==1.29.0` asserted (job 91595252891) — establishing the break as main's unpinned dependency surface, per DP-R5 R5-1. ESL record: crystalium-pin-mcp-sdk-1x (trivial, archived 2026-08-03).

**Guard 3b result (2026-08-03, post-release): PASS.** `docker run --rm ghcr.io/rynaro/crystalium@sha256:784d21487450796d6e2a0dc8af4713aba60b8996806cbd53436389cfbeaed32c python -c "importlib.metadata.version('mcp')"` → `mcp 1.29.0 | crystalium 1.9.0`, assertion `<2` held. Probed by index digest — the exact identity entering the roster. All four DP-R5 guards discharged.

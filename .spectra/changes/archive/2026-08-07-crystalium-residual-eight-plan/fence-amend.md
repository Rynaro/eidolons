# fence-amend — W-HOP ruling on the `bm25_search` fence (#44)

ruled_by: forge (recorded-ruling amendment hop; autonomous, no escalation)
ruled_at: 2026-08-05
verdict: **ALLOW** (machine-readable sibling: `fence-amend.json`, read by AC-306/S-10)
inputs: crystalium source at `b7f1a47` (fence read in situ: `retrieve.py:603-615`, echo
`:241-242`, `_is_active` `:572-584`, `resolve_sparse_weight` `:216-261`, `bm25_search`
`relational.py:494-542`, second consumer `layers/episodic.py:319`), `forge-rulings.md`
(D3/D6/D7/D9 — binding), `spec.amend-01.md` §B.3/§B.4, `spec.amend-02.md`,
`kupo-critique.md` (K-B13, fence-anchor audit rows), `kupo-critique-02.md` (FORGE-fidelity
§ on the maker's head-only call; K-C-N13). Anchor convention: `path:line` at `b7f1a47`.

---

## 1. Frame

Three questions, all bounded, all falsifiable:

1. **Fence verdict.** Does the amended §4 #44 caller-side top-up (spec.amend-01 §B.4.2)
   honour the recorded ruling at `retrieve.py:605-615` — letter AND spirit — or reverse it?
   ALLOW/DENY; DENY fires S-10 and #44 is re-filed, not half-fixed.
2. **D3/D6 composition.** On Option A's strict-subset path, what does the top-up widen —
   the global head, the per-layer backstop, both, or nothing? RAMZA chose head-only and
   flagged the choice as its own (§B.4.2: "FORGE did not rule this"). Kupo judged it
   "sound as a call, but weak exactly where it matters, and unmeasured."
3. **Scope boundary.** The exact authorised change set, as a checklist, plus what
   constitutes a breach requiring a new hop.

Decision type: CONSTRAINT-SATISFACTION (1, 3) + CONFLICT-RESOLUTION (2). Depth: standard.

## 2. The fence, read in full — what it actually protects

The recorded words (`retrieve.py:609-615`, one sentence, one grammatical subject):

> C-8(ii)/(iii): **the population is resolved ONCE here**, as a PURE-PYTHON filter over
> the crystal dicts already in hand (`bm25_search` returns full rows) — never a status
> predicate on the shared `bm25_search`, and no extra I/O beyond the one bounded
> aggregate below (DP-3, "the existing bounded aggregate", `count_for_export`; no new
> public storage method, per FORGE's ruling).

Echo (`retrieve.py:241-242`, in `resolve_sparse_weight`'s docstring):

> `bm25_search` applies no status predicate (shared method, never filtered).

Read in situ, the sentence's four clauses all modify one thing: **how the D3 selectivity
population is resolved** for the #38 sparse-weight computation — (i) once, (ii) pure-Python
over rows already fetched, (iii) never via a status predicate inside the shared method,
(iv) with `count_for_export` as the only aggregate I/O of that resolution step. The
surrounding code confirms the scope: the sentence sits directly above the
`n_scoped`/`n_sparse_resolved` computation (`:616-636`), and the hoisted `_is_active`
comment (`:564-571`) states the companion purpose — one predicate shared by response
filtering and DP-9(b), "never a second divergent definition."

So the fence protects three things, in order of weight:

1. **The shared read path.** `bm25_search` serves two consumers (`retrieve.py`,
   `layers/episodic.py:319`). A status predicate in its SQL would change the second
   consumer's semantics or fork the method; AC-349 freezes signature and SQL.
2. **The status-policy locus.** What "active" means (status + `t_valid_to` + the flag)
   lives in exactly ONE caller-side predicate. A storage-side predicate would create the
   second divergent definition the comment names.
3. **Bounded resolution cost.** The weight-resolution step adds no per-recall I/O beyond
   the one bounded aggregate.

## 3. Ruling 1 — the fence verdict: ALLOW

### Hypotheses

- **H1 — ALLOW as specified.** Letter and spirit both hold.
- **H2 — DENY.** The "no extra I/O" clause is a whole-recall bound; a caller-side loop
  issuing the same query twice at wider `k` is the status predicate by other means, so the
  spirit is defeated even though the letter survives.
- **H3 — ALLOW with narrowed authorisation.** Letter holds; spirit holds only inside an
  explicit breach fence (bounded widen, single predicate, verbatim comment preservation).

### The letter

The amended top-up adds **no** parameter to `bm25_search`, **no** public storage method,
and **no** status predicate in SQL. It calls the existing method with its existing
signature (`query, layer_filter, k` — `relational.py:494-499`), filters caller-side with
the existing `_is_active`, and leaves `layers/episodic.py:319` untouched. Every named
prohibition holds. AC-349 independently enforces the frozen signature/SQL with a live
red-check. **Letter: holds.** [Evidence tier H — source read at `b7f1a47`; Kupo's own
anchor audit (critique 1, fence table) verified the same lines verbatim.]

### The spirit — H2 steelmanned, then refuted

H2's strongest form: "no extra I/O beyond the one bounded aggregate" read as governing the
recall, so a second `bm25_search` call breaches it; and status-conditional *calling* is a
status predicate "in effect."

Three independent refutations, any one sufficient:

1. **Grammatical scope.** All four clauses share the subject "the population is resolved
   ONCE here." The fenced step is weight-population resolution. The top-up leaves that
   step byte-equivalent in structure: still resolved once, still pure-Python, still one
   bounded aggregate. Only the set of rows in hand widens.
2. **Corpus consistency.** D3 (binding, same authority as the fence's source ruling)
   ruled Option A's strict-subset backstop — up to `len(target_layers)` additional
   `bm25_search` calls — "fence-clean: existing signature, existing filters, bounded
   calls." A whole-recall "no extra I/O" reading voids D3 and Option A itself. A reading
   under which two binding rulings of the same corpus are incoherent is a misreading.
   Likewise it would make D6's live production defect (config.py:333 → server.py:600 →
   silent starvation) structurally unfixable: the fence bars the SQL predicate, AC-349
   bars the storage edit, and H2 would bar the caller-side widen — a fence that forbids
   every possible fix of a defect it did not rule on is not what was recorded.
3. **Purpose fulfilment, not defeat.** The fence pins the *locus* of status-awareness to
   the caller. Given that pin, fetch-wider-and-filter at the caller is the **only**
   remedy shape that exists for a status-censored fetch — the fence *forces* this design.
   The widened call is itself status-blind; the method's behaviour remains a pure
   function of `(query, layer_filter, k)`; the echo's sentence ("shared method, never
   filtered") stays true after the change. Status-conditional *calling* is already the
   shipped W6 design (the response filter is status-conditional caller behaviour around
   the same fetch results); the fence bans the predicate *inside* the method, not
   status-aware behaviour *around* it.

One honest caveat: a caller-side widen that looped until clean, or that grew its own
status logic, WOULD defeat purposes 2 and 3. That is not the amended design (≤ 1 widen,
`HARD_TOPUP_CEILING`, `_is_active` reused) — but it is exactly what the breach conditions
in §5 exist to keep out. So the verdict is **H3's shape with H1's answer**:

**[VERDICT] ALLOW.** The caller-side top-up honours the recorded ruling in letter and in
spirit; it is the design the fence's own logic mandates for this defect class. The fence
was consulted and satisfied, not amended-around. Confidence: **90%** (source-verified,
closed-form; the residual is implementation drift, which the breach fence covers).

Rejected: H2 (refuted on three independent grounds above); plain H1 (spirit-holding is
conditional on the breach fence, so recording ALLOW without it would overstate).

## 4. Ruling 2 — the D3/D6 composition on the strict-subset path

### The gap, precisely

Under D3's Option A, the strict-subset path fetches a global head
(`k = candidate_k * len(_ALL_LAYERS)`), post-filters to `target_layers`, and appends a
per-layer backstop (each at `candidate_k`) when coverage-starved-and-censored. RAMZA's
§B.4.2 choice: the #44 top-up widens **the head only**, never the backstop. Kupo's
finding: K-N12's premise is that the global top is dominated by EXCLUDED layers, so a
head-only widen recovers mostly rows the post-filter discards — near-inert exactly where
the subset path needs it — and **no criterion measures the top-up's efficacy there**
(AC-346/347 run on the default-path corpus; AC-355 measures layer coverage with the
top-up out of scope; AC-348 counts calls). K-C-N13 compounds it: on the subset path
`len(sparse_ranking)` is post-filtered-head + tail, not the head's raw count, so the
trigger observable itself must be captured at the call sites.

### Hypotheses

- **H-A — head-only (RAMZA).** Coherent with K-B13(c) (the signal belongs to the head);
  near-inert on the subset path; ships `fired: true` with structurally absent recovery —
  the F-V3 counter-honesty defect as *designed* behaviour.
- **H-B — backstop-only on the subset path.** Fixes the K-N12 regime; abandons the
  regime where target layers dominate a censored head and the backstop never fires.
- **H-C — per-fetch locus rule.** Widen each fetch that is *individually*
  censored-and-dirty (its own raw count reached its own requested `k`, and ≥ 1 row of its
  candidate-set contribution fails `_is_active`), at most once per fetch. Degenerates to
  H-A exactly on the default and single-layer paths (one fetch); on the subset path it
  covers both regimes at their locus.
- **H-D — suppress on the subset path.** Explicit, documented inertness; residual defect
  survives on that path; honest but closes #44 only path-scoped.

### Ruling

**H-C.** The top-up widens the fetch at the starvation locus, per-fetch:

- **Default and single-layer paths:** RAMZA's choice is UPHELD verbatim — there is one
  fetch; head-only and H-C coincide; §B.4.2 stands as written.
- **Strict-subset path:** RAMZA's head-only exclusivity is OVERRULED. The head widens
  when *it* is censored-and-dirty (dirtiness measured on its post-filtered contribution —
  inactive excluded-layer rows are discarded regardless of status and count for nothing);
  each backstop call widens when *it* is censored (raw == `candidate_k`) and dirty. Never
  a widen of one fetch decided by another fetch's signal — this is K-B13(c)'s "property
  of the fetch" principle applied *per fetch*, which is the very ground Kupo cited when
  judging head-only sound. H-C therefore strengthens, not contradicts, the principle
  RAMZA's choice rested on.
- **Precedent, not invention:** D1's terminal branch already defines this exact shape
  ("≤ 1 widened call per censored-and-dirty layer, ≤ `len(target_layers)` total") for the
  contingency where Option A dies. H-C is the composition of D3, D6/D7, and that recorded
  shape. It is an **open amendment of D3's AC-348 "≤ 1" clause**, which becomes
  path-scoped: exact `≤ 1` on default/single-layer; `≤ 1 + len(target_layers)` on strict
  subsets, each widen individually gated.
- **Censoring signal:** unchanged from B.3.2 — it remains the head's, recomputed only
  when the head itself widens; backstop widens are coverage appendages and never touch
  it. Per K-C-N13, W-45 must capture per-fetch raw counts at the call sites (the
  aggregate `len(sparse_ranking)` is not the head's raw count on this path); W-44's
  triggers read those captures. No new storage surface is involved in any of this.
- **Explain honesty:** `explain.fusion.sparse_topup` becomes
  `{fired, widened_fetches: [{fetch: "head"|"backstop:<layer>", k_initial, k_final,
  n_inactive_observed}]}` — every field derived from fetches actually performed (F-V3).

### What can FAIL on this choice — the mandated instrument

A NEW node, normative name **`test_subset_status_topup_recovers_active_hits`**, in
`test_sparse_status_topup.py`: 2-layer strict subset (`layers=["semantic","procedural"]`,
AC-355's shape), episodic (excluded) rows dominating and censoring the global head (D1's
TF/doc-length separation mechanism), the semantic backstop call censored at `candidate_k`
by deprecated rows all ranking above one planted active target,
`recall_active_only=True` asserted off the instance. **RED under head-only** (the widened
head returns more excluded-layer rows; the deprecated-censored backstop call is never
widened; the target is unrecoverable), **GREEN only with the backstop-locus widen**. It
discriminates H-A from H-C by construction, and it can fail on the defect it names.
AC-348's per-path spy and AC-356's flag-off inertness control complete the measurement
set. The AC id is assigned in amend-03.

**Stated plainly per the hop's own instruction:** until that node's AC exists in the
plan, the strict-subset composition is **UNMEASURED** — no currently-written criterion
can fail on it. That is why the node is mandatory, not advisory. If the discriminating
fixture cannot be built (S-14/rule-(f) discipline applies to its pre-fix RED), route to
**S-13** and take the bounded fallback: **suppress the top-up on the strict-subset path
explicitly** — documented inertness, named in the #44 closing comment, follow-up issue
filed — never ship the locus rule unmeasured on that path, and never relax AC-348 or
AC-355 to make it fit.

Confidence: **80%** — the locus rule is derived, not measured (the same epistemic grade
as D3's backstop, 82%); the mandated node is what converts it from argued to measured
before it ships.

## 5. Ruling 3 — scope boundary

**Authorised** (the implementer's and checker's shared checklist — normative copies in
`fence-amend.json.authorised_changes`):

1. `retrieve.py` only, plus `test_sparse_status_topup.py` (incl. the new subset node),
   in the D7 two-commit shape.
2. `_is_active` (`retrieve.py:572-584`) is the ONLY status predicate; no reimplementation.
3. Per-fetch trigger: censored (own raw count ≥ own requested `k`) AND dirty (≥ 1
   contribution row fails `_is_active`).
4. ≤ 1 widen per fetch, existing `bm25_search` signature only,
   `k_wide = min(k_requested + n_inactive_observed, HARD_TOPUP_CEILING)` with the
   ceiling a `retrieve.py`-local constant.
5. BM25-order-preserving merge within the fetch's role; dedupe.
6. Censoring recompute against the widened head only (K-B13(c)); backstop widens never
   touch the signal.
7. `explain.fusion.sparse_topup` per §4 above, F-V3-derived.
8. Structurally inert when `recall_active_only=False`; AC-356 asserts it.
9. Fence comments at `:605-615` and `:241-242` survive verbatim (adjacent cap/raw
   formula descriptions may be updated by W-45 under its own grant to match B.3.2 —
   never the fence sentences).
10. Zero edits to `relational.py`, `layers/episodic.py`, or any storage module.

**BREACH — new W-HOP required before any code** (normative copies in
`fence-amend.json.breach_conditions`): any `bm25_search` parameter/SQL/signature change;
any new public storage method; any status/temporal predicate entering SQL; a second
status predicate; any edit to `layers/episodic.py:319`; editing or weakening either
fence comment; more than one widen per fetch, loop-until-clean refetching, or
cross-fetch signal use; the top-up firing with the flag off; a censoring recompute
reading anything but the fetch actually performed. §B.4.2's own sentence stands: an
executor preferring `status_filter=` on `bm25_search` breaks the fence and must obtain
an explicit amend first.

## 6. Reversal conditions

- **[REVERSAL-CONDITION]** If the only green path through AC-345/346/348/355/356 + the
  new node requires any breach-list item, this ALLOW is void, **S-10 fires**, and #44 is
  re-filed rather than half-fixed.
- **[REVERSAL-CONDITION]** If the discriminating node shows the backstop-locus widen
  breaking AC-355 or the stated budget, the composition ruling falls back to explicit
  subset-path suppression — never to relaxing AC-348/AC-355.
- **[REVERSAL-CONDITION]** If `Config.recall_active_only`'s default flips to False,
  D6's classification reverts (D6's own reversal); the fence verdict is unaffected.

## 7. Handoffs

- **→ RAMZA (amend-03):** fold in the AC-348 per-path restatement, the new node + AC id,
  the explain-schema extension, and the K-C-N13 capture obligation as W-45/W-44 GIVEN
  text. This ruling amends D3's AC-348 clause openly; nothing else in D3/D6/D7 moves.
- **→ W-44 implementer:** the §5 checklist is the entire grant.
- **→ Kupo:** the new node is the discriminating instrument for the composition — its
  pre-fix RED (under a head-only stub) is the rule-(f) positive-capability evidence.

*FORGE. Fence consulted and satisfied; ALLOW recorded; the composition ruled per-fetch
with its own failure instrument mandated; S-10 does not fire.*

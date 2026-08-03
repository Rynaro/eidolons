---
eidolon: forge
kind: deliberation
seat: HUMAN-DECISION (delegated; rulings BINDING)
change_id: crystalium-recall-starvation-36
esl_tier: full
spec: spec.md (ramza 1.0.0)
target: Rynaro/crystalium @ af24493 (v1.8.1)
decided_at: "2026-08-02"
methodology: FORGE 1.10.0 (F→O→R→G→E per DP; evidence spot-checked at source)
---

# Binding deliberation — crystalium#36 recall starvation

Evidence verification performed before ruling (source wins over spec where they could
diverge; no divergence found):
`composer.py:122-134` (`_eviction_key = (importance, last_access, id)` asc),
`schemas.py:245` (`total_tokens: int = Field(ge=0, le=3500)`),
`schemas/recall-result.v1.json` (`additionalProperties: false`; no `explain` property;
`maximum: 3500`; `score` described as "Retrieval relevance score from the Aetheryte
hybrid retrieval"), `config.py:155-215` (per-faculty bool + "EARNED ON (T2)" /
"ablation-or-revert" convention), `importance.py:29,65-107` (legacy weights
0.25/0.30/0.25/0.20 — the measured 0.525 cold start is arithmetically consistent:
0.30·1.0 recency + 0.25·0.5 neutral outcome + 0.20·0.5 novelty),
`gate.py:228` + `procedural.py:88,133` ("T2 ALWAYS stays 'candidate' (G2)").

## 1. RULINGS

| DP | Ruling | Operative instruction to the implementer |
|----|--------|------------------------------------------|
| DP-1 | **O1 + top-k gate** (H-E-prime) | `_eviction_key = (getattr(rec,"relevance_score",0.0), importance, last_access, id)` ascending; truncate `filtered_ids` to `k` before building composer records. |
| DP-2 | **B — flag, default ON** | `Config.recall_relevance_primary: bool = True`; gates seams 3+4+5 (top-k gate, eviction key, response ordering) as ONE unit; commit-side changes, `score`, `budget`, `explain` keys, and the k clamp are NOT gated. |
| DP-3a | **Yes — k is a hard cap** | Enforce `len(result.records) <= k` via the seam-3 truncation. |
| DP-3b | **No scaling** | `total_cap` stays 3500, `Config.slots` unchanged; document that k is an upper bound subject to the fixed token budget. |
| DP-3c | **C — both** | Always-present `RecallResult.budget = {total_cap, slots, k_requested, k_applied, truncated_count}`; `k_applied` + `truncated_by_k` also added to `explain`. |
| DP-3d | **Yes — clamp [1,100]** | At `server.py:970-973` and `__main__.py:363`: numeric k clamped to [1,100]; non-coercible k falls back to the default (10), never an error. |
| DP-4 | **C — importance_fn clamped** | Shared helper `initial_importance(...) = min(importance_fn(stub, now=now), 0.30)`; ceiling is a named constant (`COLD_START_IMPORTANCE_CEILING = 0.30`); six call sites. |
| DP-4a | **utility.importance only** | Do not write `memory_dynamics` — that is Dream's writer (`dream/worker.py:842-843`); the composer fallback (`retrieve.py:461-473`) reads `utility.importance` for fresh crystals. |
| DP-4b | **No backfill — confirmed acceptable** | Existing 0.0 rows are rescued by DP-1 relevance, which is ungated on the commit side; no migration, per mission P0-3. |
| DP-4c | **Yes — echo importance** | The commit result's `importance` field reports the computed value (AC-007's surface). |
| DP-4d | **execution.py 0.5 stays** | Leave `execution.py:226,368` untouched; add a one-line comment marking 0.5 as the deliberate "currently active work" special case, distinct from the cold-start helper. |
| DP-5 | **A — raw RRF score** | Pass the fused RRF value as `score=` at `retrieve.py:561-572`; populate in BOTH flag modes; do NOT add a `rank` field. |
| DP-6 | **A — descending relevance** | Emit `records` sorted by `relevance_score` desc, `id` asc tiebreak (default mode only; flag-off restores legacy order); document in `recall()` docstring + tool description. |
| DP-7 | **A — separate truncated_count** | `evicted_count` keeps its exact current meaning (token-budget drops only); k-truncation counted in `budget.truncated_count` + `explain.truncated_by_k`. |
| DP-8 | **A — > slot_cap, advisory-only** | Fire when `summary_tokens > Config.slots[slot_for_layer]`, layer-aware, composer's own tokenizer; never a rejection; clean path byte-identical. |
| DP-9 | **A — 1.9.0** | Minor bump, conditional on DP-2=B actually shipping (see CONDITIONS C-10); `mcp-server/pyproject.toml:9` is the single source. |
| DP-X | **Yes — fix schema drift in this release** | `schemas/recall-result.v1.json` gains `budget` (strict, five fields) AND the missing `explain` (object, `additionalProperties: true`, marked diagnostic/unstable); add a jsonschema round-trip test of a live `RecallResult`. |

## 2. Per-DP reasoning

### DP-1 — O1 (relevance-primary key) + top-k gate

**Ruling: O1, applied together with the seam-3 top-k gate.** RAMZA's 65% made this
genuinely open, with O3 within noise (85.5 vs 85.0). What decides it: mission P0-1
demands the #36 fix hold *by default*, and only O1 makes fresh-crystal survival a
**provable** property. Under O3 the bug reproduces *inside* the top-k window — in a
real store the dense arm surfaces topically-weak neighbors into the top-k, and when
the slot overflows, Pass-1 eviction (`composer.py:223-245`) still pops the rank-1
importance-0.0 fresh crystal before a rank-5 stale one at 0.24. O3 fixes #36
probabilistically; O1 fixes it deterministically, and AC-004 is only red→green
provable under O1. The `getattr(..., 0.0)` default means all existing `_Rec` stubs
tie at relevance 0.0 and the old `(importance, last_access, id)` assertions in
`test_composer.py` remain meaningful — the old contract survives as the
equal-relevance case, which bounds O1's blast radius to roughly O3's plus one
function.

- Rejected O3: smallest blast radius, but not a deterministic fix — fails the
  standard the mission sets; retained as the fallback only if the composer change
  proves unshippable (it will not; see C-2).
- Rejected O2: band width `B` is an unmeasured magic knob (repo convention demands
  an eval to earn knobs, `config.py:159-166`) and still does not guarantee rank-1
  survival — complexity without determinism.
- Rejected O4: RRF is unnormalised; min-max over the live candidate set makes the
  key unstable call-to-call and destroys the reproducibility contract
  (`composer.py:6-11`). Weakest scored hypothesis (60.0).

### DP-2 — B: `recall_relevance_primary`, default True

**Ruling: B.** C is rejected outright — a default-OFF fix violates mission P0-1, and
its earn-it-on eval cannot even measure the behaviour (the retrieval_gate corpus
never triggers eviction). Between A and B: the repo's convention is explicit and
repeated — every behaviour-changing retrieval faculty ships behind its own `Config`
bool with a recorded rationale — and R-1 (unknown real corpora regress) is
med-likelihood/high-impact with the flag as the only cheap mitigation. The flag's
cost (one field, four `Config.__new__` helper updates, one dual-path test) is small
and bounded. **Flag scope is part of this ruling:** `False` reverts seams 3/4/5 as
one unit — the honest "give me pre-fix result sets" lever (AC-017). The additive
response fields, the cold-start commit change, and the k clamp stay live in both
modes: they are diagnostics and input validation, not ranking behaviour, and gating
them would double the response contract for nothing.

- Rejected A: defensible, but it discards the one-line rollback for the highest-impact
  risk in the table and breaks an established repo convention without cause.
- Rejected C: violates mission P0-1; self-defeating eval gate.

### DP-3 — k/budget semantics

**3a — yes, hard cap (settled).** It is what the tool description already promises
(`"k": "Max records to return"`, `server.py:203-206`) and what `RecallRequest.k`
(`ge=1, le=100`) already implies. Anything else preserves a documented lie.

**3b — no scaling (settled).** C is mechanically blocked by two independent hard
validators (`schemas.py:245` `le=3500`; schema `maximum: 3500`) plus the P0-9
assertion at `composer.py:269-272` — a scaled budget raises `ValidationError` inside
`recall()`. B (slot scaling) has no measured curve behind it and silently changes
`slot_breakdown` semantics. Mission P0-3 also forbids touching this.

**3c — C, both (was genuinely open at 60%).** The runner-up (explain-only) loses on
two grounds. First, it recreates the exact discoverability failure this issue is
about: the reporter could not see the budget without already suspecting it, the same
failure mode as the undiscoverable `provenance.source` enum. Second, R-6's mitigation
("a caller reading only `evicted_count` cannot tell k-truncation happened") only
works if `truncated_count` is visible *by default* — an explain-only budget defeats
DP-7. The cost of always-on (a small object on every response, and strict validators
against the published schema) is neutralised by DP-X landing in the same release.

**3d — yes, clamp [1,100] (settled).** Today's `max(0, int(k))` makes `k=0`
reachable, which becomes a *new* footgun (silent empty result) the moment k
truncates — the fix would introduce a bug. Clamp at both entry points; a
non-coercible k (AC-011's `"garbage"`) falls back to the default 10 rather than
erroring — recall is a read path and should degrade, not reject.

### DP-4 — C: importance_fn clamped to a 0.30 ceiling

**Ruling: C**, overturning RAMZA's A-with-documented-guard, but *not* toward B as
RAMZA predicted. The observation that carries it: `utility.importance` written at
commit is a **bridge value** — under the default config Dream recomputes
`importance_fn` and persists `memory_dynamics.evb` at first sweep
(`dream/worker.py:836-843`), which the composer then prefers. But under the legacy
config (`evb_enabled=False`), `persist_dynamics` is off, so the commit-time value is
**durable** — option A's 0.525 would be a *permanent* starvation inversion, not a
transient one. That elevates R-5 from "document it" to "make it mechanically
impossible", and repo memory is unambiguous that a documented caveat is not a guard
("gates are where defects hide"; "fail-open hides dead kernels"). C is A wherever A
is right: at EVB cold-start values (0.240–0.258) the clamp never binds, so the
default path is byte-identical to A — scorer-consistent, novelty-aware, equal to
what Dream would compute anyway. On the legacy path C caps at 0.30. The ceiling is
not arbitrary: it is derived from the measured band — it keeps a fresh crystal below
a proven-useful record (5 accesses, outcome 0.9, 7 days = 0.403) and inside the
reporter's live band (0.15–0.42). Name it, and test the cold-start value under
**both** scorer configs.

- Rejected A (bare): permanent inversion under legacy config; a comment is not a guard.
- Rejected B: discards `novelty_at_write` (the only real signal available at commit),
  creates a second source of truth that diverges from the scorer as EVB weights
  evolve, and buys no safety C doesn't already have.
- Rejected D: leaves `importance: 0.0` on every commit result (the reporter's primary
  tell), leaves the composer's secondary term degenerate on fresh corpora, and
  ignores the issue's explicit ask.

**Sub-rulings.** (a) `utility.importance` only — `memory_dynamics` is Dream's writer;
seeding it collides for no gain since the fresh-crystal fallback already reads
`utility.importance`. (b) No backfill, confirmed acceptable — old rows are rescued by
DP-1 relevance, which is live on the commit side regardless of the DP-2 flag.
(c) Echo the computed value in the commit result — it is the diagnostic surface the
reporter actually used, and AC-007 asserts it. (d) `execution.py`'s 0.5 stays — it is
a deliberate "currently active work" privilege, not a cold-start estimate; the fact
that 0.5 exceeds the 0.30 ceiling is intentional (active work should survive
composition) and gets a one-line comment saying exactly that.

### DP-5 — A: raw RRF score

**Ruling: A.** The published schema already defines the field as "Retrieval relevance
score from the Aetheryte hybrid retrieval" — literally the raw fusion value; A makes
the code match the published contract with zero schema change. Raw RRF is stable
across calls and preserves magnitude, which is what the reporter said they needed
("could not inspect ranking directly"). Populate in both flag modes — the RRF fusion
runs in both, and suppressing it in legacy mode would reduce diagnosability exactly
where an operator running flag-off needs it most.

- Rejected B (normalised): degenerates to 1.0 on single-record results; not
  comparable across calls.
- Rejected C (rank): discards magnitude; rank is already implicit in DP-6's ordering.
- Rejected D (eviction key): leaks an internal tuple into a public float contract.
- Also ruled: **no separate `rank` field** — `CrystalSummary` is `extra="forbid"`,
  the emitted order already conveys rank, and the contract should grow by the minimum
  that closes the issue.

### DP-6 — A: descending relevance, id tiebreak

**Ruling: A.** Today's order is an artefact (slot-insertion order, or *ascending*
eviction key when Pass 2 fires — least-important first, actively perverse for a
top-down reader). Once `score` is populated, "unspecified" (D) is untenable: clients
will sort by score and file the mismatch as a bug. Descending `relevance_score` with
`id` asc tiebreak makes AC-006 hold by construction and keeps the order reproducible.
Applies to the default mode; flag-off restores the legacy artefact order (that is
what "pre-fix behaviour" means). The known consequence — `test_retrieval_gate.py`'s
`context_pass is False` assertion depends on ordering — is handled by C-6: a flip is
a finding for the checker, never a test edit.

- Rejected B/C: B is the artefact being fixed; C orders by a key whose primary term
  is relevance anyway (collapses to A) while leaking key shape.

### DP-7 — A: separate truncated_count

**Ruling: A.** `evicted_count` has a documented, narrow meaning ("candidates evicted
to satisfy the token budget") that the reporter used as live diagnostic evidence
(`2..14`); folding k-truncation in (B) would redefine a field mid-flight, inflate it
on every large-corpus recall, and mask real budget pressure. C discards the signal.
The new counter lands inside DP-3c's `budget` object (default-visible — this is R-6's
mitigation) with `truncated_by_k` in `explain` for depth.

### DP-8 — A: > slot_cap, layer-aware, advisory-only

**Ruling: A.** It fires on the real case (the reporter's ~1500-token summary against
the 800-token episodic cap) and only on genuinely oversized summaries. B
(`>0.5·cap`) would fire around 400 episodic tokens — near-normal for this corpus
(live probe: two records totalling 544) — producing advisory fatigue and routinely
breaking the clean-path byte-identity that `test_diagnosability.py:312` locks. C
(3500) never fires; D drops a signal the reporter explicitly requested. Advisory
only — the reporter proved shrinking the summary did not restore retrievability, so
size is a hint, never a rejection (do not import the CLI's hard-reject posture).
Tokenizer hardening is C-4.

### DP-9 — A: 1.9.0

**Ruling: 1.9.0**, valid because DP-2 landed B. Nothing is removed: `score` and
`budget` are additive, the ranking change is a correction of documented behaviour
(`"k": "Max records to return"`), and the repo's own precedent
(`recall_completion=True`, which changed every recall's result set, shipped in a
minor) is directly on point. With the flag, an operator has a one-line revert, which
is what makes "minor" honest. C (1.8.2) is rejected — a patch that adds response
fields and changes result sets misstates the release to the dual-roster. B (2.0.0)
is rejected *conditionally*: it becomes the correct answer if and only if the flag is
dropped during implementation (C-10).

### DP-X — fix `schemas/recall-result.v1.json` in this release

**Ruling: yes, mandatory, same release.** This is forced by my own 3c/7 rulings:
`budget` is always-present, and the published schema says `additionalProperties:
false` — shipping 1.9.0 without the schema fix would make **every** recall response
formally invalid against the published contract, upgrading a latent drift (missing
v1.6 `explain`) into a total one. Scope: add `budget` strictly (all five fields
enumerated, `additionalProperties: false` on the sub-object); add `explain` as a
loose object (`additionalProperties: true`, description marking it
diagnostic/unstable) so evolving diagnostic keys do not re-drift the schema; keep the
`v1` filename (all changes additive; `score` was already declared, `total_tokens`
bounds unchanged). And because this schema drifted precisely *because nothing checks
it*, the fix must include a jsonschema round-trip test of a live `RecallResult`
(C-7) — repo memory: a gate that cannot fail on the defect it names is not a gate.

## 3. Cross-DP consistency chain (verified)

1. **Mission P0-1 → DP-2=B → DP-9=1.9.0.** The fix is default-on (flag defaults
   True), so no consumer changes a call to benefit — P0-1 holds. DP-9's minor bump
   was explicitly conditional on DP-2=B; the condition is satisfied. Contrapositive
   recorded as C-10: drop the flag → 2.0.0.
2. **DP-1=O1+gate → test surface.** The composer contract changes, so
   `test_composer.py::TestG6EvictionDeterministic` is extended (old assertions
   survive as the equal-relevance case via the `getattr` default), and AC-001,
   AC-003, AC-004, AC-006 are the load-bearing regression criteria; AC-017 is
   load-bearing (not deleted) because DP-2=B. Under O3 the composer tests would have
   been untouched and AC-004 unprovable — that is the fork I closed.
3. **DP-3c=C + DP-7=A → DP-X mandatory.** Always-on `budget` carrying
   `truncated_count` collides with the published schema's `additionalProperties:
   false`; therefore the schema fix cannot be deferred to a later release, and it
   sweeps in the pre-existing `explain` omission that 3c's new explain keys
   (`k_applied`, `truncated_by_k`) would otherwise widen.
4. **DP-5=A + DP-6=A → coherent client contract.** The emitted order sorts by the
   same value exposed in `score` (raw RRF), so AC-006 ("non-increasing score order")
   is true by construction and no client-observable order/score mismatch exists in
   the default mode. Flag-off mode documents legacy ordering (AC-017), with `score`
   still populated for diagnosis.
5. **DP-4=C → mission P0-3 + non-scope respected.** Writes `utility.importance`
   only, new commits only — no migration, no Dream/`memory_dynamics` collision; the
   clamp closes R-5 mechanically instead of by comment.
6. **DX-2 → mission P0-4.** The advice wording is bounded by the verified G2
   invariant (`gate.py:228`): names the procedural-candidate fallback, states caller
   identity is host-set at server start, promises no promotion.

## 4. CONDITIONS (guards the implementation must satisfy for these rulings to hold)

- **C-1 — Flag scope.** `recall_relevance_primary=False` reverts exactly seams 3+4+5
  (top-k truncation, relevance-primary eviction key, descending-relevance ordering)
  as one unit. `score`, `budget`, `explain` additions, the k clamp, and all
  commit-side changes (cold-start importance, advisories, description strings)
  remain active in both modes. AC-017 is kept and tests the flag-off path.
- **C-2 — Degradation.** `_eviction_key` reads relevance via
  `getattr(rec, "relevance_score", 0.0)`; the defence-in-depth `try/except` around
  `composer.compose()` (`retrieve.py:499-514`) and the assertion at
  `composer.py:269-272` stay intact (R-7).
- **C-3 — Cold-start helper.** One shared helper (six call sites, zero copies);
  `COLD_START_IMPORTANCE_CEILING = 0.30` as a named constant with a comment deriving
  it from the measured band; tests assert the commit-time importance under **both**
  `evb_enabled=True` and `evb_enabled=False` (closes R-5 mechanically).
- **C-4 — Advisory tokenizer safety.** The oversized-summary advisory reuses the
  hardened module-level tokenizer (`composer.py:99`, post-#32 fix); any tokenizer
  exception skips the advisory and never fails or delays the commit.
- **C-5 — RED-first proof.** AC-001, AC-002, AC-004, AC-005, AC-007 demonstrated
  failing at `af24493` before the fix lands; failing output recorded in the verify
  artefact.
- **C-6 — Eval integrity.** `retrieval-gate` run before and after; both JSON outputs
  in the PR body; `BENCH-NOTES.md` §W5(i) updated. A flipped `completion_pass` or
  `context_pass` is a checker finding — no assertion may be edited to green it.
  `evb_gate`, `forgetting_gate`, `dream_gate` re-run (uniform baseline shift —
  verify, do not assume).
- **C-7 — Schema is checked, not just fixed.** Add a test that round-trips a live
  `RecallResult` (one plain, one with `explain=true`) through `jsonschema.validate`
  against `schemas/recall-result.v1.json`.
- **C-8 — Config helpers.** The new `Config` field is assigned in all four manual
  `Config.__new__` test helpers (`test_aetheryte.py:42`, `test_composer.py:73`,
  `test_dream_worker.py:34`, `test_dream_scheduler.py:41`) in the same commit that
  adds the field (R-3).
- **C-9 — DX-2 wording gate.** Every clause of the new `TIER_VIOLATION` advice is
  verified against `gate.py:216-265`, `procedural.py:126-134`, `server.py:102-122`
  before merge; the string must not state or imply T2→semantic promotion (mission
  P0-4); `reason_code` stays `"TIER_VIOLATION"`.
- **C-10 — Version contingency.** If implementation drops the DP-2 flag for any
  reason, DP-9 flips to 2.0.0 automatically — no re-deliberation needed; any other
  deviation from these rulings returns to FORGE.
- **C-11 — k normalisation.** Numeric k clamped to [1,100] at both entry points;
  non-coercible k falls back to the default (10) rather than raising (AC-011's
  `"garbage"` case).

## 5. ESCALATIONS

None. Every docket item, including all sub-questions, landed on a ruling within the
verified evidence.

---

## Post-verification rulings (2026-08-02)

Supplementary BINDING docket after vigil's VERIFIED-with-notes attestation
(`verification.md`, HEAD `323229f`, 30/30 frozen ACs pass, 5/6 gate attacks fired).
Evidence base: vigil's own reproductions — the F-V1 four-cell k-table (real embedding
stack, clean per-cell stores), the attack-E green with seam 5 deleted plus the direct
composer probe proving seam 5 is load-bearing under eviction, and the attack-D
phantom-diagnostics result (`k_requested=15, k_applied=20, truncated_count=5` with no
truncation performed).

### RULINGS (R-docket)

| DP | Ruling | Operative instruction to the implementer |
|----|--------|------------------------------------------|
| DP-R1 | **(b) — decouple fetch width from response cap now, flag-gated (seam 3b)** | When `recall_relevance_primary` is on, every arm-seeding use of raw `k` in the retrieval pipeline (at minimum `seed_ids = dense_ranking[:k]`, `retrieve.py:355`, and the completion arm's seed set if it reads raw `k`) uses `fetch_width = max(k, FETCH_WIDTH_FLOOR)` with `FETCH_WIDTH_FLOOR = 10` (named constant; matches the existing `candidate_k` floor and the default `k`). The `[:k]` response slice alone consumes caller `k`. Flag-off retrieval byte-identical to `323229f`. New regression test: vigil's F-V1 scenario at `k=3`, flag on, fresh crystal returned — RED at `323229f`, GREEN after; enters as a new AC via the C-13 amend batch. Open a follow-up issue for the untouched pre-existing root (unweighted RRF lets a 3-arm graph neighbour outvote a 2-arm exact lexical match) — NOT in this release. |
| DP-R2 | **(a) — amend + strengthen now; re-verify AC-007's node** | Legal path only: `ramza-freeze --amend --reason` + regenerate `change.json` `acceptance_checks`; maker strengthens `TestOrdering`'s fixture so eviction fires (vigil's probe shape: slot cap forcing ≥1 eviction, four records at relevance 0.9/0.5/0.1/0.05); checker repeats attack E (delete seam 5) and must observe RED before restore. No silent edit to `spec.criteria.md`. |
| DP-R3 | **(a) — derive from the real slice, now** | Compute `truncated_count` and `k_applied` from the performed slice, not pre-slice intent: `truncated_count = len(before) - len(after)`, `k_applied = min(k_requested, len(before))`, so `k_applied <= k_requested` holds by construction. Strengthen the AC-016/017 oracles so attack D (slice deleted, counter kept) goes RED — assert record-count/`truncated_count`/`evicted_count` consistency, minimum `k_applied <= k_requested`. Re-run AC-015..018. |
| DP-R4(i) | **Release stays 1.9.0** | Nothing is tagged; R1-R3 fold into the same unreleased 1.9.0. R1(b) is flag-gated and additive; DP-9's condition (DP-2=B genuinely wired, per vigil's Step-5 audit) holds. CHANGELOG's 1.9.0 block gains one line on fetch-width decoupling. |
| DP-R4(ii) | **Full-suite re-verify + five targeted nodes, pre-tag** | vigil, fresh context, appends to `verification.md`: (1) full `make test`; (2) the frozen VERIFY batch against the amended criteria (new hash recorded); (3) attack E repeated → RED expected on strengthened AC-007; (4) attack D repeated → RED expected on strengthened AC-016/017; (5) the F-V1 four-cell probe re-run (`k∈{1,3,5,10}` × flag on/off) — flag-on returns the fresh crystal at every `k`, flag-off column unchanged; plus the flag-scope grep audit re-run (read sites now include seam 3b). |
| DP-R4(iii) | **Close the D3 trap now — None-sentinel** | `Composer.__init__(..., recall_relevance_primary: bool \| None = None)` falling back to `config.recall_relevance_primary` when `None`; both existing call sites keep their explicit kwarg (behaviour byte-identical); a future third call site can no longer produce the half-gated seams-4+5-without-seam-3 mode. |

### Per-DP reasoning

**DP-R1 — (b), not (a)/(c).** Three things carry it. First, decoupling is not a
patch bolted on post-verification — it *completes DP-3a*: once `k` means "response
cap", the ranking universe must be k-independent, and `seed_ids = dense_ranking[:k]`
makes arm membership depend on caller `k`, contradicting the semantics this release
ships. Converging small-k rankings onto the well-tested default-k=10 ranking is
strictly variance-reducing. Second, the reporter's own usage is k∈{3..15} — shipping
a release titled "fix #36" that excludes the fresh crystal at k=3 in a scenario the
checker reproduced on the real stack, defended only by a "k>=5 recommended" doc
line, is a documented caveat standing in for a guard, which this campaign's doctrine
rejects (the same reasoning that decided DP-4). The coordinator's nuance is real —
flag-off "returns it at k=3" only because it ignores `k`, and the true baseline
starved fresh crystals at every `k` in the reporter's store — but "no worse than a
broken baseline" is not the bar; P0-1's spirit is retrievability by default, and
k=3 is a default-shaped call. Third, the frozen-AC risk of (b) is bounded and
checkable: AC-002/003 (cap) live in the response slice, untouched; AC-001 uses k=10
where `max(10,10)` is byte-identical; AC-008/009 (flag-off fidelity) are protected
because seam 3b sits under the same flag — flag-off keeps `dense_ranking[:k]`
verbatim. The floor is not a new magic number: 10 is already the fetch floor
(`candidate_k = max(k*3, 10)`) and the shipped default `k`.

- Rejected (a): a recommendation string cannot fire; it would be the release's only
  defence on a MAJOR finding.
- Rejected (c) alone: defers a known, cheaply-fixable exclusion into shipped
  behaviour. Its issue-opening half survives inside (b)'s ruling for the deeper
  unweighted-RRF defect, which genuinely is out of scope (pre-existing, needs eval
  evidence, touches fusion at all `k`).

**DP-R2 — (a).** Not a close call. The doctrine — a gate that cannot fail on the
defect it names is not a gate — is the reason this campaign exists, and F-V2 is the
textbook case: vigil proved seam 5 is load-bearing (removal inverts output to
*ascending* relevance under eviction, the most misleading possible order) while its
named gate stays green. Shipping (b) leaves the release's headline behaviour
("most-relevant first") guarded by nothing a refactor would trip. The fix is fully
prescribed (vigil's probe is the fixture), the amend path is tamper-evident by
design, and re-verification is one node plus one repeated attack.

- Rejected (b): the exact species of silent failure "gates are where defects hide"
  documents; hours now vs a silent ordering inversion later is a decisive asymmetry.

**DP-R3 — (a).** The field exists because the reporter needed diagnostics that do
not lie; under attack D it reported five drops that never happened and
`k_applied > k_requested`. That is the "lockfile can lie" species — a receipt
derived from intent instead of the act, defeating its own diagnostic purpose. The
fix is arithmetic-only, self-contained in the seam-3 block, and makes the counter
true by construction; the strengthened oracle turns attack D into a firing gate for
AC-016/017 as well.

- Rejected (b): ships a diagnostic that is only coincidentally correct, in the
  release that exists because silent incorrectness went undiagnosed.

**DP-R4 — sequencing.** (i) 1.9.0 stands: nothing has shipped, all three fixes land
pre-tag, R1(b) is additive and flag-gated, and DP-9's condition (the flag, verified
genuinely wired by vigil's Step-5 audit) is intact. (ii) Full suite plus targeted
nodes, not targeted-only: the R1/R3 diffs touch `retrieve.py`'s hot path — the file
with the repo's most recent fragility history (R-7, the v1.8.1 crash) — and the
full suite costs ~13 minutes against a release-blocking risk profile;
"targeted-only" optimises the wrong scarce resource. The F-V1 probe re-run is
mandatory because the new small-k AC's unit fixture approximates a mechanism only
the real stack demonstrated. (iii) Close D3 now: the trap is latent (grep proves two
call sites), but the None-sentinel costs two lines, changes no behaviour at either
existing site, is covered by the full-suite re-run already ruled in (ii), and
eliminates a half-gated mode (`Config.recall_relevance_primary=False` silently
ignored at a future site) that belongs to the fail-open-hides-dead-kernels family.
Deferring a two-line guard while a re-verify round is already open would be scope
discipline misapplied.

**Not ruled (outside this docket, noted for the record):** F-V4 (stale seam-3
comment re `context_match`), F-V5 (AC-015 tested in one config), F-V6 (BENCH-NOTES
`context_rank.both` 4 vs 5), F-V7 (evidence-file note), D1's missing merged-echo
assertion — all MINOR/NOTE. The maker may fold the trivial ones (comment fix,
BENCH-NOTES re-measure-or-mark, one merged-echo assertion) into the R1-R3 commit
without further deliberation; none blocks release.

### DP-R5 — release-gate ruling (2026-08-03): unpinned `mcp` resolved to 2.0.0; CI and the release image break on main's own latency

Facts accepted as verified by the coordinator: PR #37 (attested at `351ba22`) fails
CI's fresh-image `pytest (container)` job — 4 `test_server.py` tests die on
`AttributeError: 'Server' object has no attribute 'list_tools'` (`server.py:729`)
because `mcp>=1.2.0` is unpinned and CI resolved `mcp==2.0.0`; the diff provably
never touches the decorator region; a fresh build of `main` fails identically (last
green 2026-07-17, pre-mcp-2.0); all other CI jobs pass; and — decisive —
`release.yml`'s OCI build also resolves fresh, so an unpinned 1.9.0 **shipped image
would carry mcp 2.0.0 and be broken at runtime**. The pin is load-bearing for the
release artifact, not just CI hygiene.

#### RULINGS (R5)

| Item | Ruling | Operative instruction |
|---|---|---|
| R5-1 disposition | **(a) — separate trivial PR to main pinning `mcp>=1.2.0,<2`; #37 refreshes on top** | Land the pin PR on `main` first; its own red→green CI on main *is* the independent proof the break is main's, with zero #36 code present. Then merge `main` into `fix/recall-starvation-36` and let CI re-run. Audit the merge-base before merging (repo memory: stale-PR merges) — main at merge time must contain only the `af24493` lineage plus the pin PR; anything else returns to FORGE. Follow-up mcp-2.0 migration issue opened regardless. |
| R5-2 re-attestation | **Delta discipline with four mechanical guards — no full re-attestation** | (1) Diff audit: `git diff 351ba22..<merge-ref>` contains exactly the one pin line plus merge bookkeeping, nothing else; (2) full CI green on the merge ref (the fresh build is now the discriminating gate that was previously missing); (3) runtime assert, not assumption: the CI/container run logs `python -c "import mcp; print(mcp.__version__)"` resolving `<2`, and the built 1.9.0 OCI image is probed the same way **before** the GHCR digest is recorded in the roster; (4) local fast AC-batch re-run on the merge ref. Recorded as an orchestrator addendum note in `verification.md` referencing this ruling. |
| R5-3 tag mechanics | **Confirmed — v1.9.0, tagged from the squash-merge of refreshed #37** | Tree = attested tree + pin + nothing else, proven by guard (1); C-15's "final pre-tag HEAD" is this merge ref. No version implication: tightening an already-declared range (`>=1.2.0` → `>=1.2.0,<2`) removes never-tested resolutions; it changes no tested behaviour. |
| R5-4 ESL bookkeeping | **(ii) — the pin gets its own trivial ESL record** | The pin fixes a latent main break that exists independent of #36 and lands as its own PR; right-sizing gate: trivial. This change's record carries only a cross-reference (C-18) noting the release-plan dependency — it does not own the pin. |

#### Reasoning

**R5-1 — (a).** (c) is rejected outright: an SDK-major migration at the release gate
is scope explosion in the exact place scope discipline exists to prevent it,
performed under pressure against an untested surface — the follow-up issue is the
correct vehicle. Between (a) and (b), attribution is not cosmetics: `351ba22`'s
attestation covers a scope, and folding an unrelated dependency pin into #37 makes
the attested PR carry a build fix its verification never mentioned — precisely the
muddying that would then *justify* demands for fuller re-attestation. (a) keeps
#37's diff byte-identical to the attested scope, and the pin PR failing-then-passing
CI on plain main is a self-contained, mechanical demonstration that the break
pre-dates the fix. That separation is what makes R5-2's delta discipline defensible
rather than merely convenient.

**R5-2 — delta, not full.** The pin does not change what the tests exercise — it
*selects* the environment (mcp 1.x) in which every existing attestation already ran.
A full fresh-context re-attestation would reproduce identical evidence in the
identical environment, now guaranteed rather than accidental: the pin makes the
attested evidence **more** representative of the shipped artifact, not less. What it
must not be is assumed — hence the four guards, two of which are runtime asserts
(CI container and the built OCI image both proving `mcp.__version__` `<2`), because
this entire incident happened by trusting an environment nobody asserted. The image
probe before the roster digest is non-negotiable: the digest is the identity key
downstream, and recording it for an image nobody ran would be the
"installer witnesses its own success" defect in release clothing.

**R5-3 — confirmed.** 1.9.0 stands on the same grounds as DP-R4(i); a constraint
tightening removes resolutions that were never tested rather than changing any
tested behaviour, and the tagged tree is provably the attested tree plus the pin.

**R5-4 — (ii).** The pin's causal story ("mcp 2.0 released upstream; main breaks on
fresh build") is disjoint from #36's; its own trivial record keeps future
archaeology honest and matches the nexus's established trivial-record pattern. A
release-plan addendum alone would leave the main-break fix with no standalone
record, discoverable only through an unrelated recall-ranking change. The pin's
CHANGELOG note is its own one-line `### Fixed` entry naming the latent main break —
it is not folded into 1.9.0's #36 entries.

### Updated CONDITIONS (append to §4)

- **C-12 — Seam 3b gating + RED-first.** The fetch-width decoupling reads the same
  `recall_relevance_primary` flag (flag-off retrieval byte-identical to pre-1.9.0);
  `FETCH_WIDTH_FLOOR = 10` is a named constant with a comment tying it to the
  existing `candidate_k` floor; the new small-k regression test is demonstrated RED
  at `323229f` before the R1 commit, and its criterion enters via C-13's amend batch.
- **C-13 — One legal amend batch.** All criteria changes (AC-007 fixture
  strengthening, the new small-k AC, any AC-016/017 oracle wording) go through a
  single `ramza-freeze --amend --reason` with regenerated `change.json`
  `acceptance_checks`; the new `spec.criteria.md` hash is recorded in the appended
  verification attestation. No direct edit to the frozen file outside the amend.
- **C-14 — Diagnostics derived from the act.** `truncated_count`/`k_applied` are
  computed from the performed slice; `k_applied <= k_requested` holds by
  construction; repeated attack D must turn the strengthened AC-016/017 oracles RED
  before restore.
- **C-15 — Re-verification before tag.** The full DP-R4(ii) scope runs on the final
  pre-tag HEAD (not per-fix intermediates), by vigil in fresh context, appended to
  `verification.md`; the tag is cut only from the attested HEAD. Per DP-R5, the
  final pre-tag HEAD is the merge ref of refreshed #37 (attested tree + pin).
- **C-16 — D3 sentinel.** `Composer`'s flag kwarg defaults to `None` → falls back to
  `config.recall_relevance_primary`; grep re-audit shows exactly the expected read
  sites and both production call sites unchanged.
- **C-17 — Pin sequencing + environment asserts (DP-R5).** The `mcp>=1.2.0,<2` pin
  lands on `main` via its own PR (own trivial ESL record) before #37 refreshes;
  merge-base audited; all four R5-2 guards pass on the merge ref; the built 1.9.0
  image's mcp version is asserted `<2` before the GHCR digest enters
  `roster/mcps.yaml`; the mcp-2.0 migration issue is opened and cross-linked from
  the pin PR.
- **C-18 — Cross-reference only.** This change's release plan references the pin PR
  as a dependency; it does not book the pin as part of the #36 scope.

### ESCALATIONS

None. All post-verification items (R1-R5) landed on rulings within verified
evidence; each fix is small, prescribed by the checker's or CI's own probes, and
re-gated before tag.

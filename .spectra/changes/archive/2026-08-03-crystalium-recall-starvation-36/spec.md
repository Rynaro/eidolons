---
eidolon: ramza
kind: spec
version: "2.1.0"
created_at: "2026-08-02T23:16:00Z"
bound_at: "2026-08-02T23:45:00Z"
status: bound-amended (C-13 batch; implementation VERIFIED-with-notes at 323229f)
deliberation: "deliberation.md (forge, 2026-08-02 — DP-1..DP-X + post-verification R-docket DP-R1..DP-R4, 0 escalations)"
verification: "verification.md (vigil, 2026-08-02, HEAD 323229f — VERIFIED-with-notes; F-V1/F-V2/F-V3)"
change_id: crystalium-recall-starvation-36
esl_tier: full
maker: vivi
checker: vigil
target_repo: Rynaro/crystalium
target_commit: af24493ff235ff1ccbedbeacddb5a445efb326c6
target_version: "1.8.1"
upstream_issue: "Rynaro/crystalium#36"
---

# Spec — recall starvation: query relevance never reaches the composer (crystalium#36)

> All `file:line` anchors below are against `/home/rynaro/workspace/oss/agents/crystalium`
> at `af24493` (tag `v1.8.1`, clean tree — verified). Every anchor cited in this spec
> was independently re-read from source; where the scout report and source disagree,
> source wins and the discrepancy is called out inline.

> **BINDING STATUS — revision 2.0.0.** FORGE issued the binding decision record at
> `deliberation.md` (same directory) on 2026-08-02: **all nine Decision-Points ruled,
> plus DP-X and eleven CONDITIONS, zero escalations.** Every ruling is bound into this
> document — §Approach carries the operative instructions, §Decision-Points records
> the ruling per DP, §Conditions carries C-1..C-11 verbatim in force. **This spec is
> the single source of truth for the maker; `deliberation.md` is cited for rationale
> but is not required reading to implement.** Where a ruling overturned the planner's
> provisional recommendation (DP-4) the change is called out inline.
>
> **REVISION 2.1.0 — post-verification amend (C-13).** vigil attested the
> implementation **VERIFIED-with-notes** at HEAD `323229f` (`verification.md`: 30/30
> frozen ACs pass, 896 passed / 2 pre-existing skips, 5 of 6 gate attacks fired).
> Three findings were escalated and FORGE ruled them binding (`deliberation.md`
> §"Post-verification rulings", DP-R1..DP-R4, conditions **C-12..C-16**):
> **F-V1** (small-`k` regression) → seam 3b fetch-width decoupling + a new criterion;
> **F-V2** (AC-007's gate cannot fail on the defect it names) → AC-007 strengthened;
> **F-V3** (`truncated_count` derived from intent, not from the act) → AC-016/AC-017
> oracles strengthened. All criteria changes landed in **one legal
> `ramza-freeze --amend` batch** — the frozen file was never edited silently.
> Criteria count: **30 → 32**. See §Acceptance Criteria and §Amendment record.

## Problem Statement

`crystalium.recall` returns records that are ordered and selected **entirely without
reference to the query**. The hybrid BM25 + dense + graph arms fuse into a relevance
ranking (`rrf_merge`, `retrieve.py:53-80`, called at `retrieve.py:339`), but that
ranking is used *only* to decide which crystals get fetched into `all_candidates` /
`filtered_ids`; the full filtered set — however large — is handed to
`Composer.compose()` (`retrieve.py:488-492,500`), whose signature takes no `k` and no
relevance (`composer.py:179`), and whose sole ordering key is
`_eviction_key(rec) -> (importance, last_access, id)` (`composer.py:122-134`, used at
`composer.py:234` for per-slot eviction and `composer.py:256` for the global
3500-token reconciliation). `_ComposerRecord` does not even carry a relevance field
(`retrieve.py:691-706`). Meanwhile every episodic/procedural/semantic commit writes
`"importance": 0.0` literally (`episodic.py:176,191,262`; `procedural.py:149,193`;
`semantic.py:233,287,380`) despite each layer being handed an `importance_fn` in its
constructor (`episodic.py:65`, `procedural.py:64`, `semantic.py:73`) that it never
calls — and a crystal's only routes off 0.0 are the post-composition access loop
(`retrieve.py:516-553`), which runs **only for records that already survived
eviction**, or the idle-gated Dream sweep (`dream/worker.py:836-843`, gated by
`idle_threshold_s=300` + `min_dream_gap_s=1800`, `config.py:110-111`). The three
mechanisms compose into a closed starvation loop exactly as issue #36 reports:
a freshly committed crystal is pinned at importance 0.0, loses every eviction round
to any older record with accumulated history regardless of topic, and therefore can
never earn the access event that would raise its importance. `k` is not a cap at all
(it only sizes `candidate_k = max(k*3, 10)`, `retrieve.py:258`, and the graph seed set,
`retrieve.py:297`), so `k=3` and `k=15` produce identical result sets; and
`CrystalSummary.score` is declared `Optional[float] = None` (`schemas.py:222`) and
never passed at its single construction site (`retrieve.py:561-572`), so the ranking
is not even inspectable from the client. Net: `commit` is silently write-only storage.

**Live corroboration.** A `crystalium.recall` issued from this planning session
(scope `{"project":"eidolons"}`, query `"crystalium recall composer eviction
importance ranking relevance retrieval"`, `k=8`, `explain=true`) returned two
topically-unrelated ECM-context records with `importance` `0.2548` / `0.2464` and
`score: null`, `explain.store = {total_crystals: 19, active: 3, embedded: 0}`.
This instance does **not** exercise the eviction path (`evicted_count: 0`,
`total_tokens: 544 < 800`) because that store has only three active crystals — it is
evidence for the `score: null` and importance-band claims, **not** for the eviction
claim. The eviction claim rests on source reading plus the reporter's
`evicted_count: 2..14` observations.

**Empirically measured cold-start values** (run at `af24493`, importing
`crystalium.evb` / `crystalium.importance` directly; reproduce with the snippet in
§Test Plan): a record with `access_count=0`, `outcome_success=None`,
`novelty_at_write=0.5`, `last_access=now` scores `evb_score = 0.240`
(`0.258` at `novelty=0.6`) and legacy `importance_score = 0.525`. The same record
untouched for 14 days scores `evb = 0.140`, at 30 days `evb = 0.085`; a record with
5 accesses, `outcome_success=0.9`, 7 days old scores `evb = 0.403`. The reporter's
observed band (`0.15`–`0.42`) sits exactly inside this range, which is what makes
DP-4 decidable: an EVB-initialised fresh crystal at `0.24` would be *competitive but
not dominant*, whereas a legacy-initialised one at `0.525` would outrank almost
everything in the store.

## Scope / Non-Scope

### In scope

| # | Item | Primary anchors |
|---|---|---|
| A | Carry query relevance into composition so it is decisive in what is returned and in what order | `retrieve.py:53-80,339,415-428,488-492`; `composer.py:122-134,179-279` |
| B | Make `k` a true upper bound on `len(records)`, and clamp `k` to `[1,100]` at both entry points | `retrieve.py:258,297`; `server.py:970-973`; `__main__.py:363` |
| C | Populate `CrystalSummary.score` | `retrieve.py:561-572`; `schemas.py:222`; `schemas/recall-result.v1.json` |
| D | Initialise `utility.importance` at commit from the injected `importance_fn` (or a documented floor) instead of the literal `0.0` | `episodic.py:176,191,262`; `procedural.py:149,193`; `semantic.py:233,287,380` |
| E | Surface the working-set budget in the recall response | `schemas.py:236-252`; `schemas/recall-result.v1.json` |
| F | Advisory (never a rejection) at commit when a summary cannot fit its destination slot | `server.py:1129-1137`; `quality.py:33-40`; `config.py:131-141` |
| G | DX-1: name the four `provenance.source` literals in the `crystalium.commit` tool description | `server.py:248-251`; `schemas.py:28`; `server.py:994-1014` |
| H | DX-2: make the `TIER_VIOLATION` advice name the procedural-candidate fallback and state where caller identity comes from | `enforcement.py:89-111` |

### Non-scope (explicitly out; do not touch in this change)

- **Dream / consolidation internals** — `dream/worker.py`, `dream/scheduler.py`,
  the promotion gate (`gate.py`), the idle/gap predicate. The fix must close the
  cold-start loop *without* a Dream change.
- **Storage-format migration** — no new SQLite column, no `ALTER TABLE`, no
  backfill of `utility.importance` on existing rows. Item D changes only what
  *new* commits write. Pre-existing 0.0-importance rows are rescued by item A
  (relevance), not by a migration.
- **MCP transport / server framing** — stdio/HTTP plumbing, the tool-dispatch
  switch, rate limiting, telemetry shape.
- **The dense arm's health.** `explain.store.embedded == 0` on the live probe above
  means this store has no embeddings and the dense arm contributes nothing; that is
  a separate defect class (embedding backfill / `embedded==0` warning) and is
  **deferred**, not fixed here. Note it in the issue thread.
- **Reranker** (`retrieve.py:362-367`, still commented out), `recall_context_match`
  (default off), `recall_prefetch` (default off), FSRS forgetting.
- **`execution.py`'s hardcoded `0.5`** (`execution.py:226,368`) — left as-is unless
  DP-4 resolves otherwise; see DP-4 sub-question (d).

### Deferred (record in the issue, do not implement)

- Stemming / prefix matching in the FTS5 sparse arm (OQ-4, noted at
  `test_aetheryte.py:160-166`).
- An `explain`-driven `doctor` verb that flags `embedded == 0`.

## Approach — Design

One causal chain applied at six seams, all bound to the FORGE rulings. Additive
throughout: nothing is deleted, no storage shape changes, and `rrf_merge` keeps its
existing signature so `test_rrf.py` stays byte-identical.

**Flag scope (per DP-2 ruling B and C-1) — read this before touching anything.**
A single new field `Config.recall_relevance_primary: bool = True` gates **seams 3, 4
and 5 as one unit**. Everything else in this change is live in **both** modes:

| Live in both modes (ungated) | Gated by `recall_relevance_primary` |
|---|---|
| `score` population (D3) | Seam 3 — top-`k` truncation |
| `budget` object + `explain` keys (D2) | Seam 4 — relevance-primary eviction key |
| `k` clamp to `[1,100]` (D2) | Seam 5 — descending-relevance ordering |
| Cold-start importance (D4) | |
| Oversized-summary advisory (D5) | |
| Tool-description + advice strings (D6, D7) | |
| Schema fix (D8) | |

Consequence the maker must not miss: with the flag **off**, `k` is **not** a cap
(seams 3 and 3b are reverted), the legacy eviction key applies, and the legacy
(slot-grouped / ascending-eviction-key) order returns — but `score`, `budget` and the
clamp still work. AC-003, AC-008 and AC-009 encode exactly this split.

**Flag plumbing — `None` sentinel (per DP-R4(iii) / C-16).** `Composer.__init__` takes
the flag as an explicit kwarg rather than reading `self.config`. vigil confirmed no
live divergence (both production call sites pass it), but flagged the latent trap: a
future third construction site that forgets the kwarg would get seams 4+5 **on** while
Aetheryte's seams 3+3b are **off** — a half-gated mode no criterion covers, in which
`Config.recall_relevance_primary=False` is silently ignored. Bound fix:
`recall_relevance_primary: bool | None = None`, falling back to
`config.recall_relevance_primary` when `None`. Both existing call sites keep their
explicit kwarg, so behaviour at each is byte-identical.

### D1 — Relevance reaches the composer (root cause a) · per DP-1 ruling O1 + top-k gate

**Seam 1 — expose RRF scores without breaking the existing pure function.**
`rrf_merge(rankings, k_rrf) -> list[str]` (`retrieve.py:53-80`) already computes a
`scores: dict[str, float]` internally and discards it. Add a sibling
`rrf_merge_scored(rankings, k_rrf) -> list[tuple[str, float]]` and reimplement
`rrf_merge` as `[cid for cid, _ in rrf_merge_scored(...)]`. Existing callers and
`test_rrf.py` are unaffected.

**Seam 2 — carry relevance on the record.** Add `relevance_score: float` and
`relevance_rank: int` (0-based position in the post-filter fused order) to
`_ComposerRecord.__slots__` (`retrieve.py:691-706`) **and** its `__init__`
(`retrieve.py:708-720`). `__slots__` is declared, so both must be edited together or
attribute assignment raises at runtime.

**Seam 3 — relevance gate before the composer** *(gated)*. `filtered_ids`
(`retrieve.py:415-428`) is already in descending-RRF order. Truncate it to the first
`k` entries before building `composer_records` (`retrieve.py:488-492`). This makes
relevance decisive over *membership* and is the mechanism by which `k` becomes a hard
cap (DP-3a).

**Seam 3b — fetch width is decoupled from the response cap** *(gated; per DP-R1)*.
`k` now means **response cap** (DP-3a), so the *ranking universe* must not depend on
it — otherwise a small `k` silently changes which arms vote. It does today:
`seed_ids = dense_ranking[:k]` (`retrieve.py:355` at `323229f`) makes graph and
completion arm membership a function of caller `k`. vigil reproduced the consequence
on the real embedding stack (`verification.md` F-V1): at `k=1` and `k=3` the fresh
distinctive-token crystal was **not returned at all** in the default configuration —
a regression against `af24493` on the exact capability #36 exists to restore, because
the walk from the fresh crystal hands its topically-unrelated neighbours a third and
fourth arm and unweighted RRF scores them ~3x1/62 = 0.048 against the exact lexical
match's 2x1/61 = 0.0328.

Bound fix: introduce a named constant

```
FETCH_WIDTH_FLOOR = 10   # matches the existing candidate_k floor (max(k*3, 10),
                         # retrieve.py:258) and the shipped default k
```

and, **when the flag is on**, use `fetch_width = max(k, FETCH_WIDTH_FLOOR)` for every
*arm-seeding* use of raw `k` in the retrieval pipeline — at minimum `seed_ids`
(`retrieve.py:355`) and the completion arm's seed set if it reads raw `k`. **The
`[:k]` response slice remains the only consumer of the caller's `k`.** Flag-off
retrieval must be **byte-identical to `323229f`** (`dense_ranking[:k]` verbatim), which
is what keeps AC-008/AC-009 valid. At the default `k=10`, `max(10, 10)` is a no-op, so
AC-001 is unaffected. New criterion **AC-031** pins this; **C-12** requires it RED at
`323229f` first.

*Out of scope, follow-up issue only:* the deeper pre-existing root — unweighted RRF
letting a 3-arm graph neighbour outvote a 2-arm exact lexical match — is **not** fixed
in this release (it touches fusion at every `k` and needs eval evidence).

**Seam 4 — relevance-primary eviction key** *(gated)*. Per the DP-1 ruling, exactly:

```
_eviction_key(rec) = (getattr(rec, "relevance_score", 0.0),
                      rec.importance,
                      last_access,
                      rec.id)          # ascending; lowest evicted first
```

The `getattr(..., 0.0)` default is **load-bearing, not defensive style** (C-2): it
makes every hand-built `_Rec` stub in `test_composer.py:35-110` tie at relevance 0.0,
so the existing `(importance, last_access, id)` assertions survive intact as the
*equal-relevance case*. That is what bounds this change's blast radius to roughly the
top-k-gate-only alternative plus one function. Keep the function pure and total — it
is consumed by `sorted()` at `composer.py:234` and `composer.py:256`.

Why both seams 3 and 4 (per the DP-1 reasoning): seam 3 alone does **not**
deterministically fix #36. In a real store the dense arm surfaces topically-weak
neighbours into the top-`k`; when the slot then overflows, Pass-1 eviction
(`composer.py:223-245`) still pops the rank-1 importance-0.0 fresh crystal before a
rank-5 stale one at 0.24. Seam 3 fixes #36 probabilistically; seams 3+4 fix it
deterministically, and AC-004 is only red→green provable with seam 4.

**Seam 5 — response ordering** *(gated)*. Today's order is an artefact: Pass 1
appends per slot in `Config.slots` insertion order (executive, procedural, semantic,
episodic, execution, buffer — `composer.py:223-245`), and when Pass 2 fires `kept` is
sorted **ascending** by eviction key (`composer.py:256`), returning records
least-important-first. Per DP-6, emit `composed.records` sorted by
`relevance_score` **descending** with `id` **ascending** as tiebreak. Document the
contract in the `recall()` docstring (`retrieve.py:182-223`) and in the
`crystalium.recall` tool description (`server.py:180-188`). Flag-off restores the
legacy artefact order — that is what "pre-fix behaviour" means.

**Importance is not orphaned.** `memory_dynamics.evb` still drives the Dream prune
cutoff (`dream/worker.py:440-442`), the forgetting percentile
(`dream/worker.py:547-552`) and prioritised replay (`dream/worker.py:575-585`).

**Docstring debt.** The eviction-rule contract in `composer.py:1-36` (module
docstring) and `composer.py:122-134` describes the old key and becomes false the
moment seam 4 lands. Rewriting it is part of the change, not a follow-up.

### D2 — `k` is a cap; the budget is explicit (root cause c) · per DP-3a/3b/3c/3d + DP-7

1. **Hard cap** (DP-3a). Seam 3 guarantees `len(result.records) <= k` in default mode.
2. **Clamp + fallback** (DP-3d, C-11). `server.py:970-973` and `__main__.py:363` both
   clamp with `max(0, int(k))` today, so `k=0` is reachable and — once `k` truncates —
   would silently return zero records, a bug the fix would *introduce*. At both sites:
   a numeric `k` is clamped into `[1, 100]`; a **non-coercible** `k` (e.g. `"garbage"`)
   falls back to the default `10` and **never raises** — recall is a read path and
   must degrade, not reject. This is ungated (input validation, not ranking).
3. **Budget does not scale** (DP-3b). `Config.total_cap = 3500` (`config.py:141`) and
   `Config.slots` (`config.py:131-140`) are unchanged. A scaled budget is
   *mechanically* impossible, not merely unconventional: `RecallResult.total_tokens:
   int = Field(ge=0, le=3500)` (`schemas.py:242`) would raise `ValidationError`
   **inside** `recall()`, `schemas/recall-result.v1.json` declares `"maximum": 3500`,
   and `composer.py:269-272` asserts it (P0-9). Document `k` as an upper bound
   *subject to* a fixed token budget.
4. **Surface the budget** (DP-3c, ruling C — both). Add an **always-present** field to
   `RecallResult` (`schemas.py:236-252`):

   ```
   budget = {
     "total_cap":       int,   # 3500
     "slots":           dict,  # Config.slots, per-slot caps
     "k_requested":     int,   # the caller's k, post-clamp
     "k_applied":       int,   # records actually returned
     "truncated_count": int,   # candidates dropped by the k gate (DP-7)
   }
   ```

   Always-present is the ruling: an `explain`-only budget recreates the exact
   discoverability failure this issue is about, and defeats DP-7's mitigation (a
   caller reading only `evicted_count` cannot tell truncation happened). Because
   `budget` is never `None`, `model_dump(exclude_none=True)` (`server.py:986`) emits
   it on every response — hence D8 is mandatory in the same release.
5. **`evicted_count` is untouched** (DP-7). It keeps its exact current meaning —
   candidates dropped to satisfy the *token budget* (`composer.py:239,261`, surfaced
   at `retrieve.py:616`). k-truncation is counted **only** in `budget.truncated_count`
   and `explain.truncated_by_k`. Do not fold the two.
6. **Diagnosability** (DP-3c). Add `k_applied` and `truncated_by_k` to the `explain`
   object (`retrieve.py:588-603`).

### D3 — `score` is populated (root cause e) · per DP-5 ruling A

Pass `score=<raw RRF fusion value for rec.id>` at the single `CrystalSummary(...)`
construction site (`retrieve.py:561-572`). Raw RRF, not normalised, not rank: the
published schema already describes the field as *"Retrieval relevance score from the
Aetheryte hybrid retrieval"*, so this makes the code match the published contract
with **zero schema change** for this item. **Populate in both flag modes** — the RRF
fusion runs regardless, and suppressing it under flag-off would remove diagnosability
exactly where an operator running the legacy path needs it most. **Do not add a
`rank` field**: `CrystalSummary` is `model_config = ConfigDict(extra="forbid")`
(`schemas.py:212`), the emitted order already conveys rank (DP-6), and the contract
should grow by the minimum that closes the issue.

### D4 — Cold-start importance (root causes b and d) · per DP-4 ruling C — **overturns the planner's provisional rec**

The planner recommended bare `importance_fn`; FORGE ruled **C — `importance_fn`
clamped**. The deciding observation: `utility.importance` is normally a *bridge*
value (under the default config Dream recomputes and persists `memory_dynamics.evb`
at first sweep, `dream/worker.py:836-843`, which the composer then prefers) — but
under the legacy config (`evb_enabled=False`) `persist_dynamics` is off, so the
commit-time value is **durable**. Bare option A's measured legacy cold start of
**0.525** would therefore be a *permanent* starvation inversion, above a
proven-useful record (5 accesses, outcome 0.9, 7 days = **0.403**). A comment is not
a guard; the clamp makes it mechanically impossible.

**Implement exactly this.** One shared helper — no copies — e.g. in
`crystalium/importance.py`:

```
COLD_START_IMPORTANCE_CEILING = 0.30   # derived from the measured band: keeps a fresh
                                       # crystal below a proven-useful record (0.403)
                                       # and inside the reporter's live band (0.15-0.42)

def initial_importance(importance_fn, utility, now) -> float:
    stub = <MemoryRecord-shaped stub from utility: access_count, last_access,
            outcome_success(_score), novelty_at_write>      # cf. retrieve.py:659-676
    return min(importance_fn(stub, now=now), COLD_START_IMPORTANCE_CEILING)
```

Call it at the **six** literal `"importance": 0.0` sites: `episodic.py:176,191,262`;
`procedural.py:149,193`; `semantic.py:233,287,380`. Each path already builds the
`utility` dict with exactly the fields the scorer needs (`access_count=0`,
`last_access=now`, `outcome_success_score=None`,
`novelty_at_write=payload.get("novelty_at_write", 0.5)`).

Measured behaviour of the bound design (verify with the snippet in §Test Plan):
under EVB (default, `evb_enabled=True`, `config.py:160`) the helper returns
**0.240** at `novelty=0.5` / **0.258** at `novelty=0.6` — **the clamp never binds**,
so the default path is byte-identical to the unclamped design. Under the legacy
scorer it returns **0.30** (clamped from 0.525).

Sub-rulings, all binding:

- **(a) `utility.importance` only.** Do **not** write `memory_dynamics` — that is
  Dream's writer (`dream/worker.py:842-843`), and the composer's fresh-crystal
  fallback already reads `utility.importance` (`retrieve.py:461-473`).
- **(b) No backfill.** Existing 0.0 rows stay 0.0; they are rescued by D1's relevance
  ranking, which is live on the commit side regardless of the flag. No migration.
- **(c) Echo the value.** The commit result's `importance` field (e.g.
  `episodic.py:262`) reports the computed value — it is the reporter's diagnostic
  surface and AC-010 asserts it.
- **(d) `execution.py`'s `0.5` stays.** Leave `execution.py:226,368` untouched and add
  a one-line comment recording that `0.5` is the deliberate "currently active work"
  privilege — **intentionally above** the 0.30 cold-start ceiling, because active work
  should survive composition — and is not a cold-start estimate.

**Root cause (d) needs no new code.** Once D1 + D4 land, a fresh crystal becomes
reachable and the *existing* post-composition access loop (`retrieve.py:544-551`:
unconditional `record_access`, plus an EVB recompute when `persist_dynamics` is on,
wired from `evb_enabled=True` at `server.py:536`) reinforces it in-session. Stated
explicitly so the checker does not hunt for code that is deliberately absent.

### D5 — Oversized-summary advisory · per DP-8 ruling A + C-4

Reuse the established additive-advisory pattern at `server.py:1129-1137`
(`scope_normalized`, `summary_quality`/`advisory`, `provenance_coercion`): tokenise
the caller-supplied summary with the composer's **module-level, post-#32-hardened**
tokenizer (`composer.py:99`, `composer.py:171-177`), compare against the destination
layer's slot cap (`Config.slots`, `config.py:131-140`), and attach
`{"summary_tokens": N, "slot_cap": M, "summary_size": "oversized", "advisory": ...}`
when `summary_tokens > slot_cap`.

Bound constraints: threshold is the **full slot cap**, layer-aware (a fractional
threshold would fire around 400 episodic tokens — near-normal for this corpus — and
would routinely break the clean-path byte-identity that
`test_diagnosability.py:312` locks in). **Advisory only, never a rejection**: the
reporter proved (issue §"What I ruled out") that shrinking the summary did not
restore retrievability, so size is a hint, not a cause — do **not** import the CLI's
hard-reject posture (`__main__.py:503-513`). **C-4:** any tokenizer exception skips
the advisory silently; it must never fail or delay a commit.

### D6 — DX-1: `provenance.source` enum discoverability

`Provenance.source` is `Literal["human","verified_agent","unverified_agent",
"environment"]` (`schemas.py:28`), mirrored at runtime as
`_VALID_PROVENANCE_SOURCES` (`server.py:994-996`) with a coercion helper
(`server.py:999-1014`, invoked at `server.py:1077`). The `crystalium.commit` tool
manifest describes `provenance` only as `"Provenance dict: {source, author_agent,
task_id, created_at}"` (`server.py:248-251`) — the four literals appear nowhere on
the tool surface. Extend that description to enumerate them and to state that an
out-of-enum value is **coerced** (with a `provenance_coercion` advisory) rather than
rejected. Pure string change.

### D7 — DX-2: `TIER_VIOLATION` advice · per C-9

`TierViolation.__init__` (`enforcement.py:89-111`) builds
`advice=f"Use a lower-trust layer or escalate caller identity above {tier}."` — which
names no mechanism and no layer. Both are answerable from source:

- Caller identity is resolved **once at server start** from
  `CRYSTALIUM_CALLER_EIDOLON` / `CRYSTALIUM_CALLER_TIER` (`server.py:102-122`; CLI
  equivalents `__main__.py:362,556`). It is host/env configuration, **not**
  escalatable per call.
- The T2 fallback the reporter found by experiment is real: `procedural` accepts a T2
  commit and lands `validation_state="candidate"` (`procedural.py:126-134,165`).

**C-9 (binding): the string must not state or imply T2→semantic promotion.**
`Gate.propose_procedural` (`gate.py:216-265`, esp. `gate.py:228`) records that **T2
ALWAYS stays `candidate` (G2) — a passing verifier never admits a T2 proposal to
shared/validated.** Suggested wording (verify every clause against `gate.py:216-265`,
`procedural.py:126-134`, `server.py:102-122` before merge):

> `Layer '<layer>' is not writable at tier <tier>. T2 callers should commit to
> 'procedural' (accepted, lands validation_state='candidate' per G2 — it stays
> candidate; promotion to a validated/semantic record requires a T1/T0 proposer
> through the corroboration gate) or to 'episodic'. Caller identity is set by the
> host at server start via CRYSTALIUM_CALLER_EIDOLON / CRYSTALIUM_CALLER_TIER and
> cannot be escalated per call.`

`reason_code` stays `"TIER_VIOLATION"` (an enumerated literal at `schemas.py:296`).

### D8 — Published schema drift · per DP-X ruling (mandatory, this release)

`schemas/recall-result.v1.json` declares `additionalProperties: false` at the result
level and **does not list the v1.6 `explain` property** — the published contract is
already out of sync with `RecallResult`, and nothing validates a live result against
it (`test_schemas.py:144-160` only checks that the schema files parse, plus
crystal/commit fixtures). Shipping D2's always-present `budget` without fixing this
would make **every** recall response formally invalid against the published schema —
upgrading a latent drift into a total one. Bound scope:

1. Add `budget` **strictly**: all five fields enumerated, `additionalProperties:
   false` on the sub-object.
2. Add `explain` **loosely**: `type: object`, `additionalProperties: true`, with a
   description marking it diagnostic/unstable, so evolving diagnostic keys
   (`k_applied`, `truncated_by_k`, and future ones) cannot re-drift the schema.
3. Keep the `v1` filename — every change is additive; `score` was already declared and
   `total_tokens` bounds are unchanged.
4. **C-7 — the schema must be checked, not just fixed.** Add a test that round-trips a
   live `RecallResult` (one plain, one with `explain=true`) through
   `jsonschema.validate` against the file.

**Hazard the maker must avoid in C-7.** The existing helper
`test_schemas.py:63-77` calls `pytest.skip("jsonschema not installed (add to dev
deps)")` on `ImportError`. A round-trip test built on that helper would **silently
skip** and could never fail on the defect it names — the exact anti-pattern C-7
exists to prevent. `jsonschema>=4.21` is a declared dependency
(`mcp-server/pyproject.toml:45`), so the new test must **import it unconditionally**
(or assert importability) rather than skipping. Prove the gate bites: temporarily
remove `budget` from the schema and confirm the new test goes red.

## Decision-Points — RULED (binding)

FORGE issued binding rulings on 2026-08-02 (`deliberation.md`, seat
HUMAN-DECISION delegated): **all nine DPs plus DP-X ruled, zero escalations.**
Evidence was spot-checked at source before ruling; no divergence from this spec's
anchors was found. The operative instruction for each ruling is reproduced here so
the maker never needs `deliberation.md`; the full reasoning lives there.

| DP | Ruling | Operative instruction |
|----|--------|-----------------------|
| DP-1 | **O1 + top-k gate** | `_eviction_key = (getattr(rec,"relevance_score",0.0), importance, last_access, id)` ascending; truncate `filtered_ids` to `k` before building composer records. §D1 seams 3+4. |
| DP-2 | **B — flag, default ON** | `Config.recall_relevance_primary: bool = True`; gates seams 3+4+5 as ONE unit. `score`, `budget`, `explain` keys, k clamp and all commit-side changes are **ungated**. §D1 flag-scope table. |
| DP-3a | **Yes — hard cap** | `len(result.records) <= k` via the seam-3 truncation. |
| DP-3b | **No scaling** | `total_cap` stays 3500; `Config.slots` unchanged; document `k` as an upper bound subject to a fixed budget. |
| DP-3c | **C — both** | Always-present `RecallResult.budget = {total_cap, slots, k_requested, k_applied, truncated_count}`; `k_applied` + `truncated_by_k` also in `explain`. §D2.4/D2.6. |
| DP-3d | **Yes — clamp [1,100]** | `server.py:970-973` + `__main__.py:363`: numeric k clamped to `[1,100]`; non-coercible k falls back to `10`, never raises. |
| DP-4 | **C — clamped `importance_fn`** | Shared helper `initial_importance(...) = min(importance_fn(stub, now=now), COLD_START_IMPORTANCE_CEILING)`, ceiling `0.30` as a named constant; six call sites. §D4. **Overturns the planner's provisional rec (bare A).** |
| DP-4a | **`utility.importance` only** | Never write `memory_dynamics` (Dream's writer). |
| DP-4b | **No backfill** | Old 0.0 rows rescued by DP-1 relevance, which is ungated on the commit side. |
| DP-4c | **Echo the value** | Commit result's `importance` reports the computed value (AC-010's surface). |
| DP-4d | **`execution.py` 0.5 stays** | Untouched + a one-line comment: deliberate "currently active work" privilege, intentionally above the 0.30 ceiling. |
| DP-5 | **A — raw RRF** | `score=` the fused RRF value at `retrieve.py:561-572`; populate in **both** flag modes; **no** `rank` field (`extra="forbid"`). |
| DP-6 | **A — descending relevance** | `relevance_score` desc, `id` asc tiebreak (default mode); flag-off restores legacy order; document in docstring + tool description. |
| DP-7 | **A — separate counter** | `evicted_count` keeps its exact current meaning (token-budget drops only); k-truncation in `budget.truncated_count` + `explain.truncated_by_k`. |
| DP-8 | **A — `> slot_cap`** | Layer-aware, composer's own tokenizer, advisory-only, clean path byte-identical. |
| DP-9 | **A — `1.9.0`** | Minor bump, valid **because** DP-2 landed B. See C-10. |
| DP-X | **Yes — fix schema drift now** | `recall-result.v1.json` gains `budget` (strict) **and** the missing `explain` (loose/diagnostic); plus a jsonschema round-trip test. §D8. |

**Deltas from the planner's provisional recommendations.** Eight of the ten matched.
Two moved, both toward *more* mechanical guarantee:

- **DP-4: A → C.** The planner recommended bare `importance_fn` with a documented
  caveat for the legacy path. FORGE ruled that a caveat is not a guard, because under
  `evb_enabled=False` the commit-time value is **durable** (no Dream write-back), so
  0.525 would be a permanent inversion. Bound to a named 0.30 ceiling; at EVB values
  (0.240–0.258) the clamp never binds, so the default path is unchanged from A.
  **Consequences in this spec:** §D4 rewritten; AC-011 and AC-012 added (cold-start
  asserted under *both* scorer configs, per C-3); R-5 downgraded from "documented" to
  "mechanically closed".
- **DP-1: 65% → settled on O1.** The planner scored O1 and O3 within 0.6 points and
  flagged it as genuinely open. FORGE closed it on mission P0-1: only O1 makes
  fresh-crystal survival provable, and AC-004 is only red→green provable under O1.
  **Consequences:** `test_composer.py::TestG6EvictionDeterministic` is extended rather
  than untouched; AC-004 is load-bearing.

Two further consequences worth stating: **AC-017 (now AC-008) is load-bearing, not
optional** — DP-2 landed B, so the flag-off path exists and must be tested; and
**DP-X is forced by DP-3c + DP-7** — the always-present `budget` carrying
`truncated_count` collides with the published schema's `additionalProperties: false`,
so the schema fix cannot be deferred.

## Conditions (binding implementation guards)

C-1..C-11 from `deliberation.md` §4, in force. Each is a merge blocker: the rulings
above hold **only if** these are satisfied. The checker (vigil) verifies each.

- **C-1 — Flag scope.** `recall_relevance_primary=False` reverts exactly seams 3+4+5
  (top-k truncation, relevance-primary eviction key, descending-relevance ordering)
  as one unit. `score`, `budget`, `explain` additions, the k clamp, and all
  commit-side changes (cold-start importance, advisories, description strings) remain
  active in both modes. AC-008 tests the flag-off path.
- **C-2 — Degradation.** `_eviction_key` reads relevance via
  `getattr(rec, "relevance_score", 0.0)`; the defence-in-depth `try/except` around
  `composer.compose()` (`retrieve.py:499-514`) and the assertion at
  `composer.py:269-272` stay intact (R-7).
- **C-3 — Cold-start helper.** One shared helper, six call sites, zero copies;
  `COLD_START_IMPORTANCE_CEILING = 0.30` as a named constant with a comment deriving
  it from the measured band; tests assert the commit-time importance under **both**
  `evb_enabled=True` and `evb_enabled=False` (closes R-5 mechanically).
- **C-4 — Advisory tokenizer safety.** The oversized-summary advisory reuses the
  hardened module-level tokenizer (`composer.py:99`, post-#32); any tokenizer
  exception skips the advisory and never fails or delays the commit.
- **C-5 — RED-first proof.** AC-001, AC-002, AC-004, AC-005, AC-010 demonstrated
  failing at `af24493` **before** the fix lands; failing output recorded in the verify
  artefact.
- **C-6 — Eval integrity.** `retrieval-gate` run before and after; both JSON outputs
  in the PR body; `evals/BENCH-NOTES.md` §W5(i) updated. A flipped `completion_pass`
  or `context_pass` is a **checker finding — no assertion may be edited to green it.**
  `evb_gate`, `forgetting_gate`, `dream_gate` re-run (uniform baseline shift — verify,
  do not assume).
- **C-7 — Schema is checked, not just fixed.** Round-trip a live `RecallResult` (one
  plain, one `explain=true`) through `jsonschema.validate` against
  `schemas/recall-result.v1.json`. **Must not use the skip-on-ImportError helper at
  `test_schemas.py:63-77`** — see §D8 hazard.
- **C-8 — Config helpers.** The new `Config` field is assigned in all four manual
  `Config.__new__` test helpers (`test_aetheryte.py:42`, `test_composer.py:73`,
  `test_dream_worker.py:34`, `test_dream_scheduler.py:41`) in the same commit that
  adds the field (R-3).
- **C-9 — DX-2 wording gate.** Every clause of the new `TIER_VIOLATION` advice
  verified against `gate.py:216-265`, `procedural.py:126-134`, `server.py:102-122`
  before merge; the string must not state or imply T2→semantic promotion;
  `reason_code` stays `"TIER_VIOLATION"`.
- **C-10 — Version contingency.** If implementation drops the DP-2 flag for any
  reason, DP-9 flips to **2.0.0 automatically** — no re-deliberation. Any *other*
  deviation from these rulings returns to FORGE.
- **C-11 — k normalisation.** Numeric k clamped to `[1,100]` at both entry points;
  non-coercible k falls back to the default `10` rather than raising.

Post-verification conditions (`deliberation.md` §"Updated CONDITIONS"), added at
revision 2.1.0 and equally binding:

- **C-12 — Seam 3b gating + RED-first.** The fetch-width decoupling reads the same
  `recall_relevance_primary` flag (flag-off retrieval **byte-identical to `323229f`**);
  `FETCH_WIDTH_FLOOR = 10` is a named constant with a comment tying it to the existing
  `candidate_k` floor; AC-031's test is demonstrated **RED at `323229f`** before the
  seam-3b commit.
- **C-13 — One legal amend batch.** All criteria changes go through a single
  `ramza-freeze --amend --reason` with regenerated `change.json` `acceptance_checks`;
  the new `spec.criteria.md` hash is recorded in the appended verification
  attestation. **No direct edit to the frozen file outside the amend.** *(Discharged
  by this revision — see §Gate record.)*
- **C-14 — Diagnostics derived from the act.** `truncated_count` and `k_applied` are
  computed from the **performed** slice — `truncated_count = len(before) - len(after)`,
  `k_applied = min(k_requested, len(before))` — so `k_applied <= k_requested` holds by
  construction. Repeated attack D must turn the strengthened AC-016/AC-017 oracles
  **RED** before restore.
- **C-15 — Re-verification before tag.** The full DP-R4(ii) scope runs on the **final
  pre-tag HEAD** (not per-fix intermediates), by vigil in fresh context, appended to
  `verification.md`: full `make test`; the frozen VERIFY batch against the **amended**
  criteria (new hash recorded); attack E repeated → RED on AC-007; attack D repeated →
  RED on AC-016/AC-017; the F-V1 four-cell probe re-run (`k in {1,3,5,10}` x flag
  on/off) with flag-on returning the fresh crystal at **every** `k` and the flag-off
  column unchanged; plus the flag-scope grep audit re-run (read sites now include
  seam 3b). The tag is cut only from the attested HEAD.
- **C-16 — D3 sentinel.** `Composer.__init__(..., recall_relevance_primary: bool | None
  = None)` falls back to `config.recall_relevance_primary` when `None`; both production
  call sites keep their explicit kwarg; a grep re-audit shows exactly the expected read
  sites.

**Not ruled, maker's discretion** (`deliberation.md`): F-V4 (the seam-3 comment claims
`filtered_ids` is in descending-RRF order, which `context_match` can falsify at
`retrieve.py:425`), F-V5 (AC-015 tested in one configuration only), F-V6
(`BENCH-NOTES` `context_rank.both` = 4 does not reproduce; vigil measured 5 — re-measure
or mark the axis run-varying), F-V7 (the RED-evidence file should note that AC-007's
fixture was amended after the RED commit), and D1's missing merged-echo `importance`
assertion. The trivial ones may fold into the R1-R3 commit without further
deliberation; none blocks release. Also unfolded: the spec's printed slow-gate command
block still omits `test_dream_gate.py` (covered by `make test`, so C-6 is discharged in
fact).

## Rejected Alternatives

Scored in the Explore gate (`ramza-score --rubric explore`; verdicts in
`.spectra/plans/crystalium-recall-starvation-36.state.json`), then adjudicated by
FORGE. All rejections below are now **binding**, not provisional.

| Hypothesis / option | Score | Verdict | Why rejected (binding) |
|---|---|---|---|
| H-C / DP-1 O4 — weighted composite `alpha*relevance + (1-alpha)*importance` | 60.0 | weak | RRF is unnormalised (`retrieve.py:53-80`); min-max over the live candidate set makes the key unstable call-to-call and destroys the reproducibility contract (`composer.py:6-11`). |
| H-D / DP-4 D — importance init only, composer untouched | 70.5 | solid | Leaves root causes (a) and (c) intact: relevance still contributes nothing, `k` still means nothing. A fresh crystal at 0.24 still loses to anything above 0.24 regardless of topic. |
| H-B / DP-2 C — config gate, default OFF | 72.5 | solid | Violates mission P0-1 (fix must be default-on); and its earn-it-on eval cannot even measure the behaviour — the `retrieval_gate` corpus never triggers eviction. |
| H-A — relevance-primary key, no `k` gate | 77.0 | solid | Leaves `k` non-binding; a large corpus still floods the composer and `k=3` still equals `k=15`. |
| H-E / DP-1 O3 — top-`k` gate only, `_eviction_key` unchanged | 85.0 | elite | **Rejected by FORGE**, though within 0.6 points. Fixes #36 only *probabilistically*: the dense arm surfaces weak neighbours into the top-k, and on slot overflow Pass-1 eviction still pops the rank-1 fresh crystal. AC-004 is unprovable under it. Retained only as an emergency fallback if the composer change proves unshippable. |
| DP-1 O2 — relevance-banded (`rank // B`) | — | — | `B` is an unmeasured magic knob (repo convention demands an eval to earn a knob, `config.py:159-166`) and still does not guarantee rank-1 survival. |
| DP-2 A — no flag | — | — | Discards the one-line rollback for the highest-impact risk (R-1) and breaks an established repo convention without cause. Would also force DP-9 to 2.0.0 (C-10). |
| DP-3b B/C — budget scaling | — | — | C is blocked by two hard validators (`schemas.py:242`, schema `maximum: 3500`) plus the P0-9 assertion; B has no measured curve and silently changes `slot_breakdown` semantics. |
| DP-4 A (bare) | — | — | Permanent inversion under `evb_enabled=False` (durable 0.525); a comment is not a guard. |
| DP-4 B — constant floor | — | — | Discards `novelty_at_write` (the only real signal at commit) and creates a second source of truth that diverges as EVB weights evolve. |
| DP-5 B/C/D + a `rank` field | — | — | Normalised degenerates to 1.0 on single-record results; rank discards magnitude (the reporter's stated need); the eviction key leaks an internal tuple. `extra="forbid"` blocks a companion field without a schema edit. |
| DP-7 B/C — fold or drop truncation count | — | — | B redefines a field the reporter used as live evidence (`evicted_count: 2..14`) and masks real budget pressure; C discards the signal. |
| DP-8 B/C/D — fractional / global / no advisory | — | — | Fractional fires around 400 episodic tokens (near-normal here; live probe: 544 for two records) → advisory fatigue + routine clean-path breakage; 3500 never fires; dropping it loses a requested signal. |
| DP-9 B/C — 2.0.0 / 1.8.2 | — | — | 2.0.0 rejected *conditionally* (becomes correct iff the flag is dropped, C-10); 1.8.2 misstates a release that adds response fields and changes result sets. |
| **H-E-prime — top-k gate + relevance-primary key** | **85.5** | **elite** | **Selected and ratified (DP-1 = O1 + gate).** |

Also rejected without scoring: scaling `total_cap` with `k`; adding a *new*
in-session reinforcement path (unnecessary — the existing loop at
`retrieve.py:544-551` closes once the record can win); backfilling
`utility.importance` on existing rows (excluded by mission P0-3 and confirmed
acceptable by DP-4b).

## Stories

Work packages for the maker (vivi), container-first (`make test` runs inside Docker,
`Makefile:27-28`). Every DP is bound, so **no story is blocked on a decision** — the
`gated on DP-n` markers from revision 1.0.0 are removed.

### S-1 — Relevance plumbing (0.5d, P0)

`rrf_merge_scored()` beside `rrf_merge()` (`retrieve.py:53-80`); `relevance_score` /
`relevance_rank` added to `_ComposerRecord.__slots__` **and** `__init__`
(`retrieve.py:691-720`); populated in `_to_composer_record` (`retrieve.py:433-486`)
from the post-filter fused order.
**Output contract:** `rrf_merge` returns the identical list for identical input —
`test_rrf.py` must pass **unmodified**.

### S-2 — The flag (0.5d, P0)

`Config.recall_relevance_primary: bool = True` with `from_yaml`/`from_env`/
`from_dict` plumbing in the style of `config.py:196-217`, a comment recording that it
is earned by **correctness** (issue #36) rather than by an ablation win, one
constructor kwarg on `Aetheryte` (`retrieve.py:105-127`) and `Composer`
(`composer.py:159-165`), one wiring line at `server.py:528-548` — **and C-8: assign
it in all four `Config.__new__` test helpers in the same commit.**

### S-3 — `k` as a cap + clamp (0.5d, P0)

Truncate `filtered_ids` to `k` before `composer_records` is built
(`retrieve.py:415-492`) *under the flag*; clamp `k` to `[1,100]` with fallback-to-10
at `server.py:970-973` and `__main__.py:363` *ungated* (C-11); add `k_applied` /
`truncated_by_k` to `explain` (`retrieve.py:588-603`), **derived from the performed
slice** per C-14.

### S-3b — Fetch-width decoupling (0.5d, P0, post-verification)

`FETCH_WIDTH_FLOOR = 10` as a named constant with the comment tying it to
`candidate_k = max(k*3, 10)`; under the flag, every arm-seeding use of raw `k` uses
`max(k, FETCH_WIDTH_FLOOR)` — at minimum `seed_ids = dense_ranking[:k]`
(`retrieve.py:355` at `323229f`) and the completion arm's seed set if it reads raw
`k`. `[:k]` stays the sole consumer of caller `k`. Flag-off byte-identical to
`323229f`. **C-12: AC-031's test RED at `323229f` first.** Open the follow-up issue
for the unweighted-RRF root; do not fix it here.

### S-3c — `Composer` flag sentinel (0.1d, P1, post-verification)

`recall_relevance_primary: bool | None = None` → falls back to
`config.recall_relevance_primary` (C-16). Two lines; no behaviour change at either
existing call site.

### S-4 — Composition ordering (1d, P0)

`_eviction_key` per DP-1 using `getattr(rec, "relevance_score", 0.0)` (C-2); emit
`composed.records` in descending relevance with `id` asc tiebreak; flag-off restores
legacy order. Rewrite the stale eviction-rule docstring (`composer.py:1-36`,
`composer.py:122-134`) and the `recall()` docstring (`retrieve.py:182-223`), and add
the ordering contract to the tool description (`server.py:180-188`).

### S-5 — `score` + `budget` + schema (1d, P0)

`score=` raw RRF at `retrieve.py:561-572`, both modes (DP-5); the always-present
`budget` object on `RecallResult` (`schemas.py:236-252`) with `truncated_count`
(DP-7); `schemas/recall-result.v1.json` gains `budget` (strict) **and** the missing
`explain` (loose) per DP-X; the C-7 round-trip test **without** the skip-on-ImportError
helper.

### S-6 — Cold-start importance (0.5d, P0)

`COLD_START_IMPORTANCE_CEILING = 0.30` + `initial_importance()` helper; six call
sites (`episodic.py:176,191,262`; `procedural.py:149,193`; `semantic.py:233,287,380`);
echo the value in the commit result (DP-4c); one-line comment on `execution.py:226,368`
(DP-4d). Tests under **both** scorer configs (C-3).

### S-7 — DX items (0.5d, P2)

Oversized-summary advisory with tokenizer-exception safety (`server.py:1129-1137`,
C-4); `provenance.source` enum in the commit tool description (`server.py:248-251`);
`TIER_VIOLATION` advice (`enforcement.py:110`) — **C-9: verify every clause against
`gate.py:216-265` and `server.py:102-122` before writing it.**

### S-8 — Tests, evals, release (1.5d, P0)

New regression file; updates to existing tests; **C-5 RED-first proof**; **C-6
before/after eval runs + BENCH-NOTES**; CHANGELOG; version bump; tag; nexus
dual-roster PR. See §Test Plan and §Release Plan.

## Acceptance Criteria

**Renumbered at revision 2.0.0** (bound). Revision 1.0.0 carried 17 criteria with
several marked `[DP-gated]`; the rulings resolved every gate and added obligations
(DP-4=C's dual-scorer assertion, DP-7's counter split, DP-X/C-7's schema round-trip,
DP-5's both-modes rule), so the set was renumbered to a contiguous 1..30. The
old→new map is in §AC renumbering below. `TF` = `mcp-server/tests/test_recall_starvation.py`
(new). Criteria are frozen in `spec.criteria.md` (sha256 recorded in the state file);
any change requires `ramza-freeze --amend --reason`.

**Revision 2.1.0 amended this set to 32** via one legal `ramza-freeze --amend` batch
(C-13) after vigil's VERIFIED-with-notes attestation: AC-007, AC-016 and AC-017
strengthened; AC-031 and AC-032 added. See §Amendment record below. IDs AC-001..030
keep their meaning except AC-017, whose displaced pin is preserved verbatim as
AC-032.

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

### Amendment record (revision 2.0.0 → 2.1.0, C-13 batch)

One `ramza-freeze --amend` batch, three ruled changes, **no ID churn for the 28
criteria vigil already attested**. New criteria are appended rather than inserted so
every already-attested ID keeps its meaning.

| Criterion | Change | Ruling / finding |
|---|---|---|
| AC-007 | **Strengthened.** Form `ubiquitous` → `event-driven`; GIVEN now mandates an eviction-forcing fixture (four records at relevance 0.9/0.5/0.1/0.05, slot cap forcing ≥1 eviction); VERIFY node renamed `test_records_ordered_by_descending_score` → `test_evicting_slot_emits_descending_score`. THEN unchanged. | DP-R2 / F-V2 — the old fixture never evicted, so attack E left the gate green. |
| AC-016 | **Strengthened.** THEN now binds `truncated_count` to the count *actually removed by the slice*; VERIFY node renamed `test_truncated_count_reports_k_drops` → `test_truncated_count_derived_from_real_slice` and asserts the `records + truncated_count == candidates` identity. | DP-R3 / F-V3 — the arithmetic oracle passed on phantom drops. |
| AC-017 | **Strengthened / re-subjected.** Now pins `k_applied <= k_requested` by construction, the second attack-D failure mode. | DP-R3 / F-V3 — attack D produced `k_applied=20 > k_requested=15` with every oracle green. |
| **AC-031** | **New.** Small-`k` fetch-width regression (`k=3`, flag on, fresh crystal returned). | DP-R1 / F-V1 — seam 3b. |
| **AC-032** | **New (relocation, text verbatim).** The `evicted_count == 0` pin displaced from AC-017. | DP-7 preserved; no coverage lost. |

Unchanged and still attested as-is: AC-001..006, 008..015, 018..030 (28 criteria).
**Total after amendment: 32.**

### AC renumbering (revision 1.0.0 → 2.0.0)

| 1.0.0 | 2.0.0 | Note |
|---|---|---|
| AC-001 | AC-001 | unchanged |
| AC-002 | AC-002 | unchanged |
| AC-003 | AC-003 | now scoped to the flag-on state (C-1) |
| AC-004 | AC-004 | unchanged; now provable (DP-1 O1) |
| AC-005 | AC-005 | scoped to default config |
| AC-006 | AC-007 | `[DP-6]` marker resolved |
| AC-007 | AC-010 | `[DP-4]` marker resolved; split — the ceiling assertions became AC-011/AC-012 |
| AC-008 | AC-014 | unchanged |
| AC-009 | AC-015 | `[DP-3c]` resolved; now enumerates the five bound fields |
| AC-010 | AC-019 | unchanged |
| AC-011 | AC-020 + AC-021 | split: numeric clamp vs non-coercible fallback (C-11) |
| AC-012 | AC-022 | `[DP-8]` resolved |
| AC-013 | AC-023 | unchanged |
| AC-014 | AC-025 | unchanged |
| AC-015 | AC-026 | unchanged |
| AC-016 | AC-030 | moved to the end |
| AC-017 | AC-008 | no longer conditional — DP-2 landed B |
| — | AC-006, AC-009, AC-011, AC-012, AC-013, AC-016, AC-017, AC-018, AC-024, AC-027, AC-028, AC-029 | new obligations created by the rulings (DP-5 both-modes, C-1 flag boundary, C-3 dual-scorer, DP-4d, DP-7 counter split, DP-3c explain keys, C-4, C-9, DP-X/C-7) |

### Exact pytest invocations

```
# Full suite (the AC-030 gate) — container-first, matches Makefile:27-28
make test

# Fast suite (skips @pytest.mark.slow model-download + eval-gate tests)
make test-fast

# The new regression file alone
docker compose run --rm crystalium pytest mcp-server/tests/test_recall_starvation.py -v

# The recall-relevant subset (ranking, budget, fusion, importance, schema, config)
docker compose run --rm crystalium pytest \
  mcp-server/tests/test_recall_starvation.py \
  mcp-server/tests/test_aetheryte.py \
  mcp-server/tests/test_composer.py \
  mcp-server/tests/test_rrf.py \
  mcp-server/tests/test_recall_cli.py \
  mcp-server/tests/test_recall_active_only.py \
  mcp-server/tests/test_diagnosability.py \
  mcp-server/tests/test_importance.py \
  mcp-server/tests/test_evb.py \
  mcp-server/tests/test_schemas.py \
  mcp-server/tests/test_config.py \
  -v

# Slow eval gates (C-6; @pytest.mark.slow, must be invoked explicitly)
docker compose run --rm crystalium pytest \
  mcp-server/tests/test_retrieval_gate.py \
  mcp-server/tests/test_evb_gate.py \
  mcp-server/tests/test_forgetting_gate.py \
  mcp-server/tests/test_prefetch_gate.py -v

# C-5 RED-first proof — run BEFORE applying the fix, from a clean af24493 worktree
# with only the new test file added. Expect AC-001, AC-002, AC-004, AC-005, AC-010 red.
docker compose run --rm crystalium pytest mcp-server/tests/test_recall_starvation.py -v
```

## Test Plan

### New tests

**`mcp-server/tests/test_recall_starvation.py`** — the issue-#36 regression suite.
Model it on the existing fast harness at `test_aetheryte.py:118-149`: a real
`RelationalStore` (so BM25/FTS5 is genuine), `MagicMock` vector store with
`embed.return_value = []`, `MagicMock` graph store with
`neighbor_expand.return_value = set()`, and `Composer(config=cfg,
tokenizer=_word_tokenizer)` where `_word_tokenizer` is one token per word
(`test_aetheryte.py:68-69`). **No `@pytest.mark.slow`** — this suite must run under
`make test-fast`.

Three harness notes that make the suite deterministic, cheap and honest:

1. **Shrink the slot caps in the fixture.** `_make_config` builds config via
   `Config.__new__(Config)` and assigns `cfg.slots` explicitly
   (`test_aetheryte.py:42,56-61`), so the new fixture can set e.g.
   `{"episodic": 20, "procedural": 20, ...}`. With a 1-token-per-word tokenizer this
   forces eviction with five-word summaries instead of requiring 800+ words. Without
   it, the eviction path is effectively untestable at speed — and AC-001/AC-004 are
   eviction-path criteria.
2. **FTS5 does not stem** (`test_aetheryte.py:160-166`): the "distinctive tokens"
   must appear verbatim in both the summary and the query.
3. **The schema round-trip must not be skippable** (C-7). `test_schemas.py:63-77`'s
   `validate()` helper calls `pytest.skip("jsonschema not installed")` on
   `ImportError`; a test built on it can never fail on the defect it names.
   `jsonschema>=4.21` is a declared dependency (`mcp-server/pyproject.toml:45`), so
   AC-028/AC-029 import it unconditionally. Prove the gate bites: temporarily delete
   `budget` from `schemas/recall-result.v1.json` and confirm both tests go red.

Classes: `TestIssue36Regression` (AC-001), `TestKIsACap` (AC-002/003),
`TestRelevanceBeatsImportance` (AC-004), `TestScorePopulated` (AC-005/006),
`TestOrdering` (AC-007), `TestLegacyPath` (AC-008/009),
`TestColdStartImportance` (AC-010..014), `TestBudgetSurfaced` (AC-015..019),
`TestKClamp` (AC-020/021), `TestOversizedSummary` (AC-022..024),
`TestDX` (AC-025..027), `TestSchemaRoundTrip` (AC-028/029),
**`TestSmallKFetchWidth` (AC-031, new at revision 2.1.0)**. AC-032 joins
`TestBudgetSurfaced`.

**Gate-strength obligations added at revision 2.1.0.** Three of the frozen gates were
shown by vigil to be weaker than their criteria. The strengthened tests must be proven
to bite, not merely to pass:

| Node | Attack that must turn it RED | Was |
|---|---|---|
| AC-007 `test_evicting_slot_emits_descending_score` | **E** — delete the seam-5 output sort | GREEN (F-V2): the old 3-record / 800-token fixture never evicted, so insertion order was already descending |
| AC-016 `test_truncated_count_derived_from_real_slice` | **D** — delete `filtered_ids = filtered_ids[:k]`, keep the counter | GREEN (F-V3): the oracle checked arithmetic (`8 - 3`), never that the set shrank |
| AC-017 `test_k_applied_never_exceeds_k_requested` | **D** — same | GREEN (F-V3): shipped `k_requested=15, k_applied=20` |
| AC-031 `test_fresh_crystal_returned_at_k3` | RED-first at `323229f` (C-12) | did not exist |

**`mcp-server/tests/test_composer.py`** — add, in the existing style (hand-built
`_Rec` stubs, `test_composer.py:35-110`): `test_eviction_evicts_least_relevant_first`
and `test_importance_breaks_relevance_ties`. Add a `relevance_score` attribute to
`_Rec`; per C-2 the implementation reads it via `getattr(..., 0.0)` so existing stubs
without the attribute still sort — which is precisely why the four
`TestG6EvictionDeterministic` tests remain meaningful as the equal-relevance case.

**`mcp-server/tests/test_rrf.py`** — add `test_rrf_merge_scored_matches_rrf_merge`
asserting `[cid for cid, _ in rrf_merge_scored(r)] == rrf_merge(r)` over the existing
fixtures. Modify no existing test in this file.

**`mcp-server/tests/test_config.py`** — add `recall_relevance_primary` to the
retrieval-defaults block in the established style (`test_config.py:331-368`):
default `True`, `from_env`, `from_dict`.

### Existing tests likely to need updating

| Test | Anchor | Why |
|---|---|---|
| Four manual `Config.__new__` helpers | `test_aetheryte.py:42`, `test_composer.py:73`, `test_dream_worker.py:34`, `test_dream_scheduler.py:41` | **C-8.** The new `Config` field must be assigned in all four in the same commit or unrelated tests fail with an opaque `AttributeError`. **Most likely source of a broad, confusing break.** |
| `test_composer.py::TestG6EvictionDeterministic` (4 tests) | `test_composer.py:113-213` | Encode the old eviction contract. Extend, do not delete — they survive as the equal-relevance case (C-2). |
| `test_composer.py::TestTotalCap` | `test_composer.py:271-329` | Must stay green **unmodified** — the G6/P0-9 tripwire (AC-019). |
| `test_aetheryte.py::test_recall_all_layers_by_default` | `test_aetheryte.py:208-232` | `k=10` over four crystals; re-check under truncation. |
| `test_aetheryte.py::test_empty_store_returns_empty` | `test_aetheryte.py:195-206` | Asserts `evicted_count == 0`; confirms DP-7 (truncation is not folded in). |
| `test_diagnosability.py::TestRecallExplain` (4 tests) | `test_diagnosability.py:368-482` | New `explain` keys (`k_applied`, `truncated_by_k`) — check for exact-dict assertions. |
| `test_diagnosability.py::test_commit_good_summary_no_advisory` | `test_diagnosability.py:312-325` | Locks the byte-identical clean-path result dict; AC-023 depends on it staying green. |
| `test_schemas.py::TestSchemaFilesAreValidJson` | `test_schemas.py:144-160` | `recall-result.v1.json` gains `budget` and `explain` (DP-X). |
| 23 `.recall(` call sites across 7 files | `test_context_match.py`, `test_deploy_modes.py`, `test_aetheryte.py`, `test_diagnosability.py`, `test_ingest_handler.py`, `test_recall_active_only.py`, `test_roundtrip_handoff.py` | Any assertion on result-set size or order. |

### Eval surface (C-6, mandatory)

`evals/retrieval_gate.py` (`python -m evals retrieval-gate`, `evals/__main__.py:88-89`;
asserted by `test_retrieval_gate.py`, both tests `@pytest.mark.slow`) is the one eval
this change moves, and it moves predictably:

- Its fixture commits 31 short episodic crystals (hub + 2 spokes + 2 noise + 24
  distractors + 2 context, `evals/retrieval_gate.py:88-102`). At ~10 tiktoken tokens
  each that is ~310 tokens against an 800-token episodic cap, so **eviction never
  fires today** and `retrieved` is the whole filtered RRF list (~30 records for
  `relevant = 3`).
- After the fix, `recall(..., k=10, ...)` (`evals/retrieval_gate.py:118-121`) is a
  genuine top-10. Precision rises mechanically in both arms (denominator ~30 → 10),
  so the recorded numbers (flat F1 0.12 / recall 0.67; completion F1 0.18 / recall
  1.0, per the `recall_completion` rationale at `config.py:199`) **will change**. The
  pass predicate is relative (`completion_ok = comp.f1 > flat.f1`,
  `evals/retrieval_gate.py:151`) and should still hold — a **prediction, not a
  measurement**.
- `test_retrieval_gate.py:28-31` asserts `context_pass is False`, which depends on
  `ctx_rank = retrieved.index(ctx_match)` (`evals/retrieval_gate.py:126`) — i.e. on
  **ordering**, which DP-6 changes. This is the single most likely eval break.

**Procedure (C-6):** run before and after, put both JSON outputs in the PR body,
update `evals/BENCH-NOTES.md` §W5(i) with the new numbers and a one-line note that
the shift is caused by `k` becoming a cap. **A flipped `completion_pass` or
`context_pass` is a checker finding — no assertion may be edited to green it.**
Re-run `evb_gate`, `forgetting_gate` and `dream_gate` too: DP-4 raises every newly
committed crystal's baseline from 0.0 to a uniform non-zero value, shifting the
absolute percentile cutoffs those gates compute (`dream/worker.py:547-552`). The
shift is uniform so relative verdicts should hold — verify, do not assume.

### Reproducing the cold-start numbers quoted in §Problem Statement and §D4

```
cd mcp-server/src && python3 -c "
import sys; sys.path.insert(0,'.')
from datetime import datetime, timezone
from crystalium import evb
from crystalium.importance import importance_score
class R:
    access_count=0; outcome_success=None; novelty_at_write=0.5
    last_access=datetime(2026,1,1,tzinfo=timezone.utc)
now=datetime(2026,1,1,tzinfo=timezone.utc)
print('evb fresh:', evb.evb_score(R(), now=now))          # 0.240 -> clamp does NOT bind
print('legacy fresh:', importance_score(R(), now=now))    # 0.525 -> clamped to 0.30
"
```

### Anti-pattern guard (repo memory: "gates are where defects hide")

Per **C-5**, AC-001, AC-002, AC-004, AC-005 and AC-010 must be demonstrated **RED at
`af24493`** before the fix lands, with the failing output recorded in the verify
artefact — a test that passes on the broken build is not a regression test. AC-025 is
written to assert against the runtime `server._VALID_PROVENANCE_SOURCES` rather than a
hardcoded list, and AC-028/AC-029 import `jsonschema` unconditionally, so neither can
pass vacuously.

## Release Plan

**Branch.** `fix/recall-starvation-36` off `Rynaro/crystalium` `main` (`af24493`).

**PR.** One PR to `Rynaro/crystalium` `main`, titled
`fix(recall): make query relevance decisive and k a real cap (#36)`. Body must carry:
the before/after `retrieval-gate` JSON (C-6), the C-5 RED-first output at `af24493`,
the C-1..C-11 checklist with evidence per condition, and the `make test` summary line.

**Version bump.** `1.8.1` → **`1.9.0`** (DP-9, **bound**; reaffirmed by DP-R4(i) —
nothing is tagged yet, so the R1-R3 fixes fold into the same unreleased 1.9.0). Valid *because* DP-2
landed B: nothing is removed, `score` and `budget` are additive, the ranking change
corrects documented behaviour (`"k": "Max records to return"`, `server.py:203-206`),
and the repo's own precedent (`recall_completion=True`, `config.py:199`, which changed
every recall's result set) shipped in a minor. The flag is what makes "minor" honest.
**C-10: if the flag is dropped during implementation, this becomes `2.0.0`
automatically — no re-deliberation.** Edit `mcp-server/pyproject.toml:9`, the single
source that `install.sh:71-75` greps (leave its hardcoded `"1.8.0"` grep-failure
fallback alone; it is not version-tracking).

**CHANGELOG.** New `## [1.9.0] — <date>` block above `## [1.8.1]` (`CHANGELOG.md:7-9`).
Sketch:

```
### Fixed

- **`crystalium.recall` no longer returns query-independent results.** The
  BM25 + dense + graph RRF fusion order reached the composer only as a *fetch*
  order: `Composer.compose()` took no `k` and ranked slot survival strictly by
  `(importance, last_access, id)`, so a topically-unrelated record with accumulated
  access history always outlived a topically-relevant one. Combined with `importance`
  being hardcoded to `0.0` on every episodic/procedural/semantic commit — and with a
  fresh crystal's only routes off 0.0 being an access event it could only earn by
  *already* winning, or an idle-gated Dream sweep — a freshly committed crystal was
  effectively unretrievable, making `commit` silent write-only storage. Relevance is
  now the primary composition signal, with `importance` retained as the secondary.
  Revertible via `recall_relevance_primary: false`. (#36)
- **The retrieval arms' seed width no longer follows the caller's `k`.** Graph and
  completion arm membership was seeded from `dense_ranking[:k]`, so a small `k` changed
  which arms voted, not just how many records came back — at `k<=3` that could push a
  freshly committed, exactly-matching crystal out of the result entirely. Arm seeding
  now uses `max(k, 10)`; the `k` slice remains the only consumer of the caller's `k`.
  (#36)
- **`k` is now an upper bound on the number of returned records.** It previously only
  sized the per-layer candidate fetch (`max(k*3, 10)`) and the graph seed set, so
  `k=3` and `k=15` returned identical result sets. `k` is also clamped to `[1, 100]`
  at the MCP handler and the CLI verb, with a non-coercible `k` falling back to the
  default 10. (#36)
- **A freshly committed crystal now starts at a non-zero `utility.importance`,**
  computed from the layer's injected `importance_fn` (wired into every layer
  constructor but never called) and clamped to a documented cold-start ceiling of
  0.30 so the legacy scorer cannot invert the ranking. No storage migration:
  pre-existing rows keep their stored value and are reachable via the new relevance
  ranking. (#36)
- **`schemas/recall-result.v1.json` now matches the emitted result.** It declared
  `additionalProperties: false` while omitting the v1.6 `explain` field; `budget` and
  `explain` are both declared now, and a round-trip test validates a live
  `RecallResult` against the file. (#36)

### Added

- `CrystalSummary.score` is populated with the raw hybrid-retrieval RRF score
  (previously declared `Optional[float]` and never set), so client-side ranking is
  inspectable. Populated in both ranking modes. (#36)
- `RecallResult.budget` surfaces the working-set token budget, the requested and
  applied `k`, and `truncated_count`. `evicted_count` keeps its existing meaning
  (token-budget evictions only). The hard 3500-token cap (P0-9) is unchanged. (#36)
- `Config.recall_relevance_primary` (default `true`) — set `false` to restore the
  pre-1.9.0 composition ordering, `k` behaviour and result sets. (#36)
- `crystalium.commit` attaches a `summary_size` advisory when a summary cannot fit
  its destination layer's slot. Advisory only — never a rejection. (#36)
- The `crystalium.commit` tool description now names the four accepted
  `provenance.source` literals, and the `TIER_VIOLATION` advice names the
  procedural-candidate fallback and states where caller identity comes from. (#36)
```

**Tag + image.** **C-15 gates the tag:** it is cut only from the HEAD vigil attests in
the appended re-verification (full `make test`, the frozen VERIFY batch against the
amended criteria hash, attacks E and D repeated to RED, the F-V1 four-cell probe, and
the flag-scope grep re-audit). Tag `v1.9.0` on the merge commit. The release runs through
`Rynaro/crystalium`'s own `.github/workflows/release.yml` — the roster records this as
`signer_workflow` (`roster/index.yaml:1353-1359`) rather than the nexus template, so
Roster Intake verifies the attestation against it.

**Downstream nexus dual-roster bump** (`Rynaro/eidolons`, branch
`fix/roster-crystalium-1-9-0`, one PR, both files in the same commit — they are
skew-guarded):

1. `roster/mcps.yaml:164-173` — `versions.latest`, `versions.pins.stable`, and a new
   `releases["1.9.0"]` with `digest` + `released_at`. The `digest` is the **index
   digest from the GHCR registry**, not a local `docker images` value; image tags are
   un-prefixed. Tool count unchanged (8 exposed tools, `roster/mcps.yaml:150-160`) —
   no `exposes_tools` edit.
2. `roster/index.yaml:1360-1373` — `versions.latest`, `versions.pins.stable`, and a
   new `releases["1.9.0"]` with `tag`, `commit`, `tree`, `archive_sha256`,
   `provenance`. `archive_sha256` is the sha256 of the **raw tarball including the
   path prefix**; the integrity PR gets no CI, so compute and verify locally.
3. Run `make schema` in the nexus before pushing.

## Risks + Rollback

| # | Risk | Likelihood | Impact | Mitigation (post-ruling) |
|---|---|---|---|---|
| R-1 | The ranking change makes some real consumer's recalls worse on a corpus we cannot see. | med | high | **Closed to a one-line revert** by DP-2=B: `recall_relevance_primary: false`. Documented in the CHANGELOG `### Added` entry, not only in `config.py`. |
| R-2 | `retrieval_gate` numbers shift and someone "fixes" the assertion instead of investigating. | high | med | **C-6**: before/after JSON in the PR body; a flipped `completion_pass`/`context_pass` is a checker finding, never a test edit. Vigil verifies the recorded numbers were actually produced. |
| R-3 | A new `Config` field breaks the four manual `Config.__new__` helpers with an opaque `AttributeError` far from the change. | high | low | **C-8**: all four updated in the same commit as the field. |
| R-4 | `_ComposerRecord.__slots__` edited without the matching `__init__` change (or vice versa) — `AttributeError` only on the hot path. | med | med | S-1's output contract; `test_rrf.py` and `test_aetheryte.py` both exercise the path. |
| R-5 | Legacy scorer (`evb_enabled=False`) gives fresh crystals 0.525 and inverts the starvation — and because `persist_dynamics` is off there, the value is **durable**, not transient. | low | high | **Mechanically closed** by DP-4=C: `min(importance_fn(...), 0.30)`. **C-3** asserts the cold-start value under both scorer configs. No longer mitigated by documentation. |
| R-6 | `k` truncation silently hides records a caller previously received. | med | med | **Closed** by DP-3c + DP-7: `budget.truncated_count` is default-visible (not explain-gated) and `explain.truncated_by_k` adds depth. |
| R-7 | The composer is recently fragile — v1.8.1's own fix (`CHANGELOG.md:9-23`) was a composer-path crash on a stored special-token string. New sort keys touch the same hot path. | med | high | **C-2**: `getattr(rec, "relevance_score", 0.0)`; the `try/except` around `composer.compose()` (`retrieve.py:499-514`) and the assertion at `composer.py:269-272` stay intact. |
| R-8 | The commit advisory tokenises every summary, adding latency or a new crash surface on the write path. | low | med | **C-4**: reuse the hardened module-level tokenizer (`composer.py:99`, post-#32); any tokenizer exception skips the advisory silently (AC-024). Do not add a scaled perf budget (repo memory: perf gates measure the runner). |
| R-9 | The published `recall-result.v1.json` is already out of sync (`additionalProperties: false`, no `explain`); always-on `budget` would make every response formally invalid. | high | med | **Closed** by DP-X in this release, plus **C-7**'s round-trip test — and the test must not use the skip-on-ImportError helper, or the gate cannot fail on the defect it names. |
| R-10 | The flag doubles the behavioural surface: two ranking modes to reason about and support. | med | low | Flag scope is bound to exactly seams 3+4+5 (**C-1**); AC-008/AC-009 pin the boundary so "what the flag does" is test-defined rather than folklore. |

**Rollback.** Three levels, cheapest first:

1. **Config revert** (available — DP-2 landed B): set `recall_relevance_primary:
   false`. Restores pre-1.9.0 ordering, `k` behaviour and result sets; no image
   redeploy beyond a restart. `score`, `budget` and the clamp remain live.
2. **Version pin revert:** in the nexus, set `versions.pins.stable` back to `1.8.1`
   in **both** `roster/mcps.yaml` and `roster/index.yaml` (keeping `1.9.0` in
   `releases`), then re-run `eidolons mcp verify` — remembering exit 3 is
   INDETERMINATE, not a pass. Both files must move together (skew guard).
3. **Revert the PR** and cut `1.9.1`. No storage migration was performed, so no data
   unwind: crystals committed under `1.9.0` carry a non-zero `utility.importance`,
   which `1.8.1` reads without complaint (same field the composer already falls back
   to at `retrieve.py:469-473`).

**Not rolled back by any of the above:** `utility.importance` values written by
`1.9.0` commits persist. Benign under DP-4=C — the clamped values (0.240–0.30) sit
inside the range Dream would have produced anyway — but it is the one irreversible
footprint of this change and belongs in the PR body.

## Confidence

**88.25 / 100 — verdict `AUTO_PROCEED`** (`ramza-score --rubric confidence`:
`pattern_match 88`, `requirement_clarity 95`, `decomposition_stability 88`,
`constraint_compliance 82`). Computed by tool, not estimated in prose; inputs and
verdict appended to `.spectra/plans/crystalium-recall-starvation-36.state.json`.

Up from **80 / VALIDATE** at revision 1.0.0. `requirement_clarity` moved 70 → 95:
every Decision-Point is bound with an operative instruction, and eleven CONDITIONS
convert the previously-soft guards into merge blockers. `constraint_compliance` is
the lowest dimension at 82 — not because a constraint is violated, but because C-5,
C-6 and C-7 are *executable* obligations that cannot be discharged from a read-only
planning pass; they are asserted, not observed.

Residual uncertainties, in order: (1) the unmeasured `retrieval_gate` delta — predicted
in §Test Plan, but running it requires a container build outside a read-only pass, so
C-6 is the real check; (2) the flag boundary (C-1) has one genuinely surprising
consequence — with the flag off, `k` is **not** a cap — which AC-009 pins but which
a reader could miss; (3) the exact `TIER_VIOLATION` wording, deliberately left as a
draft under C-9's verify-before-merge gate.

**`AUTO_PROCEED` is the rubric's verdict on the artefact's content, not a licence to
skip the remaining gate.** The full-tier critic gate is still open (§Gate record);
`ramza-gate advance --to A` continues to DENY, and that DENY stands.

**Revision 2.1.0 note.** The three findings that forced this amend were all
*gate-strength* defects, not behaviour defects — vigil verified the shipped behaviour
correct in every case and the gates weak. That is the failure mode this campaign's own
risk table (R-2, R-9) and the repo doctrine ("a gate that cannot fail on the defect it
names is not a gate") predicted, arriving in the criteria the planner wrote. Confidence
is not re-scored upward on that basis: the amendment closes three gaps a fresh-context
checker found, which is evidence the review chain worked, not that the artefact was
stronger than measured.

## Gate record

| Gate | Tool | Result |
|---|---|---|
| Right-size | `ramza-rightsize --files-est 12 --public-api --novel --stakes high` | score 6 → **full** |
| Complexity | `ramza-score --rubric complexity` | 11 → **human_loop** (routed to FORGE; rulings received) |
| Explore | `ramza-score --rubric explore` ×6 | H-E-prime 85.5 elite (**ratified as DP-1 O1 + gate**); H-E 85.0 elite (**rejected** as DP-1 O3); H-A 77.0; H-B 72.5; H-D 70.5; H-C 60.0 weak |
| Deliberation | FORGE `deliberation.md` | 9 DPs + DP-X + 11 CONDITIONS ruled; **0 escalations**; 2 planner recs overturned (DP-4), 1 close call closed (DP-1) |
| Structural lint | `ramza-lint --plan spec.md --state <state>` | **PASS** (full tier) |
| Criteria grammar | `ramza-ears-lint spec.md` / `spec.criteria.md` | **PASS** — 32 criteria (was 30 at rev 2.0.0) |
| Emission | `ramza-verify-emit --spec spec.md` | **PASS** |
| Scope declared | `ramza-drift --declare` | 16 globs recorded in state |
| Criteria freeze (rev 2.0.0) | `ramza-freeze --criteria spec.criteria.md` | **FROZEN** `sha256:8fd32daf09b7d500913fe9f46c1647b0bc5fd0ee53b3660e6bd36b314279f577` — the hash vigil verified against at `323229f` |
| Criteria amend (rev 2.1.0) | `ramza-freeze --amend --reason` | **AMENDED** — see §Amendment record; new hash below; hash-chained in `state.amendments[]` |
| Implementation verify | vigil, `verification.md` | **VERIFIED-with-notes** at `323229f` — 30/30 frozen ACs, 896 passed / 2 pre-existing skips, 5 of 6 gate attacks fired; F-V1/F-V2 MAJOR, F-V3 MINOR |
| Post-verification deliberation | FORGE `deliberation.md` §R-docket | DP-R1..DP-R4 ruled, C-12..C-16 added, **0 escalations** |
| Confidence | `ramza-score --rubric confidence` | 88.25 → **AUTO_PROCEED** |
| Critic (maker≠checker) | `ramza-gate critic --author ramza --checker <critic>` | **OPEN — NOT RECORDED.** `advance --to A` returns DENY. The plan's author cannot be its critic (`ramza-gate` exits 1 on self-approval; `skills/critic.md` P0-1 and step 1). Requires an independent identity. |

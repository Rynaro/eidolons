# Campaign state — COMPLETE 2026-08-06, record closed 2026-08-07

Both batches shipped. Independent checker verdict **APPROVE**. All 8 issues closed.

> Superseded note: this file previously read "halted 2026-08-06 on API monthly spend limit"
> and "0 of 8 issues are at a terminal state." That was true at 09:31 on 2026-08-06 and
> false by 23:12 the same day — the campaign resumed and finished. It sat stale for ~10
> hours while artifacts landed beside it. Kept as a marker: the halt was real, the halt
> was not the ending.

## Outcome

| batch | version | commit | PR | contents |
|---|---|---|---|---|
| Phase 1 | **v2.0.2** | `ff4fb5d` | #61 | shared rig + 5 gate/entrypoint units |
| Phase 2 | **v2.1.0** | `d243789` | #62 | the 3 real recall defects (#45 -> #44 -> #42) |

`release/v2.1.0` is an ancestor of `origin/main` (merge `d1691db`). Tagged
2026-08-06T23:12:02Z. W-CLI (`chore/eval-cli-registration`) and W-DOC
(`docs/disposition-55-47`) — listed as quarantined and unverified in the halted version of
this file — both finished and merged.

### Issues: 8 of 8 CLOSED (2026-08-06 22:52)

| issue | disposition |
|---|---|
| #57 | fix built + green (server entrypoint smoke) |
| #52 | gate built (strict xfail, self-enforcing) |
| #47 | **WONTFIX-with-rationale** + gate |
| #55 | **band formally unsupported**; item 2 dropped (premise false) |
| #48 | **SPLIT** — AC-138/139 RETIRED (shipped fixture), AC-322 DISCHARGED (new fixture) |
| #45 | fixed (cross-layer rank blocking) |
| #44 | fixed (sparse status top-up) |
| #42 | fixed (seed exclusion relax; default `False` per FORGE) |

Closing comments in `closing-comments/`.

## Verification

**Checker verdict: APPROVE** (`checker-report-v2.1.0.md`). Maker `ramza` != checker `kupo`.

The original v2.1.0 verdict was **REJECT** on two blocking items. Both were resolved and
then **independently re-reproduced by the checker with its own commands and its own
comparator** — not by re-reading the coordinator's artifacts:

- **AC-382** — the collection sweep produced 2 spurious BLOCKERs (RC-4: parametrized tests
  collect as `name[T1]` while criteria reference the bare name; a third instance was
  MASKED by a stale manifest entry, which is worse — the manifest was hiding a live defect
  rather than declaring a pending one). Fixed by normalising both sides before the
  set-difference, and by emptying the manifest as each wave lands. Checker re-ran it from
  scratch, then red-checked it with a fabricated node id: **1 BLOCKER, exit 1**. Live, not
  vacuously green. REJECT withdrawn.
- **AC-361** — 11 unmasked wire differences. Root cause: the golden baseline is
  `golden-wire-v1.11.0.json`, predating the deliberate v2.0.0 tool-rename and `isError`
  changes. Against the correct v2.0.2 baseline: **0 differences**. Sanity-checked against
  crystalium's own CHANGELOG, not taken on faith. REJECT withdrawn.

```
make test     -> 1097 passed, 4 skipped, 1 xfailed   EXIT=0   (867.02s)
make test-ci  -> 1093 passed, 8 skipped, 1 xfailed   EXIT=0   (331.74s)
CI literal    -> 1093 passed, 8 skipped, 1 xfailed   EXIT=0   (docker run, BAKED image)
```

`make test-ci` is **not** CI's invocation (K-N11) — it bind-mounts `.:/app`, shadowing the
image, so it cannot detect a packaging or baked-source defect. CI's literal steps were
reproduced separately and the baked source **asserted** (version 2.1.0,
`_FALLBACK_VERSION` 2.1.0, `recall_seed_derived_credit` default `False`, `sparse_topup`
present) before the green was accepted.

Three axis-independent checker red-checks, each reddening a gate on the #45/#44/#42
mechanism itself and each restored to green (`checker-redcheck-v2.1.0.json`). None replays
a maker axis — proven by patch-diff against all three `red-evidence-*.json`.

### Post-merge CI — the one open condition, now discharged

`ci-reproduction-v2.1.0.md` left exactly one follow-up open: GitHub Actions created no run
for PR #62 (most consistent with exhausted runner minutes), so three of CI's four jobs were
never reproduced. **Both workflows ran green on `main` after the merge**, 2026-08-06T23:08:40Z
— CI (4m37s, run 31129929697) and EIIS + ECL Conformance (1m55s, run 31129929723). No
fix-forward needed.

## Roster / nexus

| step | PR |
|---|---|
| publish CRYSTALIUM v2.1.0 (and v2.0.2) — both `roster/mcps.yaml` and `roster/index.yaml`, one commit | #545 |
| cut nexus v2.17.0 | #546 |
| record v2.17.0 integrity metadata | #547 |
| re-pin this project's crystalium wiring to 2.1.0 | #548 |

Stated deviation (`release-digests.md`): ONE roster bump to the final campaign version
rather than the plan's per-batch chain. Recorded openly, not absorbed.

## Planning record

Criteria chain: `eb0492ff -> a40c0d42 -> 7e680dc6 -> f385f39b -> b6be3ad5 -> 50803a00 -> 73419a70`

**64 criteria in force** (66 defined, AC-319/AC-320 STRUCK per K-B6/FORGE D4). amend-02 is
fully superseded — every criterion it defined is redefined by amend-03 or amend-04. Two
Kupo critiques (REJECT, then ACCEPT-WITH-AMENDMENTS), 9 FORGE rulings + the fence ALLOW +
the #48 SPLIT.

**Fixed at record-close:** `crystalium-residual-eight-plan.state.json` recorded
`criteria_sha256 = 50803a00` (amend-03 rev2) and its amendment chain stopped there —
amend-04 was applied to disk on 2026-08-06 but never chained. The frozen hash therefore
excluded the criteria the checker actually ran against. Backfilled 2026-08-07;
`criteria_sha256` is now `73419a70`.

## Carried forward — filed, not lost

| # | what | why non-blocking |
|---|---|---|
| [#63](https://github.com/Rynaro/crystalium/issues/63) | no criterion binds #44's censoring-signal recompute to an observable outcome on any of its 3 widen sites | the merge-skip axis the checker pivoted to does flip AC-346, so #44's fix is gated |
| [#64](https://github.com/Rynaro/crystalium/issues/64) | `compare_wire.py` reports WIRE IDENTICAL on a null `serverInfo.version` | v2.1.0 verification used a shape-guard-first wrapper instead |
| [#65](https://github.com/Rynaro/crystalium/issues/65) | re-baseline the golden wire capture to v2.0.2 | ruled explicitly non-blocking for this tag |

## The lesson this campaign kept re-learning

A criterion is not trustworthy because it was carefully written — only because it was
executed against **both** a passing and a failing input. AC-382 is the case in point: a
gate written specifically to catch criteria naming nodes that do not exist, which itself
accumulated **four** defects, every one found by RUNNING it —

1. **RC-1** phantom BLOCKERs from grepping superseded criteria files
2. **RC-2** the gate reported success having checked **1 of 20 nodes**, because
   `docker compose run` consumed the loop's own stdin
3. **RC-3** wave ownership inferred from file existence
4. **RC-4** parametrize brackets, with one instance masked by a stale manifest

RC-2 is the campaign's thesis written into the gate meant to prevent it. The
naming/anchor species recurred **12 times across 4 amendments**, each time despite an
explicit global rule against it — the 12th inside a detector added specifically to catch
fence breaches. The guard needed a guard.

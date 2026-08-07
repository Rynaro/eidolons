# VP-M1 (preliminary, `retrieved`-only) — floor-channel prediction

Measured 2026-08-05 on crystalium `b7f1a47`, container-only, 7 spawned processes
(`PYTHONHASHSEED` 0-5 plus one run OMITTING `-e` entirely per K-N17).
Probe: `evals.fusion_gate.run_floor_probe(floor=..., weighted=...)`, both arms.
Raw: `vp-m1-floor-channel.json`.

## Result

| seed | unweighted differ | weighted differ |
|---|---|---|
| 0,1,2,3,4,5,unset | false | false |

`channel_live == false` — 14/14 comparisons identical. Sample (seed 0, unweighted):
`f10_retrieved == f1000_retrieved == ["Z","target"]`, both `target_rank == 1`.

## What this DOES establish

`FETCH_WIDTH_FLOOR` 10 vs 1000 produces **no observable difference at the fused surface**
on the existing fusion fixture, deterministically, at every seed. spec.md §4 (#48)'s
prediction — that #41's all-seed expansion removed the floor's channel on this topology —
is **CONSISTENT WITH** the measurement and is not refuted.

## What this DOES NOT establish (FORGE D5's one-sidedness — stated, not buried)

This probe reads `run_arm`'s `retrieved` list only. Differing fused lists would PROVE the
channel live; identical fused lists do **NOT** prove the derived-arm MEMBERSHIP is identical.
The channel could be live at the derived-arm level and masked downstream by weights, RRF
tie-breaks, or the `[:k]` window. Carrying "channel dead" forward on this evidence alone
would be the campaign's own named defect class — an artefact presenting as evidence for a
claim it structurally cannot support (#52's species).

**Therefore:** `channel_live=false` is recorded as NOT-REFUTED, not as CONFIRMED. The
definitive measurement is FORGE D5's probe (recording spy at the `graph_store` seam, in
`evals/floor_sensitivity_gate.py`, with the `run_floor_probe` self-check). Until that runs,
no downstream artefact may cite this as proof the channel is dead.

## Collateral finding — the tree carries a stale contradicting claim

`evals/fusion_gate.py:72-92` and `:296-311` assert in prose that the floor channel is live
and measured. That text predates #41. This measurement contradicts it at the fused surface.
One of the two is stale; the prose has no measurement behind it on the post-#41 tree.
Whatever VP-M1's definitive form concludes, that prose must be corrected or dated — it is
currently a claim in the shipped source that the shipped source does not support.

## Routing (unchanged either way, per spec.md §4 #48 / verification-plan VP-M1)

The new tie-break-neutral fixture gets built regardless of outcome; only the carried-forward
prose differs. S-5 remains live: if no fixture makes the floor change the fused rank
deterministically post-#41, AC-138/AC-139 are RETIRED with a mechanism note (FORGE D9
class (c)) — never a permanent strict-xfail, never a fabricated pass.

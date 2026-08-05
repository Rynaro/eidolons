# DP-2 positive control (AC-204) — PASSES, on the retrieval gate

## Correction to the execution plan
The plan named `evals fusion-gate` for the DP-2 sweep. That is the WRONG gate and the
control fails there for a benign reason: on the fusion fixture the only competitor for
rank 0 is the graph-only phantom `Z`, so LOWERING `fusion_weight_derived` only demotes
`Z` and `target` holds rank 0 at every sub-1.0 value. Measured at 56c8510, seed 0:

    w_derived: 0.0 0.5 0.9 1.0 -> gate_pass True   (weighted=['target','target-sem'])
    w_derived: 5.0 100.0       -> gate_pass False  (weighted=['Z','target'])  <- P1 inversion

That above-1.0 flip proves the injection is effective; it is not an inert harness.

## The cliff lives on the RETRIEVAL gate
`deliberation.md:169-172` gives the mechanism: spoke2's sole vote is `w_derived/(60+r)`
against a distractor at `0.0149254`, at the last k=10 slot. `spoke1/spoke2/hub` are the
retrieval-gate fixture (k=10); the fusion gate is `target`/`Z` at k=2. Arithmetic:
    0.95/63 = 0.0150794 (r=3, green)   0.95/64 = 0.0148438 (r=4, red)
    0.90/63 = 0.0142857 -> below the distractor at EVERY rank => deterministic fail.

## Measured at 56c8510 (pre-fix), retrieval gate, 4 Aetheryte instances per run
| w_derived | seed 0 | seed 5 | recorded claim            | verdict     |
|-----------|--------|--------|---------------------------|-------------|
| 0.90      | RED    | RED    | fails deterministically   | reproduced  |
| 0.95      | RED    | GREEN  | FLAKE                     | reproduced  |
| 1.00      | GREEN  | GREEN  | passes                    | reproduced  |

## Finding worth carrying forward
The 0.95 flake appears at the OPPOSITE seeds from the #38 record (recorded: green 0-4,
red at 5; measured now: red at 0, green at 5). The flakiness reproduces; the seed->outcome
mapping does not. Consistent with DP-2's own attribution — `r` is hash-nondeterministic
because of the open `neighbor_expand` bug (#41), and ids are uuid4-fresh per run, so the
seed mapping was never a stable quantity. Post-#41 this sweep should become degenerate;
residual seed-dependence after the fix is a NEW finding, not a re-run of this one.

## Consequence for W1b
The post-fix DP-2 sweep MUST run against `python -m evals retrieval-gate`, not fusion-gate.
Injection point: `Aetheryte.__init__` (read back off the instance, never off the kwarg dict
— the kwarg readback is a tautology).

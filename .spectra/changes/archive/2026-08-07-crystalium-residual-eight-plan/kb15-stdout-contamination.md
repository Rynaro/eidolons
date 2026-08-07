# K-B15 (found by execution, not review) — structlog contaminates stdout, breaking every `| jq` criterion

Discovered while capturing VP-B3 on 2026-08-05. Kupo could not have found this by reading;
it requires running the command.

## Observation

`docker compose run --rm crystalium /app/.venv/bin/python -m evals fusion-gate` writes
structlog lines to **stdout**, ahead of the JSON result:

```
2026-08-05 22:42:01 [debug    ] tokenizer_backend              backend=tiktoken_cl100k_base
2026-08-05 22:42:01 [info     ] recall_ok                      after_compose=2 ... query_len=35
2026-08-05 22:42:01 [info     ] recall_ok                      after_compose=2 ... query_len=35
{
  "weighted": { ... },
  "gate_pass": true,
  ...
}
```

Only docker's own `Container ... Creating/Created` chatter goes to stderr. Verified by
redirecting each stream separately.

## Consequence

Every acceptance criterion of the paste-able form `... python -m evals <gate> | jq -e '<pred>'`
fails with `jq: parse error: Invalid numeric literal` **regardless of what the gate measured**.

Affected criteria (spec.criteria.md): AC-310, AC-312, AC-314, AC-317, AC-319, AC-322,
AC-344, AC-352 — i.e. the primary oracle of every Wave-1 gate plus the AC-125 seed protocol
and the DP-1(b) re-check.

First observed empirically: a 7-seed VP-B3 capture returned `rc=0` on all seven runs with an
EMPTY `gate_pass` for each. Exit code 0, no signal. This is the "fail-open hides dead kernels"
shape — silence is not health.

## Severity

This is a FALSE-NEGATIVE class defect (criterion reads red while the gate is fine), which is
less dangerous than the false-positive class Kupo catalogued, but it breaks the entire
Wave-1 exit gate and would be misread as "the gate is red" — which for G-XL, a gate that is
SUPPOSED to be red, is indistinguishable from success. That coincidence is the dangerous part:
**AC-310 would "pass" for a reason unrelated to the defect it names.**

## Required fix (for the amendment)

Every gate criterion must extract the JSON deterministically rather than piping raw stdout.
Either:
  (a) each gate module writes its result JSON to a `--out FILE` path and the criterion reads
      that file (preferred — no parsing heuristics, and the artefact is retained as evidence); or
  (b) the criterion pipes through `awk '/^\{/{f=1} f'` / `sed -n '/^{/,$p'` before `jq`.

(a) is preferred: it also gives every red-check a durable artefact instead of a scrollback.

Whichever is chosen, the criteria must additionally assert the JSON parsed — a bare
`jq -e '<pred>'` on unparseable input exits non-zero and is indistinguishable from a
legitimate red.

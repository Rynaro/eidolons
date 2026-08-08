# Drift check at record-close — 2026-08-08 — CLEAN, with a stated caveat

Run as the `verified → archived` precondition for both `routing-recall-gap` and
`chain-three-class`, after checker `kupo` APPROVED each (round 4 and round 3
respectively).

## Verdict: CLEAN — 0 undeclared paths

Comparing the union of the two `spec.yaml` `files_touched` declarations against
everything that actually changed across the campaign
(`e427d07..HEAD`, spanning PR #551, PR #553 and the `esl-close` remediation):

| changed path | declared by | status |
|---|---|---|
| `roster/routing.yaml` | both | in scope |
| `cli/src/run.sh` | routing-recall-gap | in scope |
| `cli/src/harness_hook.sh` | routing-recall-gap | in scope |
| `cli/src/eval.sh` | routing-recall-gap | in scope |
| `cli/tests/harness.bats` | routing-recall-gap | in scope |
| `cli/tests/eval.bats` | routing-recall-gap | in scope |
| `cli/tests/routing_chains.bats` | chain-three-class | in scope |
| `evals/routing-suite.yaml` | both | in scope |
| `scripts/verify-recall-mutation.sh` | routing-recall-gap | in scope |
| `methodology/cortex/chain-templates.md` | chain-three-class | in scope |
| `EIDOLONS.md` | routing-recall-gap | in scope |
| `CHANGELOG.md` · `VERSION` | both | in scope |
| `.spectra/changes/{routing-recall-gap,chain-three-class}/` | respective | in scope |

No undeclared paths. No declared-but-unchanged paths (`cli/src/eval.sh`,
`cli/tests/eval.bats` and `EIDOLONS.md` changed in the original `ec92dce`
merge rather than in the remediation, so they are in scope for the change as a
whole). Working tree clean apart from a pre-existing untracked `.atlas/`.

## Caveat — this check is WEAKER than it looks, and should not be read as equal to a plan-time freeze

`spec.md` and `spec.yaml` for both changes were **written during this closing
pass**, after the code had shipped — they did not exist at plan time, which is
why ESL check `C3` (`tier_artifacts_present`) was failing on both records while
`tonberry verify` reported `exit_code: 0` in warn mode.

A declaration authored *after* the work cannot disagree with the work. This
check therefore answers "did anything land outside the stated scope?" — a real
but weak question — and **cannot** answer "did the design move away from what
was planned?", which is the question a frozen `declared_scope` exists to
answer. The two archived crystalium campaigns of 2026-08-07 make the same
distinction; the residual-eight record could find real drift precisely because
its declaration was frozen before the design moved.

What partially substitutes for it here is four rounds of independent checking
against the *behaviour* rather than the declaration: two checkers rejected
three times between them, and every rejection was a property the record
asserted and the code did not have. That is a stronger signal about
spec-vs-impl agreement than this table is — but it is not drift detection, and
recording it as such would be the same species of overclaim this campaign spent
four rounds removing.

## Checker identity

Maker: `vivi`. Checker: `kupo` (distinct actor, clean context, dispatched
per-change). C4 maker ≠ checker holds; the maker did not sign either verdict.

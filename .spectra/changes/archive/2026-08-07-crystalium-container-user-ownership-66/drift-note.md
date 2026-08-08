# Drift check at record-close — 2026-08-07 — CLEAN, with a stated caveat

Run as the `verified -> archived` precondition, after checker kupo APPROVED at `760405e`.

## Verdict: CLEAN — 0 mismatches

Comparing the declaration against the actual tree `d1691db..a587ae1` (campaign base -> merged
`main`, spanning PR #67 and PR #68):

| declared (`spec.yaml` files_touched) | changed in tree | status |
|---|---|---|
| `Dockerfile` | yes | in scope |
| `docker-compose.yml` | yes | in scope |
| `Makefile` | yes | in scope |
| `.github/workflows/ci.yml` | yes | in scope |
| `CHANGELOG.md` | yes | in scope |
| `scripts/check-ownership.sh` | yes | in scope |

Six declared, six changed, **no undeclared paths**. The crystalium working tree is clean
(`git status --porcelain` empty) and `main` is at `a587ae1` with both post-merge workflows
green.

## Caveat — this is a WEAKER check than the one it resembles, and should not be read as equal

The residual-eight drift check (archived same day) compared against a `declared_scope` that
was **frozen at plan time**, `2026-08-05T21:35:48Z`, before the design moved. That is what
made it able to find real drift: the declaration could disagree with the work, and it did.

This change had no such declaration:

1. **`change.json` carried no `declared_scope` at all.** `mcp__tonberry__propose` does not
   scaffold one, and nothing added it. The drift comparison therefore had no machine-readable
   input in the manifest — `spec.yaml`'s `files_touched` served as the declaration by
   convention only.
2. **`files_touched` was maintained alongside the work, not ahead of it.**
   `scripts/check-ownership.sh` was created in `a587ae1` and added to `files_touched` in the
   same working session, as part of the REJECT-01 remediation.

A declaration that is updated whenever the work grows cannot disagree with the work. So
"0 mismatches" here means *"nothing was built outside what the spec was made to say"*, not
*"nothing was built outside what was committed to in advance."* Those are different claims
and only the second is a real drift check.

This is recorded rather than smoothed over because a clean drift verdict on a self-updating
declaration is exactly the shape of a gate that cannot fail — the species this whole change,
and the campaign it followed, exist to document.

**Remediation for future changes, not retrofittable to this one:** `declared_scope` should be
written into `change.json` at `proposed`, before implementation, and any later widening should
be an explicit amendment with its own record (as the residual-eight scope amendment was).

## Recorded at close

`declared_scope` is now written into `change.json` so the archived record is self-describing
and a future re-check can be mechanical. It is stamped `declared_at: record-close` to mark
that it was NOT a plan-time commitment and carries none of that authority.

It covers both repos, which the single-repo `files_touched` did not:

- the six crystalium paths above
- `.spectra/changes/crystalium-container-user-ownership-66/*` — the ESL artifacts, which live
  in the nexus rather than the code repo. The residual-eight record declared its own artifact
  path this way; this one did not until now.

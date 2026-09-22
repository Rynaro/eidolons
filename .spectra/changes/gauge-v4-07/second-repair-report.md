# V4-07 bounded empty-set and numeric repair

Actor: Vivi `/root/vivi_v4_07_empty_sets`. Sole source/test writer for this repair in `/private/tmp/eidolons-gauge-v4-07`; CRYSTALIUM unavailable. Incoming VIGIL envelope d99fc8f6-a6ae-481e-90cb-93070ab583f7 was accepted only after reading the actual keyed SHA-256 verify_pass in the review scratch directory. Seed: original spec/decisions, current source and localized independent report; no prior maker conversation/reasoning or attempt diffs read.

## Change

One source candidate changes `gauge/internal/contract/policy.go`: `Allowed` and `Billing` use `omitzero`, retaining nil omission and explicit-empty arrays throughout JSON persistence, normalized preference/request digests, and policy provenance. Nonempty behavior and semantically neutral Denied/Ceilings omission are unchanged. Ceiling validation checks the floating-point sign bit, rejecting negative input that underflows to signed zero, as well as other negative/nonfinite values. Existing numeric identity normalization remains untouched.

Additive `gauge/internal/store/reviewer_regressions_test.go` is the exact independent oracle, SHA-256 `4f7da1a9e3ba47befd36d28c6069ea2522f6d3b328018d812a7292f05b880b15`. No helper collisions. All 170 test/fixture files were frozen before source edits; final byte hashes match. No existing tests were formatted or edited. No docs, lifecycle, commits, push, publication, merge, paid calls or live authority operations performed.

## Verification

The real protected substrate reports `final=passed`, `red_gate=verified-red`, `k=2`, one repair candidate, two evaluation attempts (initial red, then green twice), `tamper_rejections=0`, `merged=false`. See `qualified-loop.stdout.json`, `qualified-loop/loop.json`, complete per-phase command/output/exit records and `phases.json`. Regression-first includes inherited Go race tests, Go vet and all 29 Gauge/compatibility Bats cases. Reproduction explicitly runs every `TestV407` and `TestReviewer`. Lint hook compiled all packages and ran vet before re-testing.

Fresh pre-edit failures independently reproduced persistence widening, request identity collision, authorized-empty-patch substitution, and negative underflow. After repair, both acceptance passes preserve explicit empty permission/billing arrays, reject altered authorized patches, and reject -1e-1000. All paired controls passed, including nonempty intersections, missing authorizer rejection, rollback/replay/reopen, distinct scopes and exact revision provenance 9007199254740993.

Separate full Go race suite and vet passed with reviewer tests present explicitly in verbose output; existing primary T01–T08 discovery passed without changing its script. Real predecessor CLI migration passed against stable old06 source aa155c8738209f1672cc3fc663b0019740ba54a6. Full combined log: `phase.bs0ncJ`, exit 0.

Execution used the qualified pinned Go1.27.1/Bats1.11.1 Linux image, network none, read-only source and root, UID501:GID20, dropped capabilities, no-new-privileges, executable tmpfs, local/offline Go toolchain and scoped caches. `docker-via.sh` retains exact launch settings. Runner hashes match their initial freeze.

An initial runner setup omitted the nine Gauge Bats anchors (20 CLI cases only). It was terminated before any source edit; its orphaned hook only captured feedback and waited before termination. All logs and scripts remain preserved; it supplies no acceptance claim. A newly named immutable corrected runner includes all29. See `setup-omission.md`; no active script was edited. There was no failed source-repair candidate or self-repair cycle.

## Frozen handoff

- `repair.diff`: exact repair-only source plus additive-oracle diff; SHA-256 48c4f40852be383b2594d24b1f16d5e68aef250d3421fbd85e3f2f5af33371b5. The substrate candidate diff is the entire current working-tree diff from predecessor HEAD and is not the repair-only diff.
- `source-freeze.json`: repaired Gauge file hashes; contract source SHA-256 bd24e0e7aefb8018795904479e26d54c81c839d5958cb75ca907945d3ee2c7e1.
- `protected-before.json`, `protected-after.json`, `protected-verification.json`: frozen test/fixture integrity.
- `qualified-runners-before.json`, `runners-after.json`: stable runner integrity.
- `phases.json`: every preserved phase command, log, exit and SHA.

Local fixture repair verification is complete. Independent checker re-evaluation and root-owned native macOS checks remain separate. Hosted CI/publication remain blocked/pending under the original boundary; production activation remains authorizer_boundary_unqualified. This handoff grants no live, release or merge acceptance. Source/test write authority is yielded to root after this freeze.

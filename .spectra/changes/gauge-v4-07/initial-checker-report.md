# V4-07 independent review — changes required

Checker: `v4_07_review` (VIGIL), distinct from maker and repair actor. Review scope: frozen local fixture implementation only. Production activation remains intentionally `authorizer_boundary_unqualified`; no production exploitability, hosted CI, publication or merge acceptance is claimed.

Fresh context was spec/artifact-only preparation before source freeze. Later root coordination disclosed a prior repair, its green native/Linux status and docs-only writer. No maker reasoning/conversation or maker tests were read. Independent executable probes were written from the prepared matrix and production APIs. All candidate source remained untouched; the harness is a byte-identical production-only copy plus independent tests outside the repository. CRYSTALIUM unavailable.

## [FINDING-01] P1 — explicit empty allow/billing sets disappear in persistence and request identity

**Observed twice with paired controls; confidence H for the observable contract violation.** Canonical R02/R03/R04/R06/R07 and the binding decision require restrictive set intersection, immutable semantic identity, and authorization bound to the actual canonical patch.

Source anchors (relative to candidate): `gauge/internal/contract/policy.go:55–59` gives `Allowed` and `Billing` `omitempty`; `:117` and `:263–272` marshal those restrictions into preference and request digests. `gauge/internal/store/policy.go:177–200` persists the same representation; `:274–277` distinguishes nil (no restriction) from explicit empty (allow none). The actual authorization validation and transaction use the colliding digest (`:230–234`, `:492–546`).

Reproduction: decode `{"schema_version":1,"restrictions":[{"allowed":[]}]}`. A direct run restriction under an authenticated fixture grant yields no permissions. After successful `UpdatePreferences("user",0,p)`, the stored document contains `"restrictions":[{}]`; the same compilation grants `[execute read write]`. `billing:[]` similarly changes empty billing into `[pool-a pool-b]`. A normal nonempty persisted restriction remains restrictive: intersect `{read,write}` and `{read,execute}`, deny write, yields only read; billing remains pool-a.

This is also a request substitution, not merely a display problem. The fixture authorizer binds ID `restricted-auth` to a patch containing explicit empty allowed/billing sets. Submit an altered patch with those sets omitted. `ApplyPolicy` accepts it and writes an active policy with full grant permissions/billing. The requests have the same digest. Both runs of `TestReviewerAuthorizedEmptyPatchSubstitution` reproduce this through authorization validation and the real bbolt transaction. No authorization bypass/assertion was substituted for the production path; only the explicitly intended test-only private authorizer capability is installed.

The independently bounded alternatives are: (1) the intersection operator treats explicit empty incorrectly, (2) persistence/digest serialization loses semantic presence, (3) fixture authorization ignores patch binding. Controls rule against (1): direct empty restriction denies all; (3): normal missing designated source rejects and altered request matches the bound digest. The source trace and persisted bytes localize the loss to serialization. No production-source counterfactual patch was executed under read-only authority; this is an actionable reproduced defect, not a claim of a verified repair.

**Repair contract:** retain the distinction between absent and explicit empty `Allowed`/`Billing` consistently in stored preferences, normalized patch serialization, request digest, and provenance/policy identities. Preserve existing nil semantics and nonempty controls. Same inspection of `Denied` and `Ceilings` finds that empty and absent both mean no additional deny/bound, so their omission does not have this restrictive-empty meaning. No broader schema redesign is requested.

## [FINDING-02] P2 — negative JSON limit underflow passes strict validation

**Observed twice with rejection control; confidence H for the observable validation violation.** R06 explicitly requires rejection of negative limits. `gauge/internal/contract/policy.go:28–34` decodes limit into `*float64`; `:49–50` only tests numeric `<0`, NaN and infinity. JSON limit `-1e-1000` becomes negative zero and `DecodePreferences` accepts it. Identical structure with `-1` is rejected. `TestReviewerNegativeUnderflow` contains both inputs. Repair must retain negative-input rejection through numeric conversion; preserve ordinary nonnegative finite inputs and existing number/identity behavior. This input is more restrictive after rounding, so no grant escalation is claimed for this separate validation defect.

## Executed controls and limits

The final independent suite runs each probe twice under the Go race detector. Passing controls:

- Nonempty allow intersections, deny accumulation, billing subset and missing designated authorizer rejection.
- Controller-wide cross-root authorization-ID rejection; exact original retry after later amendment; active binding remains later policy; historical retry survives reopen without requiring new authorizer.
- Atomic rollback at snapshot-written, authorization-consumed and binding-written, with no result/binding leakage.
- Five concrete task/project/account/window/concurrency token bounds plus distinct USD bound retained, same-scope task minimum retained.
- Provenance revision 9007199254740993 and canonical policy identity survive serialization/reopen.

The earlier numeric probe had an invalid oracle because an empty user document contributed no field; it was corrected to supply a real preset contributor. Its initial failure in independent-3.log is **not a product finding**. independent-4.log contains the corrected passing control.

Final run: `./run-review.sh`, image `sha256:d9b4537412ed447276fbf3a745c3c953f254d412e70da57b5888831a0d61c795`, `go test -race -count=2 -v ./internal/store -run TestReviewer`. Container: network none, read-only root and source, UID501:GID20, drop ALL, no-new-privileges, tmpfs /tmp rw/exec/nosuid, existing module cache read-only, GOTOOLCHAIN local and GOPROXY off. Full command in run-review.sh. Full output `independent-4.log`, exit file `independent-4.exit` = 1. Prior attempts preserve entrypoint and module-cache setup errors as independent-1/2 logs; these are environment invocation errors, not findings.

Review stopped for bounded repair at root's instruction once the reproducible blockers were established. Full race/01–08/06 regression, real old06 migration and CLI execution were **not independently completed by this checker** at this stage. Root reported those checks green elsewhere; those are coordination facts, not substituted independent evidence. Static controller migration and policy guard ordering was inspected, with no additional finding emitted.

## Frozen artifacts and handoff

- `independent-regressions_test.go`: final additive independent tests, frozen before repair; copy into the same store package for protected regressions or replace only production files in an external harness.
- `run-review.sh`: exact qualified container command; points at the original frozen external harness. Do not accidentally claim it tests a repaired candidate without replacing that harness's production files from the repaired freeze.
- `final-source-hashes.json`: candidate file hashes after review and original freeze verification; 287 matched, no candidate source modifications.
- `regression-freeze.json`: hash identities of the independent test/runner/log evidence.
- `review-report.envelope.json`: relative-path orchestrator handoff.
- `review-for-vivi.envelope.json`: relative-path Vivi repair handoff.

Recommendation: repair these two localized contract violations, preserve the additive regressions and existing controls, then freeze and return for independent recheck. No acceptance is issued.

# V4-05 independent checker — scoped acceptance

Disposition: ACCEPTED for the reviewed V4-05 source and local deterministic fixture scope. No remaining actionable findings. This does not claim live managed qualification, protected execution, or independently accepted production artifacts. Hosted CI and lifecycle completion remain the orchestrator's separate gates.

## Independence and scope

The initial VIGIL assignment was a distinct checker with fresh artifact context, the canonical pinned requirements, and source/tests; it did not receive maker reasoning. Subsequent coordination explicitly shared localized findings, requested compatibility probes, and repair status/hash information. This final recheck is therefore a coordinated repair review, not a claim of wholly blinded fresh review. Acceptance rests on inspecting the actual frozen source and independently executing the reproductions, not on the maker's reported pass counts. No repository files were edited by this checker; all outputs are under `/private/tmp/v4-05-review-probes/`. CRYSTALIUM was unavailable. No paid or model probes were made.

Authority: `/private/tmp/eidolons-gauge-v4-05/.spectra/changes/gauge-v4-05/spec.md`, canonical plan c581308f055a0e252013bf09f2a7b2e1426ff811 `docs/campaigns/gauge/01-foundations.md` V4-05 R01–R07.

## Closed findings

FINDING-001 (R02 ancestor metadata omission): `resolution_metadata()` now binds the worktree directory mode, every traversed directory mode, and every symlink target along original and resolved paths. The original two-run matrix now reports stale for parent chmod and ancestor symlink changes across tracked, discovered and required-ignored files; restoration reports current. A tracked symlink's ignored target-file chmod and target-parent chmod both invalidate. Additional independent two-run probes also invalidate an ignored intermediary symlink target spelling change with the same resolved final file, and modes on that resolved target parent. Original journal bytes remain unchanged by status reads.

FINDING-002 (legacy retry compatibility): legacy `complete` retry comparison removes only its historical derived `independent` and `completion` fields from the comparison, without rewriting the event. A journal actually created with V4-04 source d1b56bb06bc22a7aab1f6ec8a4a07cb8f68aa138 retries successfully in the repaired implementation and preserves exact original bytes. Current projection remains self-attested/not accepted. Independent checker, scope, verdict, evidence-content and evidence-path changes all conflict. Generic record retries retain complete-payload comparison, including capture metadata differences.

## Independently observed verification

- Actual macOS `/bin/bash` 3.2.57, driven by Python subprocess: all nine completion anchors exit 0. Log: `host-repaired.jsonl`.
- Existing Docker image `eidolons-v4-03-qualified:local`, source mounted read-only: `bats cli/tests/completion_conformance.bats cli/tests/ledger.bats cli/tests/product_leap.bats` exits 0, 15/15 tests. Completion tests include the two additive repair anchors.
- Original ancestor matrix replay: two trials, three file categories, six steps each; all unchanged/restored controls current and mutations stale. Log: `ancestors-repaired.jsonl`.
- Original focused compatibility matrix replay: two trials; target-file/target-parent mode mutations stale; exact real-baseline legacy retries exit 0 and retain bytes; differing baseline verdict remains conflict. Log: `compatibility-repaired.jsonl`. The reproduction was changed only to expect the repaired success for the original exact-retry call.
- Independent expanded probes: two trials of intermediary ignored symlink topology/resolved-parent modes, and actual baseline legacy caller/content conflicts plus generic-capture strictness. Log: `extra-repaired.jsonl`.
- Existing Python T01–T07 test content is byte-for-byte preserved: removing only the two additive new functions from the repaired suite yields original SHA-256 a927ba8f2f6289d0aa9c28d9032ada865af2e64fcb22a71d600f003713af1e73.
- All 17 files in the supplied final source/lifecycle manifest pass independent `shasum -a 256 -c` validation after tests.

## Requirement mapping and limits

| Requirement | Observed scoped evidence |
|---|---|
| R01 latest applicable result | T01 production pass/fail/pass and authenticated pure controls; invocation identity does not partition selection; unrelated/wrong-candidate failures do not poison current evidence. |
| R02 conservative invalidation | T02 plus repaired independent mode/symlink ancestry matrices; tracked, required/discovered untracked, criteria, configuration, environment and base changes invalidate; unchanged controls remain current. |
| R03 provenance floor | T03 production labels/forged fields/serialized fixture remain self-attested; independent pure control requires separate authenticated invocation/context object. |
| R04 canonical views | T04 frozen captured timestamp/invocation, stable JSON/text/Markdown, edited-view drift rejection and new canonical outcome; augment canonical reference shim rejects old arrays. |
| R05 missing/stale/cancelled/wrong candidate | T05 negative receipts/evidence and positive pure fixture; changing/deleting artifact bytes lowers integrity and withholds acceptance. |
| R06 distinct grades | T06 integrity/provenance/acceptance fields remain separate; matching artifacts do not upgrade manual labels. |
| R07 termination only | T07 native/A2A/MCP completion does not supply acceptance; failed/missing checks remain unaccepted. |

Production deliberately has no qualified provenance producer; trusted positive cases are in-memory pure evaluator fixtures only. The mutable filesystem snapshot is not protected execution. This report does not independently attest the maker's red-loop, journal/run regression counts, or hosted CI; those remain separately attributable receipts.

## Reviewed core SHA-256

- cli/src/ledger.sh: 22e90ed6f5710f10f76653d09f52d558a5af3727de472415193bb51ff2901d5a
- cli/src/ledger_completion.py: 33e08c8698dca94922a70f48ae5667623d85af320d112200a52b43e47896c6b5
- cli/src/augment.sh: 103fff4de1932465fa271850287a772e96dab9eeb9877678cd49c447254f553a
- cli/tests/completion_conformance.py: dce59cdcf3d6f7606d4ea3af6371a8c111b6948bfa16b6199860709d59dbf76d
- cli/tests/completion_conformance.bats: 6b081454209c49d42619adae6b0c562dbff0e28b3ac98d716a9291a7ef154062
- schemas/completion.schema.json: 21f99934c111ae11684dc4b07966397d2ae21a860a24287f6871301ad65dc2c7

Full independently validated manifest is copied alongside as `reviewed-candidate-files.sha256`.

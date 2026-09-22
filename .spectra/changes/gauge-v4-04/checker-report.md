# V4-04 distinct checker report

Verdict: local acceptance for the reviewed stable source/test snapshot. No unresolved actionable finding remains. This is not hosted-CI, lifecycle, merge, power-loss, or network-filesystem certification.

Checker: v4_04_review; maker: vivi_v4_core. Authority was read-only for repository/lifecycle artifacts; only scratch probes, logs, and this report were written under /private/tmp. Initial context was frozen requirement/test artifacts only, before mutable source access. Checker is a distinct agent using the same model family; no statistical independence claim. CRYSTALIUM unavailable and skipped. Read EIDOLONS.md and installed VIGIL agent/verify instructions. Requirements pinned to plan c581308f055a0e252013bf09f2a7b2e1426ff811, docs/campaigns/gauge/01-foundations.md V4-04; checkout base HEAD 1a4697e2101f5c588dcf3632c6823e7b73c86d58.

## Resolved finding

P1: the first candidate's cli/src/ledger.sh:169 nested hashing inside jq --arg. A sha256sum process exiting 44 was masked by outer jq success. Independently reproduced twice: record returned 0 and published event_digest=""; status then rejected the run. Two working-hash controls succeeded. Evidence: /private/tmp/v4-04-review-hashfail.py and /private/tmp/v4-04-review-hashfail.log. Initial ledger SHA256: 890549e3cc888fc2e652a2dbaf6a21ed4b5d80884cb2f72c05d7fe77a2df8ac9.

Maker repaired publication by checking the digest assignment separately and requiring 64 lowercase hexadecimal characters (current ledger.sh:178-180; journal_sha:49), and checked related date/JSON construction and identity-query subprocesses. Independent identical fault replay on the repaired candidate rejected both attempts with nonzero exit and no event publication; working-hash controls passed twice. Maker-authored regression cases additionally cover plausible hash stdout with failing exit, invalid stdout with successful exit, timestamp failure, identity-query failure, unchanged existing prefix, and successful clean retry. Qualified suite and direct Bash 3.2 corruption gate exercised these cases.

## Oracle adequacy

All V4-04 T01-T05 anchors map to R01-R05. Initial gaps were addressed before final acceptance: duplicate ID/payload and retry byte-stability assertions; observed/type/evidence content conflicts; complex legacy values exercised through actual status+append; language-neutral invalid.json mutation fixture. The fixtures preserve legacy jq -cS payload bytes including final LF. Tests separate damaged controls from a readable valid legacy control and reject both status and append for invalid histories.

## Independent observed validation

Final exact Docker invocation (exit 0):

```sh
docker run --rm --entrypoint bash -v /private/tmp/eidolons-gauge-v4-04:/repo:ro -v /private/tmp/v4-04-review-hashfail.py:/hashfail.py:ro -v /private/tmp/v4-04-review-extra.py:/extra.py:ro -v /private/tmp/v4-04-review-probes.py:/probes.py:ro -w /repo eidolons-v4-03-qualified:local -c 'python3 /hashfail.py && python3 /extra.py && python3 /probes.py && bats cli/tests/ledger.bats cli/tests/journal_conformance.bats' > /private/tmp/v4-04-review-final.log 2>&1
```

Observed: all 8 Bats tests passed (3 existing ledger + 5 V4-04 anchors); two failed-hash attempts rejected before publication; two working-hash controls passed; 12 simultaneous conflicting submissions accepted exactly one and retained the winner's payload; supplied/generated identity collision rejected and explicit unique retry succeeded; dotfile/directory/symlink/missing sequence/swapped filenames rejected by reader and append without changing existing entries; malformed multi-object/empty-file framing rejected twice; slash/newline/Unicode identity tests and exact retry preservation passed twice.

Direct real host Bash 3.2 validation (exit 0), run from /private/tmp/eidolons-gauge-v4-04:

```sh
LEDGER_TEST_BASH=/bin/bash python3 cli/tests/journal_conformance.py interruption > /private/tmp/v4-04-review-bash32.log 2>&1 && LEDGER_TEST_BASH=/bin/bash python3 cli/tests/journal_conformance.py unknown >> /private/tmp/v4-04-review-bash32.log 2>&1 && LEDGER_TEST_BASH=/bin/bash python3 cli/tests/journal_conformance.py corruption >> /private/tmp/v4-04-review-bash32.log 2>&1
```

Observed environment: GNU Bash 3.2.57(1)-release arm64-apple-darwin26, jq-1.7.1-apple, Darwin arm64. Explicit Python assertions/return-code checks were used; host Bats was not an acceptance runner. T03 ownership and delayed-child interruption, T04 absent-run no mutation, and T05 corruption/legacy/failure construction passed. Docker qualification comes from the supplied qualified Bash 5.2/Bats 1.11.1 image; local scratch filesystem behavior only. SIGKILL locks deliberately remain recovery-required until established quiescence/manual recovery. No automatic lock recovery or power-loss durability claim.

## Reviewed final snapshot SHA256

ddd0b85eaf90b81efe8c437df131b74ce2c8d9f379800e0a81734c7b75ef7fcd  cli/src/ledger.sh
d52429318f570a95e18335624166df1a0667f1f0e2d722d738e2594d6b7bf78c  cli/src/lib.sh
6de7d9cb5846cd9f5222c889196ff4ff3375fdfdf0321572670e7ef1483bc2f6  cli/tests/journal_conformance.py
dca0227fb288520c2449882c62155b54fe212be3028b0e4df4e82e38b8a03929  cli/tests/journal_conformance.bats
99b5c50875d5e0be283db245a7143646001d54246397aa93b389897696f78b8d  cli/tests/fixtures/journal/canonical.json
5eaa14b0cf70768be0ea261d258502db05d227ea518de774a7718695d8d35f4f  cli/tests/fixtures/journal/invalid.json
4910d6148cc0cf670b01d2a1b605ccf0fb836373d2d0e529396707e878176f62  cli/tests/fixtures/journal/legacy-complex.json
98ecc277b50031c9f305ca2c7d707c125a3bdba3f5ddfb87da5453e62f5aa285  cli/tests/fixtures/journal/legacy.json

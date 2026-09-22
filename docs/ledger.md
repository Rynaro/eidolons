# Experimental local ledger

The ledger records requested and observed execution state in the current project's `.eidolons/.ledger/<run-id>/events/` directory. V4-04 adds ordered, validated publication and bounded append ownership. It does not authenticate observations or establish that a task was accepted. See the [implementation receipt](campaigns/gauge/receipts/V4-04.md) for observed checks and qualification limits.

## Record and inspect

```sh
eidolons ledger open --run-id example --route route.json --event-id example-plan
eidolons ledger record --run-id example --type dispatched \
  --event-id example-dispatch \
  --requested '{"dispatch":"requested"}' \
  --observed '{"dispatch":"observed"}'
eidolons ledger status --run-id example --json
```

`open` requires an existing route artifact. `record` requires an event type; requested and observed values must each be one JSON object. An optional `--evidence PATH` records an evidence reference. Run IDs accept letters, digits, dots, underscores and dashes, except the IDs `.` and `..`.

Writers (`open`, `record`, `complete`) accept an optional nonempty `--event-id`. Retrying the same ID with the same event type, requested object, observed object and evidence references succeeds without adding another event. A changed value conflicts and fails. Derived sequence, timestamp, predecessor and event digest do not determine retry equivalence. Omit the option to retain generated IDs; use stable caller IDs when a retry must refer to the same operation.

`status` validates the entire published prefix before producing its summary. Reading an unknown run returns a nonzero exit with `unknown run`; it creates no run directory or home/cache files. An unresolved append lock or an empty existing journal reports `recovery-required`.

## Integrity and publication

Events use numeric contiguous filenames and sequences. Every append validates the published prefix while holding exclusive append ownership, then checks caller identity, allocates the next sequence and predecessor, and publishes one event by rename. Published events are not rewritten. Malformed JSON, unsupported versions, duplicate identities or sequences, broken predecessor links and invalid event hashes prevent successful projection and further append.

Schema 1.0 event hashes retain the legacy byte contract: SHA-256 over `jq -cS` output of the event without `event_digest`, including its trailing newline. These hashes check integrity; they are not signatures or authentication of the event author. [Canonical fixtures](../cli/tests/fixtures/journal/README.md) preserve compatibility examples for a future implementation.

Append ownership uses a per-run `.append-lock` directory. `EIDOLONS_LEDGER_LOCK_TIMEOUT` sets an acquisition budget of 1–300 integer seconds, default 60. Contending callers wait within this bound and fail with `recovery-required` if ownership remains unavailable. The budget limits lock acquisition, not the total append or validation duration. The implementation does not reclaim a lock because its PID appears dead, its metadata is missing, or it is old.

## Interrupted operation and recovery

Catchable interruption retains ownership until a foreground publishing child finishes. SIGKILL or interruption around ownership metadata can leave `.append-lock` behind. A published event remains part of the journal; an unpublished private `event` file may remain inside the lock. A subsequent caller must not infer success or safely reusable ownership from the parent process's death alone.

[ACTION] On `recovery-required`, the operator must stop new writers and establish that **all writers and publication-capable children are quiescent** before manually recovering the lock. Preserve the published event files, lock metadata and any private pending event as evidence before changing the interrupted state. Do not automatically delete a lock, replay a pending event, or replace a published event. If quiescence cannot be established, retain the state and investigate. After recovery, inspect the journal and retry a known operation with its original caller ID and content where available.

Process-interruption behavior was exercised on same-host APFS and Linux overlayfs. This does not establish network-filesystem safety, cross-host coordination, or power-loss durability. There is no fsync guarantee or automatic SIGKILL lock reclamation.

## Completion and route identity remain experimental

`complete --run-id ID --artifact PATH --checker ID --scope TEXT --verdict pass|fail` records an artifact digest and a declared checker observation. Existing `independently-verified` labels remain lower-trust legacy output: a supplied checker label does not prove independent review, and the current projection does not enforce the V4-05 acceptance rules. Treat native/tool termination, journal integrity and task acceptance as separate facts.

`EIDOLONS_LEDGER=1 eidolons run …` continues to record an optional planned route, using the semantic route digest as the run ID. Matching route digests therefore reuse an ID. Root execution lineage belongs to V4-08; V4-04 does not change this integration or its failure-suppressed behavior.

The runtime retains the existing Bash 3.2 and jq dependency floor. Python is used by the conformance tests, not added as a ledger runtime prerequisite.

## Provenance

IDG 1.8.1, 2026-09-21. Sources: [V4-04 specification](../.spectra/changes/gauge-v4-04/spec.md), [ownership decision](../.spectra/changes/gauge-v4-04/decision.md), maker/root handoffs and the [receipt](campaigns/gauge/receipts/V4-04.md). CHT: C:5/5 H:5/5 T:5/5. No incoming ECL envelope; verification skipped. CRYSTALIUM unavailable.

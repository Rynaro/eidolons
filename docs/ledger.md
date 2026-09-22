# Experimental local ledger

The ledger records requested and observed execution state in the current project's `.eidolons/.ledger/<run-id>/events/` directory. V4-04 supplies ordered publication and bounded append ownership; V4-05 adds current-candidate projection and reproducible historical views. Journal integrity does not authenticate observations. Production independent acceptance remains unavailable until a qualified provenance source exists. See the [V4-04 receipt](campaigns/gauge/receipts/V4-04.md) and [V4-05 receipt](campaigns/gauge/receipts/V4-05.md) for evidence and limits.

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

Writers (`open`, `record`, `complete`, `candidate`, `capture`) accept an optional nonempty `--event-id`. Retrying the same ID with the same event type, requested object, observed object and evidence references succeeds without adding another event. A changed value conflicts and fails. Derived sequence, timestamp, predecessor and event digest do not determine retry equivalence. Omit the option to retain generated IDs; use stable caller IDs when a retry must refer to the same operation.

`status` validates the entire published prefix before producing its summary. Reading an unknown run returns a nonzero exit with `unknown run`; it creates no run directory or home/cache files. An unresolved append lock or an empty existing journal reports `recovery-required`.

## Integrity and publication

Events use numeric contiguous filenames and sequences. Every append validates the published prefix while holding exclusive append ownership, then checks caller identity, allocates the next sequence and predecessor, and publishes one event by rename. Published events are not rewritten. Malformed JSON, unsupported versions, duplicate identities or sequences, broken predecessor links and invalid event hashes prevent successful projection and further append.

Schema 1.0 event hashes retain the legacy byte contract: SHA-256 over `jq -cS` output of the event without `event_digest`, including its trailing newline. These hashes check integrity; they are not signatures or authentication of the event author. [Canonical fixtures](../cli/tests/fixtures/journal/README.md) preserve compatibility examples for a future implementation.

Append ownership uses a per-run `.append-lock` directory. `EIDOLONS_LEDGER_LOCK_TIMEOUT` sets an acquisition budget of 1–300 integer seconds, default 60. Contending callers wait within this bound and fail with `recovery-required` if ownership remains unavailable. The budget limits lock acquisition, not the total append or validation duration. The implementation does not reclaim a lock because its PID appears dead, its metadata is missing, or it is old.

## Interrupted operation and recovery

Catchable interruption retains ownership until a foreground publishing child finishes. SIGKILL or interruption around ownership metadata can leave `.append-lock` behind. A published event remains part of the journal; an unpublished private `event` file may remain inside the lock. A subsequent caller must not infer success or safely reusable ownership from the parent process's death alone.

[ACTION] On `recovery-required`, the operator must stop new writers and establish that **all writers and publication-capable children are quiescent** before manually recovering the lock. Preserve the published event files, lock metadata and any private pending event as evidence before changing the interrupted state. Do not automatically delete a lock, replay a pending event, or replace a published event. If quiescence cannot be established, retain the state and investigate. After recovery, inspect the journal and retry a known operation with its original caller ID and content where available.

Process-interruption behavior was exercised on same-host APFS and Linux overlayfs. This does not establish network-filesystem safety, cross-host coordination, or power-loss durability. There is no fsync guarantee or automatic SIGKILL lock reclamation.

## Current-candidate completion

Run candidate capture and current status from the Git worktree root. A criteria file names a nonempty mandatory check set; each check has an `id` and an `oracle_id`:

```json
{
  "schema_version": "1.0",
  "required_checks": [{"id": "tests", "oracle_id": "tests@1"}],
  "required_untracked": [],
  "environment": [],
  "configuration": []
}
```

Save this as `criteria.json` in the project. `required_untracked` names additional required files, including ignored inputs. `environment` names variables that must be set; their values are hashed. `configuration` names relevant configuration files. Required files must exist. Criteria and configuration paths belong inside the worktree.

```sh
eidolons ledger candidate --run-id example --criteria criteria.json \
  --integration-base HEAD --event-id candidate-1
eidolons ledger complete --run-id example --candidate candidate-1 \
  --check-id tests --artifact /path/outside/project/test-output.txt \
  --checker reviewer-label --scope tests --verdict pass --event-id check-1
eidolons ledger status --run-id example --json
```

Use an existing evidence file for `--artifact`; `complete` records a claim, not a test execution. Typed completion accepts `pass`, `fail`, or `cancelled`. It rejects an unknown check or stale candidate. Capture a new candidate and new observations after changing acceptance inputs.

The snapshot binds tracked files, discovered nonignored untracked files, explicitly required untracked files, HEAD, integration base, criteria, and declared environment/configuration. It includes bytes, file kinds and modes, ancestor directory modes (including the worktree root), and the symlinks traversed to reach each input and its resolved target. Changes to a target's parent permissions therefore invalidate prior evidence even when file bytes stay the same. Unsupported external symlinks, missing inputs and non-file inputs fail closed. User-defined exclusions are rejected; fixed Git and ledger operational state cannot be required inputs. Keep evidence and generated views outside the candidate tree to avoid invalidating it. This mutable snapshot does not freeze or protect execution.

For each required check, the latest applicable journal sequence wins for the full candidate/criteria/environment/configuration/integration-base tuple and check/oracle identity. Invocation identity is provenance, not a grouping key: a later failure displaces an earlier pass even from another invocation. Unrelated historical failures do not poison the current candidate. Missing, stale, wrong-candidate, cancelled, skipped or unknown evidence withholds acceptance; referenced evidence bytes are rechecked for changes or disappearance. There is no time-based TTL policy.

The projection exposes separate typed fields:

| Field | Meaning |
|---|---|
| `candidate_status.status` | `current`, `stale`, or `unavailable`. |
| `artifact_integrity.status` | `verified`, `missing`, `changed`, or `unavailable`; matching bytes alone prove no execution provenance. |
| `execution_provenance.status` | `self-attested` or `unavailable` in production; the pure test harness alone supplies authenticated independent context. |
| `acceptance_status.status` | `accepted` or `not-accepted`, with reasons; production manual observations remain `not-accepted`. |

Manual checker labels, maker labels, supplied independence fields and serialized fixture receipts cannot confer independent provenance. Native success, A2A completion and MCP tool success record termination only. The fixture positive control supplies already-authenticated invocation/context data in memory; no CLI, environment or configuration trust switch enables that grade. Protected execution belongs to V4-14.

Legacy `complete --run-id ID --artifact PATH --checker ID --scope TEXT --verdict pass|fail` remains supported. Historical `independent:true` or `independently-verified` declarations remain unchanged in their original events, while their derived provenance stays self-attested. An identical legacy retry preserves the original event bytes; changing checker, scope, verdict, artifact reference or artifact digest conflicts. Typed retries compare the stable request and freshly recomputed inputs under append ownership before assigning a new timestamp or invocation ID. Generic `record` retains exact payload comparison.

## Capture and regenerate historical views

```sh
eidolons ledger capture --run-id example --event-id view-1
eidolons ledger render --run-id example --event-id view-1 --format markdown \
  > /path/outside/project/evidence.md
eidolons ledger render --run-id example --event-id view-1 --format markdown \
  --compare /path/outside/project/evidence.md
```

`capture` stores projection inputs, including current revalidation results, in the canonical journal. `render` validates that journal and derives JSON (default), text or Markdown from the named capture. Timestamp and invocation identity come from the capture, never the rendering clock. Repeating a render is deterministic; `--compare` fails when the saved view differs. Subsequent events do not change an older capture. A historical view is explicitly historical, never proof of current acceptance; use `status` for current candidate/evidence revalidation. Revalidation errors remain visible.

### `augment evidence` compatibility change

`eidolons augment evidence reference.json` now renders an existing canonical capture. **Old raw observation arrays, including empty arrays, are rejected.** Create a ledger capture, then save this versioned reference (the IDs must identify that capture):

```json
{
  "schema_version": "1.0",
  "kind": "completion-view-reference",
  "run_id": "example",
  "event_id": "view-1"
}
```

```sh
eidolons augment evidence reference.json
eidolons ledger render --reference reference.json
```

Both produce the same canonical historical JSON. Malformed or missing references fail; rendering does not initialize augment cache/product state or invent a comparative verdict. Other augment verbs retain their existing behavior. The [completion schema](../schemas/completion.schema.json) describes observations and references; it grants no authentication authority.

## Runtime and route identity

Bash 3.2 and jq remain the journal writer/validator floor. `candidate`, `complete` (including legacy form), `status`, `capture`, `render`, and `augment evidence` require Python 3 with its standard library. Missing Python produces an actionable error, never a legacy-success fallback. Ordinary `open`, `record`, and optional run instrumentation gain no Python dependency. New candidate capture requires Git; legacy non-Git history remains readable but unaccepted.

`EIDOLONS_LEDGER=1 eidolons run …` continues to record an optional planned route, using the semantic route digest as the run ID. Matching route digests reuse an ID. Root execution lineage belongs to V4-08; optional failure-suppressed instrumentation is unchanged.

## Provenance

IDG 1.8.1, updated 2026-09-22. Sources: [V4-04 specification](../.spectra/changes/gauge-v4-04/spec.md), [ownership decision](../.spectra/changes/gauge-v4-04/decision.md), [V4-05 specification](../.spectra/changes/gauge-v4-05/spec.md), [completion decision](../.spectra/changes/gauge-v4-05/decision.md), supplied maker/checker/repair handoffs, and the explicit command/schema/conformance files named in the [V4-05 receipt](campaigns/gauge/receipts/V4-05.md). CHT: C:5/5 H:5/5 T:5/5. No incoming ECL envelope; verification skipped. CRYSTALIUM unavailable.

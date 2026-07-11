# Attempt 1 — DISCARDED (billing outage, not a capability measurement)

Runs launched 2026-07-11 were progressively killed by the account's monthly
spend limit: meta.jsonl records exit=1/secs=8 stubs whose "reports" contain
only the provider error string ("You've hit your monthly spend limit").
The harness-v2 relaunch additionally overwrote the handful of real
harness-v1 reports. No verified-completion rate can honestly be computed
from this mixture, in either direction (scoring an outage as mission
failure would be as wrong as retrying real failures).

Disposition: entire attempt discarded pre-scoring; preserved here for audit.
The official Arm-1 measurement is the clean re-run in ../arm1-runs/
(same frozen missions, same oracle, single consistent harness), executed
after capacity was restored. Recorded for the gate checker (AC-G05).

## Cleanup (2026-07-11, follow-up)

The ~45 identical provider-error stub files originally preserved here were
removed post-merge — they carried no audit information beyond repetition.
Retained as evidence: this note, `meta.jsonl` (exit=1/secs≈8 for every
cell), and one representative stub (`run1/arm1-01.report.md`).

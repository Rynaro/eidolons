# V4-06 preparatory store decision

FORGE actor forge_v4_06, two passes, no independent execution or file inspection. Supplied primary docs and actual Junction inspection support architectural choice; runtime acceptance remains unobserved. CRYSTALIUM unavailable. Implementation gated on V4-04/V4-05 acceptance.

Select bbolt1.5.0 conditionally: small pure-Go single-file transactions fit short dependent policy/accounting updates. moderncSQLite remains viable for demonstrated relational/query needs but adds translated-engine/libc/configuration surface. Whole-state JSON rename/fsync/OSlocking minimizes dependencies but makes this project own recovery/locking/growth correctness. No Junction source import justified.

Boundary: cooperating processes on separately qualified local Linux/macOS filesystems only. No network/cloud-sync/removable/Windows qualification. Keep sync enabled, never NoSync; bound lock waits; copy values before transactions end; no provider/subprocess/human wait inside a transaction. Corruption, future versions, failed writes and permissions fail closed without recreating state. Process interruption tests do not qualify power-loss durability.

Required gates before production use:
1. Atomic related records under barrier-synchronized processes, rollback callback, conflicting mutations; readers see complete old/new state.
2. Kill at controlled points around work/commit, reopen newprocess; acknowledged commits remain, unacknowledged operation all-or-nothing, retry exactly once.
3. Bounded contention timeout and success after actual release, never delete lockstate; returned buffers survive Tx closure.
4. Explicit frozen-inventory legacy import, original IDs/rawbytes/grade preserved, repeat no-op, identity/byte conflicts rejected, invalid/future/partial history never partially authoritative. Keep legacy jq canonical hashes including LF, not Go JSON reserialization.
5. Read-only schema preflight before writable opening, plus schema guard on mutation. Future-version refusal preserves database content and rollback-reader usability; test missingmigration/partialimport.
6. Backend authority registered per execution and enforced by every mutator. Legacy remains authoritative until explicit import/promotion; afterward Bash writes reject. Competing promotions cannot split authority. Cross-resource promotion needs explicit recoverable fail-closed intermediate states, not an invented cross-filesystem transaction guarantee.
7. Actual lockeddependency build and execution with isolated Go1.27.1 Linuxarm64; qualify macOS separately, cleaninit/permissions/writefailures where reproducible, no hostGo requirement. Keep four statefamilies and configmanifest typed/distinct.

Reverse on unresolved fault/locking/durability or packaging failures, required unsupportedfilesystems, or measured workload/query requirements favoring SQLite. No performance or live qualification established.

Primary inputs and exact URLs: gauge-v4-06-store-inputs.md and gauge-v4-06-junction-reuse.md beside this scratch decision. This is a compact orchestrator transcription of FORGE's emitted verdict, not its own new execution evidence.

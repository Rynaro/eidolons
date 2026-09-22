# V4-06 bounded store decision inputs, preparatory

No store has been selected and no authoritative Gauge store mutation has run.

## Constraints

One local transaction must commit dependent task/history/policy/receipt updates. Unknown/future schema diagnostics must not mutate state. Explicit legacy import preserves original bytes, identity, grade and retry/recovery behavior. No transaction may span a provider call. Local macOS/Linux are initial packaging targets; network/distributed filesystems and real power-loss qualification must not be inferred from process-kill tests.

## Viable choices

1. bbolt: official documentation describes a pure-Go, single-file key/value transaction store, single read-write transaction with concurrent snapshots, and file locking with a configurable opening timeout. Transaction byte slices must be copied before their transaction ends. Never enable NoSync. Bounded opens and read-only diagnostics need explicit tests. Current official release observed: v1.5.0. Sources: https://github.com/etcd-io/bbolt/blob/main/doc.go, https://github.com/etcd-io/bbolt, https://github.com/etcd-io/bbolt/releases/tag/v1.5.0.
2. SQLite via modernc.org/sqlite: Go driver avoids cgo but adds a translated SQLite dependency stack; its documentation requires matching its libc dependency version. SQLite WAL supports same-host access, excludes network filesystems, and synchronous FULL syncs commits. SQL constraints/querying could help richer relationships but add schema/driver configuration. Sources: https://pkg.go.dev/modernc.org/sqlite, https://sqlite.org/wal.html, https://sqlite.org/pragma.html.
3. Versioned whole-state JSON snapshot with OS locking, atomic rename and file/directory fsync: minimal external dependencies, but own migration/corruption/recovery/locking code and whole-state rewrite growth. This is a proposed alternative, not an observed implementation or qualified guarantee.

No performance comparison has run. Actual Junction inspection is recorded separately in gauge-v4-06-junction-reuse.md; it has no suitable cross-process transactional store to import. Official Go1.27.1 Docker toolchain observed and available without host installation.

Decision must record fault gates: atomic all-or-nothing dependent changes; callback failure rollback; process interruption before/after commit; multi-process lock contention bounded; concurrent mutations exactly once; read-only future-version bytes unchanged; import retry/interruption preserves grades and original bytes; offline CGO-disabled builds for supported targets. These application tests do not independently prove upstream storage power-loss guarantees.

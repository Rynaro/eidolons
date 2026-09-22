# Journal v1 conformance fixtures

These fixtures belong to V4-04 T01–T05 and are reusable at the V4-06 import
boundary. They do not establish stronger completion or independent-checker
semantics; those belong to V4-05.

`legacy.json` contains two events captured from the unmodified ledger writer
at commit `1a4697e2101f5c588dcf3632c6823e7b73c86d58`, before the V4-04 source edit.
`legacy-complex.json` was captured by executing that same commit's writer from
`git show`, with Unicode, escapes, nested values and numeric values in requested
content. Its helper source differs only in read-only cache initialization; the
SHA-256 helper is unchanged. Both captures used macOS jq 1.7.1-apple. T05 sends
both frozen histories through the actual status and append paths, verifies their
digests independently, and checks that original event bytes remain unchanged.

`canonical.json` records explicit UTF-8 canonical bytes and SHA-256 results.
For schema 1.0 the byte contract is `jq -cS 'del(.event_digest)'`, **including
the final LF**. This is the existing jq serialization contract, not RFC 8785 or
Python/Go JSON serialization. Property order, Unicode combining sequences,
escaped control characters and number spelling matter. Each fixture contains
the parsed payload, canonical string (whose final `\n` is part of the data), and
hex digest. The conformance runner checks actual jq output against these pinned
bytes before testing the product. A serializer that produces different numeric
bytes must preserve the legacy bytes or explicitly reject incompatible input;
silently recomputing old events changes their evidence identity.

`invalid.json` is a language-neutral mutation manifest applied independently to
event 2 of `legacy.json`. Restore the valid history before each case. `raw`
replaces the file bytes verbatim; otherwise apply the fields in `replace` and
recompute the event's own digest, unless `reseal` is false. This isolates a broken
predecessor, duplicate sequence, unsupported version, duplicate identity and
foreign run from a separate self-digest error. Both status and append must reject
every invalid history without changing its published bytes.

Run the five anchors with `bats cli/tests/journal_conformance.bats`. The Python
driver is test infrastructure only; the ledger still requires Bash 3.2, jq and
the existing SHA-256 tools. `LEDGER_TEST_BASH=/bin/bash` selects macOS Bash 3.2
for direct probes using explicit Python assertions, avoiding host Bats' known
intermediate-assertion false passes. T01 and T02 print measured durations when
the Python driver is invoked directly.

## Ownership and recovery boundary

The run's `.append-lock` directory serializes all participating appenders.
`owner` contains diagnostic PID and a private ownership token. PID liveness,
age, missing metadata and a reused PID never authorize reclamation. Acquisition
waits at most the configured `EIDOLONS_LEDGER_LOCK_TIMEOUT` budget (integer
seconds 1–300, default 60) between local filesystem operations, then returns
`recovery-required`. Status also withholds its projection while it observes
unresolved ownership. SIGKILL may leave a lock even after its publishing child
finishes. Recovery is deliberately manual: establish that **every** writer and
publishing child is quiescent, preserve and inspect the published prefix and
pending `event`, and only then remove the unresolved lock. A PID check alone is
insufficient. The CLI does not automatically perform that recovery.

T03 uses real PATH-interposed mkdir/mv/rm subprocesses and barrier files to stop
the writer before/after rename, before owner metadata and during cleanup.
It kills or terminates the actual writer while the subprocess is alive, checks
that another writer is refused, then releases the child and checks published
events. Catchable-signal cleanup waits for foreground publisher completion;
SIGKILL preserves the recovery-required lock. All test processes and state live
in temporary directories; no product-only fault injection switches are used.

The tested storage boundary is a local filesystem and same-filesystem atomic
rename. These tests make no power-loss durability, network filesystem, hostile
nonparticipating-writer or automatic SIGKILL-recovery claim.

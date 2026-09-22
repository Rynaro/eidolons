# V4-11 reservation decision — fixture-local atomic admission

Actor vivi_v4_11, implementing from canonical EARS in `03-managed-delivery.md` §V4-11 and ARCHITECTURE.md §Durable dispatch and resource policy. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base bf629db (V4-09 merged). No live/provider dispatch authorization. Architectural confidence high for local bookkeeping only.

Select fixture-local atomic admission in one bbolt Update transaction over (a) remote/provider call inside a store transaction (forbidden by architecture) or (b) auto-release on uncertain outcomes (violates R04). Challenge invented scientific/live parameters and exact external billing claims — none are introduced.

Schema 2 preserved. Additive typed namespaces: `reservations`, `scope_balances`, `reservation_events`, with `meta.reservation_receipt` and typed version guards (same pattern as observation/instrument). Pre-V4-11 schema-2 stores remain openable; reservation APIs call `EnsureReservationNamespaces`.

Admission intersects known V4-07 Ceiling scopes (task/project/account/window/concurrency) under an active PolicyBinding identity — never invents grants. Concurrent contenders serialize through bbolt's exclusive writer; each admit re-reads balances so joint exposure cannot exceed known ceilings.

Protected verification/recovery headroom is carved out of optional implementation availability (R02). Observed overrun/late usage/corrections move estimate holds into consumed actual and never clamp exposure below observed (R03). Crash/timeout/missing callback/cancellation-after-send move reserved → uncertain; release requires explicit reconcile with proof (R04). Provider window epoch reset creates a fresh window balance; task consumed is preserved (R05).

Authoritative accounting faults are fixture-injected (corruption, lock timeout, full storage, read-only) without real FS damage outside test tmpdirs; managed admit rejects; advisory hooks return a distinct error (R06). Hard-limited dimensions without usable observation require explicit bounded mode plus authorized conservative bound; unsupported data never becomes unlimited (R07). Child/retry joint-reserve implementation+integration+verification under the parent and cannot borrow protected headroom (R08).

Mutators retain V4-06 append lock + active claim/inventory checks. V4-09 live admission remains fail-closed. Zero real network/transport. Bash 3.2 legacy CLI unchanged; reservation CLI is opt-in Go only. No V4-12+, no merge/release, no paid probes, no cross-device accounting.

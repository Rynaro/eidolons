# V4-12 dispatch decision — one fixture-qualified native adapter

Actor vivi_v4_12, implementing from canonical EARS in `03-managed-delivery.md` §V4-12 and ARCHITECTURE.md §Durable dispatch and resource policy. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base 9ff1c65 (V4-11 merged via #608). No live/provider dispatch authorization. Architectural confidence high for fixture-local durable dispatch only.

Select exactly one fixture-qualified FakeNativeAdapter (`codex-cli` / `0.154.0` / `local` / `exec-sandbox-readonly` / subscription `auth-sub-1`) over (a) live host probes (blocked by V4-09) or (b) silent privileged sibling fallback (forbidden by architecture). Challenge invented live qualification and exactly-once claims from checkpoint replay — none are introduced.

Schema 2 preserved. Additive typed namespaces: `dispatch_intents`, `dispatch_events`, `dispatch_acks`, `dispatch_ops`, with `meta.dispatch_receipt` and typed version guards. Pre-V4-12 schema-2 stores remain openable; dispatch APIs call `EnsureDispatchNamespaces`.

Managed sequence is non-atomic across the provider boundary: (1) V4-11 AdmitReservation (2) durable CommitIntent (3) fake Start (4) RecordAck. Fault injectors cover both sides of each step; NativeMethodCounters prove Start never precedes durable intent. Uncertain sends call MarkReservationUncertain and stay pending ReconcileDispatch (lookup-capable resolves; unsupported remains unknown — no auto-retry).

NativeAdapter (Preflight/Start/Resume/Events/Interrupt/Lookup/Cleanup/Reconstruct) wraps the native loop without replacing it. HostAdapter remains for TestV409*. Requested vs observed settings are recorded separately. Cancellation requested / interrupt accepted / confirmed stopped / final reconciled are distinct states. Cleanup is ownership-ID scoped. Method and granularity mismatches preflight-reject. Idempotent replay reuses operation identity; missing lookup/key support stays unresolved. Reconstruction reports portable checkpoints without claiming native-session continuity.

Mutators retain V4-06 append lock + active claim/inventory checks. V4-09 live admission remains fail-closed. Zero real network/transport. Bash 3.2 legacy CLI unchanged; dispatch CLI is opt-in Go only. No V4-13+, no merge/release, no paid probes, no privileged sibling fallback.

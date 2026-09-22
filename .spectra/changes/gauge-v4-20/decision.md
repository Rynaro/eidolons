# V4-20 delivery decision — truthful CLI status projections (core-cli)

Actor vivi_v4_20, implementing from canonical EARS in `04-methodology-and-ecosystem.md` §V4-20 and ARCHITECTURE/HANDOFF (views from canonical observations; no duplicated budget engine; terminal/green badge ≠ acceptance; status/preview observational). Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base 7528827 (V4-15 merged via #612). No live/provider dispatch authorization. Architectural confidence high for fixture-local observational status projection only.

Select additive schema-2 status namespaces over (a) a schema bump or (b) rewriting delivery.go. Challenge invented quota percentages, fictional teams, premature cancel done/refund, and treating GAMBIT as a deferred follow-up — none are introduced.

Schema 2 preserved. Additive typed namespaces: `status_projections`, `status_client_receipts`, `status_events`, with `meta.status_receipt` and typed version guards. Pre-V4-20 schema-2 stores remain openable; status APIs call `EnsureStatusNamespaces`.

Status projection layer extends V4-15 InspectSnapshot without replacing delivery. Shared contract `gauge-status@1`. Slice `core-cli` required; **`optional-GAMBIT` out of scope (dropped; not used)** with fixture consumer proving optional-client contract conformance.

Mutators retain V4-06 append lock for authority paths; status inspect/preview remain observational. Zero real network/transport. Bash 3.2 legacy CLI unchanged; status CLI is opt-in Go only. No V4-16+, no V4-21, no merge/release, no paid probes.

# V4-15 delivery decision — observable runnable slice and recovery demonstrator

Actor vivi_v4_15, implementing from canonical EARS in `03-managed-delivery.md` §V4-15 and ARCHITECTURE.md (one maker default; process/session/env replacement ≠ new budget root; classify failures before recovery; preserve partial artifacts; no silent scope reduction / routine continue prompts / fake background work). Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base de25cd9 (V4-14 merged via #611). No live/provider dispatch authorization. Architectural confidence high for fixture-local managed delivery demonstrator only.

Select additive schema-2 delivery namespaces over (a) a schema bump or (b) embedding delivery state in acceptance/dispatch buckets. Challenge invented progress from routine continue prompts, stub/prose/fake-log milestones, fabricated live arms, or silent scope reduction — none are introduced.

Schema 2 preserved. Additive typed namespaces: `delivery_loops`, `delivery_checkpoints`, `delivery_obligations`, `delivery_interventions`, `delivery_events`, with `meta.delivery_receipt` and typed version guards. Pre-V4-15 schema-2 stores remain openable; delivery APIs call `EnsureDeliveryNamespaces`. New stores initialize delivery namespaces alongside acceptance.

Delivery sequence: admit (V4-11) → optional dispatch commit/send (V4-12) → edit → freeze (V4-14) → check (V4-14) → checkpoint → accepted/partial/blocked. Fault inject at dispatch/edit/freeze/check/checkpoint. Failure classes classified before recovery. Resume reconciles uncertainty before dependent work. Inspect/status/resume/cancel/compact are observational minimal CLI; full V4-20 deferred. Comparison arms go through V4-09 eligibility — live remains ineligible unless explicitly authorized, never fabricated.

Mutators retain V4-06 append lock + active claim/inventory checks. V4-09 live admission remains fail-closed. Zero real network/transport. Bash 3.2 legacy CLI unchanged; delivery CLI is opt-in Go only. No V4-16+, no V4-20 full surface, no V4-21, no merge/release, no paid probes.

# V4-19 delivery decision — core context and bounded information access

Actor vivi_v4_19, implementing from canonical EARS in `04-methodology-and-ecosystem.md` §V4-19 and ARCHITECTURE (information access and bounded learning). Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base eddd021 (main after V4-20 #614 / V4-21 #613). No live/provider dispatch authorization. Architectural confidence high for fixture-local core-context only.

Select additive schema-2 context namespaces over (a) a schema bump or (b) inventing indexed/recursive adapters. Challenge treating CRYSTALIUM as operational truth, mandatory vector stores, and treating `one-justified-optional-adapter` as a deferred follow-up — none are introduced.

Schema 2 preserved. Additive typed namespaces: `context_sessions`, `context_evidence`, `context_memory`, `context_navigation`, `context_overhead`, `context_features`, `context_events`, with `meta.context_receipt` and typed version guards. Pre-V4-19 schema-2 stores remain openable; context APIs call `EnsureContextNamespaces`.

Reuse pin IDs from `roster/pins.yaml` and zone/debounce posture from `roster/context-policy.yaml` / `cli/src/lib_context.sh` as reference constants — not a new ECM rewrite. CRYSTALIUM optional never operational truth; Atomos compose/verify-only; no mandatory vector store.

Slice `core-context` required; **`one-justified-optional-adapter` out of scope (dropped; not used)**. R11/R12 recorded N/A with `feature_condition_absent` — do not invent indexing/recursion.

Zero real network/transport. Bash 3.2 legacy CLI unchanged; context CLI is opt-in Go only. No V4-10/16/17/18/22, no merge/release, no paid probes.

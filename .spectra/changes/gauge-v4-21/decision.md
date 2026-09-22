# V4-21 evaluation decision — auditable instrument expansion

Actor vivi_v4_21, implementing from canonical EARS in `05-evaluation-and-rollout.md` §V4-21. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base 7528827 (V4-15 merged via #612). No live/provider dispatch authorization. Architectural confidence high for fixture-local auditable evaluation only.

Select additive schema-2 evaluation namespaces over (a) a schema bump or (b) replacing V4-09 instrument buckets. Challenge fabricated pending-arm zeros, undefined-ratio-as-zero, gold-patch-as-model-capability, holdout leakage into maker memory, and silent promotion of tuning-influenced material — none are introduced.

Schema 2 preserved. Additive typed namespaces listed in the receipt, with `meta.evaluation_receipt` and typed version guards. Pre-V4-21 schema-2 stores remain openable; evaluation APIs call `EnsureEvaluationNamespaces`. New stores initialize evaluation namespaces alongside delivery.

Comparison roles map onto V4-09 arm kinds: native → native, original-v3 → original_v3 (exact SHA `752194ef5ceaa8cee1f5995fd0d374888696d8fc`), v4_fixed_model → managed, structural → structural (pending without V4-10). Cost arithmetic reuses SummarizeAttempts K/Z/U/W. Live remains blocked; paid trials require allowance.

Mutators retain V4-06 append lock + active claim/inventory checks. Zero real network/transport. Bash 3.2 legacy CLI unchanged; evaluation CLI is opt-in Go only. No V4-20, no V4-22, no V4-10, no merge/release, no paid probes.

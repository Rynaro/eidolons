# V4-22 calibration decision — strategy ablation and adaptation gates

Actor vivi_v4_22, implementing from canonical EARS in `05-evaluation-and-rollout.md` §V4-22. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base fcafd0d (main tip after V4-19). No live/provider dispatch authorization. Architectural confidence high for fixture-local calibration only.

Select additive schema-2 calibration namespaces over (a) a schema bump or (b) mutating V4-21 evaluation buckets. Challenge fabricated pending-arm zeros, holdout-driven tuning, cherry-picked winners, default flips from null/inconclusive, self-authorized overage, hidden adaptive reasoning, silent activation of failed/stale/self-attested experience, same-batch-as-generalization, and offline self-promotion — none are introduced.

Schema 2 preserved. Additive typed namespaces listed in the receipt, with `meta.calibration_receipt` and typed version guards. Pre-V4-22 schema-2 stores remain openable; calibration APIs call `EnsureCalibrationNamespaces`. New stores initialize calibration namespaces alongside context.

Mechanism prerequisites follow plan.yaml: lean_planning→V4-16, maker_continuity→V4-17, method_fusion_isolation→V4-18, context_tool_economy→V4-19, structural→V4-10; parallelism and model_effort_routing are fixture-eligible without extra packages. Missing packages stay pending/ineligible.

Required slices `workflow-ablations` and `routing-calibration` are in scope. `optional-offline-adaptation` implements R10 fixture isolation (sandbox proposals; no production self-mod) rather than deferring with N/A.

Mutators retain V4-06 append lock + identity conflict checks. Zero real network/transport. Bash 3.2 legacy CLI unchanged; calibration CLI is opt-in Go only. No V4-18, no V4-23, no merge/release, no paid probes, no learning framework / weight training / autonomous harness evolution as mandatory deps.

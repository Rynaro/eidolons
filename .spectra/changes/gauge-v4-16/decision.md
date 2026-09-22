# V4-16 RAMZA decision — lean methods without fabricated certainty

Actor vivi_v4_16, implementing from canonical EARS in `04-methodology-and-ecosystem.md` §V4-16. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base eddd021 (main after V4-20 #614; V4-15/V4-21 already merged). No live/provider dispatch authorization. Architectural confidence high for fixture-local versioned method contracts only.

Select additive schema-2 RAMZA namespaces over (a) a schema bump or (b) relocating/archiving `Rynaro/Ramza`. Challenge mandatory invented alternatives for clear lite work, file-count-as-risk, rubric-as-probability, default flip, and converting unsupported assumptions into user requirements — none are introduced.

Schema 2 preserved. Additive typed namespaces: `ramza_plans`, `ramza_heuristics`, `ramza_assumptions`, `ramza_profiles`, `ramza_consume_receipts`, `ramza_events`, with `meta.ramza_receipt` and typed version guards. Pre-V4-16 schema-2 stores remain openable; RAMZA APIs call `EnsureRamzaNamespaces`. New stores initialize RAMZA namespaces alongside status.

Consumer contract `gauge-ramza@1` / `ramza-lite@2` is hosted in the eidolons Gauge seam. Full (`ramza-full@1`) and legacy (`ramza-legacy@1`) profiles preserve declared controls. Primary owner `Rynaro/Ramza` remains canonical until accepted V4-10; when the sibling checkout is absent, producer artifacts are fixture-simulated. Method use inside a maker is not an independent planner or critique.

Mutators retain V4-06 append lock + active claim/inventory checks. Zero real network/transport. Bash 3.2 legacy CLI unchanged; RAMZA CLI is opt-in Go only. No V4-17, no V4-18, no V4-10, no V4-19, no V4-22, no merge/release, no paid probes.

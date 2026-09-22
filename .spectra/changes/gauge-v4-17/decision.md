# V4-17 delivery decision — explicit Vivi candidate and context modes

Actor vivi_v4_17, implementing from canonical EARS in `04-methodology-and-ecosystem.md` §V4-17 and ARCHITECTURE/HANDOFF (named opt-in modes; maker continuity ≠ clean checker; Gauge does not grant publication authority). Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base eddd021 (main after V4-20 #614; V4-15/V4-21 present). No live/provider dispatch authorization. Architectural confidence high for fixture-local Vivi mode contracts only. Sibling `Rynaro/Vivi` remains canonical until accepted V4-10 relocation.

Select additive schema-2 vivi namespaces over (a) a schema bump or (b) rewriting Vivi's sibling methodology in-place. Challenge silent default flips of fresh-context/human-apply, treating maker rename as independent checker, claiming unsupported host compaction as completed, and Gauge-granted publication — none are introduced.

Schema 2 preserved. Additive typed namespaces: `vivi_sessions`, `vivi_modes`, `vivi_edits`, `vivi_proposals`, `vivi_applications`, `vivi_continuity`, `vivi_verifications`, `vivi_boundaries`, `vivi_context_strategies`, `vivi_events`, with `meta.vivi_receipt` and typed version guards. Pre-V4-17 schema-2 stores remain openable; vivi APIs call `EnsureViviNamespaces`.

Named opt-in modes: `proposal_only` and `candidate_workspace`. Continuity and context strategies are versioned records. Zero real network/transport. Bash 3.2 legacy CLI unchanged; vivi CLI is opt-in Go only. No V4-16/18/10/19/22, no merge/release, no paid probes.

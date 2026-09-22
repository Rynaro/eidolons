# V4-18 roster decision — need-based specialist adoption

Actor forge_v4_18, implementing from canonical EARS in `04-methodology-and-ecosystem.md` §V4-18. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base fcafd0d (main after #618; V4-13/16/17/19 already on tip). No live/provider dispatch authorization. Architectural confidence high for fixture-local profile registry and routing only.

Select additive schema-2 roster namespaces over (a) a schema bump or (b) global specialist rename. Challenge silent embedded substitution for independent requests, unexplained fan-out, falsely certified rationale, invented version tags, and advertising unproven benefits as measured — none are introduced.

Schema 2 preserved. Additive typed namespaces: `roster_profiles`, `roster_assignments`, `roster_controls`, `roster_compat`, `roster_isolation`, `roster_benefits`, `roster_registries`, `roster_events`, with `meta.roster_receipt` and typed version guards. Pre-V4-18 schema-2 stores remain openable; roster APIs call `EnsureRosterNamespaces`. New stores initialize roster namespaces alongside context.

Consumer contract `gauge-roster-adoption@1`. Required slices registered as fixture profiles with preserved display names, aliases, charters, and ceilings. Reuses V4-13 `SkillContract` / execution forms; nexus-adoption marks V4-16 RAMZA and V4-17 Vivi reuse. Opt-out/legacy selection retained. No refusal weakening.

Mutators retain V4-06 append lock patterns via shared store. Zero real network/transport. Bash 3.2 legacy CLI unchanged; roster CLI is opt-in Go only. No V4-22, no V4-23, no merge/release, no paid probes.

# V4-10 consolidation decision — inventory slice only

Actor vivi_v4_10_inventory, implementing from canonical EARS in `04-methodology-and-ecosystem.md` §V4-10 focusing R01 and R07. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base eddd021 (main after V4-20 #614; V4-21 already on main). No live/provider dispatch authorization. Architectural confidence high for inventory artifact + validators only.

Select a committed machine-readable inventory (`docs/campaigns/gauge/inventory/v4-10.json`) plus Go contract validators over (a) schema-2 store namespaces or (b) performing an import/compiler in this assignment. Challenge silent passes of deferred slices, performance claims from null/blocked/inconclusive V4-21 results, automatic `.spectra/` archive, privileged-tool merger, and protocol rewrite — none are introduced.

Schema 2 unchanged (store namespaces optional and unused). Inventory enumerates ten specialists, four contracts, Junction, tonberry, atomos, atlas-aci, CRYSTALIUM, evaluation tooling, and optional ACP/A2A clients with consumers/license/provenance/replacement/boundaries. R02–R03 deferred to `registry-and-discovery-compiler`; R04–R06 partial readiness only; `one-component-import` not yet assigned.

Mutators: none beyond the inventory artifact. Zero real network/transport. Bash 3.2 legacy CLI unchanged. No CLI required. No merge/release, no paid probes, no import/compiler execution.

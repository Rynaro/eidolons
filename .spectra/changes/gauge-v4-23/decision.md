# V4-23 release decision — evidence-scoped migration and release gates

Actor vivi_v4_23, implementing from canonical EARS in `05-evaluation-and-rollout.md` §V4-23. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base 5136c21 (main tip after V4-18 + V4-22). No live/provider dispatch authorization. No merge/tag/release/deploy/archival authorization. Architectural confidence high for fixture-local gate refusals only.

Select additive schema-2 release namespaces (`release_migrations`, `release_recoveries`, `release_candidates`, `release_authorizations`, `release_retirements`, `release_host_caps`, `release_readiness`, `release_rollbacks`, `release_events`) with `meta.release_receipt` and typed version guards over (a) a schema bump or (b) mutating production `cli/install.sh` behavioral defaults. Challenge force-integrity bypass, smoke-as-live-evidence, prepared-report-as-tag-authorization, composite green badges, unmigrated-consumer archival, host-version-stale managed claims, stale acceptance / budget refill / wider authority on rollback — none are introduced.

Schema 2 preserved. Pre-V4-23 schema-2 stores remain openable; release APIs call `EnsureReleaseNamespaces`. New stores initialize release namespaces after calibration.

Contract file: `gauge/internal/contract/release.go` (coherent name covering migration + release + retirement + readiness). CLI split: `release.go` + `migration.go`. Reuses V4-07 migration patterns, V4-20 status separation, V4-21/22 evidence separation without rewriting those packages.

v4.0.0 readiness reporting covers only actually implemented breaks; governance-only improvements labeled as such (not measured speed/cost superiority). Optional experiments/clients may remain deferred with explicit labels.

Mutators retain V4-06 append lock + identity conflict checks. Zero real network/transport. Bash 3.2 legacy CLI unchanged; release/migration CLI is opt-in Go only. Publication/tag/release/merge/archival explicitly blocked by gate fixtures.

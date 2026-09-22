# V4-13 compiler decision — assignments without mandatory agent chains

Actor vivi_v4_13, implementing from canonical EARS in `03-managed-delivery.md` §V4-13 and ARCHITECTURE.md §Expertise without mandatory topology. Plan commit c581308f055a0e252013bf09f2a7b2e1426ff811. Implementation base 47fc0a4 (V4-12 merged via #609). No live/provider dispatch authorization. Architectural confidence high for fixture-local assignment compilation only.

Select continuing-maker default over (a) mandatory agent-chain fan-out or (b) automatic worker allocation from skill names. Challenge invented independence from rename/fork/same-model and invented acceptance from method use — none are introduced.

Schema 2 preserved. Additive typed namespaces: `compiled_plans`, `method_bindings`, `assignment_splits`, `consultant_receipts`, with `meta.compiler_receipt` and typed version guards. Pre-V4-13 schema-2 stores remain openable; compiler APIs call `EnsureCompilerNamespaces`. New stores initialize compiler namespaces alongside dispatch.

Compile sequence: resolve effective authority (operator∩task∩assignment∩specialist∩host) → validate each method’s versioned skill contract before any dispatch → bind compatible methods into the maker assignment → emit separately identified WorkerStart records only when a concrete boundary reason applies. Selection reasons are inspectable and explicitly fallible. Experimental profile `gauge-experimental-compiler@0.1` until roster charters are amended.

Role rebinding that cannot safely revoke prior capabilities requires a new restricted execution; prompt-only revocation is insufficient. Evidence classification withholds clean-context status when maker/privileged context is inherited. Consultant results must pass bounded output validation (size, artifact ref, task/candidate, schema; no transcript dumps) before maker use. Concurrent writers require isolated workspaces, integration owner, and integration/check reservations; merge still revalidates.

Mutators retain V4-06 append lock + active claim/inventory checks. V4-09 live admission remains fail-closed. Zero real network/transport. Bash 3.2 legacy CLI unchanged; compiler CLI is opt-in Go only. No V4-14+, no merge/release, no paid probes, no mandatory agent chains.

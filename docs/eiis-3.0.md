# EIIS 3.0 — self-contained Eidolons

EIIS 3.0 removes generated methodology copies. A consumer installation has one authoritative tree:

```text
EIDOLONS.md
.eidolons/<agent>/
├── EIIS_VERSION
├── PERSONA.md
├── SPEC.md
└── skills/<methodology>/
    ├── SKILL.md
    └── <resources>
```

`EIDOLONS.md` MUST exist at the repository root and is the canonical routing surface. `AGENTS.md`, `CLAUDE.md`, and other host instruction files MAY exist, but their Eidolons-owned content MUST only direct the host to `EIDOLONS.md` and the canonical `.eidolons` paths.

The legacy `.eidolons/cortex/EIDOLONS.md` path MAY remain only as a relative symlink to root `EIDOLONS.md`; it must not be another copy.

`PERSONA.md` is the concise identity, scope, triggers, refusal boundaries, and dispatch contract. `SPEC.md` is the normative methodology. An Eidolon MUST NOT also install `agent.md` at EIIS 3.0.

Each skill MUST use `skills/<methodology>/SKILL.md`. Skill-specific scripts, references, schemas, examples, and assets live in that same directory. Shared resources may live elsewhere under the same agent tree and must be referenced relatively. A methodology body MUST occur exactly once.

Host adapters are discovery metadata. If a host requires its own `SKILL.md` path, the adapter MUST be a relative symlink to the canonical file; copying the body is non-conformant. Hosts that support instruction pointers should use a small pointer file instead. Removing a host adapter must never remove canonical content.

Every v3 install manifest records `eiis_version: "3.0"`, the canonical persona and spec paths, skill entrypoints, and adapter paths. Hooks remain fail-open at runtime, but are not considered installed until `eidolons harness check` proves that each lock-recorded shim exists, is executable, parses, and is registered in the corresponding host surface.

Compatibility is read-side only: doctor continues to inspect legacy `agent.md` and flat skill files for EIIS 1.x installations. A member declaring EIIS 3.0 receives the strict v3 layout checks; it cannot claim v3 while retaining duplicate files.

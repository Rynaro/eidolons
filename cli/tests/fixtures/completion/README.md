# Completion conformance fixtures

`control.json` supplies language-neutral candidate identity, mandatory checks,
sequenced observations, current identity and independently observed artifact
integrity inputs to the pure evaluator. `expected.json` pins the three separate
grades for a qualified positive control. Symbolic identities are deliberate
fixture values; real candidate captures use SHA-256 fingerprints.

Authenticated maker/checker/context-access objects are constructed only in the
Python test harness, in memory. They are not in the JSON fixture, accepted by a
CLI flag, read from the environment, or reconstructed from a serialized receipt.
The identical JSON input without that separate authority must remain unaccepted.
These controls establish fixture behavior, not production protected execution.

The tests also drive the actual CLI: pass/fail/pass outcomes remain visible even
though production manual provenance cannot qualify for independent acceptance;
candidate mutations invalidate current status; altered/deleted artifacts lose
integrity; native/A2A/MCP completion remains termination only. The original
manual-label false success is the real sandbox red-gate reproduction.

Candidate inputs include all tracked files, discovered nonignored untracked
files, explicit required-untracked files (including ignored files), modes,
symlink identities, criteria bytes, HEAD/integration base, and explicit named
environment/configuration digests. Values from environment/configuration are
not copied into journal records. `.git` and the ledger's own operational outputs
are fixed exclusions; tracked or required inputs there are rejected. Directory
and external symlink inputs are unsupported and fail closed. A captured mutable
tree is not frozen execution or protected verification.

Historical views use captured event time and reporter invocation identity.
They do not re-establish current acceptance or authenticated provenance.
`augment evidence` accepts a canonical journal-capture reference and rejects its
former raw-array input with migration guidance; no rendering-time IDs or
comparative conclusions are emitted. Other augment commands retain their
existing behavior.

V4-06 can reuse these inputs, expected grades and V4-04 journal fixtures without
changing old event bytes. Snapshot fingerprints use sorted-key ASCII-escaped
compact JSON plus LF; this is distinct from the unchanged legacy jq event hash.

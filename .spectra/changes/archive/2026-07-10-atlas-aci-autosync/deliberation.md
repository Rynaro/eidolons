# Deliberation — auto-sync cadence

The one open decision was **how often to fire the incremental reindex**, a freshness-vs-latency
trade against the harness's ECM ≤300 ms prompt-path budget. Presented to the maintainer with
four grounded options; decision recorded here (maintainer choice, requires_checker: false —
this feeds implementation, not an irreversible action).

**DECISION: per-turn background.** A UserPromptSubmit hook fires a non-blocking
`atlas-aci index --since` before each turn and returns immediately; the rebuild completes async
and atomically swaps in. Plus a SessionStart refresh.

- **[CONTEXT]** The maintainer explicitly named mid-session staleness ("affect sessions in
  mid-flight") as the pain. Session-start-only cannot address it.
- **[REJECTED] session-start-only** — fresh at start, stale mid-session. Under-serves the pain.
- **[REJECTED] blocking per-turn** — would block the prompt path; ECM budget is ≤300 ms.
- **[REJECTED] git post-commit hook** — misses uncommitted working-tree edits, which is most of
  what an agent reads mid-task; heavier install footprint.
- **[CONSEQUENCE]** Adds one detached container spin per turn (deduped to at most one in-flight
  per project). Freshness lags edits by at most ~one turn.
- **[REVERSAL]** If per-turn container spin proves too costly on some host, fall back to
  session-start + a debounce; the opt-out already lets any project disable it entirely.

Safety of concurrent reindex-while-serving is not in doubt: atlas-aci's index writes a temp file
and atomically renames under a single-writer lock (AC-H-17); serve opens mode=ro. This is the
same docker-in-hook shape `eidolons memory preflight` already uses.

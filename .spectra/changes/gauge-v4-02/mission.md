# V4-02 legacy fixture scout

DECISION_TARGET: identify the smallest faithful, reproducible fixture coverage for V4-02 and the current upgrade mutation/rollback boundaries. Read-only source authority; isolated /private/tmp probe output is allowed, but no source edits or production upgrades.

Read the pinned V4-02 stage table and spec.md. Trace sidecar backfill, tracked-file dirtiness, .git/info/exclude/worktree handling, staging, verification and rollback. Inspect actual local tags v1.10.0/v1.40.0/v1.41.0/v1.41.1/v2.20.0/v3.3.1. Recommend an offline CI fixture strategy that does not call relabeled modern code a historical installation. Report source anchors, exact tag commits, baseline failing behavior where practical, and the real executable delivery boundary. Do not redesign the updater, fetch unneeded external dependencies, edit source/tests, run actual user upgrades, or spawn agents.

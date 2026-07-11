# HARNESS-V1 RUNS — INVALID FOR THE GATE, PRESERVED FOR THE RECORD

These runs (full run1, first 3 cells of run2) executed under a defective
harness: `claude -p --agent gilgamesh` with NO --allowedTools, so the
headless permission layer denied Bash commands that are squarely inside
gilgamesh's frontmatter allowlist (shellcheck/bats/make/wc). Agents honestly
reported "blocked" instead of fabricating pass — the failures measure the
harness, not capability. Runner stopped at 2026-07-11T14:1xZ, defect
verified by probe, official runs re-executed under harness-v2
(--allowedTools mirroring the agent frontmatter exactly — no expansion).
Gate author: gate-author-sonnet-fresh. Nothing in this directory feeds the
official arm1-results.jsonl / arm1-verdict.json.

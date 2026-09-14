SHELL := /usr/bin/env bash

# Parallelism for `make test` / `make test-fast`. Override on the command
# line: `make test JOBS=4`.
JOBS ?= 8

.PHONY: help test test-fast test-file lint schema token-budget check

help:
	@echo "Targets:"
	@echo "  test         Run the full bats suite in parallel (JOBS=$(JOBS))."
	@echo "  test-fast    Alias for test; intended for the local inner loop."
	@echo "  test-file F=cli/tests/init.bats   Run a single file."
	@echo "  test-file F=cli/tests/init.bats P='preset pipeline'  Run a single test by name pattern."
	@echo "  lint         shellcheck the CLI sources."
	@echo "  schema       Validate roster + schema JSON structurally."
	@echo "  token-budget Check always-loaded dispatch token budgets."
	@echo "  check        lint + schema + test."
	@echo ""
	@echo "Override JOBS to tune parallelism, e.g. \`make test JOBS=4\`."

# Files are parallelised across; tests within a file stay sequential to
# match CI's contention profile (harness install + cache fixtures).
test test-fast:
	@if [ "$(JOBS)" -gt 1 ]; then \
	  bats --jobs "$(JOBS)" --no-parallelize-within-files cli/tests/; \
	else \
	  bats cli/tests/; \
	fi

# Run a single file (or a single test by name pattern).
#   make test-file F=cli/tests/init.bats
#   make test-file F=cli/tests/init.bats P='preset pipeline'
test-file:
	@if [ -z "$(F)" ]; then \
	  echo "usage: make test-file F=cli/tests/<name>.bats [P='filter']"; \
	  exit 2; \
	fi; \
	if [ -n "$(P)" ]; then \
	  bats "$(F)" -f "$(P)"; \
	else \
	  bats "$(F)"; \
	fi

lint:
	@find cli -name '*.sh' -type f -print0 | xargs -0 shellcheck -x -S error
	@shellcheck -x -S error cli/eidolons

schema:
	@jq empty schemas/*.json
	@yq eval '.' roster/index.yaml >/dev/null
	@bash cli/src/check_roster_mcp_skew.sh
	@bash cli/src/check_change_specs.sh

token-budget:
	@bash scripts/token-budget-check.sh EIDOLONS.md --ceiling 850

check: lint schema token-budget test

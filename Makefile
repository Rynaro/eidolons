SHELL := /usr/bin/env bash

# Parallelism for `make test` / `make test-fast`. Override on the command
# line: `make test JOBS=4`.
JOBS ?= 8
PYTHON ?= python3
# Optional explicit release candidate, e.g. make schema PUBLISH=nexus@3.4.0
PUBLISH ?=
RELEASE_RECORD ?=

.PHONY: help test test-fast test-file lint schema token-budget check gauge-build gauge-test gauge-package

help:
	@echo "Targets:"
	@echo "  test         Run the full bats suite in parallel (JOBS=$(JOBS))."
	@echo "  test-fast    Alias for test; intended for the local inner loop."
	@echo "  test-file F=cli/tests/init.bats   Run a single file."
	@echo "  test-file F=cli/tests/init.bats P='preset pipeline'  Run a single test by name pattern."
	@echo "  lint         shellcheck the CLI sources."
	@echo "  schema       Validate authored keys and publication integrity records."
	@echo "  token-budget Check always-loaded dispatch token budgets."
	@echo "  check        lint + schema + test."
	@echo "  gauge-build  Explicitly build the optional Gauge binary (Go 1.27.1)."
	@echo "  gauge-test   Run separate Gauge conformance anchors (Go, Bats, jq, Python)."
	@echo "  gauge-package Package the optional binary with required license notices."
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
	@$(PYTHON) scripts/validate-registry.py $(if $(PUBLISH),--publish "$(PUBLISH)") $(if $(RELEASE_RECORD),--release-record "$(RELEASE_RECORD)")
	@bash cli/src/check_roster_mcp_skew.sh
	@bash cli/src/check_change_specs.sh

token-budget:
	@bash scripts/token-budget-check.sh EIDOLONS.md --ceiling 850

check: lint schema token-budget test

# Optional compiled path. These are deliberately absent from ordinary check
# and install: consumers who opt out do not require Go or a Gauge binary.
gauge-build:
	@bash scripts/gauge-build.sh build $(if $(GAUGE_OUT),"$(GAUGE_OUT)")

gauge-test:
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/policy-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/observation-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/instrument-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/reservation-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/dispatch-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/compiler-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/acceptance-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/delivery-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/evaluation-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bash gauge/tests/status-anchors.sh
	@GAUGE_REPO="$(CURDIR)" GOTOOLCHAIN=local bats --print-output-on-failure gauge/tests/conformance.bats

gauge-package:
	@bash scripts/gauge-build.sh package $(if $(GAUGE_OUT),"$(GAUGE_OUT)")

#!/usr/bin/env bash
# check-eidolon-stamps.sh <eidolon-checkout-dir> <version>
#
# Pre-flight stamp checker for Eidolon releases.
# Logs PASS/FAIL for each check to stderr; exits nonzero if any fail.
# Stdout is kept clean (repo convention — capture-friendly).
# Bash 3.2 compatible (no associative arrays, no readarray, no ${var,,}).

set -euo pipefail

usage() {
  printf 'Usage: %s <eidolon-checkout-dir> <version>\n' "$(basename "$0")" >&2
  printf 'Example: %s ../ATLAS 1.12.0\n' "$(basename "$0")" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  usage
fi

dir="$1"
version="$2"

if [ ! -d "$dir" ]; then
  printf 'ERROR: directory not found: %s\n' "$dir" >&2
  exit 1
fi

# Escape dots in version for use in ERE patterns (1.2.3 -> 1\.2\.3).
escaped_ver="$(printf '%s' "$version" | sed 's/\./\\./g')"

failures=0

pass() { printf '[PASS] %s\n' "$1" >&2; }
fail() { printf '[FAIL] %s\n' "$1" >&2; failures=$((failures + 1)); }
note() { printf '[NOTE] %s\n' "$1" >&2; }

# ── Check 1: install.sh EIDOLON_VERSION ───────────────────────────────────────
if [ ! -f "${dir}/install.sh" ]; then
  fail "install.sh not found in ${dir}"
else
  if grep -qE "^[[:space:]]*(readonly[[:space:]]+)?EIDOLON_VERSION=\"${escaped_ver}\"" "${dir}/install.sh"; then
    pass "install.sh EIDOLON_VERSION=\"${version}\""
  else
    fail "install.sh EIDOLON_VERSION does not match ${version} — found:"
    grep "EIDOLON_VERSION" "${dir}/install.sh" >&2 || printf '  (no EIDOLON_VERSION line)\n' >&2
  fi
fi

# ── Check 2: CHANGELOG.md has a heading for the version ───────────────────────
if [ ! -f "${dir}/CHANGELOG.md" ]; then
  fail "CHANGELOG.md not found in ${dir}"
else
  if grep -qE "^## \[${escaped_ver}\]" "${dir}/CHANGELOG.md"; then
    pass "CHANGELOG.md contains ## [${version}]"
  else
    fail "CHANGELOG.md is missing ## [${version}] heading"
  fi
fi

# ── Check 3: agent.md frontmatter version: ────────────────────────────────────
if [ ! -f "${dir}/agent.md" ]; then
  note "agent.md not found in ${dir} — skipping frontmatter version check"
else
  if grep -q "^version:" "${dir}/agent.md"; then
    if grep -qE "^version:[[:space:]]*${escaped_ver}[[:space:]]*$" "${dir}/agent.md"; then
      pass "agent.md frontmatter version: ${version}"
    else
      fail "agent.md frontmatter version: does not match ${version} — found:"
      grep "^version:" "${dir}/agent.md" >&2
    fi
  else
    note "agent.md has no 'version:' frontmatter key — skipping"
  fi
fi

# ── Check 4: AGENTS.md frontmatter version: ───────────────────────────────────
if [ ! -f "${dir}/AGENTS.md" ]; then
  note "AGENTS.md not found in ${dir} — skipping frontmatter version check"
else
  if grep -q "^version:" "${dir}/AGENTS.md"; then
    if grep -qE "^version:[[:space:]]*${escaped_ver}[[:space:]]*$" "${dir}/AGENTS.md"; then
      pass "AGENTS.md frontmatter version: ${version}"
    else
      fail "AGENTS.md frontmatter version: does not match ${version} — found:"
      grep "^version:" "${dir}/AGENTS.md" >&2
    fi
  else
    note "AGENTS.md has no 'version:' frontmatter key — skipping"
  fi
fi

# ── Check 5: SPEC.md mentions version in first 10 lines ───────────────────────
if [ ! -f "${dir}/SPEC.md" ]; then
  note "SPEC.md not found in ${dir} — skipping header version check"
else
  if head -10 "${dir}/SPEC.md" | grep -qF "${version}"; then
    pass "SPEC.md first 10 lines mention ${version}"
  else
    fail "SPEC.md first 10 lines do not mention ${version} — found:"
    head -10 "${dir}/SPEC.md" >&2
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n' >&2
if [ "$failures" -gt 0 ]; then
  printf '[RESULT] %d check(s) FAILED for %s @ %s\n' "$failures" "$dir" "$version" >&2
  exit 1
else
  printf '[RESULT] All checks passed for %s @ %s\n' "$dir" "$version" >&2
  exit 0
fi

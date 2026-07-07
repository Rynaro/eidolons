#!/usr/bin/env bats
# cli/tests/verify_envelope.bats — the mechanical ECL hand-off integrity gate.
# Roadmap #2: blocking + symmetric SHA-256 verification (no LLM). Covers the
# verdict matrix (pass/tamper/inconsistent/unverifiable/missing/malformed), the
# staged warn|block modes, and the `eidolons run --verify` pre-step.

load helpers

_field() { echo "$output" | jq -r "$1"; }

# Build a valid payload + envelope in $1 with a correct SHA-256.
_mkenv() {
  local dir="$1" content="${2:-hello ecl payload}"
  mkdir -p "$dir"
  printf '%s' "$content" > "$dir/spec.md"
  local sha size
  sha="$( { shasum -a 256 "$dir/spec.md" 2>/dev/null || sha256sum "$dir/spec.md"; } | awk '{print $1}')"
  size="$(wc -c < "$dir/spec.md" | tr -d '[:space:]')"
  cat > "$dir/spec.md.envelope.json" <<EOF
{
  "envelope_version": "2.0",
  "from": {"eidolon": "spectra", "version": "4.7.0"},
  "to": {"eidolon": "apivr", "version": "3.5.0"},
  "performative": "PROPOSE",
  "artifact": {"kind": "spec", "schema_version": "1.0", "path": "spec.md", "sha256": "$sha", "size_bytes": $size},
  "integrity": {"method": "sha256", "value": "$sha"}
}
EOF
  echo "$dir/spec.md.envelope.json"
}

@test "verify-envelope: --help exits 0" {
  run eidolons verify-envelope --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ECL hand-off envelope" ]]
}

@test "verify-envelope: no envelope is a clean error" {
  run eidolons verify-envelope
  [ "$status" -ne 0 ]
}

@test "pass: payload SHA matches integrity tag -> verdict pass, exit 0" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/ok")"
  run eidolons verify-envelope "$env" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.verdict')" = "pass" ]
  [ "$(_field '.blocked')" = "false" ]
}

@test "tamper warn: mutated payload -> verdict tamper, exit 0 (warn does not block)" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/tw")"
  echo "MUTATED" >> "$BATS_TEST_TMPDIR/tw/spec.md"
  run eidolons verify-envelope "$env" --mode warn --json
  [ "$status" -eq 0 ]
  [ "$(_field '.verdict')" = "tamper" ]
  [ "$(_field '.blocked')" = "false" ]
}

@test "tamper block: mutated payload -> refuse, exit 3, blocked true" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/tb")"
  echo "MUTATED" >> "$BATS_TEST_TMPDIR/tb/spec.md"
  run eidolons verify-envelope "$env" --block --json
  [ "$status" -eq 3 ]
  [ "$(_field '.verdict')" = "tamper" ]
  [ "$(_field '.blocked')" = "true" ]
}

@test "block mode via EIDOLONS_ECL_VERIFY_MODE env" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/tenv")"
  echo "MUTATED" >> "$BATS_TEST_TMPDIR/tenv/spec.md"
  EIDOLONS_ECL_VERIFY_MODE=block run eidolons verify-envelope "$env"
  [ "$status" -eq 3 ]
}

@test "unverifiable: placeholder SHA -> exit 0 even in block (parent must fill)" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/ph")"
  tmp="$(jq '.integrity.value="PARENT_FILLS_SHA" | .artifact.sha256=""' "$env")"
  echo "$tmp" > "$env"
  run eidolons verify-envelope "$env" --block --json
  [ "$status" -eq 0 ]
  [ "$(_field '.verdict')" = "unverifiable" ]
}

@test "inconsistent: artifact.sha256 != integrity.value -> block refuses" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/inc")"
  tmp="$(jq '.artifact.sha256="0000000000000000000000000000000000000000000000000000000000000000"' "$env")"
  echo "$tmp" > "$env"
  run eidolons verify-envelope "$env" --block
  [ "$status" -eq 3 ]
}

@test "missing_payload: payload removed -> block refuses, exit 3" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/mp")"
  rm -f "$BATS_TEST_TMPDIR/mp/spec.md"
  run eidolons verify-envelope "$env" --block
  [ "$status" -eq 3 ]
}

@test "malformed: invalid JSON -> exit 2" {
  mkdir -p "$BATS_TEST_TMPDIR/bad"
  echo "{ not json" > "$BATS_TEST_TMPDIR/bad/x.envelope.json"
  run eidolons verify-envelope "$BATS_TEST_TMPDIR/bad/x.envelope.json"
  [ "$status" -eq 2 ]
}

@test "malformed: missing required fields -> exit 2" {
  mkdir -p "$BATS_TEST_TMPDIR/mf"
  echo '{"envelope_version":"2.0"}' > "$BATS_TEST_TMPDIR/mf/x.envelope.json"
  run eidolons verify-envelope "$BATS_TEST_TMPDIR/mf/x.envelope.json"
  [ "$status" -eq 2 ]
}

@test "trace: --trace appends a verify_pass JSONL event" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/tr")"
  run eidolons verify-envelope "$env" --trace "$BATS_TEST_TMPDIR/tr/trace.jsonl"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/tr/trace.jsonl" ]
  [ "$(jq -r '.event' "$BATS_TEST_TMPDIR/tr/trace.jsonl")" = "verify_pass" ]
}

# ── eidolons run --verify pre-step (the kernel integration) ───────────────────

@test "run --verify pass: routes and records incoming_verify pass" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/rv")"
  run eidolons run "map the auth flow" --verify "$env" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.selected[0]')" = "atlas" ]
  [ "$(_field '.incoming_verify.verdict')" = "pass" ]
}

@test "run --verify warn: tampered hand-off still routes but records tamper" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/rw")"
  echo "MUTATED" >> "$BATS_TEST_TMPDIR/rw/spec.md"
  run eidolons run "map the auth flow" --verify "$env" --json
  [ "$status" -eq 0 ]
  [ "$(_field '.incoming_verify.verdict')" = "tamper" ]
}

@test "run --verify-block: tampered hand-off REFUSES to route (exit 3)" {
  env="$(_mkenv "$BATS_TEST_TMPDIR/rb")"
  echo "MUTATED" >> "$BATS_TEST_TMPDIR/rb/spec.md"
  run eidolons run "map the auth flow" --verify "$env" --verify-block
  [ "$status" -eq 3 ]
  [[ "$output" =~ "blocked" ]]
}

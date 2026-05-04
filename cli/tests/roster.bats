#!/usr/bin/env bats

load helpers

@test "roster: team view lists every Eidolon" {
  run eidolons roster
  [ "$status" -eq 0 ]
  [[ "$output" =~ ATLAS ]]
  [[ "$output" =~ SPECTRA ]]
  [[ "$output" =~ cycle: ]]
  [[ "$output" =~ methodology: ]]
}

@test "roster atlas: single-member summary" {
  run eidolons roster atlas
  [ "$status" -eq 0 ]
  [[ "$output" =~ ATLAS ]]
  [[ "$output" =~ Methodology: ]]
  [[ "$output" =~ Handoffs: ]]
  [[ "$output" =~ Security: ]]
}

@test "roster atlas --methodology: methodology view only" {
  run eidolons roster atlas --methodology
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "ATLAS"' >/dev/null
  echo "$output" | jq -e '.cycle' >/dev/null
}

@test "roster atlas --handoffs: handoff view only" {
  run eidolons roster atlas --handoffs
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.downstream | length > 0' >/dev/null
}

@test "roster atlas --references: references list" {
  run eidolons roster atlas --references
  [ "$status" -eq 0 ]
  [[ "$output" =~ research/ ]]
}

@test "roster atlas --json: full entry as JSON" {
  run eidolons roster atlas --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "atlas"' >/dev/null
  echo "$output" | jq -e '.source.repo' >/dev/null
}

@test "roster: unknown name exits 1 with actionable message" {
  run eidolons roster not-a-real-eidolon
  [ "$status" -eq 1 ]
  [[ "$output" =~ not\ found ]]
}

@test "roster -h: help prints" {
  run eidolons roster -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ roster ]]
}

# ─── G15: source.repo casing audit ────────────────────────────────────────
# Static check: assert that roster/index.yaml source.repo values match the
# GitHub canonical casing confirmed by the audit in spec §2.
# Canonical values (verified 2026-05-04 via GitHub API / curl redirect):
#   atlas  → Rynaro/ATLAS
#   spectra → Rynaro/SPECTRA
#   apivr  → Rynaro/APIVR-Delta
#   idg    → Rynaro/IDG
#   forge  → Rynaro/FORGE
#   vigil  → Rynaro/VIGIL
@test "roster source.repo casing matches GitHub canonical casing for all shipped Eidolons" {
  run eidolons roster atlas --json
  [ "$status" -eq 0 ]
  actual_atlas="$(echo "$output" | jq -r '.source.repo')"
  [ "$actual_atlas" = "Rynaro/ATLAS" ]

  run eidolons roster spectra --json
  [ "$status" -eq 0 ]
  actual_spectra="$(echo "$output" | jq -r '.source.repo')"
  [ "$actual_spectra" = "Rynaro/SPECTRA" ]

  run eidolons roster apivr --json
  [ "$status" -eq 0 ]
  actual_apivr="$(echo "$output" | jq -r '.source.repo')"
  [ "$actual_apivr" = "Rynaro/APIVR-Delta" ]

  run eidolons roster idg --json
  [ "$status" -eq 0 ]
  actual_idg="$(echo "$output" | jq -r '.source.repo')"
  [ "$actual_idg" = "Rynaro/IDG" ]

  run eidolons roster forge --json
  [ "$status" -eq 0 ]
  actual_forge="$(echo "$output" | jq -r '.source.repo')"
  [ "$actual_forge" = "Rynaro/FORGE" ]

  run eidolons roster vigil --json
  [ "$status" -eq 0 ]
  actual_vigil="$(echo "$output" | jq -r '.source.repo')"
  [ "$actual_vigil" = "Rynaro/VIGIL" ]
}

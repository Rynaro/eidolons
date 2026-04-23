#!/usr/bin/env bats
#
# dispatch_eidolon tests — generic per-Eidolon subcommand router.
# We can't clone live Eidolon repos in tests, so these cover the
# dispatcher's resolution logic against a fabricated .eidolons/ tree.

load helpers

@test "dispatch_eidolon: unknown command (not a roster eidolon) exits 2 with usage" {
  # The catch-all in cli/eidolons tests membership against the roster;
  # a non-roster name falls through to the 'Unknown command' path and
  # does NOT touch the dispatcher — keeps error surface minimal.
  run eidolons not-a-real-eidolon fit
  [ "$status" -eq 2 ]
  [[ "$output" =~ Unknown\ command ]]
}

@test "dispatch_eidolon: known eidolon with no install and no cache explains clearly" {
  # spectra is a known roster entry, but nothing is installed and no cache
  run eidolons spectra fit
  [ "$status" -ne 0 ]
  [[ "$output" =~ no\ commands/\ directory ]]
}

@test "dispatch_eidolon: --help lists available subcommands from installed commands/" {
  mkdir -p ".eidolons/spectra/commands"
  cat > ".eidolons/spectra/commands/fit.sh" <<'EOF'
#!/usr/bin/env bash
echo "fit ran: $*"
EOF
  chmod +x ".eidolons/spectra/commands/fit.sh"

  run eidolons spectra --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ Available\ subcommands\ for\ spectra ]]
  [[ "$output" =~ fit ]]
}

@test "dispatch_eidolon: dispatches to subcommand script with pass-through args" {
  mkdir -p ".eidolons/spectra/commands"
  cat > ".eidolons/spectra/commands/fit.sh" <<'EOF'
#!/usr/bin/env bash
echo "fit ran: $*"
EOF
  chmod +x ".eidolons/spectra/commands/fit.sh"

  run eidolons spectra fit --some-flag value
  [ "$status" -eq 0 ]
  [[ "$output" =~ fit\ ran:\ --some-flag\ value ]]
}

@test "dispatch_eidolon: unknown subcommand for known eidolon errors actionably" {
  mkdir -p ".eidolons/spectra/commands"
  cat > ".eidolons/spectra/commands/fit.sh" <<'EOF'
#!/usr/bin/env bash
echo "ok"
EOF
  chmod +x ".eidolons/spectra/commands/fit.sh"

  run eidolons spectra not-a-subcommand
  [ "$status" -ne 0 ]
  [[ "$output" =~ no\ subcommand ]]
  [[ "$output" =~ --help ]]
}

@test "dispatch_eidolon: catch-all does not shadow core commands" {
  # 'init' must still route to init.sh, not to a per-eidolon lookup.
  run eidolons init --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ init ]]
}

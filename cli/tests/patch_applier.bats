#!/usr/bin/env bats
# cli/tests/patch_applier.bats — deterministic fuzzy edit applier (Kupo executor).
# The harness-owned, non-LLM bridge from emitted edit-text -> file changes in a
# SCRATCH --root. Never the real tree (no default root); diff-not-apply discipline.

load helpers

# A scratch sandbox dir + a target file under it. Returns the scratch path via $SCRATCH.
_scratch() {
  SCRATCH="$TEST_PROJECT/scratch"
  mkdir -p "$SCRATCH/src"
}

@test "apply: refuses without --root (never defaults to the real tree)" {
  _scratch
  echo '{"edits":[]}' > p.json
  run eidolons sandbox apply --proposal p.json
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--root" ]]
}

@test "apply: refuses a missing proposal" {
  _scratch
  run eidolons sandbox apply --proposal nope.json --root "$SCRATCH"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "proposal not found" ]]
}

@test "apply: search_replace exact match (level 1)" {
  _scratch
  printf 'def greet():\n    return "hi"\n' > "$SCRATCH/src/a.py"
  cat > p.json <<'JSON'
{"edits":[{"op":"search_replace","path":"src/a.py","search":"    return \"hi\"","replace":"    return \"kupo\""}]}
JSON
  run eidolons sandbox apply --proposal p.json --root "$SCRATCH" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.ok')" = "true" ]
  [ "$(echo "$output" | jq -r '.results[0].status')" = "applied" ]
  grep -q 'return "kupo"' "$SCRATCH/src/a.py"
  ! grep -q 'return "hi"' "$SCRATCH/src/a.py"
}

@test "apply: search_replace tolerates indent drift (level 2 fuzzy)" {
  _scratch
  # File has 2-space indent; the proposal's search block uses 4-space indent.
  printf 'def f():\n  x = 1\n  return x\n' > "$SCRATCH/src/b.py"
  cat > p.json <<'JSON'
{"edits":[{"op":"search_replace","path":"src/b.py","search":"    x = 1","replace":"  x = 2"}]}
JSON
  run eidolons sandbox apply --proposal p.json --root "$SCRATCH" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].status')" = "applied" ]
  [[ "$(echo "$output" | jq -r '.results[0].detail')" =~ "level=2" ]]
  grep -q 'x = 2' "$SCRATCH/src/b.py"
}

@test "apply: whole_file write" {
  _scratch
  cat > p.json <<'JSON'
{"edits":[{"op":"write_file","path":"src/new.txt","content":"hello\nworld\n"}]}
JSON
  run eidolons sandbox apply --proposal p.json --root "$SCRATCH" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.results[0].status')" = "applied" ]
  [ "$(cat "$SCRATCH/src/new.txt")" = "$(printf 'hello\nworld')" ]
}

@test "apply: search block not found -> not_found, non-zero, file untouched" {
  _scratch
  printf 'alpha\nbeta\n' > "$SCRATCH/src/c.txt"
  cat > p.json <<'JSON'
{"edits":[{"op":"search_replace","path":"src/c.txt","search":"gamma","replace":"delta"}]}
JSON
  run eidolons sandbox apply --proposal p.json --root "$SCRATCH" --json
  [ "$status" -ne 0 ]
  [ "$(echo "$output" | jq -r '.ok')" = "false" ]
  [ "$(echo "$output" | jq -r '.results[0].status')" = "not_found" ]
  grep -q 'alpha' "$SCRATCH/src/c.txt"
}

@test "apply: rejects path traversal (..)" {
  _scratch
  cat > p.json <<'JSON'
{"edits":[{"op":"write_file","path":"../escape.txt","content":"nope"}]}
JSON
  run eidolons sandbox apply --proposal p.json --root "$SCRATCH" --json
  [ "$status" -ne 0 ]
  [ "$(echo "$output" | jq -r '.results[0].status')" = "error" ]
  [ ! -f "$TEST_PROJECT/escape.txt" ]
}

@test "apply: multiple edits, mixed ops, all applied" {
  _scratch
  printf 'one\ntwo\n' > "$SCRATCH/src/d.txt"
  cat > p.json <<'JSON'
{"edits":[
  {"op":"search_replace","path":"src/d.txt","search":"two","replace":"TWO"},
  {"op":"write_file","path":"src/e.txt","content":"made\n"}
]}
JSON
  run eidolons sandbox apply --proposal p.json --root "$SCRATCH" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.applied')" = "2" ]
  [ "$(echo "$output" | jq -r '.failed')" = "0" ]
  grep -q 'TWO' "$SCRATCH/src/d.txt"
  [ -f "$SCRATCH/src/e.txt" ]
}

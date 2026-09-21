#!/usr/bin/env bats
# V4-01 acceptance anchors: R01–R05 -> T01–T05, local/offline fixtures.
load helpers

policy_roster() {
  mkdir -p "$TEST_PROJECT/policy-nexus/roster"
  export EIDOLONS_NEXUS="$TEST_PROJECT/policy-nexus"
  printf '%s\n' "$1" > "$EIDOLONS_NEXUS/roster/index.yaml"
}

policy_read() {
  /bin/bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; integrity_enforcement_mode'
}

seed_policy_member() {
  policy_roster '{"integrity":{"enforcement":"strict"},"eidolons":[{"name":"atlas","source":{"repo":"Rynaro/ATLAS"},"versions":{"releases":{}}}]}'
  seed_lock_with_versions atlas=1.0.0
}

seed_policy_evidence() {
  seed_policy_member
  git init -q artifact
  git -C artifact -c user.name=Fixture -c user.email=fixture@example.test commit --allow-empty -qm fixture
  git -C artifact tag v1.0.0
  export POLICY_COMMIT="$(git -C artifact rev-parse HEAD)"
  export POLICY_TREE="$(git -C artifact rev-parse 'HEAD^{tree}')"
  git -C artifact archive --format=tar --prefix=ATLAS-1.0.0/ HEAD > artifact.tar
  export POLICY_ARCHIVE="$(shasum -a 256 artifact.tar | awk '{print $1}')"
  jq --arg c "$POLICY_COMMIT" --arg t "$POLICY_TREE" --arg a "$POLICY_ARCHIVE" \
    '.eidolons[0].versions.releases["1.0.0"] = {tag:"v1.0.0",commit:$c,tree:$t,archive_sha256:$a}' \
    "$EIDOLONS_NEXUS/roster/index.yaml" > roster.new
  mv roster.new "$EIDOLONS_NEXUS/roster/index.yaml"
  cat > eidolons.lock <<LOCK
members:
  - name: atlas
    version: "1.0.0"
    commit: "$POLICY_COMMIT"
    tree: "$POLICY_TREE"
    archive_sha256: "$POLICY_ARCHIVE"
    target: "./.eidolons/atlas"
LOCK
}

clone_gate() {
  /bin/bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; _verify_release_integrity_internal atlas 1.0.0 "$PWD/artifact" || exit $?; touch accepted'
}

@test "V4-01-T01: reader canonicalizes case and surrounding whitespace from both sources" {
  local mode expected
  for mode in strict STRICT Strict ' strict ' $'\tSTRICT\r\n' warn WARN; do
    case "$mode" in warn|WARN) expected=warn ;; *) expected=strict ;; esac
    export EIDOLONS_INTEGRITY_ENFORCEMENT="$mode"
    run policy_read
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    unset EIDOLONS_INTEGRITY_ENFORCEMENT
    policy_roster "$(jq -n --arg m "$mode" '{integrity:{enforcement:$m}}')"
    run policy_read
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
  done
}

@test "V4-01-T01: real verify consumer applies canonical strict and explicit advisory" {
  seed_policy_member
  local mode
  for mode in strict STRICT Strict ' strict '; do
    export EIDOLONS_INTEGRITY_ENFORCEMENT="$mode"
    run eidolons verify atlas
    [ "$status" -ne 0 ]
    [[ "$output" == *'missing roster release integrity metadata'* ]]
  done
  export EIDOLONS_INTEGRITY_ENFORCEMENT=' WARN '
  run eidolons verify atlas
  [ "$status" -eq 0 ]
  [[ "$output" == *'compatibility verification is warning-only'* ]]
}

@test "V4-01-T02 T05: invalid and explicitly empty overrides reject with source-only diagnostics" {
  seed_policy_evidence
  local mode
  for mode in bogus '' '   ' 'str ict' 'CANARY_POLICY_SECRET'; do
    export EIDOLONS_INTEGRITY_ENFORCEMENT="$mode"
    run /bin/bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; integrity_enforcement_mode >out 2>err'
    [ "$status" -ne 0 ]
    [ ! -s out ]
    grep -q 'integrity-policy error.*EIDOLONS_INTEGRITY_ENFORCEMENT' err
    ! grep -q CANARY_POLICY_SECRET err
    run eidolons verify atlas
    [ "$status" -ne 0 ]
    [[ "$output" == *'integrity-policy error'* ]]
    [[ "$output" != *CANARY_POLICY_SECRET* ]]
    run clone_gate
    [ "$status" -ne 0 ]
    [ ! -e accepted ]
    [[ "$output" == *'integrity-policy error'* ]]
  done
}

@test "V4-01-T02: configured wrong types and empty strings reject; absent policy stays advisory" {
  unset EIDOLONS_INTEGRITY_ENFORCEMENT
  local value
  for value in null false true 1 '[]' '{}' '""' '"str ict"' '"bogus"'; do
    policy_roster "{\"integrity\":{\"enforcement\":$value}}"
    run policy_read
    [ "$status" -ne 0 ]
    [[ "$output" == *'integrity-policy error'*'roster/index.yaml'* ]]
  done
  for value in null false '[]' '"strict"'; do
    policy_roster "{\"integrity\":$value}"
    run policy_read
    [ "$status" -ne 0 ]
  done
  policy_roster '{}'
  run policy_read
  [ "$status" -eq 0 ]
  [ "$output" = warn ]
}

@test "V4-01-T03 T05: invalid YAML, missing file and absent backend fail at consumer policy gate" {
  seed_policy_member
  unset EIDOLONS_INTEGRITY_ENFORCEMENT
  printf 'integrity: [CANARY_YAML_SECRET\n' > "$EIDOLONS_NEXUS/roster/index.yaml"
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" == *'integrity-policy error'*'roster/index.yaml'* ]]
  [[ "$output" != *CANARY_YAML_SECRET* ]]
  rm "$EIDOLONS_NEXUS/roster/index.yaml"
  run policy_read
  [ "$status" -ne 0 ]
  [[ "$output" == *'integrity-policy error'* ]]
  seed_policy_member
  export _YAML_TO_JSON_BACKEND=none
  run /bin/bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; release_integrity_status atlas 1.0.0'
  [ "$status" -ne 0 ]
  [[ "$output" == *'integrity-policy error'*'roster/index.yaml'* ]]
}

@test "V4-01-T03 T05: failed YAML pipeline cannot accept valid stdout or disclose parser stderr" {
  seed_policy_member
  unset EIDOLONS_INTEGRITY_ENFORCEMENT
  run /bin/bash -c '
    . "$EIDOLONS_ROOT/cli/src/lib.sh"
    set +o pipefail
    yaml_to_json() { echo '\''{"integrity":{"enforcement":"warn"}}'\''; echo CANARY_PARSER_SECRET >&2; return 7; }
    integrity_enforcement_mode >out 2>err'
  [ "$status" -ne 0 ]
  [ ! -s out ]
  grep -q 'integrity-policy error' err
  ! grep -q CANARY_PARSER_SECRET err
}

@test "V4-01-T03: unavailable JSON parser rejects an explicit valid override" {
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  run /bin/bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; jq() { return 127; }; integrity_enforcement_mode'
  [ "$status" -ne 0 ]
  [[ "$output" == *'integrity-policy error'* ]]
}

@test "V4-01-T04: real clone and installed verification gates accept valid evidence" {
  seed_policy_evidence
  export EIDOLONS_INTEGRITY_ENFORCEMENT=STRICT
  run clone_gate
  [ "$status" -eq 0 ]
  [ -e accepted ]
  [[ "$output" == *'release integrity verified'* ]]
  run eidolons verify atlas
  [ "$status" -eq 0 ]
  [[ "$output" == *'atlas@1.0.0 verified'* ]]
}

@test "V4-01-T04: strict gates reject missing malformed and mismatched required evidence" {
  seed_policy_evidence
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  cp "$EIDOLONS_NEXUS/roster/index.yaml" valid-roster
  local mutation
  for mutation in 'del(.eidolons[0].versions.releases["1.0.0"])' \
    '.eidolons[0].versions.releases["1.0.0"] = {}' \
    '.eidolons[0].versions.releases["1.0.0"].commit = "bad"' \
    '.eidolons[0].versions.releases["1.0.0"].tree = false' \
    '.eidolons[0].versions.releases["1.0.0"].archive_sha256 = []' \
    '.eidolons[0].versions.releases["1.0.0"].commit = "1111111111111111111111111111111111111111"'; do
    jq "$mutation" valid-roster > "$EIDOLONS_NEXUS/roster/index.yaml"
    run clone_gate
    [ "$status" -ne 0 ]
    [ ! -e accepted ]
    [[ "$output" == *'integrity metadata'* || "$output" == *'commit mismatch'* ]]
    run eidolons verify atlas
    [ "$status" -ne 0 ]
    [[ "$output" == *'integrity metadata'* || "$output" == *'commit mismatch'* ]]
  done
}

@test "V4-01-T02 T03: release status never emits verified or legacy on a policy failure" {
  seed_policy_evidence
  export EIDOLONS_INTEGRITY_ENFORCEMENT=bogus
  run /bin/bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; release_integrity_status atlas 1.0.0 >out 2>err'
  [ "$status" -ne 0 ]
  [ ! -s out ]
  grep -q 'integrity-policy error' err
}

@test "V4-01-T02 T03: fetch rejects policy failure without re-clone or install side effects" {
  seed_policy_evidence
  export EIDOLONS_INTEGRITY_ENFORCEMENT=bogus
  mkdir -p "$EIDOLONS_HOME/cache"
  cp -R artifact "$EIDOLONS_HOME/cache/atlas@1.0.0"
  run /bin/bash -c '
    . "$EIDOLONS_ROOT/cli/src/lib.sh"
    git() { if [[ "$1" = clone ]]; then touch cloned; return 99; fi; command git "$@"; }
    fetch_eidolon atlas 1.0.0 >out 2>err || exit $?
    touch installed'
  [ "$status" -ne 0 ]
  [ ! -s out ]
  [ ! -e cloned ]
  [ ! -e installed ]
  [ -d "$EIDOLONS_HOME/cache/atlas@1.0.0/.git" ]
  grep -q 'integrity-policy error' err
}

@test "V4-01-T01 T03: doctor validates current policy without reinterpreting historical legacy status" {
  seed_policy_member
  seed_manifest
  export EIDOLONS_INTEGRITY_ENFORCEMENT=bogus
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *'integrity-policy error'* ]]
  export EIDOLONS_INTEGRITY_ENFORCEMENT=' STRICT '
  run eidolons doctor
  [[ "$output" != *'integrity-policy error'* ]]
  [[ "$output" == *'no roster release metadata (legacy)'* ]]
}

@test "V4-01-T04: independent valid partial hash evidence remains supported" {
  seed_policy_evidence
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  cp "$EIDOLONS_NEXUS/roster/index.yaml" valid-roster
  local field
  for field in commit tree archive_sha256; do
    jq --arg f "$field" '.eidolons[0].versions.releases["1.0.0"] |= {($f):.[$f],manifest_sha256:null}' valid-roster > "$EIDOLONS_NEXUS/roster/index.yaml"
    run clone_gate
    [ "$status" -eq 0 ]
    run eidolons verify atlas
    [ "$status" -eq 0 ]
  done
}

@test "V4-01-T02 T03 T05: sync and upgrade reject policy before roster use or mutation" {
  seed_policy_member
  seed_manifest
  mkdir -p "$EIDOLONS_HOME/cache/atlas@1.0.0"
  echo preserved > "$EIDOLONS_HOME/cache/atlas@1.0.0/sentinel"
  cp eidolons.lock lock.before
  local policy command
  for policy in malformed bogus; do
    unset EIDOLONS_INTEGRITY_ENFORCEMENT
    if [[ "$policy" = malformed ]]; then
      printf 'integrity: [CANARY_CONSUMER_SECRET\n' > "$EIDOLONS_NEXUS/roster/index.yaml"
    else
      seed_policy_member
      export EIDOLONS_INTEGRITY_ENFORCEMENT=CANARY_CONSUMER_SECRET
    fi
    for command in sync upgrade; do
      run eidolons "$command" --yes --non-interactive
      [ "$status" -ne 0 ]
      [[ "$output" == *'integrity-policy error'* ]]
      [[ "$output" != *CANARY_CONSUMER_SECRET* ]]
      [ ! -d .eidolons/atlas ]
      [ "$(cat "$EIDOLONS_HOME/cache/atlas@1.0.0/sentinel")" = preserved ]
      cmp eidolons.lock lock.before
    done
  done
}

@test "V4-01-T03: unavailable YAML backend reaches verify and doctor policy diagnostics" {
  seed_policy_member
  seed_manifest
  unset EIDOLONS_INTEGRITY_ENFORCEMENT
  export _YAML_TO_JSON_BACKEND=none
  local command
  for command in verify doctor; do
    run eidolons "$command"
    [ "$status" -ne 0 ]
    [[ "$output" == *'integrity-policy error'*'roster/index.yaml'* ]]
  done
}

@test "V4-01-T04: manifest-only evidence verifies installed bytes but cannot admit a clone" {
  seed_policy_evidence
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  mkdir -p .eidolons/atlas
  printf '{"name":"atlas"}\n' > .eidolons/atlas/install.manifest.json
  local digest
  digest="$(shasum -a 256 .eidolons/atlas/install.manifest.json | awk '{print $1}')"
  jq --arg d "$digest" '.eidolons[0].versions.releases["1.0.0"] = {manifest_sha256:$d}' \
    "$EIDOLONS_NEXUS/roster/index.yaml" > roster.new
  mv roster.new "$EIDOLONS_NEXUS/roster/index.yaml"
  run eidolons verify atlas
  [ "$status" -eq 0 ]
  [[ "$output" == *'atlas@1.0.0 verified'* ]]
  run clone_gate
  [ "$status" -ne 0 ]
  [ ! -e accepted ]
  [[ "$output" == *'invalid required release integrity metadata'* ]]
  printf '{"name":"tampered"}\n' > .eidolons/atlas/install.manifest.json
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" == *'manifest checksum mismatch'* ]]
  rm .eidolons/atlas/install.manifest.json
  run eidolons verify atlas
  [ "$status" -ne 0 ]
  [[ "$output" == *'install.manifest.json missing'* ]]
}

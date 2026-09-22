#!/usr/bin/env bats
load helpers

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT/roster" "$TEST_PROJECT/schemas"
  cd "$TEST_PROJECT"
  cp "$EIDOLONS_ROOT/roster/"*.yaml roster/
  cp "$EIDOLONS_ROOT/schemas/"*.json schemas/
}

gate() { python3 "$EIDOLONS_ROOT/scripts/validate-registry.py" --root "$TEST_PROJECT" "$@"; }

@test "V4-03 T01: authored YAML and JSON duplicates fail before resolution" {
  run gate
  [ "$status" -eq 0 ]
  for data in 'x: 1\nx: 1' 'outer:\n  x: 1\n  x: 2' '{"x":1,"x":1}' '{"outer":{"x":1,"x":2}}' 'x: {<<: {a: 1, a: 1}}' 'x: {<<: [{a: 1, a: 1}, {b: 2}]}' 'x: {<<: {a: 1}, <<: {b: 2}}'; do
    printf '%b\n' "$data" > roster/duplicate.yaml
    run gate
    [ "$status" -ne 0 ]
    [[ "$output" == *duplicate* ]]
    rm roster/duplicate.yaml
  done
  printf 'defaults: &defaults {x: 1}\nmerged: {<<: *defaults, x: 2}\n' > roster/valid-merge.yaml
  run gate
  [ "$status" -eq 0 ]
  printf '{"x":1,"x":1}\n' > schemas/duplicate.json
  run gate
  [ "$status" -ne 0 ]
  [[ "$output" == *duplicate* ]]
}

@test "V4-03 T02: every publication digest rejects missing short nonhex placeholder and wrong types" {
  for field in commit tree archive_sha256; do
    for invalid in missing short nonhex zero null number; do
      FIELD="$field" INVALID="$invalid" python3 - <<'PY'
import os,yaml
p='roster/index.yaml'; d=yaml.safe_load(open(p)); r=d['nexus']['versions']['releases']['test']={'commit':'12'*20,'tree':'34'*20,'archive_sha256':'56'*32,'draft':True}
f=os.environ['FIELD']; v=os.environ['INVALID']; n=64 if f=='archive_sha256' else 40
if v!='missing': r[f]={'short':'abc','nonhex':'g'*n,'zero':'0'*n,'null':None,'number':123}[v]
else: del r[f]
open(p,'w').write(yaml.safe_dump(d))
PY
      run gate --publish nexus@test
      [ "$status" -ne 0 ]
      [[ "$output" == *"nexus@test"*"$field"* ]]
    done
  done
}

@test "V4-03 T02: incomplete drafts are authored history but explicit publication never skips them" {
  python3 - <<'PY'
import yaml
p='roster/index.yaml'; d=yaml.safe_load(open(p)); d['nexus']['versions']['releases']['draft']={'draft':True}; open(p,'w').write(yaml.safe_dump(d))
PY
  run gate
  [ "$status" -eq 0 ]
  run gate --publish nexus@draft
  [ "$status" -ne 0 ]
  run gate --publish nexus@absent
  [ "$status" -ne 0 ]
  python3 - <<'PY'
import yaml
p='roster/index.yaml'; d=yaml.safe_load(open(p)); d['nexus']['versions']['releases']['draft'].update(commit='12'*20,tree='34'*20,archive_sha256='56'*32); open(p,'w').write(yaml.safe_dump(d))
PY
  run gate --publish nexus@draft
  [ "$status" -eq 0 ]
}

@test "V4-03 T02: advertised latest and stable release pointers cannot advertise incomplete drafts" {
  for pointer in latest stable; do
    POINTER="$pointer" python3 - <<'PY'
import os,yaml
p='roster/index.yaml'; d=yaml.safe_load(open(p)); v=d['eidolons'][0]['versions']; v['releases']['draft']={'draft':True}
if os.environ['POINTER']=='latest': v['latest']='draft'
else: v['pins']['stable']='draft'
open(p,'w').write(yaml.safe_dump(d))
PY
    run gate
    [ "$status" -ne 0 ]
    [[ "$output" == *'atlas@draft'* ]]
  done
}

@test "V4-03 T03: make schema uses shared gate and rejects equal-valued duplicate registry" {
  # Run the real Makefile against an isolated checkout copy; no repository writes.
  cp "$EIDOLONS_ROOT/Makefile" .
  cp -R "$EIDOLONS_ROOT/cli" "$EIDOLONS_ROOT/scripts" .
  run make schema
  [ "$status" -eq 0 ]
  printf '\nregistry_version: "1.1"\n' >> roster/index.yaml
  run make schema
  [ "$status" -ne 0 ]
  [[ "$output" == *duplicate* ]]
}

@test "V4-03 T01 T02: raw intake JSON is checked before jq can discard duplicates" {
  printf '{"commit":"%s","tree":"%s","archive_sha256":"%s"}\n' "$(printf '12%.0s' {1..20})" "$(printf '34%.0s' {1..20})" "$(printf '56%.0s' {1..32})" > release.json
  run gate --release-record release.json
  [ "$status" -eq 0 ]
  python3 - <<'PY'
p='release.json'; s=open(p).read(); open(p,'w').write(s.replace('{','{"commit":"'+'12'*20+'",',1))
PY
  run gate --release-record release.json
  [ "$status" -ne 0 ]
  [[ "$output" == *duplicate* ]]
}

@test "V4-03 T03: actual PR health and release workflow shared commands reject the same invalid registry" {
  [ "$(uname -s)" = Linux ] || skip "Workflow shell bodies target Ubuntu; shared make gate is tested on both OSes"
  cp "$EIDOLONS_ROOT/Makefile" .
  cp -R "$EIDOLONS_ROOT/cli" "$EIDOLONS_ROOT/scripts" .
  # Extract the actual workflow run text, not a copied approximation. Only the
  # read-only shared gate steps are executed; no workflow or release dispatch.
  python3 - <<'PY'
import os,yaml,pathlib
root=pathlib.Path(os.environ['EIDOLONS_ROOT'])
for file,job in [('ci.yml','lint'),('roster-health.yml','validate-roster'),('release-nexus.yml','release'),('roster-intake.yml','intake')]:
    workflow=yaml.safe_load((root/'.github/workflows'/file).read_text())
    steps=[s for j in workflow['jobs'].values() for s in j.get('steps',[]) if s.get('name')=='Validate authored registries and publication records']
    assert len(steps)==1, file
    pathlib.Path(file+'.sh').write_text(steps[0]['run'])
PY
  for command in *.yml.sh; do
    run bash "$command"
    [ "$status" -eq 0 ]
  done
  printf '\nregistry_version: "1.1"\n' >> roster/index.yaml
  for command in *.yml.sh; do
    run bash "$command"
    [ "$status" -ne 0 ]
    [[ "$output" == *duplicate* ]]
  done
}

@test "V4-03 T03: release candidate gate precedes tag push and rejects invalid generated evidence" {
  [ "$(uname -s)" = Linux ] || skip "Release workflow shell body targets Ubuntu"
  cp "$EIDOLONS_ROOT/Makefile" .
  cp -R "$EIDOLONS_ROOT/cli" "$EIDOLONS_ROOT/scripts" .
  python3 - <<'PY'
import os,yaml,pathlib
root=pathlib.Path(os.environ['EIDOLONS_ROOT'])
steps=yaml.safe_load((root/'.github/workflows/release-nexus.yml').read_text())['jobs']['release']['steps']
get=lambda name: next(i for i,s in enumerate(steps) if s.get('name')==name)
a=get('Update roster/index.yaml with release metadata')
assert get('Build canonical archive') < a < get('Create tag') < get('Create GitHub Release')
command=steps[a]['run']
for key,value in [('ver.outputs.version','99.0.0'),('shas.outputs.commit','12'*20),('shas.outputs.tree','34'*20),('archive.outputs.archive_sha256','56'*32)]:
    command=command.replace('${{ steps.'+key+' }}',value)
pathlib.Path('candidate.sh').write_text(command)
pathlib.Path('invalid.sh').write_text(command.replace('12'*20,'0'*40))
PY
  run bash candidate.sh
  [ "$status" -eq 0 ]
  run bash invalid.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *'nexus@99.0.0'*commit* ]]
}

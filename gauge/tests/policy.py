#!/usr/bin/env python3
"""External V4-07 oracle. Baseline failure is an executable missing command,
not a claim that V4-06 violated its own supported behavior."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(os.environ.get('GAUGE_REPO', Path(__file__).resolve().parents[2]))

def build(source, target):
    subprocess.run(['go', 'build', '-mod=readonly', '-trimpath', '-o', str(target), './cmd/eidolons-gauge'], cwd=source / 'gauge', check=True)

def call(binary, project, command, *args, ok=True):
    p = subprocess.run([str(binary), command, '--project', str(project), *args], text=True, capture_output=True)
    if ok and p.returncode != 0:
        raise AssertionError(f'{command}: exit={p.returncode}, stdout={p.stdout}, stderr={p.stderr}')
    if not ok and p.returncode == 0:
        raise AssertionError(f'{command}: unexpectedly succeeded: {p.stdout}')
    return p

with tempfile.TemporaryDirectory(prefix='gauge07 espaço 日本 ') as tmp:
    tmp = Path(tmp)
    binary = Path(os.environ.get('GAUGE_POLICY_BIN', tmp / 'gauge'))
    if 'GAUGE_POLICY_BIN' not in os.environ:
        build(REPO, binary)
    project = tmp / 'project with spaces'
    project.mkdir()
    config = tmp / 'prefs.json'
    config.write_text('{"schema_version":1,"preset":"Conserve"}')
    # Positive predecessor control precedes the red unsupported-feature check.
    call(binary, project, 'init', '--root', 'root')
    call(binary, project, 'fixture', '--root', 'root', '--event-id', 'before', '--outcome', 'pass')
    call(binary, project, 'preferences-set', '--layer', 'user', '--expected-revision', '0', '--input', str(config))
    before = call(binary, project, 'preferences').stdout
    for content in ['{"schema_version":1,"preset":"Balanced","preset":"Conserve"}', '{"schema_version":1,"restrictions":[{"denied":[],"denied":["write"]}]}', '{"schema_version":1,"preset":"turbo"}', '{"schema_version":1,"source":"operator"}', '{"schema_version":1,"restrictions":[{"ceilings":[{"resource":"tokens","unit":"token","pool":"pool","interval":"run","scope":"task","limit":-1}]}]}']:
        config.write_text(content)
        call(binary, project, 'preferences-set', '--layer', 'user', '--expected-revision', '1', '--input', str(config), ok=False)
        assert call(binary, project, 'preferences').stdout == before
    for command in ['policy-bind', 'policy-amend']:
        refused = call(binary, project, command, '--root', 'root', '--authorization-id', 'forged-operator', ok=False)
        assert 'authorizer_boundary_unqualified' in refused.stderr, refused.stderr
    # Real predecessor binary creates history, replay state, claims and manifest.
    predecessor = Path('/predecessor')
    assert predecessor.is_dir(), 'qualified predecessor mount is required'
    old = tmp / 'old-gauge'
    build(predecessor, old)
    historical = tmp / 'historical project'
    historical.mkdir()
    call(old, historical, 'init', '--root', 'historic')
    call(old, historical, 'fixture', '--root', 'historic', '--event-id', 'receipt', '--outcome', 'pass')
    status = json.loads(call(old, historical, 'status', '--root', 'historic').stdout)
    claims = {p: p.read_bytes() for p in (historical / '.eidolons' / '.ledger').rglob('*.json')}
    refused = call(binary, historical, 'status', '--root', 'historic', ok=False)
    assert 'migration_required' in refused.stderr
    call(binary, historical, 'migrate')
    assert json.loads(call(binary, historical, 'status', '--root', 'historic').stdout) == status
    assert all(p.read_bytes() == data for p, data in claims.items()), 'migration changed ownership proofs'
    call(old, historical, 'status', '--root', 'historic', ok=False)
    call(old, historical, 'fixture', '--root', 'historic', '--event-id', 'unsafe-old-write', '--outcome', 'pass', ok=False)
    retry = json.loads(call(binary, historical, 'fixture', '--root', 'historic', '--event-id', 'receipt', '--outcome', 'pass').stdout)
    assert retry['id'] == 'receipt'
    assert len(json.loads(call(binary, historical, 'status', '--root', 'historic').stdout)['history']) == len(status['history'])
print('V4-07 external CLI and genuine predecessor migration: passed')

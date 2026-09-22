#!/usr/bin/env python3
"""Render a scoped Codex runtime repair to stdout; never write the input file.

Python 3.11+ tomllib validates both the original and candidate. Unknown fields
and other servers must remain semantically identical; text outside the selected
managed server table is copied unchanged. Missing/unowned markers fail closed.
"""
import copy
import datetime
import json
import math
import re
import sys
from pathlib import Path
try:
    import tomllib
except ImportError:
    sys.exit('Codex wiring comparison requires Python 3.11+ (tomllib); no settings changed')


def value(item):
    if isinstance(item, str):
        return json.dumps(item, ensure_ascii=False)
    if isinstance(item, bool):
        return str(item).lower()
    if isinstance(item, (datetime.datetime, datetime.date, datetime.time)):
        return item.isoformat()
    if isinstance(item, (float, int)):
        return str(item).lower()
    if isinstance(item, list):
        return '[' + ', '.join(value(v) for v in item) + ']'
    if isinstance(item, dict):
        return '{' + ', '.join(json.dumps(k) + ' = ' + value(v) for k, v in item.items()) + '}'
    raise ValueError('unsupported TOML field type; preserving input')


def same(left, right):
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(same(left[k], right[k]) for k in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(same(a, b) for a, b in zip(left, right))
    return left == right or (isinstance(left, float) and isinstance(right, float) and math.isnan(left) and math.isnan(right))


def render(path, name, expected):
    original = path.read_text() if path.exists() else ''
    parsed = tomllib.loads(original)
    desired = copy.deepcopy(parsed)
    servers = desired.setdefault('mcp_servers', {})
    previous = servers.get(name, {})
    updated = copy.deepcopy(previous)
    updated['command'] = expected['command']
    updated['args'] = expected['args']
    if expected.get('env'):
        updated['env'] = {**updated.get('env', {}), **expected['env']}
    servers[name] = updated
    if same(parsed, desired):
        return original
    lines = original.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.strip() == '# eidolon:mcp start']
    ends = [i for i, line in enumerate(lines) if line.strip() == '# eidolon:mcp end']
    if not starts and not ends and name not in parsed.get('mcp_servers', {}):
        lines += ['\n# eidolon:mcp start\n', '# eidolon:mcp end\n']
        starts, ends = [len(lines)-2], [len(lines)-1]
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        raise ValueError('missing or ambiguous managed markers; preserving user settings')
    start, end = starts[0], ends[0]
    headers = []
    # Header locations only guide the splice. Full TOML reparse + whole-document
    # semantic comparison below is the authority, including multiline strings.
    for i, line in enumerate(lines):
        match = re.match(r'^\s*\[([^\[\]]+)\]\s*(?:#.*)?$', line.rstrip())
        if match:
            try:
                header = tomllib.loads('[' + match[1] + ']')
                keys = []
                while isinstance(header, dict) and len(header) == 1:
                    key, header = next(iter(header.items()))
                    keys.append(key)
                headers.append((i, keys))
            except tomllib.TOMLDecodeError:
                pass
    spans = []
    for j, (i, keys) in enumerate(headers):
        if keys[:2] == ['mcp_servers', name]:
            stop = headers[j+1][0] if j+1 < len(headers) else len(lines)
            stop = min(stop, end)
            if not start < i < end:
                raise ValueError('server table is user-owned (outside managed markers); preserving it')
            spans.append((i, stop))
    if previous and not spans:
        raise ValueError('cannot locate owned server table; preserving user settings')
    table = '[' + 'mcp_servers.' + json.dumps(name) + ']\n'
    table += ''.join(json.dumps(k) + ' = ' + value(v) + '\n' for k, v in updated.items())
    candidate_lines = lines[:]
    if spans:
        for i, stop in reversed(spans):
            candidate_lines[i:stop] = [table] if i == spans[0][0] else []
    else:
        candidate_lines[end:end] = [table]
    candidate = ''.join(candidate_lines)
    if not same(tomllib.loads(candidate), desired):
        raise ValueError('scoped repair would alter other settings; preserving input')
    return candidate


try:
    print(render(Path(sys.argv[1]), sys.argv[2], json.load(sys.stdin)), end='')
except (ValueError, KeyError, TypeError, OSError) as error:
    # Never print field values: configuration may contain credentials.
    sys.exit('Codex wiring: cannot safely reconcile managed server table (' + type(error).__name__ + '); no settings changed')

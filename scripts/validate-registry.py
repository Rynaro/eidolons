#!/usr/bin/env python3
"""Duplicate-aware authored registry and selected publication validation.

Historical releases remain authored data. Advertised latest/stable releases of
shipped Eidolons and the nexus, and every explicit --publish name@version, are
publication evidence. A draft flag never bypasses a selected publication check.
Requires Python 3 + PyYAML; no dependency is added to the installed CLI.
"""
import argparse
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("registry: PyYAML is required; install python3-yaml or python3 -m pip install PyYAML")


class Invalid(ValueError):
    pass


class UniqueLoader(yaml.SafeLoader):
    def get_single_data(self):
        node = self.get_single_node()
        if node is None:
            return None
        visited = set()

        def check(raw):
            if id(raw) in visited:
                return
            visited.add(id(raw))
            if isinstance(raw, yaml.MappingNode):
                seen = set()
                for key, value in raw.value:
                    if not isinstance(key, yaml.ScalarNode):
                        raise Invalid(f"non-scalar mapping key at line {key.start_mark.line + 1}")
                    resolved = key.value if key.tag == 'tag:yaml.org,2002:merge' else self.construct_object(key, deep=True)
                    if resolved in seen:
                        raise Invalid(f"duplicate mapping key at line {key.start_mark.line + 1}")
                    seen.add(resolved)
                    check(value)
            elif isinstance(raw, yaml.SequenceNode):
                for value in raw.value:
                    check(value)

        # Traverse the composed graph before *any* flatten_mapping call. Inline
        # merge sources otherwise disappear before construct_mapping sees them.
        check(node)
        return self.construct_document(node)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Invalid("duplicate JSON mapping key")
        result[key] = value
    return result


def read(path):
    try:
        with path.open() as stream:
            if path.suffix == '.json':
                return json.load(stream, object_pairs_hook=unique_pairs)
            return yaml.load(stream, Loader=UniqueLoader)
    except (ValueError, yaml.YAMLError, OSError) as error:
        raise Invalid(f"{path}: {error}") from None


def release(row, name, version, schema):
    label = f"{name}@{version}"
    record = row.get('versions', {}).get('releases', {}).get(version)
    if not isinstance(record, dict):
        raise Invalid(f"{label}: publication record is missing")
    for field in schema['required']:
        pattern = schema['properties'][field]['pattern']
        value = record.get(field)
        if not isinstance(value, str) or not re.fullmatch(pattern, value):
            raise Invalid(f"{label}: publication {field} must be a non-placeholder complete lowercase hex digest")


def validate(root, publish, release_records):
    # Only authored registries and schema definitions, never arbitrary fixture
    # trees or frozen lifecycle archives. Check originals before any conversion.
    documents = {}
    for directory, patterns in [('roster', ('*.yaml', '*.yml', '*.json')), ('schemas', ('*.json',))]:
        for pattern in patterns:
            for path in sorted((root / directory).glob(pattern)):
                documents[path] = read(path)
    schema = documents[root / 'schemas/roster.schema.json']['$defs']['publishableRelease']
    for path in release_records:
        record = read(path)
        release({'versions': {'releases': {'candidate': record}}}, str(path), 'candidate', schema)
    index_path = root / 'roster/index.yaml'
    index = documents.get(index_path)
    if not isinstance(index, dict) or not isinstance(index.get('eidolons'), list) or not isinstance(index.get('nexus'), dict):
        raise Invalid(f"{index_path}: expected eidolons array and nexus mapping")
    if not isinstance(index.get('registry_version'), str):
        raise Invalid(f"{index_path}: registry_version must be a string")
    rows = {'nexus': index['nexus']}
    for row in index['eidolons']:
        if not isinstance(row, dict) or not isinstance(row.get('name'), str):
            raise Invalid(f"{index_path}: invalid Eidolon entry")
        name = row['name']
        if name in rows:
            raise Invalid(f"{index_path}: duplicate Eidolon name {name}")
        rows[name] = row
        # Preserve the previous CI's required-field gate at the shared boundary.
        for parent, fields in [('methodology', ('name', 'version', 'cycle')), ('source', ('repo',)), ('versions', ('latest',)), ('handoffs', ('upstream', 'downstream'))]:
            section = row.get(parent)
            if not isinstance(section, dict) or any(section.get(f) is None for f in fields):
                raise Invalid(f"{name}: missing required {parent} fields")
    for name, row in rows.items():
        if name != 'nexus' and row.get('status') != 'shipped':
            continue
        versions = row.get('versions', {})
        selected = [versions.get('latest')]
        stable = versions.get('pins', {}).get('stable')
        if stable is not None:
            selected.append(stable)
        for version in selected:
            if not isinstance(version, str) or not version:
                raise Invalid(f"{name}: publication version pointer is missing")
            release(row, name, version, schema)
    for selector in publish:
        name, separator, version = selector.partition('@')
        if not separator or not version or name not in rows:
            raise Invalid(f"{selector}: expected known name@version publication selector")
        release(rows[name], name, version, schema)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--publish', action='append', default=[], metavar='NAME@VERSION')
    parser.add_argument('--release-record', type=Path, action='append', default=[], metavar='PATH', help='validate a raw release manifest before any JSON conversion')
    args = parser.parse_args()
    try:
        validate(args.root, args.publish, args.release_record)
    except (Invalid, TypeError, AttributeError, KeyError) as error:
        print(f"registry: {error}", file=sys.stderr)
        return 1
    print('registry: authored keys and selected publication records valid', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())

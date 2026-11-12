#!/usr/bin/env python3
"""Keep app, Tauri and Cargo release versions consistent."""
import argparse
import json
import os
from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')

def read_versions(root=ROOT):
    package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
    tauri = json.loads((root / 'src-tauri/tauri.conf.json').read_text(encoding='utf-8'))
    cargo = tomllib.loads((root / 'src-tauri/Cargo.toml').read_text(encoding='utf-8'))
    lock = tomllib.loads((root / 'src-tauri/Cargo.lock').read_text(encoding='utf-8'))
    entries = [entry for entry in lock['package'] if entry['name'] == cargo['package']['name']]
    if len(entries) != 1:
        raise ValueError('Cargo.lock must contain exactly one app package')
    values = [package['version'], tauri['version'], cargo['package']['version'], entries[0]['version']]
    if len(set(values)) != 1 or not PATTERN.fullmatch(values[0]):
        raise ValueError(f'Release versions disagree or are invalid: {values}')
    return values[0], cargo['package']['name']

def set_version(version, root=ROOT):
    if not PATTERN.fullmatch(version):
        raise ValueError('Use MAJOR.MINOR.PATCH, for example 0.2.1')
    old, name = read_versions(root)
    changes = {}
    for relative in ['package.json', 'src-tauri/tauri.conf.json']:
        path = root / relative
        data = json.loads(path.read_text(encoding='utf-8'))
        data['version'] = version
        changes[path] = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    path = root / 'src-tauri/Cargo.toml'
    text = path.read_text(encoding='utf-8')
    changes[path], count = re.subn(r'(?ms)(^\[package\]\s*.*?^version\s*=\s*)"' + re.escape(old) + '"', lambda match: match[1] + json.dumps(version), text, count=1)
    if count != 1:
        raise ValueError('App Cargo version was not found')
    path = root / 'src-tauri/Cargo.lock'
    text = path.read_text(encoding='utf-8')
    pattern = r'(?m)(^name = "' + re.escape(name) + r'"\r?\nversion = )"' + re.escape(old) + '"'
    changes[path], count = re.subn(pattern, lambda match: match[1] + json.dumps(version), text, count=1)
    if count != 1:
        raise ValueError('App Cargo.lock version was not found')
    for path, text in changes.items():
        path.write_bytes(text.encode('utf-8'))
    return read_versions(root)[0]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'set'])
    parser.add_argument('version', nargs='?')
    args = parser.parse_args()
    version = set_version(args.version) if args.command == 'set' and args.version else read_versions()[0]
    if args.command == 'set' and not args.version:
        parser.error('set requires a version')
    if os.environ.get('GITHUB_REF', '').startswith('refs/tags/') and os.environ.get('GITHUB_REF_NAME') != 'v' + version:
        raise ValueError('Git tag must match the version in all four files')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as stream:
            stream.write(f'version={version}\ntag=v{version}\n')
    print(version)

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Inventory first-party source/doc URLs and placeholder markers without visiting sites."""
import json
import re
import subprocess
from urllib.parse import urlencode
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXCLUDED = {'.git', 'node_modules', 'dist', 'target', 'vendor', 'releases'}
TEXT = {'.ts', '.tsx', '.rs', '.py', '.sh', '.ps1', '.json', '.yaml', '.yml', '.html', '.md', '.nsh', '.toml', '.m', '.c', '.desktop'}
URL = re.compile(r'''https?://[^\s<>"'`\)\]\}]+''')
MARKER = re.compile(r'\bplaceholders?\b|example\.(?:com|org|invalid)|https?://[^\s]*\.test[/:]|\bTODO\b|\bFIXME\b|203\.0\.113\.|198\.51\.100\.|2001:db8|HOME_HOST=|HOME_PORT=|HOME_USER=|HOME_PASS=', re.I)

def main():
    files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    records, markers, scanned = [], [], []
    for name in sorted(set(filter(None, files))):
        path = Path(name)
        if EXCLUDED.intersection(path.parts) or path.suffix not in TEXT or name.endswith('audit-links.py') or name in {'docs/link-inventory.json', 'docs/customization-audit.md'}:
            continue
        source = ROOT / path
        if not source.is_file():
            continue
        scanned.append(name)
        text = source.read_text(encoding='utf-8-sig', errors='replace')
        for number, line in enumerate(text.splitlines(), 1):
            for match in URL.finditer(line):
                url = match.group().rstrip('.,;')
                records.append({'file': name, 'line': number, 'url': url})
            if MARKER.search(line):
                markers.append({'file': name, 'line': number, 'text': line.strip()[:350]})
    providers = json.loads((ROOT / 'assets/resources.json').read_text(encoding='utf-8'))
    provider_urls = {name: value['url'] for name, value in providers.items()}
    result = {'scope': 'First-party tracked and untracked text source/config/docs, excluding vendor, lockfiles, generated artifacts and binary/SVG assets. Includes test fixtures; these are not automatically production links.', 'verification': 'Static inventory only; no remote page availability or ownership verification.', 'scanned_files': scanned, 'url_occurrences': records, 'placeholder_occurrences': markers, 'compiled_provider_urls': provider_urls}
    output = ROOT / 'docs/link-inventory.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'scanned_files': len(scanned), 'url_occurrences': len(records), 'unique_url_literals': len({item['url'] for item in records}), 'placeholder_lines': len(markers), 'output': str(output)}, ensure_ascii=False))

if __name__ == '__main__':
    main()

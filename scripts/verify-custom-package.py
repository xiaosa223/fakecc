#!/usr/bin/env python3
"""Verify build staging and copy the completed installer; never install on this host."""
import hashlib
import json
import shutil
import struct
from pathlib import Path
from versioning import read_versions

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'src-tauri/target/release'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def pe_machine(path):
    with path.open('rb') as stream:
        assert stream.read(2) == b'MZ', f'Not PE: {path}'
        stream.seek(0x3c)
        offset = struct.unpack('<I', stream.read(4))[0]
        stream.seek(offset)
        assert stream.read(4) == b'PE\0\0', f'Invalid PE: {path}'
        return hex(struct.unpack('<H', stream.read(2))[0])

def verify_tree(source, staged):
    originals = {path.relative_to(source).as_posix(): path for path in source.rglob('*') if path.is_file()}
    copies = {path.relative_to(staged).as_posix(): path for path in staged.rglob('*') if path.is_file()}
    assert originals and originals.keys() == copies.keys(), f'Incomplete resource tree: {source}'
    for name, path in originals.items():
        assert digest(path) == digest(copies[name]), f'Resource mismatch: {name}'
    return len(originals)

def main():
    config = json.loads((ROOT / 'src-tauri/tauri.windows.conf.json').read_text(encoding='utf-8'))
    assert config['plugins']['updater']['endpoints'] == []
    assert 'build:custom' in config['build']['beforeBuildCommand']
    engine_count = verify_tree(ROOT / 'browser-runtime/WindowsBrowser', BUILD / 'browser-runtime/WindowsBrowser')
    ui_count = verify_tree(ROOT / 'dist', BUILD / 'browser-ui')
    for source, target in [('LICENSE', 'licenses/LICENSE.CCBaga.txt'), ('NOTICE.md', 'licenses/NOTICE.md'), ('browser-runtime/icons/browser.ico', 'browser-runtime/icons/browser.ico')]:
        assert digest(ROOT / source) == digest(BUILD / target), target
    terminal_files = 0
    for source, target in config['bundle']['resources'].items():
        if target.startswith('terminal-setup/'):
            assert digest(ROOT / 'src-tauri' / source) == digest(BUILD / target), target
            terminal_files += 1
    assert terminal_files == 8
    assert pe_machine(BUILD / 'requirement-french.exe') == '0x8664'
    assert pe_machine(BUILD / 'browser-runtime/WindowsBrowser/chrome.exe') == '0x8664'
    generated = (BUILD / 'nsis/x64/installer.nsi').read_text(encoding='utf-8-sig')
    for expected in ['!define ARCH "x64"', '!define INSTALLMODE "currentUser"', 'LICENSE.CCBaga.txt', 'NOTICE.md', 'browser.ico', 'chrome.exe']:
        assert expected in generated, f'NSIS script missing: {expected}'
    version = read_versions(ROOT)[0]
    installer = BUILD / f'bundle/nsis/CCBaga-A_{version}_x64-setup.exe'
    installer_machine = pe_machine(installer)  # NSIS may use an x86 bootstrapper for an x64 payload.
    installer_hash = digest(installer)
    delivery = ROOT / 'releases' / version / 'fakecc.exe'
    delivery.parent.mkdir(parents=True, exist_ok=True)
    if delivery.exists():
        assert digest(delivery) == installer_hash, 'Refusing to replace a different existing installer'
    else:
        shutil.copy2(installer, delivery)
    assert digest(delivery) == installer_hash
    sums = {path.name: digest(path) for path in delivery.parent.glob('*.exe')}
    (delivery.parent / 'SHA256SUMS').write_text(''.join(f'{value}  {name}\n' for name, value in sorted(sums.items())), encoding='utf-8')
    report = {'status': 'passed', 'installer': delivery.name, 'version': version, 'bytes': delivery.stat().st_size, 'sha256': installer_hash, 'installer_bootstrapper_machine': installer_machine, 'application_and_browser_machine': '0x8664', 'staged_engine_files_verified_by_sha256': engine_count, 'staged_ui_files_verified_by_sha256': ui_count, 'staged_terminal_files_verified_by_sha256': terminal_files, 'license_and_browser_icon_resources_match': True, 'upstream_updates_disabled': True, 'verification_scope': 'Source to NSIS build-staging hashes and generated NSIS script; installer PE/copy hash. Installer was not unpacked, executed, installed or uninstalled on this host.'}
    (delivery.parent / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()

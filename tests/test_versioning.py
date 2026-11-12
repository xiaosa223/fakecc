import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('versioning', ROOT / 'scripts/versioning.py')
versioning = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versioning)

class VersioningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / 'src-tauri').mkdir()
        fixtures = {
            'package.json': '{"name":"test","version":"0.2.0"}',
            'src-tauri/tauri.conf.json': '{"version":"0.2.0"}',
            'src-tauri/Cargo.toml': '[package]\nname = "test"\nversion = "0.2.0"\n\n[dependencies]\nother = "0.2.0"\n',
            'src-tauri/Cargo.lock': 'version = 4\n\n[[package]]\nname = "other"\nversion = "0.2.0"\n\n[[package]]\nname = "test"\nversion = "0.2.0"\n',
        }
        for name, text in fixtures.items():
            (self.root / name).write_text(text, encoding='utf-8')
    def tearDown(self):
        self.temporary.cleanup()
    def test_updates_every_release_file_without_changing_dependency_versions(self):
        self.assertEqual(versioning.set_version('0.2.1', self.root), '0.2.1')
        self.assertEqual(versioning.read_versions(self.root)[0], '0.2.1')
        self.assertIn('other = "0.2.0"', (self.root / 'src-tauri/Cargo.toml').read_text())
        self.assertIn('name = "other"\nversion = "0.2.0"', (self.root / 'src-tauri/Cargo.lock').read_text())
    def test_rejects_invalid_input_without_touching_files(self):
        for value in ['v0.2.1', '0.2', '01.2.3', '1.2.3;whoami', '../1.2.3']:
            with self.assertRaises(ValueError):
                versioning.set_version(value, self.root)
        self.assertEqual(versioning.read_versions(self.root)[0], '0.2.0')

if __name__ == '__main__':
    unittest.main()

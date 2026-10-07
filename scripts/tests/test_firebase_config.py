"""Synthetic configuration fixtures; never installed in the application."""
import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('firebase_config', Path(__file__).parents[1] / 'configure-firebase.py')
config = importlib.util.module_from_spec(spec); spec.loader.exec_module(config)
class FirebaseConfigurationTests(unittest.TestCase):
    def fixture(self):
        return {'PROJECT_ID': config.PROJECT, 'BUNDLE_ID': config.BUNDLE, 'GOOGLE_APP_ID': config.APP,
                'CLIENT_ID': 'test-fixture.apps.googleusercontent.com',
                'REVERSED_CLIENT_ID': 'com.googleusercontent.apps.test-fixture', 'API_KEY': 'test-fixture-only'}
    def test_foreign_project_bundle_or_app_rejected(self):
        for field in ['PROJECT_ID', 'BUNDLE_ID', 'GOOGLE_APP_ID']:
            value = self.fixture(); value[field] = 'foreign'
            with self.assertRaises(ValueError): config.validate(value)
    def test_google_missing_and_mismatched_scheme_rejected(self):
        for field in ['CLIENT_ID', 'REVERSED_CLIENT_ID', 'API_KEY']:
            value = self.fixture(); value.pop(field)
            with self.assertRaises(ValueError): config.validate(value)
    def test_install_preserves_deep_links_is_idempotent_and_saves_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); app = root / 'ios/Athar'; app.mkdir(parents=True)
            info = app / 'Info.plist'; original = plistlib.dumps({'CFBundleURLTypes': [{'CFBundleURLSchemes': ['nooralruh']}]})
            info.write_bytes(original)
            source = root / 'fixture.plist'; source.write_bytes(plistlib.dumps(self.fixture()))
            config.install(source, root); config.install(source, root)
            result = plistlib.loads(info.read_bytes())
            self.assertEqual(len(result['CFBundleURLTypes']), 2)
            self.assertEqual(result['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['nooralruh'])
            self.assertEqual(info.with_suffix('.plist.before-firebase').read_bytes(), original)
            self.assertEqual((app / 'GoogleService-Info.plist').read_bytes(), source.read_bytes())
if __name__ == '__main__': unittest.main()

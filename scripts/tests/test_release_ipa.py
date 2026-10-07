"""Distribution regressions using synthetic payloads, never signing evidence."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from account_privacy import configure as configure_privacy

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-release-ipa.py'
spec = importlib.util.spec_from_file_location('release_ipa', SCRIPT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class ReleasePayloadTests(unittest.TestCase):
    def payload(self, folder, omit=None, stale_build=False, wrong_project=False, local_policy=False, local_manifest=False):
        path = Path(folder) / 'test.ipa'
        config = {'PROJECT_ID': 'wrong' if wrong_project else 'noor-alruh',
                  'BUNDLE_ID': gate.BUNDLE,
                  'GOOGLE_APP_ID': '1:149675464789:ios:32a19ae8e5a62439561cdc',
                  'API_KEY': 'synthetic-not-a-real-key'}
        root = 'Payload/Athar.app/'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(root + 'Info.plist', plistlib.dumps({
                'CFBundleIdentifier': gate.BUNDLE, 'CFBundleShortVersionString': '1.0',
                'CFBundleVersion': '14', 'CFBundleURLTypes': [{'CFBundleURLSchemes': ['nooralruh']}]}))
            if omit != 'firebase':
                archive.writestr(root + 'GoogleService-Info.plist', plistlib.dumps(config))
            archive.writestr(root + 'embedded.mobileprovision', b'synthetic-profile')
            if omit != 'privacy':
                archive.writestr(root + 'PrivacyInfo.xcprivacy', plistlib.dumps(configure_privacy({}, not local_manifest)))
            archive.writestr(root + 'app-legal.json', __import__('json').dumps({
                'accountMode': 'local-only' if local_policy else 'firebase-opt-in',
                'contact': {'supportEmail': 'noralrohsupport@gmail.com'}}))
            for identifier, point in gate.EXTENSIONS.items():
                if omit == identifier:
                    continue
                ext = root + 'PlugIns/' + identifier.rsplit('.', 1)[1] + '.appex/'
                archive.writestr(ext + 'Info.plist', plistlib.dumps({
                    'CFBundleIdentifier': identifier, 'CFBundleShortVersionString': '1.0',
                    'CFBundleVersion': '13' if stale_build else '14',
                    'NSExtension': {'NSExtensionPointIdentifier': point}}))
                archive.writestr(ext + 'embedded.mobileprovision', b'synthetic-profile')
        return path

    def test_complete_payload_reports_without_claiming_device_acceptance(self):
        with tempfile.TemporaryDirectory() as folder:
            result = gate.verify(self.payload(folder))
            self.assertEqual(len(result['extensions']), 4)
            self.assertFalse(result['deviceTested'])

    def test_each_missing_extension_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for identifier in gate.EXTENSIONS:
                with self.subTest(identifier=identifier), self.assertRaisesRegex(ValueError, 'Missing required extensions'):
                    gate.verify(self.payload(folder, omit=identifier))

    def test_local_only_or_wrong_firebase_project_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(KeyError):
                gate.verify(self.payload(folder, omit='firebase'))
            with self.assertRaisesRegex(ValueError, 'PROJECT_ID'):
                gate.verify(self.payload(folder, wrong_project=True))

    def test_stale_extension_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'version/build differs'):
                gate.verify(self.payload(folder, stale_build=True))

    def test_account_build_with_stale_local_privacy_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'privacy policy still describes local-only'):
                gate.verify(self.payload(folder, local_policy=True))

    def test_missing_or_local_only_privacy_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(KeyError):
                gate.verify(self.payload(folder, omit='privacy'))
            with self.assertRaisesRegex(ValueError, 'Account privacy manifest'):
                gate.verify(self.payload(folder, local_manifest=True))

if __name__ == '__main__':
    unittest.main()

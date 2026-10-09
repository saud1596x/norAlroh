"""Distribution regressions using synthetic payloads, never signing evidence."""
import importlib.util
import hashlib
import json
import shutil
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from account_privacy import configure as configure_privacy

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-release-ipa.py'
spec = importlib.util.spec_from_file_location('release_ipa', SCRIPT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class ReleasePayloadTests(unittest.TestCase):
    def setUp(self):
        self.resources = tempfile.TemporaryDirectory()
        self.addCleanup(self.resources.cleanup)
        root = Path(self.resources.name)
        for directory in ['scripts', 'content-sources', 'docs']:
            (root / directory).mkdir()
        shutil.copyfile(gate.ROOT / 'scripts/configure-firebase.py', root / 'scripts/configure-firebase.py')
        self.model_files = {'model/AudioEncoder.mlmodelc/weights/weight.bin': b'synthetic-model',
                            'tokenizer/tokenizer.json': b'synthetic-tokenizer'}
        (root / 'content-sources/recitation-model-manifest.json').write_text(json.dumps({
            'schema': 1, 'files': [{'path': name, 'bytes': len(data),
                                   'sha256': hashlib.sha256(data).hexdigest()}
                                  for name, data in self.model_files.items()]}))
        (root / 'content-sources/recitation-word-script.json').write_bytes(b'synthetic-word-script')
        for name in ['WHISPER-MODEL-LICENSE.txt', 'TARTEEL-MODEL-LICENSE.txt', 'RECITATION-MODEL-NOTICE.txt']:
            (root / 'docs' / name).write_bytes(name.encode())
        self.root_patch = patch.object(gate, 'ROOT', root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def payload(self, folder, omit=None, stale_build=False, wrong_project=False, local_policy=False, local_manifest=False, missing_name=None, corrupt=None):
        path = Path(folder) / 'test.ipa'
        config = {'PROJECT_ID': 'wrong' if wrong_project else 'noor-alruh',
                  'BUNDLE_ID': gate.BUNDLE,
                  'GOOGLE_APP_ID': '1:149675464789:ios:32a19ae8e5a62439561cdc',
                  'API_KEY': 'synthetic-not-a-real-key'}
        root = 'Payload/Athar.app/'
        with zipfile.ZipFile(path, 'w') as archive:
            resources = {'RecitationModel/' + name: data for name, data in self.model_files.items()}
            resources.update({'RecitationModel/Whisper-LICENSE.txt': b'WHISPER-MODEL-LICENSE.txt',
                              'RecitationModel/Tarteel-LICENSE.txt': b'TARTEEL-MODEL-LICENSE.txt',
                              'RecitationModel/NOTICE.txt': b'RECITATION-MODEL-NOTICE.txt',
                              'recitation-word-script.json': b'synthetic-word-script'})
            for name, data in resources.items():
                if name != omit:
                    archive.writestr(root + name, b'x' * len(data) if name == corrupt else data)
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
                    **({} if missing_name == identifier else {'CFBundleDisplayName': 'نور الروح'}),
                    'NSExtension': {'NSExtensionPointIdentifier': point}}))
                archive.writestr(ext + 'embedded.mobileprovision', b'synthetic-profile')
        return path

    def test_complete_payload_reports_without_claiming_device_acceptance(self):
        with tempfile.TemporaryDirectory() as folder:
            result = gate.verify(self.payload(folder))
            self.assertEqual(len(result['extensions']), 4)
            self.assertFalse(result['deviceTested'])
            self.assertEqual(result['recognitionResourcesVerified'], len(self.model_files))

    def test_missing_model_or_tokenizer_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in self.model_files:
                with self.subTest(name=name), self.assertRaises(KeyError):
                    gate.verify(self.payload(folder, omit='RecitationModel/' + name))

    def test_same_size_corrupted_model_or_tokenizer_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in self.model_files:
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Incorrect bundled recognition resource'):
                    gate.verify(self.payload(folder, corrupt='RecitationModel/' + name))

    def test_model_notices_and_word_script_must_match(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ['RecitationModel/Whisper-LICENSE.txt', 'RecitationModel/Tarteel-LICENSE.txt',
                         'RecitationModel/NOTICE.txt', 'recitation-word-script.json']:
                with self.subTest(name=name), self.assertRaises(KeyError):
                    gate.verify(self.payload(folder, omit=name))
                with self.subTest(name=name), self.assertRaises(ValueError):
                    gate.verify(self.payload(folder, corrupt=name))

    def test_each_extension_requires_a_nonempty_display_name(self):
        with tempfile.TemporaryDirectory() as folder:
            for identifier in gate.EXTENSIONS:
                with self.subTest(identifier=identifier), self.assertRaisesRegex(ValueError, 'Missing extension display name'):
                    gate.verify(self.payload(folder, missing_name=identifier))

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

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
        (root / 'ios/Athar').mkdir(parents=True)
        self.quran_files = {'quran.json': b'synthetic-pinned-quran',
                            'reciter-word-timings.json': b'synthetic-pinned-timings',
                            'Reciter-Timings-LICENSE.txt': b'synthetic-timing-license',
                            'surah-ayah-timings.json': b'synthetic-pinned-ayah-timings',
                            'surah-ayah-timing-coverage.json': b'synthetic-pinned-coverage',
                            'Reciter-Ayah-Timings-SOURCE.txt': b'synthetic-timing-source',
                            'mushaf-snapshot.json': b'synthetic-pinned-mushaf-edition',
                            'quran-basmalas.json': b'synthetic-pinned-basmalas',
                            'haramain-reciters.json': json.dumps({'schema': 1, 'reciters': [
                                {'id': 54, 'surahs': list(range(1, 115))}]}).encode()}
        for name, data in self.quran_files.items():
            (root / 'ios/Athar' / name).write_bytes(data)
        (root / 'ios/Athar/mic-start.wav').write_bytes(b'synthetic-UI-feedback-not-recitation')
        for directory in ['scripts', 'content-sources', 'docs']:
            (root / directory).mkdir()
        (root / 'release').mkdir()
        self.tajweed_files = {}
        tajweed = []
        for page in range(1, 605):
            font = f't4-p{page}.ttf'; data = f'synthetic-font-{page}'.encode(); layers = b'synthetic-layer'
            self.tajweed_files[font] = data
            self.tajweed_files[f't4-p{page}.json'] = layers
            tajweed.append({'page': page, 'file': font, 'bytes': len(data),
                            'sha256': hashlib.sha256(data).hexdigest(), 'layersSha256': hashlib.sha256(layers).hexdigest()})
        self.tajweed_files['qcf-v4-manifest.json'] = json.dumps({'fonts': tajweed}).encode()
        (root / 'release/qcf-v4-manifest.json').write_bytes(self.tajweed_files['qcf-v4-manifest.json'])
        snapshot = self.quran_files['mushaf-snapshot.json']
        (root / 'content-sources/mushaf-snapshot-manifest.json').write_text(json.dumps({
            'bytes': len(snapshot), 'sha256': hashlib.sha256(snapshot).hexdigest()}))
        shutil.copyfile(gate.ROOT / 'scripts/configure-firebase.py', root / 'scripts/configure-firebase.py')
        self.model_files = {'model/AudioEncoder.mlmodelc/weights/weight.bin': b'synthetic-model',
                            'tokenizer/tokenizer.json': b'synthetic-tokenizer'}
        (root / 'content-sources/recitation-model-manifest.json').write_text(json.dumps({
            'schema': 1, 'model': 'synthetic-test-model', 'revision': 'test-revision', 'files': [{'path': name, 'bytes': len(data),
                                   'sha256': hashlib.sha256(data).hexdigest()}
                                  for name, data in self.model_files.items()]}))
        (root / 'content-sources/recitation-word-script.json').write_bytes(b'synthetic-word-script')
        vocabulary=(gate.ROOT/'content-sources/independent-ctc-vocab.json').read_bytes()
        notice=(gate.ROOT/'docs/QURAN-CTC-MODEL-NOTICE.txt').read_bytes()
        (root/'content-sources/independent-ctc-vocab.json').write_bytes(vocabulary)
        (root/'docs/QURAN-CTC-MODEL-NOTICE.txt').write_bytes(notice)
        self.independent_files={'quran-ctc.mlmodelc/compiled.bin':b'synthetic-compiled-resource-not-a-model',
            'vocab.json':vocabulary,'NOTICE.txt':notice}
        self.independent_descriptor={'schema':1,'revision':gate._ctc_source.REVISION,'precision':'float32',
            'sourceWeightsSHA256':'202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf',
            'sourceSpecSHA256':gate._ctc_source.PINS['Data/com.apple.CoreML/model.mlmodel'],
            'convertedWeightsSHA256':gate._ctc_source.PINS['Data/com.apple.CoreML/weights/weight.bin'],
            'files':{n:hashlib.sha256(b).hexdigest() for n,b in self.independent_files.items()}}
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
            resources.update(self.quran_files)
            resources.update(self.tajweed_files)
            resources.update({'IndependentCTC/'+name:data for name,data in self.independent_files.items()})
            resources['IndependentCTC/verified-model.json']=json.dumps(self.independent_descriptor).encode()
            resources['mic-start.wav'] = b'synthetic-UI-feedback-not-recitation'
            resources['RecitationModel/verified-model.json'] = json.dumps({
                'schema': 1, 'model': 'synthetic-test-model', 'revision': 'test-revision',
                'configuration': 'ar;wordTimestamps=true;temperatureFallbackCount=0;concurrentWorkerCount=1'
            }).encode()
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

    def test_independent_payload_rejects_missing_files_corruption_and_unreviewed_source(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in self.independent_files:
                with self.subTest(name=name),self.assertRaises((KeyError,ValueError)):
                    gate.verify(self.payload(folder,omit='IndependentCTC/'+name))
                with self.subTest(name=name),self.assertRaises(ValueError):
                    gate.verify(self.payload(folder,corrupt='IndependentCTC/'+name))
            self.independent_descriptor['sourceSpecSHA256']='a'*64
            with self.assertRaisesRegex(ValueError,'source descriptor'):
                gate.verify(self.payload(folder))

    def test_missing_or_corrupted_original_tajweed_font_or_layers_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ['t4-p1.ttf', 't4-p604.json', 'qcf-v4-manifest.json']:
                with self.subTest(name=name), self.assertRaises(KeyError):
                    gate.verify(self.payload(folder, omit=name))
                with self.subTest(name=name), self.assertRaises(ValueError):
                    gate.verify(self.payload(folder, corrupt=name))

    def test_same_size_corrupted_model_or_tokenizer_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in self.model_files:
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Incorrect bundled recognition resource'):
                    gate.verify(self.payload(folder, corrupt='RecitationModel/' + name))

    def test_model_notices_and_word_script_must_match(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ['RecitationModel/Whisper-LICENSE.txt', 'RecitationModel/Tarteel-LICENSE.txt',
                         'RecitationModel/NOTICE.txt', 'RecitationModel/verified-model.json', 'recitation-word-script.json']:
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

    def test_missing_or_corrupted_quran_resources_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in self.quran_files:
                with self.subTest(resource=name):
                    with self.assertRaises(KeyError):
                        gate.verify(self.payload(folder, omit=name))
                    with self.assertRaisesRegex(ValueError, 'Incorrect bundled Quran or reciter resource'):
                        gate.verify(self.payload(folder, corrupt=name))

    def test_missing_or_corrupted_microphone_feedback_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(KeyError):
                gate.verify(self.payload(folder, omit='mic-start.wav'))
            with self.assertRaisesRegex(ValueError, 'Incorrect bundled microphone UI feedback'):
                gate.verify(self.payload(folder, corrupt='mic-start.wav'))

    def test_identical_but_incomplete_reciter_catalog_is_rejected(self):
        name = 'haramain-reciters.json'
        data = json.dumps({'schema': 1, 'reciters': [{'id': 54, 'surahs': list(range(1, 114))}]}).encode()
        self.quran_files[name] = data
        (gate.ROOT / 'ios/Athar' / name).write_bytes(data)
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'incomplete Quran'):
                gate.verify(self.payload(folder))

    def test_missing_or_local_only_privacy_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(KeyError):
                gate.verify(self.payload(folder, omit='privacy'))
            with self.assertRaisesRegex(ValueError, 'Account privacy manifest'):
                gate.verify(self.payload(folder, local_manifest=True))

if __name__ == '__main__':
    unittest.main()

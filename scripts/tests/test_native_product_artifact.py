"""Synthetic transport fixtures; these tests do not claim a native build."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'native-product-artifact.py'
spec = importlib.util.spec_from_file_location('native_product', SCRIPT)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
COMMIT, RUN_ID = 'c' * 40, '42'
ENV = {'developerDirectory': '/Applications/Xcode_26.3.app/Contents/Developer',
       'xcode': 'Xcode 26.3\nBuild version SYNTHETIC', 'sdkVersion': '26.3',
       'sdkBuildVersion': 'SYNTHETIC', 'sdkPath': '/Applications/Xcode_26.3.app/SDK',
       'architecture': 'arm64'}


def create_fixture(base):
    products, producer = base / 'Products', base / 'producer'
    app = products / 'Release-iphonesimulator/Athar.app'
    for bundle in (app, app / 'PlugIns/NoorWidgets.appex',
                   app / 'PlugIns/AtharTests.xctest',
                   products / 'Release-iphonesimulator/AtharUITests-Runner.app',
                   products / 'Release-iphonesimulator/AtharUITests-Runner.app/PlugIns/AtharUITests.xctest'):
        bundle.mkdir(parents=True)
        # .exe allows Windows stat to represent execute bits for transport tests.
        executable = bundle / (bundle.stem + '.exe')
        executable.write_bytes(b'SYNTHETIC NOT A MACH-O EXECUTABLE')
        executable.chmod(0o755)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': executable.name}))
    for name in ('qcf-v2-manifest.json', 'qcf-v4-manifest.json', 'recitation-word-script.json'):
        (app / name).write_text('SYNTHETIC RESOURCE\n')
    for name in ('RecitationModel', 'IndependentCTC'):
        (app / name).mkdir()
        (app / name / 'fixture.bin').write_bytes(b'SYNTHETIC MODEL RESOURCE - NOT LOADED')
    (products / 'Athar_iphonesimulator26.3-arm64.xctestrun').write_bytes(plistlib.dumps({
        'TestConfigurations': [{'TestTargets': [
            {'BlueprintName': 'AtharTests', 'TestBundlePath': '__TESTROOT__/Release-iphonesimulator/Athar.app/PlugIns/AtharTests.xctest',
             'TestHostPath': '__TESTROOT__/Release-iphonesimulator/Athar.app/Athar.exe'},
            {'BlueprintName': 'AtharUITests', 'TestBundlePath': '__TESTROOT__/Release-iphonesimulator/AtharUITests-Runner.app/PlugIns/AtharUITests.xctest',
             'UITargetAppPath': '__TESTROOT__/Release-iphonesimulator/Athar.app'}]}]}))
    producer.mkdir()
    native.write(producer / 'commands.json', {'build': {'exitCode': 0, 'deadlineSeconds': 1200, 'log': 'build.txt'}})
    (producer / 'build.txt').write_text(''.join('NOOR_NATIVE_PROCESS ' + json.dumps({
        'stage': 'BUILD', 'event': event, 'deadlineSeconds': 1200, 'exitCode': 0}) + '\n'
        for event in ('start', 'end')))
    (producer / 'project-generation.txt').write_text('SYNTHETIC PROJECT GENERATION\n')
    return products, producer


class NativeProductArtifactTests(unittest.TestCase):
    def setUp(self):
        base = SCRIPT.parents[1] / 'release/native-product-tests'
        base.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='fixture-', dir=base)
        self.base = Path(self.temp.name)
        self.products, self.producer = create_fixture(self.base)
        self.artifact, self.destination = self.base / 'artifact', self.base / 'extracted'
        self.environment = patch.object(native, 'environment', return_value=copy.deepcopy(ENV))
        self.binary = patch.object(native, 'binary_architecture')
        self.environment.start()
        self.binary.start()
        self.addCleanup(self.environment.stop)
        self.addCleanup(self.binary.stop)
        self.addCleanup(self.temp.cleanup)

    def pack(self):
        return native.pack(self.products, self.producer, self.artifact, COMMIT, RUN_ID)

    def unpack(self, **overrides):
        args = dict(artifact=self.artifact, destination=self.destination, commit=COMMIT, run_id=RUN_ID,
                    manifest_hash=native.digest(self.artifact / 'manifest.json'),
                    archive_hash=native.digest(self.artifact / 'native-products.tar.gz'))
        args.update(overrides)
        return native.unpack(**args)

    def rewrite_archive(self, change):
        archive = self.artifact / 'native-products.tar.gz'
        with tarfile.open(archive, 'r:gz') as tar:
            rows = [(row, tar.extractfile(row).read() if row.isfile() else None) for row in tar.getmembers()]
        rows = change(rows)
        with tarfile.open(archive, 'w:gz') as tar:
            for row, data in rows:
                tar.addfile(row, io.BytesIO(data) if data is not None else None)
        manifest = json.loads((self.artifact / 'manifest.json').read_text())
        manifest['archiveSHA256'] = native.digest(archive)
        native.write(self.artifact / 'manifest.json', manifest)

    def test_complete_tree_and_xctestrun_and_original_log_survive_unchanged(self):
        expected = self.pack()
        actual = self.unpack()
        self.assertEqual(actual, expected)
        self.assertEqual(native.inventory(self.destination), expected['files'])
        self.assertEqual((self.destination / 'producer/build.txt').read_bytes(), (self.producer / 'build.txt').read_bytes())
        self.assertIn('Build/Products/Release-iphonesimulator/Athar.app/IndependentCTC/fixture.bin', expected['files'])

    def test_archive_byte_tamper_rejected_before_extraction(self):
        manifest = self.pack()
        with (self.artifact / 'native-products.tar.gz').open('ab') as stream:
            stream.write(b'TAMPER')
        with self.assertRaisesRegex(ValueError, 'archive hash mismatch'):
            self.unpack(archive_hash=manifest['archiveSHA256'])
        self.assertFalse(self.destination.exists())

    def test_manifest_tamper_rejected_before_extraction(self):
        self.pack()
        trusted_hash = native.digest(self.artifact / 'manifest.json')
        with (self.artifact / 'manifest.json').open('a') as stream:
            stream.write(' ')
        with self.assertRaisesRegex(ValueError, 'manifest hash mismatch'):
            self.unpack(manifest_hash=trusted_hash)
        self.assertFalse(self.destination.exists())

    def test_different_source_and_run_rejected(self):
        self.pack()
        for args in ({'commit': 'd' * 40}, {'run_id': '43'}):
            with self.subTest(args=args), self.assertRaisesRegex(ValueError, 'Cross-source/run'):
                self.unpack(**args)
        self.assertFalse(self.destination.exists())

    def test_different_xcode_sdk_sdk_build_path_and_architecture_rejected(self):
        self.pack()
        for key in ENV:
            changed = {**ENV, key: 'DIFFERENT'}
            with self.subTest(key=key), patch.object(native, 'environment', return_value=changed):
                with self.assertRaisesRegex(ValueError, 'Xcode/SDK/architecture mismatch'):
                    self.unpack()
        self.assertFalse(self.destination.exists())

    def test_missing_app_extension_test_bundle_or_resources_cannot_be_packaged(self):
        import shutil
        for name in ('PlugIns/NoorWidgets.appex', 'PlugIns/AtharTests.xctest', 'RecitationModel',
                     'IndependentCTC', 'qcf-v2-manifest.json', 'qcf-v4-manifest.json', 'recitation-word-script.json'):
            with self.subTest(name=name), tempfile.TemporaryDirectory(dir=self.base) as temp:
                base = Path(temp)
                products, producer = create_fixture(base)
                path = products / 'Release-iphonesimulator/Athar.app' / name
                shutil.rmtree(path) if path.is_dir() else path.unlink()
                with self.assertRaises((ValueError, FileNotFoundError)):
                    native.pack(products, producer, base / 'artifact', COMMIT, RUN_ID)

    def test_generated_xctestrun_cannot_reference_original_runner_absolute_path(self):
        run = next(self.products.glob('*.xctestrun'))
        value = plistlib.loads(run.read_bytes())
        value['TestConfigurations'][0]['TestTargets'][0]['TestHostPath'] = '/Users/runner/old/Athar.app/Athar'
        run.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ValueError, 'Nonrelocatable'):
            self.pack()

    def test_generated_testhost_placeholder_remains_unmodified_and_resolves_inside_app(self):
        run = next(self.products.glob('*.xctestrun'))
        value = plistlib.loads(run.read_bytes())
        value['TestConfigurations'][0]['TestTargets'][0]['TestBundlePath'] = '__TESTHOST__/PlugIns/AtharTests.xctest'
        run.write_bytes(plistlib.dumps(value))
        original = run.read_bytes()
        manifest = self.pack()
        self.unpack()
        self.assertEqual((self.destination / manifest['xctestrun']).read_bytes(), original)

    def test_generated_xctestrun_cannot_escape_or_reference_missing_product(self):
        run = next(self.products.glob('*.xctestrun'))
        original = plistlib.loads(run.read_bytes())
        for target in ('__TESTROOT__/../../../escape', '__TESTROOT__/missing.app'):
            value = copy.deepcopy(original)
            value['TestConfigurations'][0]['TestTargets'][0]['TestHostPath'] = target
            run.write_bytes(plistlib.dumps(value))
            with self.assertRaisesRegex(ValueError, 'Missing/escaping'):
                self.pack()
            # pack stages by rename; return products to fixture for next attempt.
            import shutil
            shutil.move(str(self.artifact / 'payload/Build/Products'), str(self.products))
            shutil.rmtree(self.artifact)

    def test_requires_one_generated_xctestrun(self):
        next(self.products.glob('*.xctestrun')).unlink()
        with self.assertRaisesRegex(ValueError, 'Exactly one'):
            self.pack()

    def test_missing_or_failed_original_build_is_rejected(self):
        (self.producer / 'build.txt').write_text('BUILD SUCCEEDED - NOT A REAL BOUNDED RECEIPT')
        with self.assertRaisesRegex(ValueError, 'Build log'):
            self.pack()

    def test_cannot_extract_over_existing_destination(self):
        self.pack()
        self.destination.mkdir()
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            self.unpack()

    def test_tampered_file_with_rehashed_archive_still_fails_file_hash(self):
        self.pack()
        def change(rows):
            for index, (row, data) in enumerate(rows):
                if row.name.endswith('fixture.bin'):
                    rows[index] = (row, b'X' * len(data))
                    break
            return rows
        self.rewrite_archive(change)
        with self.assertRaisesRegex(ValueError, 'file hash mismatch'):
            self.unpack()
        self.assertFalse(self.destination.exists())

    def test_duplicate_tar_member_rejected(self):
        self.pack()
        self.rewrite_archive(lambda rows: rows + [rows[-1]])
        with self.assertRaisesRegex(ValueError, 'Duplicate or missing'):
            self.unpack()
        self.assertFalse(self.destination.exists())

    def test_path_traversal_absolute_backslash_and_special_files_rejected(self):
        self.pack()
        original = (self.artifact / 'native-products.tar.gz').read_bytes()
        for name, kind in (('../escape', tarfile.REGTYPE), ('/tmp/escape', tarfile.REGTYPE),
                           ('Build\\escape', tarfile.REGTYPE), ('Build/Products/evil', tarfile.FIFOTYPE),
                           ('Build/Products/evil', tarfile.LNKTYPE)):
            with self.subTest(name=name, kind=kind):
                (self.artifact / 'native-products.tar.gz').write_bytes(original)
                def change(rows):
                    row, data = rows[-1]
                    row.name, row.type = name, kind
                    return rows[:-1] + [(row, data if kind == tarfile.REGTYPE else None)]
                self.rewrite_archive(change)
                with self.assertRaises(ValueError):
                    self.unpack()
                self.assertFalse(self.destination.exists())

    def test_symlink_lexical_safety_rejects_absolute_and_escape(self):
        for target in ('/tmp/evil', '../../../../escape', 'C:\\evil', '..\\evil'):
            with self.subTest(target=target), self.assertRaises(ValueError):
                native.safe_link('Build/Products/App.app/link', target)
        native.safe_link('Build/Products/Framework.framework/Versions/Current', 'A')

    @unittest.skipIf(os.name == 'nt', 'Creating real symlinks on Windows requires a separate OS privilege')
    def test_framework_style_symlinks_and_execute_modes_survive_transport(self):
        framework = self.products / 'Release-iphonesimulator/Fixture.framework'
        (framework / 'Versions/A').mkdir(parents=True)
        binary = framework / 'Versions/A/Fixture'
        binary.write_bytes(b'SYNTHETIC FRAMEWORK')
        binary.chmod(0o755)
        (framework / 'Versions/Current').symlink_to('A', target_is_directory=True)
        (framework / 'Fixture').symlink_to('Versions/Current/Fixture')
        expected = self.pack()
        self.unpack()
        actual = self.destination / 'Build/Products/Release-iphonesimulator/Fixture.framework'
        self.assertTrue((actual / 'Fixture').is_symlink())
        self.assertEqual(os.readlink(actual / 'Versions/Current'), 'A')
        self.assertEqual(native.inventory(self.destination), expected['files'])

    def test_unsafe_symlink_and_descendant_under_symlink_are_rejected_before_extraction(self):
        self.pack()
        original = (self.artifact / 'native-products.tar.gz').read_bytes()
        original_manifest = (self.artifact / 'manifest.json').read_bytes()
        for target, nested in (('/tmp/escape', False), ('../../../../escape', False),
                               ('Release-iphonesimulator', True)):
            with self.subTest(target=target, nested=nested):
                (self.artifact / 'native-products.tar.gz').write_bytes(original)
                (self.artifact / 'manifest.json').write_bytes(original_manifest)
                name = 'Build/Products/link'
                def change(rows):
                    link = tarfile.TarInfo(name)
                    link.type, link.linkname, link.mode = tarfile.SYMTYPE, target, 0o777
                    rows.append((link, None))
                    if nested:
                        child = tarfile.TarInfo(name + '/evil')
                        child.mode, child.size = 0o644, 1
                        rows.append((child, b'X'))
                    return rows
                self.rewrite_archive(change)
                manifest = json.loads((self.artifact / 'manifest.json').read_text())
                manifest['files'][name] = {'kind': 'symlink', 'target': target, 'mode': 0o777}
                if nested:
                    import hashlib
                    manifest['files'][name + '/evil'] = {'kind': 'file', 'mode': 0o644,
                        'size': 1, 'sha256': hashlib.sha256(b'X').hexdigest()}
                native.write(self.artifact / 'manifest.json', manifest)
                with self.assertRaisesRegex(ValueError, 'symlink|Symlink'):
                    self.unpack()
                self.assertFalse(self.destination.exists())

    def test_missing_bundle_executable_cannot_be_packaged(self):
        next(self.products.rglob('Athar.exe')).unlink()
        with self.assertRaisesRegex(ValueError, 'Missing/escaping|Missing executable'):
            self.pack()

    def test_successful_command_receipt_cannot_replace_failed_original_log(self):
        text = (self.producer / 'build.txt').read_text()
        (self.producer / 'build.txt').write_text(text.replace('"exitCode": 0', '"exitCode": 65'))
        with self.assertRaisesRegex(ValueError, 'Build log'):
            self.pack()

    @unittest.skipIf(os.name == 'nt', 'Windows cannot represent removed executable permission on .exe fixtures')
    def test_executable_mode_is_required(self):
        next(self.products.rglob('Athar.exe')).chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'execute mode'):
            self.pack()

    def test_lipo_must_confirm_exact_arm64(self):
        # Exercise the real architecture validator, mocked only at subprocess boundary.
        self.binary.stop()
        with patch.object(native.subprocess, 'check_output', return_value='x86_64 arm64\n'):
            with self.assertRaisesRegex(ValueError, 'architecture'):
                native.binary_architecture(Path('synthetic.exe'), 'arm64')
        with patch.object(native.subprocess, 'check_output', return_value='arm64\n'):
            native.binary_architecture(Path('synthetic.exe'), 'arm64')


if __name__ == '__main__':
    unittest.main()

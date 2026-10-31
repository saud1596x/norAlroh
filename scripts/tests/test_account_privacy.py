"""Release generation must keep the policy and manifest on the same mode."""
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from account_privacy import ACCOUNT_DATA_TYPES, configure

class AccountPrivacyTests(unittest.TestCase):
    def test_actual_timer_and_cache_space_reasons_survive_both_modes(self):
        manifest = plistlib.loads((ROOT / 'ios/Athar/PrivacyInfo.xcprivacy').read_bytes())
        for accounts in [False, True]:
            with self.subTest(accounts=accounts):
                reasons = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons']
                           for entry in configure(manifest, accounts)['NSPrivacyAccessedAPITypes']}
                self.assertIn('35F9.1', reasons.get('NSPrivacyAccessedAPICategorySystemBootTime', []))
                self.assertIn('E174.1', reasons.get('NSPrivacyAccessedAPICategoryDiskSpace', []))
                self.assertIn('CA92.1', reasons['NSPrivacyAccessedAPICategoryUserDefaults'])
                self.assertIn('1C8F.1', reasons['NSPrivacyAccessedAPICategoryUserDefaults'])
                self.assertIn('C617.1', reasons['NSPrivacyAccessedAPICategoryFileTimestamp'])

    def test_group_defaults_consumer_has_one_monitor_only_manifest_resource(self):
        """Static XcodeGen membership preflight, not built-bundle evidence."""
        def target_sources(spec, target):
            text = (ROOT / 'ios' / spec).read_text(encoding='utf-8')
            block = re.search(r'(?ms)^  ' + re.escape(target) + r':\n(.*?)(?=^  \w|\Z)', text).group(1)
            sources = re.search(r'(?ms)^    sources:\n(.*?)(?=^    \w|\Z)', block).group(1)
            return [(ROOT / 'ios' / match[0], match[1]) for match in re.findall(
                r'(?m)^      - path: ([^\n]+)\n((?:        [^\n]*\n)*)', sources)]

        def files(rows, suffix):
            result = []
            for path, options in rows:
                result.extend(path.rglob('*' + suffix) if path.is_dir() else [path] if path.suffix == suffix else [])
            return result

        monitor = target_sources('project-focus.yml', 'NoorFocusMonitor')
        source = '\n'.join(path.read_text(encoding='utf-8') for path in files(monitor, '.swift'))
        self.assertRegex(source, r'UserDefaults\(suiteName:')
        manifests = files(monitor, '.xcprivacy')
        self.assertEqual(len(manifests), 1, 'Group-defaults monitor needs exactly one manifest resource')
        monitor_path = manifests[0]
        self.assertTrue(any(path == monitor_path and 'buildPhase: resources' in options for path, options in monitor))
        manifest = plistlib.loads(monitor_path.read_bytes())
        self.assertEqual(manifest['NSPrivacyAccessedAPITypes'], [{
            'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
            'NSPrivacyAccessedAPITypeReasons': ['1C8F.1']}])
        self.assertFalse(manifest['NSPrivacyTracking'])
        self.assertEqual(manifest['NSPrivacyCollectedDataTypes'], [])
        self.assertEqual(manifest['NSPrivacyTrackingDomains'], [])
        # Putting another PrivacyInfo under recursively shared source directories
        # would introduce duplicate app resources or unsupported extension claims.
        app = target_sources('project.yml', 'Athar')
        self.assertEqual(files(app, '.xcprivacy'), [ROOT / 'ios/Athar/PrivacyInfo.xcprivacy'])
        for target in ['NoorFocusShield', 'NoorFocusAction']:
            self.assertNotIn(monitor_path, files(target_sources('project-focus.yml', target), '.xcprivacy'))
        self.assertNotIn(monitor_path, files(target_sources('project.yml', 'NoorWidgets'), '.xcprivacy'))

    def test_generation_check_and_local_rollback_preserve_api_reasons(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            for name in ['scripts/prepare-publishing.py', 'scripts/account_privacy.py',
                         'release/config.json', 'release/legal-content.json',
                         'release/legal-content-accounts.json', 'ios/Athar/PrivacyInfo.xcprivacy']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, target)
            manifest = root / 'ios/Athar/PrivacyInfo.xcprivacy'
            original = plistlib.loads(manifest.read_bytes())
            script = root / 'scripts/prepare-publishing.py'
            def run(*args):
                return subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)
            self.assertNotEqual(run('--accounts', '--check').returncode, 0)
            self.assertEqual(run('--accounts').returncode, 0)
            account = plistlib.loads(manifest.read_bytes())
            self.assertEqual(account['NSPrivacyAccessedAPITypes'], original['NSPrivacyAccessedAPITypes'])
            self.assertEqual({x['NSPrivacyCollectedDataType'] for x in account['NSPrivacyCollectedDataTypes']}, set(ACCOUNT_DATA_TYPES))
            self.assertEqual(run('--accounts', '--check').returncode, 0)
            self.assertNotEqual(run('--check').returncode, 0)
            self.assertEqual(run().returncode, 0)
            self.assertEqual(plistlib.loads(manifest.read_bytes()), original)
            self.assertEqual(run('--check').returncode, 0)

if __name__ == '__main__':
    unittest.main()

"""Release generation must keep the policy and manifest on the same mode."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from account_privacy import ACCOUNT_DATA_TYPES

class AccountPrivacyTests(unittest.TestCase):
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

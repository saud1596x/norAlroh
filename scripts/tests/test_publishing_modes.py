import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PublishingPolicyModeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['scripts/prepare-publishing.py', 'scripts/account_privacy.py',
                     'release/config.json', 'release/legal-content.json',
                     'release/legal-content-accounts.json', 'ios/Athar/PrivacyInfo.xcprivacy']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def run_generator(self, *args):
        env = dict(os.environ, PYTHONIOENCODING='utf-8', PYTHONUTF8='0')
        return subprocess.run([sys.executable, str(self.root/'scripts/prepare-publishing.py'), *args],
                              capture_output=True, text=True, encoding='utf-8', env=env)

    def test_local_app_and_optional_account_website_are_generated_and_checked_independently(self):
        generated = self.run_generator()
        self.assertEqual(generated.returncode, 0, generated.stderr)
        app = json.loads((self.root/'ios/Athar/app-legal.json').read_text(encoding='utf-8'))
        self.assertEqual(app['accountMode'], 'local-only')
        self.assertEqual(app['appName'], 'نور الروح')
        report = json.loads((self.root/'release/publishing-content-report.json').read_text(encoding='utf-8'))
        for name, expected_hash in report['files'].items():
            self.assertEqual(hashlib.sha256((self.root/name).read_bytes()).hexdigest(), expected_hash)
        for page in ['privacy', 'terms', 'support', 'index']:
            self.assertEqual((self.root/f'support-site/{page}.html').read_text(encoding='utf-8'),
                             (ROOT/f'support-site/{page}.html').read_text(encoding='utf-8'))
        self.assertEqual(self.run_generator('--check').returncode, 0)

    def test_signed_account_app_can_use_existing_account_website_without_weakening_policy(self):
        generated = self.run_generator('--accounts')
        self.assertEqual(generated.returncode, 0, generated.stderr)
        app = json.loads((self.root/'ios/Athar/app-legal.json').read_text(encoding='utf-8'))
        self.assertEqual(app['accountMode'], 'firebase-opt-in')
        self.assertEqual((self.root/'support-site/privacy.html').read_text(encoding='utf-8'),
                         (ROOT/'support-site/privacy.html').read_text(encoding='utf-8'))
        self.assertEqual(self.run_generator('--accounts', '--check').returncode, 0)
        self.assertNotEqual(self.run_generator('--check').returncode, 0)

    def test_unknown_public_policy_mode_cannot_silently_remove_account_disclosures(self):
        config_file = self.root/'release/config.json'
        config = json.loads(config_file.read_text(encoding='utf-8'))
        config['publicWebsiteAccountMode'] = 'unknown'
        config_file.write_text(json.dumps(config, ensure_ascii=False), encoding='utf-8')
        self.assertNotEqual(self.run_generator().returncode, 0)
        self.assertFalse((self.root/'support-site/privacy.html').exists())

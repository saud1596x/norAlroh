"""Keep every full helper-suite entry point explicit about its PNG dependency."""
import contextlib
import importlib.metadata
import io
from pathlib import Path
import re
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class HelperDependencyTests(unittest.TestCase):
    def test_shared_dependency_is_pinned_once(self):
        pins = [line.strip() for line in (ROOT / 'scripts/tests/requirements.txt').read_text(encoding='utf-8').splitlines()
                if line.strip() and not line.lstrip().startswith('#')]
        self.assertEqual(pins, ['Pillow==11.3.0'])

    def test_every_full_helper_ci_suite_installs_the_shared_manifest_first(self):
        whole_suite = re.compile(r'-m unittest discover -s scripts/tests(?:\s|$)')
        checked = []
        for path in sorted((ROOT / '.github/workflows').glob('*.yml')):
            source = path.read_text(encoding='utf-8')
            for line in source.splitlines():
                if whole_suite.search(line) and ' -p ' not in line:
                    self.assertIn('-r scripts/tests/requirements.txt', source, str(path))
                    self.assertLess(source.index('-r scripts/tests/requirements.txt'), source.index(line.strip()), str(path))
                    checked.append(path.name)
        self.assertIn('ios-checks.yml', checked)
        self.assertIn('recitation-backend.yml', checked)

    def test_closure_uses_the_same_png_dependency_manifest(self):
        source = (ROOT / '.github/workflows/mushaf-closure.yml').read_text(encoding='utf-8')
        self.assertIn('-r scripts/tests/requirements.txt', source)
        self.assertNotIn("'Pillow==11.3.0'", source)

    def prerequisite(self):
        source = (ROOT / 'scripts/test-noor-linux.sh').read_text(encoding='utf-8')
        match = re.search(r"python3 - <<'PY'\n(.*?)\nPY", source, re.S)
        self.assertIsNotNone(match)
        return match[1]

    def test_server_check_rejects_missing_package_without_installation(self):
        with patch.object(importlib.metadata, 'version', side_effect=importlib.metadata.PackageNotFoundError('Pillow')):
            with self.assertRaisesRegex(SystemExit, 'Missing prerequisite: Pillow==11.3.0'):
                exec(self.prerequisite(), {})

    def test_server_check_rejects_wrong_version_without_installation(self):
        with patch.object(importlib.metadata, 'version', return_value='0.0.0'):
            with self.assertRaisesRegex(SystemExit, 'requires 11.3.0, found 0.0.0'):
                exec(self.prerequisite(), {})

    def test_server_check_accepts_preprovisioned_dependency_without_installation(self):
        source = self.prerequisite()
        self.assertNotIn('subprocess', source)
        self.assertNotIn('pip install', source)
        output = io.StringIO()
        with patch.object(importlib.metadata, 'version', return_value='11.3.0'), contextlib.redirect_stdout(output):
            exec(source, {})
        self.assertIn('no packages installed', output.getvalue())


if __name__ == '__main__':
    unittest.main()

"""Runtime-check control regressions; no framework or acoustic model executes."""
import json
from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

PROBE = Path(__file__).resolve().parents[1]
ROOT = PROBE.parents[1]
sys.path.insert(0, str(PROBE))
import verify_runtime


class RuntimeContractTests(unittest.TestCase):
    def test_versions_reject_numpy2_arrow26_and_missing_packages(self):
        pins = {'numpy': '1.26.4', 'pyarrow': '18.1.0'}
        for actual in [{'numpy': '2.0.0', 'pyarrow': '18.1.0'},
                       {'numpy': '1.26.4', 'pyarrow': '26.0.0'},
                       {'numpy': '1.26.4', 'pyarrow': None}]:
            with self.assertRaises(RuntimeError):
                verify_runtime.verify_versions(pins, actual)

    def test_only_official_cpu_local_suffix_is_accepted(self):
        verify_runtime.verify_versions({'torch': '2.7.0'}, {'torch': '2.7.0+cpu'})
        for name, actual in [('torch', '2.7.0+cu128'), ('numpy', '1.26.4+modified')]:
            with self.assertRaises(RuntimeError):
                verify_runtime.verify_versions({name: '2.7.0' if name == 'torch' else '1.26.4'}, {name: actual})

    def test_runtime_import_error_is_nonzero_with_failed_receipt(self):
        directory = ROOT / 'release/fastconformer-source-probe-tests'
        directory.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='runtime-control-', dir=directory) as temporary:
            output = Path(temporary) / 'runtime-check.json'
            stderr, stdout = io.StringIO(), io.StringIO()
            with patch.object(verify_runtime, 'read_pins', return_value={'numpy': '1.26.4'}), \
                 patch.object(verify_runtime.metadata, 'version', return_value='1.26.4'), \
                 patch.object(verify_runtime, 'run_checks', side_effect=ImportError('INTENTIONAL ABI CONTROL FAILURE')), \
                 redirect_stderr(stderr), redirect_stdout(stdout):
                self.assertEqual(verify_runtime.main(['--output', str(output)]), 1)
            report = json.loads(output.read_text(encoding='utf-8'))
            self.assertFalse(report['runtimeImportsVerified'])
            self.assertFalse(report['inferenceExecuted'])
            self.assertFalse(report['productionApproved'])
            self.assertEqual(report['error']['type'], 'ImportError')
            self.assertIn('INTENTIONAL ABI CONTROL FAILURE', stderr.getvalue())
            self.assertIn('SOURCE_PROBE_RUNTIME_IMPORTS_FAILED', stdout.getvalue())

    def test_workflow_requires_runtime_receipt_before_real_probe(self):
        workflow = (ROOT / '.github/workflows/fastconformer-source-probe.yml').read_text(encoding='utf-8')
        self.assertIn('-r tools/streaming_recitation_probe/requirements-runtime-linux.txt', workflow)
        self.assertIn('python -m pip check', workflow)
        self.assertIn('python tools/streaming_recitation_probe/verify_runtime.py', workflow)
        self.assertLess(workflow.index('verify_runtime.py'), workflow.index('run_probe.py'))


if __name__ == '__main__':
    unittest.main()

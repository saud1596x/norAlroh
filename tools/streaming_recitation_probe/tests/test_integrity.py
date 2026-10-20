"""Synthetic evidence tests. These never execute or approve an ASR model."""
import copy
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

PROBE = Path(__file__).resolve().parents[1]
ROOT = PROBE.parents[1]
sys.path.insert(0, str(PROBE))
from probe_contract import (ARCHIVE_SHA, COMPLETE, CONFIG_SHA, END_MARKER,
                            EXPECTED_CASE_COUNT, MARKER, MODEL, REVISION, SCOPE,
                            expected_cases)
from validate_result import validate_result

COMMIT = 'f' * 40


def temporary_evidence():
    # Keep disposable test evidence in the workspace, including on sandboxed
    # Windows hosts whose default OS temp directory may have restrictive ACLs.
    base = ROOT / 'release/fastconformer-source-probe-tests'
    base.mkdir(parents=True, exist_ok=True)
    temporary = tempfile.TemporaryDirectory(prefix='synthetic-', dir=base)
    assert Path(temporary.name).resolve().parent == base.resolve()
    return temporary


def synthetic_report():
    """A validator fixture only: not audio, ASR execution or accuracy evidence."""
    rows = [{'file': name, 'kind': kind, 'sourceMP3SHA256': pin,
             'sourceFrames': 32000 if kind == 'public-first-two-seconds' else 16000,
             'sourceFloatSHA256': 'a' * 64, 'rawTranscript': 'SYNTHETIC UNIT TEST ONLY',
             'rawTokenIDs': [1], 'encoderFrames': 50, 'seconds': 0.1,
             'inferenceCompleted': True} for name, kind, pin in expected_cases()]
    return {'schemaVersion': 1, 'sourceCommit': COMMIT, 'sourceModel': MODEL,
            'revision': REVISION, 'archiveSHA256': ARCHIVE_SHA,
            'configurationSHA256': CONFIG_SHA, 'scope': SCOPE, 'status': COMPLETE,
            'appIntegrated': False, 'productionApproved': False, 'expectedPassageInput': False,
            'expectedCaseCount': EXPECTED_CASE_COUNT, 'inferenceCaseCount': len(rows),
            'inferenceCompleted': True, 'modelLoadSeconds': 0.2, 'torchVersion': 'UNIT-TEST-FIXTURE',
            'sourceConfiguration': 'FP32/offline/full-context/CTC-head/no-RNNT-LM', 'cases': rows}


def write_fixture(folder, report=None):
    report = report if report is not None else synthetic_report()
    (folder / 'source.txt').write_text(COMMIT + '\n', encoding='utf-8')
    (folder / 'actual-source.json').write_text(json.dumps(report), encoding='utf-8')
    (folder / 'process.txt').write_text(''.join(MARKER + json.dumps(row) + '\n'
                                              for row in report['cases']) + END_MARKER + '\n',
                                      encoding='utf-8')


class EvidenceContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = temporary_evidence()
        self.folder = Path(self.temp.name)
        write_fixture(self.folder)

    def tearDown(self):
        self.temp.cleanup()

    def test_complete_fixture_verifies_execution_without_approving_model(self):
        result = validate_result(self.folder, COMMIT)
        self.assertEqual(result['inferenceCaseCount'], 26)
        self.assertFalse(result['productionApproved'])
        self.assertFalse(result['learnerAccuracyVerified'])
        self.assertFalse(result['streamingVerified'])
        self.assertFalse(result['iPhoneAcceptance'])

    def test_missing_output_fails_even_with_existing_log(self):
        (self.folder / 'actual-source.json').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing actual-source'):
            validate_result(self.folder, COMMIT)

    def test_corrupt_output_fails(self):
        (self.folder / 'actual-source.json').write_text('{', encoding='utf-8')
        with self.assertRaises(ValueError):
            validate_result(self.folder, COMMIT)

    def test_zero_inference_cases_cannot_pass(self):
        report = synthetic_report()
        report.update(cases=[], inferenceCaseCount=0)
        write_fixture(self.folder, report)
        with self.assertRaisesRegex(ValueError, 'completed inference count'):
            validate_result(self.folder, COMMIT)

    def test_partial_run_cannot_claim_completion(self):
        report = synthetic_report()
        report['cases'].pop()
        write_fixture(self.folder, report)
        with self.assertRaisesRegex(ValueError, 'exactly 26'):
            validate_result(self.folder, COMMIT)

    def test_duplicate_case_cannot_replace_missing_case(self):
        report = synthetic_report()
        report['cases'][1] = copy.deepcopy(report['cases'][0])
        write_fixture(self.folder, report)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            validate_result(self.folder, COMMIT)

    def test_wrong_commit_cannot_reuse_a_prior_green_report(self):
        with self.assertRaisesRegex(ValueError, 'sourceCommit'):
            validate_result(self.folder, 'e' * 40)

    def test_started_and_failed_runs_are_rejected(self):
        for status in ('STARTED', 'FAILED_INFERENCE_NOT_VERIFIED'):
            with self.subTest(status=status):
                report = synthetic_report()
                report['status'] = status
                write_fixture(self.folder, report)
                with self.assertRaisesRegex(ValueError, 'status'):
                    validate_result(self.folder, COMMIT)

    def test_completed_status_without_inference_is_rejected(self):
        report = synthetic_report()
        report['inferenceCompleted'] = False
        write_fixture(self.folder, report)
        with self.assertRaisesRegex(ValueError, 'did not complete'):
            validate_result(self.folder, COMMIT)

    def test_invalid_measurements_or_token_outputs_are_rejected(self):
        for key, value in (('seconds', float('nan')), ('encoderFrames', 0),
                           ('rawTokenIDs', [1024]), ('sourceFloatSHA256', ''),
                           ('inferenceCompleted', False)):
            with self.subTest(key=key):
                report = synthetic_report()
                report['cases'][0][key] = value
                write_fixture(self.folder, report)
                with self.assertRaises(ValueError):
                    validate_result(self.folder, COMMIT)

    def test_empty_transcript_is_preserved_not_replaced_by_expected_words(self):
        report = synthetic_report()
        report['cases'][0].update(rawTranscript='', rawTokenIDs=[])
        write_fixture(self.folder, report)
        self.assertEqual(validate_result(self.folder, COMMIT)['inferenceCaseCount'], 26)

    def test_log_must_have_exactly_the_same_actual_rows(self):
        (self.folder / 'process.txt').write_text(END_MARKER + '\n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'same 26'):
            validate_result(self.folder, COMMIT)

    def test_missing_completion_marker_is_rejected(self):
        path = self.folder / 'process.txt'
        path.write_text(path.read_text(encoding='utf-8').replace(END_MARKER, ''), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'completion marker'):
            validate_result(self.folder, COMMIT)


class ProducerExitTests(unittest.TestCase):
    def setUp(self):
        self.temp = temporary_evidence()
        self.folder = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, source):
        return subprocess.run([sys.executable, str(PROBE / 'run_probe.py'), '--output-dir',
                               str(self.folder), '--expected-commit', COMMIT, '--',
                               sys.executable, '-u', '-c', source], capture_output=True,
                              text=True, encoding='utf-8', timeout=10)

    def writer(self, report):
        return ("import json; from pathlib import Path; p=Path(" + repr(str(self.folder)) + "); "
                "r=json.loads(" + repr(json.dumps(report)) + "); "
                "(p/'source.txt').write_text(" + repr(COMMIT + '\n') + ",encoding='utf-8'); "
                "(p/'actual-source.json').write_text(json.dumps(r),encoding='utf-8'); "
                "[print(" + repr(MARKER) + "+json.dumps(x),flush=True) for x in r['cases']]; "
                "print(" + repr(END_MARKER) + ",flush=True); ")

    def test_intentional_producer_failure_survives_logging_and_complete_report(self):
        result = self.invoke(self.writer(synthetic_report()) + 'raise SystemExit(7)')
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        receipt = json.loads((self.folder / 'execution.json').read_text(encoding='utf-8'))
        self.assertEqual(receipt['exitCode'], 7)
        self.assertFalse(receipt['inferenceVerified'])
        self.assertFalse((self.folder / 'validation.json').exists())

    def test_zero_exit_and_zero_cases_still_fails(self):
        report = synthetic_report()
        report.update(cases=[], inferenceCaseCount=0)
        result = self.invoke(self.writer(report))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('completed inference count', result.stderr)

    def test_zero_exit_without_output_cannot_reuse_stale_evidence(self):
        write_fixture(self.folder)
        (self.folder / 'validation.json').write_text('{}', encoding='utf-8')
        result = self.invoke('print("INTENTIONAL NO INFERENCE")')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.folder / 'actual-source.json').exists())
        self.assertFalse((self.folder / 'validation.json').exists())

    def test_only_complete_successful_producer_passes_wrapper(self):
        result = self.invoke(self.writer(synthetic_report()))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads((self.folder / 'execution.json').read_text(encoding='utf-8'))
        self.assertTrue(receipt['inferenceVerified'])
        self.assertFalse(receipt['productionApproved'])


class WorkflowIntegrityTests(unittest.TestCase):
    def test_all_workflow_shell_steps_require_pipefail(self):
        workflow = (ROOT / '.github/workflows/fastconformer-source-probe.yml').read_text(encoding='utf-8')
        steps = re.findall(r'^        run: \|\n(.*?)(?=^      -|\Z)', workflow, re.M | re.S)
        self.assertEqual(len(steps), 5)
        for step in steps:
            self.assertEqual(step.strip().splitlines()[0].strip(), 'set -euo pipefail')
        self.assertIn('run_probe.py --output-dir', workflow)
        self.assertIn('--expected-commit "$GITHUB_SHA"', workflow)
        self.assertNotIn('verify_source.py 2>&1 | tee', workflow)

    def test_audio_dependency_is_hash_pinned_and_never_builds_from_source(self):
        requirements = (PROBE / 'requirements-audio-linux.txt').read_text(encoding='utf-8')
        workflow = (ROOT / '.github/workflows/fastconformer-source-probe.yml').read_text(encoding='utf-8')
        self.assertIn('av==14.2.0 --hash=sha256:e7647d4a8d1855d05fe70784a962b15e103a2d4a0eba1dea7bfbfd95753dedb9', requirements)
        self.assertIn('--only-binary=:all: --require-hashes --index-url https://pypi.org/simple', workflow)
        self.assertNotIn("'av==14.4.0'", workflow)

    @unittest.skipUnless(shutil.which('bash'), 'Bash is exercised on the actual Ubuntu runner')
    def test_intentional_pipeline_failure_is_not_hidden_by_tee(self):
        result = subprocess.run(['bash', '-c', 'set -euo pipefail; false | tee /dev/null; printf FALSE_GREEN'],
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('FALSE_GREEN', result.stdout)


if __name__ == '__main__':
    unittest.main()

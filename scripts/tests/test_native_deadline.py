import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
WRAPPER = ROOT / 'scripts/run-native-with-deadline.py'


class NativeDeadlineTests(unittest.TestCase):
    def test_actual_workflow_deadlines_pass_preflight_before_simulator_boot(self):
        yaml = (ROOT/'codemagic.yaml').read_text(encoding='utf-8')
        values = re.findall(r"NOOR_NATIVE_TEST_DEADLINE:\s*['\"]?(\d+)",yaml)
        self.assertTrue(values)
        for value in values:
            result = subprocess.run([sys.executable,str(WRAPPER),'--check',value],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
        source = (ROOT/'scripts/test-continuous-reader.sh').read_text(encoding='utf-8')
        self.assertLess(source.index('--check "$test_deadline"'),source.index('xcodegen generate'))

    def test_child_failure_is_never_reported_as_success(self):
        result = subprocess.run([sys.executable,str(WRAPPER),'2',sys.executable,'-c','raise SystemExit(7)'],capture_output=True)
        self.assertEqual(result.returncode,7)

    def test_over_limit_deadline_rejects_command_without_running_it(self):
        result = subprocess.run([sys.executable,str(WRAPPER),'721',sys.executable,'-c','print("CHILD_EXECUTED")'],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('CHILD_EXECUTED',result.stdout)

    def test_cold_build_budget_cannot_extend_test_execution(self):
        accepted = subprocess.run([sys.executable,str(WRAPPER),'--check-build','1200'],capture_output=True)
        self.assertEqual(accepted.returncode,0)
        rejected = subprocess.run([sys.executable,str(WRAPPER),'--check-build','1201'],capture_output=True)
        self.assertNotEqual(rejected.returncode,0)
        for command in ([sys.executable,'-c','print("CHILD_EXECUTED")'],
                        ['xcodebuild','test-without-building'], ['xcodebuild','test']):
            result = subprocess.run([sys.executable,str(WRAPPER),'--build','1200',*command],
                                    capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertNotIn('CHILD_EXECUTED',result.stdout)

    def test_live_journey_keeps_original_runtime_and_assertions(self):
        source = (ROOT/'scripts/test-live-recitation.sh').read_text(encoding='utf-8')
        self.assertIn('--build 1200 xcodebuild build-for-testing',source)
        self.assertIn('180 xcodebuild test-without-building',source)
        self.assertIn('-default-test-execution-time-allowance 100',source)
        self.assertIn('-maximum-test-execution-time-allowance 120',source)

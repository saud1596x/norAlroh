import pathlib
import importlib.util
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import Mock, patch

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
        events = [json.loads(line.partition(' ')[2]) for line in result.stdout.decode().splitlines()
                  if line.startswith('NOOR_NATIVE_PROCESS ')]
        self.assertEqual([e['event'] for e in events], ['start','end'])
        self.assertEqual(events[-1]['exitCode'],7)
        self.assertGreaterEqual(events[-1]['elapsedSeconds'],events[0]['elapsedSeconds'])

    def test_actual_deadline_kills_child_and_never_reports_success(self):
        result = subprocess.run([sys.executable,str(WRAPPER),'0.1',sys.executable,
                                 '-c','import time; time.sleep(20)'],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,124)
        self.assertIn('tests NOT passed',result.stdout)
        events = [json.loads(line.partition(' ')[2]) for line in result.stdout.splitlines()
                  if line.startswith('NOOR_NATIVE_PROCESS ')]
        self.assertEqual(events[-1]['exitCode'],124)

    def test_success_and_failure_preserve_complete_stdout_and_stderr(self):
        # Exceed the bounded relay queue and end without a newline, exercising
        # complete draining rather than a small print swallowed at root exit.
        for code in [0, 7]:
            text = 'relay-bytes-' * 50_000
            script = ('import sys; sys.stdout.write("relay-bytes-" * 50000); '
                      'sys.stdout.flush(); sys.stderr.write("TAIL-STDERR"); '
                      f'sys.stderr.flush(); raise SystemExit({code})')
            result = subprocess.run([sys.executable,str(WRAPPER),'5',sys.executable,'-c',script],
                                    capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,code,result.stderr)
            self.assertIn(text + 'TAIL-STDERR',result.stdout)
            events = [json.loads(line.partition(' ')[2]) for line in result.stdout.splitlines()
                      if line.startswith('NOOR_NATIVE_PROCESS ')]
            self.assertEqual([e['event'] for e in events],['start','end'])
            self.assertEqual(events[-1]['exitCode'],code)

    def test_group_exit_race_is_harmless_for_term_kill_and_presence(self):
        spec = importlib.util.spec_from_file_location('deadline_race_test',WRAPPER)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        fake_os = types.SimpleNamespace(name='posix',killpg=Mock(side_effect=ProcessLookupError()))
        fake_signals = types.SimpleNamespace(SIGTERM=15,SIGKILL=9)
        process = types.SimpleNamespace(pid=12345)
        with patch.object(module,'os',fake_os), patch.object(module,'signal',fake_signals):
            self.assertFalse(module.signal_process_group(process,force=False))
            self.assertFalse(module.signal_process_group(process,force=True))
            self.assertFalse(module.process_group_exists(process))
        self.assertEqual([call.args for call in fake_os.killpg.call_args_list],
                         [(12345,15),(12345,9),(12345,0)])

    def test_root_exit_does_not_skip_group_kill_and_final_reap_is_bounded(self):
        spec = importlib.util.spec_from_file_location('deadline_escalation_test',WRAPPER)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        for reap_timeout in [False,True]:
            process = Mock()
            process.poll.return_value = -15
            if reap_timeout:
                process.wait.side_effect = subprocess.TimeoutExpired('synthetic-root',2)
            relay = Mock(eof=False)
            clock = types.SimpleNamespace(monotonic=Mock(side_effect=[0,0,0,6,6]),sleep=Mock())
            with patch.object(module,'time',clock), \
                 patch.object(module,'process_group_exists',return_value=True) as exists, \
                 patch.object(module,'signal_process_group') as send:
                self.assertEqual(module.stop_process_group(process,relay),not reap_timeout)
            self.assertEqual([call.kwargs for call in send.call_args_list],[{'force':False},{'force':True}])
            process.wait.assert_called_once_with(timeout=module.REAP_SECONDS)
            exists.assert_called_once_with(process)
            relay.drain_until.assert_called_once()

    @unittest.skipUnless(os.name == 'posix','Actual process-group/EOF regression requires POSIX')
    def test_timeout_kills_term_ignoring_descendant_after_root_exits_and_releases_outer_stdout(self):
        folder = ROOT/'release/native-deadline-tests'
        folder.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='descendant-',dir=folder) as temporary:
            pid_file = pathlib.Path(temporary)/'child.pid'
            pgid_file = pathlib.Path(temporary)/'group.pid'
            child = ('import os,signal,sys,time,pathlib; '
                     'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                     'pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); '
                     'print("DESCENDANT_READY_RETAINING_STDOUT",flush=True); time.sleep(60)')
            parent = ('import os,pathlib,subprocess,sys,time; '
                      'pathlib.Path(sys.argv[2]).write_text(str(os.getpid())); '
                      f'subprocess.Popen([sys.executable,"-u","-c",{child!r},sys.argv[1]]); '
                      'print("ROOT_READY_DEFAULT_TERM",flush=True); time.sleep(60)')
            started = time.monotonic()
            try:
                # This asserts real capture_output EOF, not only wrapper.poll().
                # On the old implementation the root exits on TERM but its
                # descendant keeps this outer pipe open until the test times out.
                result = subprocess.run([sys.executable,str(WRAPPER),'1',sys.executable,'-u','-c',parent,
                                         str(pid_file),str(pgid_file)],capture_output=True,text=True,timeout=12)
                elapsed = time.monotonic()-started
                self.assertEqual(result.returncode,124,result.stderr)
                self.assertLess(elapsed,11,'A descendant retaining stdout cannot defeat the bounded wrapper')
                self.assertIn('DESCENDANT_READY_RETAINING_STDOUT',result.stdout)
                self.assertIn('tests NOT passed',result.stdout)
                events = [json.loads(line.partition(' ')[2]) for line in result.stdout.splitlines()
                          if line.startswith('NOOR_NATIVE_PROCESS ')]
                self.assertEqual([e['event'] for e in events],['start','end'])
                self.assertEqual(events[-1]['exitCode'],124)
                self.assertTrue(events[-1]['rootReaped'])
                self.assertTrue(events[-1]['outputEOF'],'The ignoring descendant must close its internal writer after KILL')
                child_pid = int(pid_file.read_text())
                self.assertFalse(self._posix_process_running(child_pid),
                                 'TERM-ignoring descendant must not remain running after wrapper exit')
            finally:
                # Clean this isolated test group even if the old regression or
                # a setup failure prevents run(capture_output) from completing.
                if pgid_file.exists():
                    try: os.killpg(int(pgid_file.read_text()),signal.SIGKILL)
                    except ProcessLookupError: pass
                if pid_file.exists():
                    try: os.kill(int(pid_file.read_text()),signal.SIGKILL)
                    except ProcessLookupError: pass

    @unittest.skipUnless(os.name == 'posix','Actual retained-pipe/EOF regression requires POSIX')
    def test_escaped_descendant_cannot_retain_the_outer_logger_pipe(self):
        folder = ROOT/'release/native-deadline-tests'
        folder.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='escaped-',dir=folder) as temporary:
            pid_file = pathlib.Path(temporary)/'child.pid'
            pgid_file = pathlib.Path(temporary)/'group.pid'
            child = ('import os,signal,sys,time,pathlib; os.setsid(); '
                     'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                     'pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); '
                     'print("ESCAPED_INTERNAL_WRITER_READY",flush=True); time.sleep(60)')
            parent = ('import os,pathlib,subprocess,sys,time; '
                      'pathlib.Path(sys.argv[2]).write_text(str(os.getpid())); '
                      f'subprocess.Popen([sys.executable,"-u","-c",{child!r},sys.argv[1]]); time.sleep(60)')
            started=time.monotonic()
            try:
                result=subprocess.run([sys.executable,str(WRAPPER),'1',sys.executable,'-u','-c',parent,
                                       str(pid_file),str(pgid_file)],capture_output=True,text=True,timeout=8)
                self.assertEqual(result.returncode,124,result.stderr)
                self.assertLess(time.monotonic()-started,7)
                self.assertIn('ESCAPED_INTERNAL_WRITER_READY',result.stdout)
                events=[json.loads(line.partition(' ')[2]) for line in result.stdout.splitlines()
                        if line.startswith('NOOR_NATIVE_PROCESS ')]
                self.assertEqual(events[-1]['exitCode'],124)
                self.assertFalse(events[-1]['outputEOF'],
                    'Escaped child still owns only the internal pipe; outer capture must finish anyway')
            finally:
                if pgid_file.exists():
                    try: os.killpg(int(pgid_file.read_text()),signal.SIGKILL)
                    except ProcessLookupError: pass
                if pid_file.exists():
                    try: os.kill(int(pid_file.read_text()),signal.SIGKILL)
                    except ProcessLookupError: pass

    @staticmethod
    def _posix_process_running(pid):
        try:
            os.kill(pid,0)
        except ProcessLookupError:
            return False
        # A killed orphan may briefly remain as a zombie awaiting init's reap;
        # it owns no stdout writer and is not an executing descendant.
        status = subprocess.run(['ps','-o','stat=','-p',str(pid)],capture_output=True,text=True,timeout=2)
        return status.returncode == 0 and bool(status.stdout.strip()) and not status.stdout.strip().startswith('Z')

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
        self.assertIn('local deadline=180',source)
        self.assertIn('live-storage|startup-policy) deadline=600',source)
        self.assertIn('"$deadline" xcodebuild test-without-building',source)
        self.assertIn('-default-test-execution-time-allowance 100',source)
        self.assertIn('-maximum-test-execution-time-allowance 120',source)

"""Synthetic validator fixtures only; no app launch, ASR or native result claims."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/verify-mushaf-closure-evidence.py'
spec = importlib.util.spec_from_file_location('mushaf_closure', SCRIPT)
closure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(closure)
COMMIT = 'c' * 40
UDID = '00000000-0000-0000-0000-000000000001'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'


def write(path, value):
    path.write_text(json.dumps(value), encoding='utf-8')


def synthetic_png(path, size):
    from PIL import Image
    Image.new('RGB', size, 'white').save(path)


def fake_video_probe(path):
    """In-memory validator fixture, deliberately not executable video evidence."""
    return {'frames': 120, 'durationSeconds': 8, 'width': 750, 'height': 1334,
            'scope': 'UNIT_TEST_FIXTURE_NOT_NATIVE_VIDEO'}


def fixture(folder, size='small'):
    expected = closure.lanes(size)
    context = {'schemaVersion': 1, 'sourceCommit': COMMIT, 'configuration': 'Release',
               'project': 'project-accounts.yml', 'displayClass': size,
               'deviceName': closure.DEVICES[size], 'deviceTypeIdentifier': closure.DEVICE_TYPES[size],
               'deviceUDID': UDID, 'runtime': RUNTIME, 'runtimeVersion': '26.2',
               'priorReferenceRuntimeVersion': '26.2', 'runtimeMatchesPriorReference': True,
               'xcode': 'Xcode 26.3\nBuild version UNIT-TEST-FIXTURE',
               'looks': ['light', 'dark'], 'expectedLanes': expected,
               'expectedTests': {lane: closure.selectors(lane) for lane in expected}}
    write(folder / 'context.json', context)
    (folder / 'source.txt').write_text(COMMIT + '\n', encoding='utf-8')
    (folder / 'xcode.txt').write_text(context['xcode'] + '\n', encoding='utf-8')
    write(folder / 'actual-booted-devices.json', {'devices': {RUNTIME: [
        {'udid': UDID, 'state': 'Booted', 'isAvailable': True,
         'deviceTypeIdentifier': closure.DEVICE_TYPES[size]}]}})
    synthetic_png(folder / 'actual-display.png', (750, 1334))
    commands, collection = {}, {}
    for lane in ['build'] + expected:
        deadline = 1200 if lane == 'build' else 600 if lane == 'geometry' else 180
        commands[lane] = {'exitCode': 0, 'deadlineSeconds': deadline, 'log': lane + '.txt'}
        stage = 'BUILD' if lane == 'build' else 'TEST'
        raw_log = ''.join('NOOR_NATIVE_PROCESS ' + json.dumps(
            {'stage': stage, 'event': event, 'deadlineSeconds': deadline,
             **({'exitCode': 0, 'elapsedSeconds': 8} if event == 'end' else {'elapsedSeconds': 0})}) + '\n' for event in ('start', 'end'))
        if closure.ui_prefix(lane) == 'journey':
            raw_log += 'MUSHAF_UI_DRIVER_OPEN_SECONDS 0.5\n' + ''.join(
                'MUSHAF_UI_DRIVER_TURN target=%d seconds=0.25\n' % target for target in (15, 16, 15, 14))
        (folder / (lane + '.txt')).write_text(raw_log, encoding='utf-8')
        events = [{'kind': 'native-process', 'observerSeconds': 0,
                   'process': {'event': 'start', 'elapsedSeconds': 0}}]
        if closure.ui_prefix(lane):
            events.extend([{'kind': 'test-start', 'observerSeconds': 1},
                           {'kind': 'test-end', 'observerSeconds': 7,
                            'reportedTestSeconds': 6, 'result': 'passed'}])
        events.append({'kind': 'native-process', 'observerSeconds': 8,
                       'process': {'event': 'end', 'elapsedSeconds': 8, 'exitCode': 0}})
        write(folder / (lane + '-observations.json'), {
            'schemaVersion': 1, 'lane': lane, 'events': events,
            'sourceLogSHA256': closure.digest(folder / (lane + '.txt')),
            'scope': 'SYNTHETIC UNIT TEST FIXTURE NOT NATIVE PERFORMANCE'})
        if lane == 'build':
            continue
        methods = closure.selectors(lane)
        write(folder / (lane + '-summary.json'), {'result': 'Passed', 'passedTests': len(methods),
                                                  'failedTests': 0, 'skippedTests': 0})
        write(folder / (lane + '-tests.json'), {'testNodes': [
            {'nodeType': 'Test Case', 'nodeIdentifier': 'AtharTests/' + name + '()', 'result': 'Passed'}
            for name in methods]})
        collection[lane] = {'summaryExitCode': 0, 'testsExitCode': 0, 'attachmentsExitCode': 0}
        attachments = folder / (lane + '-attachments')
        attachments.mkdir()
        names = (list(closure.UI_SHOTS[closure.ui_prefix(lane)]) if closure.ui_prefix(lane) else
                 ['QCF-V2-shaped-page-%03d' % page for page in range(1, 605)] if lane == 'geometry' else
                 list(closure.READER_LIBRARY_SHOTS))
        records = []
        for index, name in enumerate(names):
            path = attachments / ('synthetic-%03d.png' % index)
            synthetic_png(path, (560, 940) if lane == 'geometry' else (750, 1334))
            records.append({'exportedFileName': path.name, 'suggestedHumanReadableName': name + '_0.png'})
        write(attachments / 'manifest.json', [{'testName': 'SYNTHETIC VALIDATOR FIXTURE ONLY', 'attachments': records}])
    write(folder / 'commands.json', commands)
    write(folder / 'collection.json', collection)
    for look in ('light', 'dark'):
        (folder / ('appearance-' + look + '.txt')).write_text(look + '\n', encoding='utf-8')
        video = folder / ('journey-' + look + '.mp4')
        video.write_bytes(b'SYNTHETIC TEST FIXTURE: NOT A REAL MP4')
        write(folder / ('video-' + look + '-status.json'), {
            'look': look, 'deviceUDID': UDID, 'guardSeconds': 180, 'guardTriggered': False,
            'forcedKill': False, 'started': True, 'interrupted': False, 'finishRequested': True, 'exitCode': 0,
            'bytes': video.stat().st_size})


class MushafClosureEvidenceTests(unittest.TestCase):
    def setUp(self):
        base = ROOT / 'release/mushaf-closure-validator-unit-tests'
        base.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='synthetic-', dir=base)
        self.folder = Path(self.temporary.name)
        self.assertEqual(self.folder.resolve().parent, base.resolve())

    def tearDown(self):
        self.temporary.cleanup()

    def verify(self, size='small'):
        with contextlib.redirect_stdout(io.StringIO()):
            result = closure.verify(self.folder, size, COMMIT, video_probe=fake_video_probe)
        self.report = json.loads((self.folder / 'report.json').read_text(encoding='utf-8'))
        return result

    def mutate(self, name, update):
        path = self.folder / name
        value = json.loads(path.read_text(encoding='utf-8'))
        update(value)
        write(path, value)

    def test_complete_contract_does_not_claim_asr_device_or_release_approval(self):
        fixture(self.folder)
        self.assertEqual(self.verify(), 0, self.report['errors'])
        self.assertFalse(self.report['publicationApproved'])
        self.assertFalse(self.report['fullReleaseApproval'])
        self.assertEqual(self.report['ASRLatency'], 'NOT_EVALUATED')
        self.assertEqual(self.report['physicalDeviceTesting'], 'NOT_VERIFIED')
        self.assertEqual(self.report['originalPNGCount'], 54)

    def test_medium_requires_all_604_original_baseline_pngs(self):
        fixture(self.folder, 'medium')
        self.assertEqual(self.verify('medium'), 0, self.report['errors'])
        self.assertEqual(self.report['baselinePageCount'], 604)

    def test_missing_baseline_page_is_not_replaced_by_gallery_count(self):
        fixture(self.folder, 'medium')
        self.mutate('geometry-attachments/manifest.json', lambda value: value[0]['attachments'].pop())
        self.assertNotEqual(self.verify('medium'), 0)
        self.assertTrue(any('604 distinct' in error for error in self.report['errors']))

    def test_duplicate_baseline_label_fails_even_with_604_files(self):
        fixture(self.folder, 'medium')
        def duplicate(value):
            value[0]['attachments'][-1]['suggestedHumanReadableName'] = 'QCF-V2-shaped-page-001_0.png'
        self.mutate('geometry-attachments/manifest.json', duplicate)
        self.assertNotEqual(self.verify('medium'), 0)

    def test_zero_native_cases_never_passes(self):
        fixture(self.folder)
        self.mutate('journey-light-summary.json', lambda value: value.update(passedTests=0))
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('zero or absent actual test count' in error for error in self.report['errors']))

    def test_failed_or_skipped_case_never_passes_even_with_exit_zero(self):
        fixture(self.folder)
        self.mutate('journey-light-summary.json', lambda value: value.update(failedTests=1))
        self.assertNotEqual(self.verify(), 0)
        self.mutate('journey-light-summary.json', lambda value: value.update(failedTests=0, skippedTests=1))
        self.assertNotEqual(self.verify(), 0)

    def test_exit_code_65_cannot_be_hidden_by_tee_or_command_receipt(self):
        fixture(self.folder)
        path = self.folder / 'journey-light.txt'
        path.write_text(path.read_text(encoding='utf-8').replace('"exitCode": 0', '"exitCode": 65'), encoding='utf-8')
        self.assertNotEqual(self.verify(), 0)

    def test_process_timeout_cannot_be_approved_by_good_summary(self):
        fixture(self.folder)
        self.mutate('commands.json', lambda value: value['journey-light'].update(exitCode=124))
        self.assertNotEqual(self.verify(), 0)

    def test_missing_test_tree_cannot_be_replaced_by_positive_summary(self):
        fixture(self.folder)
        write(self.folder / 'journey-light-tests.json', {'testNodes': []})
        self.assertNotEqual(self.verify(), 0)

    def test_attachment_export_failure_is_a_gate_failure(self):
        fixture(self.folder)
        self.mutate('collection.json', lambda value: value['journey-light'].update(attachmentsExitCode=1))
        self.assertNotEqual(self.verify(), 0)

    def test_missing_required_ui_state_is_not_rescued_by_other_pngs(self):
        fixture(self.folder)
        self.mutate('journey-light-attachments/manifest.json', lambda value: value[0]['attachments'].pop())
        self.assertNotEqual(self.verify(), 0)

    def test_missing_gallery_lane_cannot_be_rescued_by_other_successful_lanes(self):
        fixture(self.folder)
        (self.folder / 'gallery-special-dark-summary.json').unlink()
        self.assertNotEqual(self.verify(), 0)
        self.assertIn('journey-dark', self.report['testResults'])
        self.assertNotIn('gallery-special-dark', self.report['testResults'])

    def test_passed_reader_library_with_empty_manifest_still_fails_original_png_gate(self):
        fixture(self.folder, 'medium')
        write(self.folder / 'reader-library-attachments/manifest.json', [])
        self.assertNotEqual(self.verify('medium'), 0)
        self.assertEqual(self.report['testResults']['reader-library']['passedTests'], 1)
        self.assertEqual(self.report['testResults']['reader-library']['failedTests'], 0)
        self.assertTrue(any('reader-library zero original PNG screenshots' in error for error in self.report['errors']))
        self.assertTrue(any('closure-reader-library-selected-voice-final-surah' in error for error in self.report['errors']))

    def test_unrelated_reader_library_png_cannot_replace_selected_voice_final_surah(self):
        fixture(self.folder, 'medium')
        def unrelated(value):
            value[0]['attachments'][0]['suggestedHumanReadableName'] = 'unrelated-reader-library-screen_0.png'
        self.mutate('reader-library-attachments/manifest.json', unrelated)
        self.assertNotEqual(self.verify('medium'), 0)
        self.assertTrue(any('reader-library: missing/repeated mandatory actual screenshot closure-reader-library-selected-voice-final-surah'
                            in error for error in self.report['errors']))

    def test_all_eight_gallery_reference_pages_are_mandatory_in_their_own_lanes(self):
        shots = (closure.GALLERY_OPENING_SHOTS + closure.GALLERY_DENSE_SHOTS
                 + closure.GALLERY_SPECIAL_SHOTS + closure.GALLERY_FINAL_SHOTS)
        self.assertEqual(len(shots), 16)
        self.assertEqual(set(shots), {
            'closure-page-%03d-%s' % (number, mode)
            for number in (1, 2, 3, 187, 379, 501, 48, 604) for mode in ('normal', 'tajweed')})
        fixture(self.folder)
        def remove_501(value):
            value[0]['attachments'] = [row for row in value[0]['attachments']
                                        if not row['suggestedHumanReadableName'].startswith('closure-page-501-normal')]
        self.mutate('gallery-special-light-attachments/manifest.json', remove_501)
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('closure-page-501-normal' in error for error in self.report['errors']))

    def test_split_gallery_cannot_omit_dense_or_final_lane(self):
        fixture(self.folder)
        (self.folder / 'gallery-dense-dark-summary.json').unlink()
        (self.folder / 'gallery-final-light-summary.json').unlink()
        self.assertNotEqual(self.verify(), 0)
        self.assertNotIn('gallery-dense-dark', self.report['testResults'])
        self.assertNotIn('gallery-final-light', self.report['testResults'])
        self.assertIn('gallery-openings-dark', self.report['testResults'])

    def test_dense_gallery_png_in_final_lane_cannot_substitute_original_lane(self):
        fixture(self.folder)
        source = self.folder / 'gallery-dense-light-attachments/manifest.json'
        final = self.folder / 'gallery-final-light-attachments/manifest.json'
        dense_manifest = json.loads(source.read_text(encoding='utf-8'))
        final_manifest = json.loads(final.read_text(encoding='utf-8'))
        final_manifest.extend(dense_manifest)
        write(final, final_manifest)
        write(source, [])
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('gallery-dense-light: missing/repeated mandatory actual screenshot closure-page-187-tajweed'
                            in error for error in self.report['errors']))

    def test_normal_page_cannot_replace_missing_tajweed_capture(self):
        fixture(self.folder)
        manifest = self.folder / 'gallery-special-light-attachments/manifest.json'
        before = json.loads(manifest.read_text(encoding='utf-8'))[0]['attachments']
        self.assertTrue(any(row['suggestedHumanReadableName'].startswith('closure-page-501-normal') for row in before))
        self.assertTrue(any(row['suggestedHumanReadableName'].startswith('closure-page-501-tajweed') for row in before))
        def remove_color(value):
            value[0]['attachments'] = [row for row in value[0]['attachments']
                                        if not row['suggestedHumanReadableName'].startswith('closure-page-501-tajweed')]
        self.mutate('gallery-special-light-attachments/manifest.json', remove_color)
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('gallery-special-light: missing/repeated mandatory actual screenshot closure-page-501-tajweed'
                            in error for error in self.report['errors']))
        self.assertFalse(any('missing/repeated mandatory actual screenshot closure-page-501-normal'
                             in error for error in self.report['errors']))

    def test_controls_capture_cannot_be_substituted_by_a_core_journey_capture(self):
        fixture(self.folder)
        path = self.folder / 'journey-light-attachments/synthetic-extra.png'
        synthetic_png(path, (750, 1334))
        self.mutate('journey-light-attachments/manifest.json', lambda value: value[0]['attachments'].append({
            'exportedFileName': path.name, 'suggestedHumanReadableName': 'closure-tajweed-on_0.png'}))
        self.mutate('controls-light-attachments/manifest.json', lambda value: value[0]['attachments'].pop(0))
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('controls-light: missing/repeated' in error for error in self.report['errors']))

    def test_raw_driver_metrics_keep_startup_body_post_and_do_not_claim_p95(self):
        fixture(self.folder)
        self.assertEqual(self.verify(), 0, self.report['errors'])
        actual = self.report['uiDriverMetrics']['journey-light']
        self.assertEqual(actual['rawDriverOpenSeconds'], [0.5])
        self.assertEqual([row['target'] for row in actual['rawDriverPageTurns']], [15, 16, 15, 14])
        self.assertEqual(actual['observedStartupSeconds'], 1)
        self.assertEqual(actual['reportedXCTestBodySeconds'], 6)
        self.assertEqual(actual['observedPostTestSeconds'], 1)
        self.assertEqual(actual['p95'], 'NOT_ESTIMATED_FROM_SPARSE_DRIVER_SAMPLES')

    def test_timeout_preserves_partial_raw_metrics_and_original_captures(self):
        fixture(self.folder)
        path = self.folder / 'journey-light.txt'
        path.write_text(path.read_text(encoding='utf-8').replace('"exitCode": 0', '"exitCode": 124'), encoding='utf-8')
        self.mutate('commands.json', lambda value: value['journey-light'].update(exitCode=124))
        def partial(value):
            value['events'] = [row for row in value['events'] if row['kind'] != 'test-end']
            value['events'][-1]['process']['exitCode'] = 124
            value['sourceLogSHA256'] = closure.digest(path)
        self.mutate('journey-light-observations.json', partial)
        self.assertNotEqual(self.verify(), 0)
        actual = self.report['uiDriverMetrics']['journey-light']
        self.assertEqual(actual['processExitCode'], 124)
        self.assertEqual(actual['rawDriverOpenSeconds'], [0.5])
        self.assertTrue(actual['coverageErrors'])
        self.assertEqual(self.report['originalPNGCount'], 54)

    def test_log_recorder_preserves_actual_text_and_records_observed_boundaries(self):
        raw = ('NOOR_NATIVE_PROCESS {"event":"start","elapsedSeconds":0}\n'
               "Test Case '-[AtharUITests.NoorMushafClosureUITests " + closure.JOURNEY + "]' started.\n"
               'MUSHAF_UI_DRIVER_OPEN_SECONDS 0.5\n' + ''.join(
                   'MUSHAF_UI_DRIVER_TURN target=%d seconds=0.25\n' % target for target in (15, 16, 15, 14)) +
               "Test Case '-[AtharUITests.NoorMushafClosureUITests " + closure.JOURNEY + "]' passed (6.0 seconds).\n"
               'NOOR_NATIVE_PROCESS {"event":"end","elapsedSeconds":8,"exitCode":0}\n')
        result = subprocess.run([sys.executable, str(SCRIPT), 'log', '--output-dir', str(self.folder), '--lane', 'journey-light'],
                                input=raw, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.folder / 'journey-light.txt').read_text(encoding='utf-8'), raw)
        actual = closure.driver_metrics(self.folder, 'journey-light')
        self.assertEqual(actual['coverageErrors'], [])
        self.assertEqual(actual['reportedXCTestBodySeconds'], 6)

    def test_altered_log_rejects_stale_timing_observations(self):
        fixture(self.folder)
        path = self.folder / 'journey-light.txt'
        path.write_text(path.read_text(encoding='utf-8') + 'CHANGED AFTER CAPTURE\n', encoding='utf-8')
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('Timing observations do not match' in error for error in self.report['errors']))

    def test_wrong_phone_type_cannot_be_labelled_as_small(self):
        fixture(self.folder)
        self.mutate('context.json', lambda value: value.update(deviceTypeIdentifier=closure.DEVICE_TYPES['large']))
        self.assertNotEqual(self.verify(), 0)
        self.assertTrue(any('device type' in error for error in self.report['errors']))

    def test_video_guard_failure_is_not_a_passing_recording(self):
        fixture(self.folder)
        self.mutate('video-light-status.json', lambda value: value.update(guardTriggered=True))
        self.assertNotEqual(self.verify(), 0)

    def test_early_recorder_exit_cannot_claim_the_full_journey(self):
        fixture(self.folder)
        self.mutate('video-light-status.json', lambda value: value.update(finishRequested=False))
        self.assertNotEqual(self.verify(), 0)

    def test_short_valid_video_cannot_replace_the_actual_journey(self):
        fixture(self.folder)
        path = self.folder / 'journey-light.txt'
        path.write_text(path.read_text(encoding='utf-8').replace('"elapsedSeconds": 8', '"elapsedSeconds": 60'), encoding='utf-8')
        self.assertNotEqual(self.verify(), 0)

    def test_video_absence_or_decoder_failure_is_fatal(self):
        fixture(self.folder)
        (self.folder / 'journey-light.mp4').unlink()
        self.assertNotEqual(self.verify(), 0)

    def test_os_appearance_mismatch_is_not_dark_evidence(self):
        fixture(self.folder)
        (self.folder / 'appearance-dark.txt').write_text('light', encoding='utf-8')
        self.assertNotEqual(self.verify(), 0)

    def test_old_source_cannot_reuse_current_screenshots(self):
        fixture(self.folder)
        self.mutate('context.json', lambda value: value.update(sourceCommit='d' * 40))
        self.assertNotEqual(self.verify(), 0)

    def test_cli_missing_outputs_returns_failure_and_writes_failure_report(self):
        result = subprocess.run([sys.executable, str(SCRIPT), 'verify', '--output-dir', str(self.folder),
                                 '--expected-size', 'small', '--expected-commit', COMMIT],
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((self.folder / 'report.json').read_text(encoding='utf-8'))
        self.assertEqual(report['status'], 'FAILED_INCOMPLETE_MUSHAF_EVIDENCE')

    def test_unavailable_small_type_fails_without_any_fallback_or_create(self):
        write(self.folder / 'device-types.json', {'devicetypes': [
            {'name': closure.DEVICES['large'], 'identifier': closure.DEVICE_TYPES['large']}]})
        with patch.object(closure.subprocess, 'check_output') as command:
            with self.assertRaisesRegex(ValueError, 'Exact device type unavailable'):
                closure.select_device(self.folder, 'small')
            command.assert_not_called()

    def test_device_creation_failure_is_not_retried_on_a_larger_phone(self):
        (self.folder / 'source.txt').write_text(COMMIT, encoding='utf-8')
        write(self.folder / 'device-types.json', {'devicetypes': [
            {'name': closure.DEVICES['small'], 'identifier': closure.DEVICE_TYPES['small']}]})
        write(self.folder / 'runtimes.json', {'runtimes': [
            {'identifier': RUNTIME, 'version': '26.2', 'isAvailable': True}]})
        write(self.folder / 'devices.json', {'devices': {}})
        error = subprocess.CalledProcessError(1, ['xcrun', 'simctl', 'create'])
        with patch.object(closure.subprocess, 'check_output', side_effect=error) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                closure.select_device(self.folder, 'small')
            self.assertEqual(command.call_count, 1)
            self.assertIn(closure.DEVICE_TYPES['small'], command.call_args.args[0])

    def test_available_reference_runtime_26_2_is_preferred_to_newer_runtime(self):
        (self.folder / 'source.txt').write_text(COMMIT, encoding='utf-8')
        (self.folder / 'xcode.txt').write_text('Xcode 26.3', encoding='utf-8')
        write(self.folder / 'device-types.json', {'devicetypes': [
            {'name': closure.DEVICES['small'], 'identifier': closure.DEVICE_TYPES['small']}]})
        newer = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5'
        write(self.folder / 'runtimes.json', {'runtimes': [
            {'identifier': newer, 'version': '26.5', 'isAvailable': True},
            {'identifier': RUNTIME, 'version': '26.2', 'isAvailable': True}]})
        write(self.folder / 'devices.json', {'devices': {runtime: [
            {'udid': UDID, 'isAvailable': True, 'deviceTypeIdentifier': closure.DEVICE_TYPES['small']}]
            for runtime in (RUNTIME, newer)}})
        with contextlib.redirect_stdout(io.StringIO()):
            closure.select_device(self.folder, 'small')
        actual = json.loads((self.folder / 'context.json').read_text(encoding='utf-8'))
        self.assertEqual(actual['runtime'], RUNTIME)
        self.assertTrue(actual['runtimeMatchesPriorReference'])

    def test_different_runtime_is_disclosed_instead_of_claiming_matched_evidence(self):
        fixture(self.folder)
        newer = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5'
        self.mutate('context.json', lambda value: value.update(
            runtime=newer, runtimeVersion='26.5', runtimeMatchesPriorReference=False))
        self.mutate('actual-booted-devices.json', lambda value:
                    value['devices'].update({newer: value['devices'].pop(RUNTIME)}))
        self.assertEqual(self.verify(), 0, self.report['errors'])
        self.assertEqual(self.report['runtimeComparison'],
                         'DIFFERENT_RUNTIME_NOT_MATCHING_PRIOR_IOS26_2_EVIDENCE')


if __name__ == '__main__':
    unittest.main()

"""Collect and verify original native Mushaf evidence; never ASR/release approval."""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEVICES = {'small': 'iPhone SE (3rd generation)', 'medium': 'iPhone 17 Pro',
           'large': 'iPhone 17 Pro Max'}
DEVICE_TYPES = {'small': 'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation',
                'medium': 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro',
                'large': 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max'}
JOURNEY = 'testMeasuredReadingJourneyKeepsGeometryAndSurvivesActualCapture'
LARGE_TEXT = 'testLargeInterfaceTextKeepsControlsOutsideTheQuran'
GALLERY_OPENINGS = 'testReferenceOpeningAndDensePagesKeepGeometry'
GALLERY_SPECIAL = 'testReferenceSpecialAndFinalPagesKeepGeometry'
CONTROLS = 'testTajweedFullscreenAndAyahActionsKeepGeometry'
JOURNEY_SHOTS = ('closure-page-014-normal',
    'closure-tools-hidden-stable', 'closure-ayah-selection-stable',
    'closure-actual-microphone',
    'closure-after-finish-same-page', 'closure-restored-position')
GALLERY_OPENING_SHOTS = tuple('closure-page-' + page + '-' + mode
                              for page in ('001', '002', '003', '187') for mode in ('normal', 'tajweed'))
GALLERY_SPECIAL_SHOTS = tuple('closure-page-' + page + '-' + mode
                             for page in ('379', '501', '048', '604') for mode in ('normal', 'tajweed'))
CONTROL_SHOTS = ('closure-tajweed-on', 'closure-tajweed-off',
                 'closure-fullscreen-restored-actions', 'closure-six-ayah-actions')
UI_METHODS = {'journey': JOURNEY, 'gallery-openings': GALLERY_OPENINGS,
              'gallery-special': GALLERY_SPECIAL, 'controls': CONTROLS, 'large-text': LARGE_TEXT}
UI_SHOTS = {'journey': JOURNEY_SHOTS, 'gallery-openings': GALLERY_OPENING_SHOTS,
            'gallery-special': GALLERY_SPECIAL_SHOTS, 'controls': CONTROL_SHOTS,
            'large-text': ('closure-large-interface-text',)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1_048_576), b''):
            result.update(block)
    return result.hexdigest()


def lanes(size):
    return (['geometry', 'reader-library'] if size == 'medium' else []) + [
        prefix + '-' + look for look in ('light', 'dark') for prefix in UI_METHODS]


def ui_prefix(lane):
    return next((prefix for prefix in UI_METHODS if lane in (prefix + '-light', prefix + '-dark')), None)


def selectors(lane):
    prefix = ui_prefix(lane)
    if prefix:
        return ['NoorMushafClosureUITests/' + UI_METHODS[prefix]]
    classes = ('InteractiveMushafTests', 'MushafViewportTests') if lane == 'geometry' else ('NoorReciterLibraryTests',)
    bundle = 'AtharTests' if lane == 'geometry' else 'AtharUITests'
    result = []
    for name in classes:
        source = (ROOT / 'ios' / bundle / (name + '.swift')).read_text(encoding='utf-8')
        source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
        result.extend(name + '/' + method for method in re.findall(r'\bfunc\s+(test\w+)\s*\(', source))
    if lane == 'geometry':
        result.extend('NoorContinuousMushafTests/' + name for name in (
            'testOriginalTajweedLayersRenderAll604PagesAndPreserveHiddenWordGeometry',
            'testOriginalTajweedPaletteUsesRequestedCanvasStyleDespiteOppositeAmbientTraits'))
    require(result, 'No expected native test methods discovered: ' + lane)
    return result


def select_device(folder, size):
    require(not (folder / 'context.json').exists(), 'Previous native evidence exists; do not overwrite it')
    types = read(folder / 'device-types.json')['devicetypes']
    matching = [row for row in types if row.get('name') == DEVICES[size]]
    require(len(matching) == 1, 'Exact device type unavailable: ' + DEVICES[size])
    device_type = matching[0]
    require(device_type.get('identifier') == DEVICE_TYPES[size], 'Wrong actual device type identifier')
    runtimes = [row for row in read(folder / 'runtimes.json')['runtimes']
                if row.get('isAvailable') and row.get('identifier', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-26-')]
    require(runtimes, 'An actually available iOS 26 runtime is required')
    reference_runtimes = [row for row in runtimes if row['version'].split('.')[:2] == ['26', '2']]
    runtime = max(reference_runtimes or runtimes,
                  key=lambda row: tuple(int(x) for x in row['version'].split('.')))
    existing = [row for row in read(folder / 'devices.json')['devices'].get(runtime['identifier'], [])
                if row.get('isAvailable') and row.get('deviceTypeIdentifier') == device_type['identifier']]
    if existing:
        device = existing[0]
        udid = device['udid']
    else:
        # Creation failure is fatal, especially for SE3; never substitute a larger phone.
        udid = subprocess.check_output(['xcrun', 'simctl', 'create', 'Noor Mushaf closure ' + size,
                                        device_type['identifier'], runtime['identifier']], text=True).strip()
    require(re.fullmatch(r'[0-9A-Fa-f-]{36}', udid), 'Invalid actual simulator identifier')
    context = {'schemaVersion': 1, 'sourceCommit': (folder / 'source.txt').read_text(encoding='utf-8').strip(),
               'configuration': 'Release', 'project': 'project-accounts.yml', 'displayClass': size,
               'deviceName': device_type['name'], 'deviceTypeIdentifier': device_type['identifier'],
               'deviceUDID': udid, 'runtime': runtime['identifier'], 'runtimeVersion': runtime['version'],
               'priorReferenceRuntimeVersion': '26.2',
               'runtimeMatchesPriorReference': runtime['version'].split('.')[:2] == ['26', '2'],
               'beforeAfterComparison': 'NOT_AUTOMATICALLY_APPROVED',
               'xcode': (folder / 'xcode.txt').read_text(encoding='utf-8').strip(),
               'looks': ['light', 'dark'], 'expectedLanes': lanes(size),
               'expectedTests': {lane: selectors(lane) for lane in lanes(size)},
               'scope': 'SIMULATOR_RELEASE_MUSHAF_ONLY_NOT_ASR_OR_PHYSICAL_DEVICE_OR_FULL_RELEASE_APPROVAL'}
    write(folder / 'context.json', context)
    print(udid)


def record_command(folder, lane, exit_code, deadline):
    path = folder / 'commands.json'
    commands = read(path) if path.is_file() else {}
    require(lane not in commands, 'Command receipt already exists: ' + lane)
    commands[lane] = {'exitCode': exit_code, 'deadlineSeconds': deadline, 'log': lane + '.txt'}
    write(path, commands)


def collect(folder, lane):
    result = folder / (lane + '.xcresult')
    receipt = {'summaryExitCode': None, 'testsExitCode': None, 'attachmentsExitCode': None}
    for kind, command in (
        ('summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)]),
        ('tests', ['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(result)]),
        ('attachments', ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                         '--output-path', str(folder / (lane + '-attachments'))])):
        try:
            process = subprocess.run(command, capture_output=True, timeout=90)
            receipt[kind + 'ExitCode'] = process.returncode
            (folder / (lane + '-' + kind + ('.json' if kind != 'attachments' else '.txt'))).write_bytes(process.stdout)
            (folder / (lane + '-' + kind + '-stderr.txt')).write_bytes(process.stderr)
        except (OSError, subprocess.TimeoutExpired) as error:
            receipt[kind + 'Error'] = type(error).__name__
    path = folder / 'collection.json'
    all_receipts = read(path) if path.is_file() else {}
    all_receipts[lane] = receipt
    write(path, all_receipts)
    return 0 if all(receipt[key] == 0 for key in ('summaryExitCode', 'testsExitCode', 'attachmentsExitCode')) else 1


def capture_log(folder, lane):
    """Preserve stdout verbatim and timestamp observation, never producer success."""
    started = time.monotonic()
    events = []
    with (folder / (lane + '.txt')).open('w', encoding='utf-8', newline='') as log:
        for line in sys.stdin:
            elapsed = time.monotonic() - started
            log.write(line)
            log.flush()
            print(line, end='', flush=True)
            if line.startswith('NOOR_NATIVE_PROCESS '):
                events.append({'kind': 'native-process', 'observerSeconds': elapsed,
                               'process': json.loads(line[len('NOOR_NATIVE_PROCESS '):])})
            elif re.search(r"Test Case '.+' started\.", line):
                events.append({'kind': 'test-start', 'observerSeconds': elapsed})
            else:
                result = re.search(r"Test Case '.+' (passed|failed) \(([\d.]+) seconds\)\.", line)
                if result:
                    events.append({'kind': 'test-end', 'observerSeconds': elapsed,
                                   'result': result[1], 'reportedTestSeconds': float(result[2])})
    write(folder / (lane + '-observations.json'), {
        'schemaVersion': 1, 'lane': lane,
        'sourceLogSHA256': digest(folder / (lane + '.txt')),
        'scope': 'CI_STDOUT_RECEIPT_CLOCK_ONLY_NOT_APP_ANIMATION_OR_ASR_OR_PHYSICAL_DEVICE_LATENCY',
        'events': events})
    return 0


def driver_metrics(folder, lane):
    lines = (folder / (lane + '.txt')).read_text(encoding='utf-8').splitlines()
    opens, turns = [], []
    for line in lines:
        match = re.search(r'\bMUSHAF_UI_DRIVER_OPEN_SECONDS\s+([^\s]+)', line)
        if match:
            value = float(match[1])
            require(math.isfinite(value) and value >= 0, 'Invalid raw driver opening measurement')
            opens.append(value)
        match = re.search(r'\bMUSHAF_UI_DRIVER_TURN\s+target=(\d+)\s+seconds=([^\s]+)', line)
        if match:
            value = float(match[2])
            require(math.isfinite(value) and value >= 0, 'Invalid raw driver turn measurement')
            turns.append({'target': int(match[1]), 'seconds': value})
    observations = read(folder / (lane + '-observations.json'))
    require(observations.get('schemaVersion') == 1 and observations.get('lane') == lane,
            'Missing or stale command observation record')
    require(observations.get('sourceLogSHA256') == digest(folder / (lane + '.txt')),
            'Timing observations do not match the original command log')
    events = observations.get('events')
    require(isinstance(events, list), 'Missing command observation events')
    native_start = [row for row in events if row.get('kind') == 'native-process' and row.get('process', {}).get('event') == 'start']
    native_end = [row for row in events if row.get('kind') == 'native-process' and row.get('process', {}).get('event') == 'end']
    starts = [row for row in events if row.get('kind') == 'test-start']
    ends = [row for row in events if row.get('kind') == 'test-end']
    coverage_errors = []
    if len(native_start) != 1 or len(native_end) != 1:
        coverage_errors.append('Missing actual process clock observations')
    if ui_prefix(lane) and (len(starts) != 1 or len(ends) != 1):
        coverage_errors.append('UI test did not produce one start/end observation')
    for row in events:
        require(type(row.get('observerSeconds')) in (int, float) and math.isfinite(row['observerSeconds'])
                and row['observerSeconds'] >= 0, 'Invalid observed process clock')
    require(all(left['observerSeconds'] <= right['observerSeconds'] for left, right in zip(events, events[1:])),
            'Observed process clock moved backwards')
    result = {'scope': observations.get('scope'), 'lane': lane,
              'nativeProcessSeconds': native_end[0]['process'].get('elapsedSeconds') if len(native_end) == 1 else None,
              'processExitCode': native_end[0]['process'].get('exitCode') if len(native_end) == 1 else None,
              'rawDriverOpenSeconds': opens, 'rawDriverPageTurns': turns,
              'coverageErrors': coverage_errors,
              'physicalDeviceLatency': 'NOT_MEASURED', 'ASRLatency': 'NOT_MEASURED',
              'p95': 'NOT_ESTIMATED_FROM_SPARSE_DRIVER_SAMPLES'}
    if len(starts) == 1 and len(native_start) == 1:
        result['observedStartupSeconds'] = starts[0]['observerSeconds'] - native_start[0]['observerSeconds']
    if len(ends) == 1:
        result['reportedXCTestBodySeconds'] = ends[0].get('reportedTestSeconds')
        result['reportedXCTestResult'] = ends[0].get('result')
    if len(ends) == 1 and len(native_end) == 1:
        result['observedPostTestSeconds'] = native_end[0]['observerSeconds'] - ends[0]['observerSeconds']
    if ui_prefix(lane) == 'journey':
        if len(opens) != 1 or [row['target'] for row in turns] != [15, 16, 15, 14]:
            coverage_errors.append('Core journey did not retain its one opening and four actual page-turn measurements')
    return result


def record_video(folder, look, device):
    start = time.monotonic()
    stop = folder / ('video-' + look + '-stop')
    status = {'look': look, 'deviceUDID': device, 'guardSeconds': 180, 'guardTriggered': False,
              'forcedKill': False, 'started': False, 'microphoneAudioCaptured': False}
    process = None
    interrupted = False

    def interrupt(*_):
        nonlocal interrupted
        interrupted = True

    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    video = folder / ('journey-' + look + '.mp4')
    try:
        require(not video.exists() and not stop.exists(), 'Previous video evidence exists')
        with (folder / ('video-' + look + '.txt')).open('w', encoding='utf-8') as log:
            process = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)],
                                       stdout=log, stderr=log, start_new_session=True)
            status['started'] = True
            while process.poll() is None and not stop.exists() and not interrupted:
                if time.monotonic() - start >= 180:
                    status['guardTriggered'] = True
                    break
                time.sleep(0.2)
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGINT)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    status['forcedKill'] = True
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
    except Exception as error:
        status['errorType'] = type(error).__name__
    finally:
        status.update(exitCode=process.returncode if process else None,
                      elapsedSeconds=time.monotonic() - start,
                      bytes=video.stat().st_size if video.is_file() else 0,
                      interrupted=interrupted, finishRequested=stop.exists())
        write(folder / ('video-' + look + '-status.json'), status)
    return 0 if (status['started'] and not status['guardTriggered'] and not status['forcedKill']
                 and not interrupted and status['exitCode'] in (0, -signal.SIGINT, 128 + signal.SIGINT)
                 and status['finishRequested'] and status['bytes'] > 0) else 1


def native_events(path):
    return [json.loads(line[len('NOOR_NATIVE_PROCESS '):]) for line in path.read_text(encoding='utf-8').splitlines()
            if line.startswith('NOOR_NATIVE_PROCESS ')]


def validate_command(folder, commands, lane, deadline):
    value = commands[lane]
    require(value['exitCode'] == 0, lane + ' command failed or timed out')
    require(value['deadlineSeconds'] == deadline, lane + ' deadline changed')
    events = native_events(folder / value['log'])
    require(len(events) == 2 and [x['event'] for x in events] == ['start', 'end'],
            lane + ' missing original bounded command execution')
    require(events[-1].get('exitCode') == 0 and all(x.get('deadlineSeconds') == deadline for x in events),
            lane + ' actual subprocess did not succeed with its required deadline')
    require(events[0].get('stage') == ('BUILD' if lane == 'build' else 'TEST'), 'Wrong command stage')


def case_nodes(value, parents=()):
    if isinstance(value, list):
        for child in value:
            yield from case_nodes(child, parents)
    elif isinstance(value, dict):
        labels = tuple(str(value[key]) for key in ('name', 'nodeIdentifier', 'testIdentifier', 'testIdentifierString')
                       if isinstance(value.get(key), str))
        path = parents + labels
        if str(value.get('nodeType', '')).replace(' ', '').lower() == 'testcase':
            yield {'path': '/'.join(path), 'result': value.get('result')}
        for key, child in value.items():
            if isinstance(child, (list, dict)):
                yield from case_nodes(child, path)


def validate_tests(folder, lane, expected, collection):
    exported = collection[lane]
    require(all(exported.get(key) == 0 for key in ('summaryExitCode', 'testsExitCode', 'attachmentsExitCode')),
            lane + ' result or attachment export failed')
    summary = read(folder / (lane + '-summary.json'))
    require(summary.get('result') == 'Passed', lane + ' actual xcresult did not pass')
    for key in ('failedTests', 'skippedTests'):
        require(type(summary.get(key)) is int and summary[key] == 0, lane + ' nonzero or absent ' + key)
    passed = summary.get('passedTests')
    require(type(passed) is int and passed > 0, lane + ' zero or absent actual test count')
    require(summary.get('expectedFailures', 0) == 0, lane + ' expected failure is not success')
    actual = list(case_nodes(read(folder / (lane + '-tests.json'))))
    require(len(actual) == passed and all(row['result'] == 'Passed' for row in actual),
            lane + ' test tree is absent, incomplete, skipped or failed')
    require(len(expected) == passed, lane + ' did not execute exactly the requested test methods')
    for selector in expected:
        class_name, method = selector.split('/')
        matches = [row for row in actual if re.search(r'\b' + re.escape(class_name) + r'\b', row['path'])
                   and re.search(r'\b' + re.escape(method) + r'\b', row['path'])]
        require(len(matches) == 1, lane + ' missing or repeated actual case ' + selector)
    return {'passedTests': passed, 'failedTests': 0, 'skippedTests': 0, 'actualSelectors': expected}


def attachment_records(value):
    if isinstance(value, dict):
        if isinstance(value.get('exportedFileName'), str):
            yield value
        for child in value.values():
            yield from attachment_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from attachment_records(child)


def png_info(path):
    from PIL import Image
    with Image.open(path) as image:
        require(image.format == 'PNG', 'Attachment is not an original PNG')
        dimensions = image.size
        image.verify()
    return dimensions


def attachment_index(folder, lane, image_probe=png_info):
    attachments = folder / (lane + '-attachments')
    require(attachments.is_dir(), lane + ' original attachments absent')
    manifests = list(attachments.rglob('manifest.json'))
    require(manifests, lane + ' exported attachment manifest absent')
    output, seen = [], set()
    for manifest in manifests:
        for item in attachment_records(read(manifest)):
            name = item['exportedFileName']
            if Path(name).suffix.lower() != '.png':
                continue
            require(Path(name).name == name, 'Unsafe attachment filename')
            candidates = list(attachments.rglob(name))
            require(len(candidates) == 1, 'Missing or duplicate original PNG: ' + name)
            path = candidates[0]
            require(path.resolve().is_relative_to(attachments.resolve()), 'Attachment escapes evidence folder')
            require(path not in seen, 'Repeated original attachment record')
            seen.add(path)
            width, height = image_probe(path)
            output.append({'lane': lane, 'name': item.get('suggestedHumanReadableName', ''),
                           'file': path.relative_to(folder).as_posix(), 'width': width, 'height': height,
                           'bytes': path.stat().st_size, 'sha256': digest(path), 'visualReview': 'PENDING'})
    require(output, lane + ' zero original PNG screenshots')
    return output


def inspect_video(path):
    import av
    frames, first, last = 0, None, None
    with av.open(str(path)) as container:
        require(len(container.streams.video) == 1, 'Exactly one actual video stream is required')
        stream = container.streams.video[0]
        require(stream.duration is not None and stream.time_base is not None, 'Video duration unavailable')
        duration = float(stream.duration * stream.time_base)
        require(0 < duration <= 180, 'Video missing or exceeds the three-minute guard')
        width, height = stream.codec_context.width, stream.codec_context.height
        for frame in container.decode(stream):
            require(frame.width == width and frame.height == height, 'Video dimensions changed during the journey')
            require(frame.pts is not None and frame.time_base is not None, 'Decoded video frame has no actual clock')
            clock = float(frame.pts * frame.time_base)
            require(last is None or clock >= last, 'Video clock moved backwards')
            first = clock if first is None else first
            last = clock
            frames += 1
    require(frames > 1 and last > first, 'Video has no continuously decoded frames')
    return {'frames': frames, 'durationSeconds': duration, 'width': width, 'height': height,
            'firstFrameSeconds': first, 'lastFrameSeconds': last, 'sha256': digest(path),
            'bytes': path.stat().st_size, 'scope': 'ACTUAL_SIMULATOR_UI_NO_MICROPHONE_AUDIO'}


def validate_video(folder, look, context, display, video_probe=inspect_video):
    status = read(folder / ('video-' + look + '-status.json'))
    require(status.get('started') is True and status.get('guardSeconds') == 180, 'Actual video recorder did not start')
    require(status.get('guardTriggered') is False and status.get('forcedKill') is False
            and status.get('interrupted') is False, 'Video reached guard, was interrupted or forcibly killed')
    require(status.get('finishRequested') is True, 'Recorder ended before the journey requested its stop')
    require(status.get('exitCode') in (0, -signal.SIGINT, 128 + signal.SIGINT), 'Video recorder failed')
    require(status.get('look') == look and status.get('deviceUDID') == context['deviceUDID'], 'Stale/wrong-device video')
    path = folder / ('journey-' + look + '.mp4')
    require(path.is_file() and path.stat().st_size > 0 and path.stat().st_size == status.get('bytes'),
            'Video output absent or truncated after its receipt')
    result = video_probe(path)
    require((result['width'], result['height']) == display, 'Video does not match the actual simulator display')
    command = native_events(folder / ('journey-' + look + '.txt'))
    require(len(command) == 2 and command[-1].get('event') == 'end', 'Journey execution clock missing')
    elapsed = command[-1].get('elapsedSeconds')
    require(type(elapsed) in (int, float) and elapsed > 0, 'Actual journey process duration missing')
    # The recorder starts before the command and stops one second afterwards.
    # Allow only endpoint frame timestamps, never a short introductory clip.
    require(result['durationSeconds'] + 2 >= elapsed, 'Video did not cover the actual bounded journey')
    return result


def contact_sheets(folder, images):
    from PIL import Image, ImageDraw, ImageOps
    pages = sorted((row for row in images if re.search(r'QCF-V2-shaped-page-(\d{3})(?:\b|_)', row['name'])),
                   key=lambda row: row['name'])
    if not pages:
        return []
    output = folder / 'contact-sheets'
    output.mkdir(exist_ok=True)
    names = []
    for offset in range(0, len(pages), 48):
        sheet = Image.new('RGB', (8 * 170, 6 * 305), '#eee9df')
        draw = ImageDraw.Draw(sheet)
        for slot, row in enumerate(pages[offset:offset + 48]):
            with Image.open(folder / row['file']) as original:
                thumbnail = ImageOps.contain(original.convert('RGB'), (160, 274))
                x, y = slot % 8 * 170, slot // 8 * 305
                sheet.paste(thumbnail, (x + (170 - thumbnail.width) // 2, y + 4))
            page = re.search(r'QCF-V2-shaped-page-(\d{3})', row['name'])[1]
            draw.text((x + 8, y + 283), 'Page ' + page, fill='#493522')
        path = output / ('pages-%03d-%03d.jpg' % (offset + 1, min(offset + 48, len(pages))))
        sheet.save(path, quality=95)
        names.append(path.relative_to(folder).as_posix())
    return names


def verify(folder, size, commit, *, make_sheets=False, image_probe=png_info, video_probe=inspect_video):
    folder.mkdir(parents=True, exist_ok=True)
    errors, images, results, videos, metrics = [], [], {}, {}, {}

    def attempt(label, function):
        try:
            return function()
        except Exception as error:
            errors.append(label + ': ' + type(error).__name__ + ': ' + str(error))
            return None

    context = attempt('context', lambda: read(folder / 'context.json')) or {}

    def check_context():
        require(re.fullmatch(r'[0-9a-f]{40}', commit), 'Full exact source commit required')
        require(context.get('sourceCommit') == commit and (folder / 'source.txt').read_text(encoding='utf-8').strip() == commit,
                'Evidence source is stale or unknown')
        require(context.get('displayClass') == size and context.get('deviceName') == DEVICES[size],
                'Wrong display/device; fallback is forbidden')
        require(context.get('deviceTypeIdentifier') == DEVICE_TYPES[size], 'Wrong actual device type identifier')
        booted = [row for row in read(folder / 'actual-booted-devices.json')['devices'].get(context.get('runtime'), [])
                  if row.get('udid') == context.get('deviceUDID')]
        require(len(booted) == 1 and booted[0].get('isAvailable') is True and booted[0].get('state') == 'Booted'
                and booted[0].get('deviceTypeIdentifier') == DEVICE_TYPES[size],
                'Exact requested simulator was not actually available and booted')
        require(context.get('configuration') == 'Release' and context.get('project') == 'project-accounts.yml',
                'Requires actual full-resource Release accounts product')
        require(context.get('runtime', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-26-'), 'Unsupported runtime')
        require(context['runtime'].rsplit('iOS-', 1)[-1].split('-')[:2]
                == str(context.get('runtimeVersion', '')).split('.')[:2], 'Runtime identifier/version mismatch')
        require(context.get('priorReferenceRuntimeVersion') == '26.2'
                and context.get('runtimeMatchesPriorReference') is
                (str(context.get('runtimeVersion', '')).split('.')[:2] == ['26', '2']),
                'Runtime comparison provenance is missing or misleading')
        require(re.match(r'Xcode (?:2[6-9]|[3-9]\d)', context.get('xcode', '')), 'Actual Xcode 26+ required')
        require((folder / 'xcode.txt').read_text(encoding='utf-8').strip() == context.get('xcode'), 'Xcode receipt mismatch')
        require(context.get('looks') == ['light', 'dark'] and context.get('expectedLanes') == lanes(size),
                'Incomplete appearance/test matrix')
        for lane in lanes(size):
            require(context.get('expectedTests', {}).get(lane) == selectors(lane), 'Changed/missing selectors: ' + lane)

    attempt('source and actual device', check_context)
    commands = attempt('commands', lambda: read(folder / 'commands.json')) or {}
    collection = attempt('collection', lambda: read(folder / 'collection.json')) or {}
    attempt('build', lambda: validate_command(folder, commands, 'build', 1200))
    display = attempt('actual display PNG', lambda: image_probe(folder / 'actual-display.png'))
    for lane in lanes(size):
        attempt(lane + ' command', lambda lane=lane: validate_command(folder, commands, lane, 600 if lane == 'geometry' else 180))
        result = attempt(lane + ' xcresult', lambda lane=lane: validate_tests(folder, lane, selectors(lane), collection))
        if result:
            results[lane] = result
        timing = attempt(lane + ' raw timing', lambda lane=lane: driver_metrics(folder, lane))
        if timing:
            metrics[lane] = timing
            errors.extend(lane + ' raw timing: ' + error for error in timing['coverageErrors'])
        captures = attempt(lane + ' screenshots', lambda lane=lane: attachment_index(folder, lane, image_probe)) or []
        images.extend(captures)
        prefix = ui_prefix(lane)
        if prefix:
            required = UI_SHOTS[prefix]
            for name in required:
                matches = [row for row in captures if re.search(r'(?:^|/)' + re.escape(name) + r'(?:\b|_)', row['name'])]
                if len(matches) != 1:
                    errors.append(lane + ': missing/repeated mandatory actual screenshot ' + name)
                elif display and (matches[0]['width'], matches[0]['height']) != display:
                    errors.append(lane + ': screenshot is not the actual full simulator display: ' + name)
    pages = []
    for row in images:
        match = re.search(r'QCF-V2-shaped-page-(\d{3})(?:\b|_)', row['name'])
        if match:
            pages.append(int(match[1]))
            if row['lane'] != 'geometry' or (row['width'], row['height']) != (560, 940):
                errors.append('Baseline production page is not geometry/560x940: ' + row['name'])
    if size == 'medium' and (len(pages) != 604 or set(pages) != set(range(1, 605))):
        errors.append('Expected exactly 604 distinct original QCF-V2-shaped-page-001...604 PNGs')
    for look in ('light', 'dark'):
        appearance = attempt(look + ' actual OS appearance', lambda look=look:
                             (folder / ('appearance-' + look + '.txt')).read_text(encoding='utf-8').strip().lower())
        if appearance != look:
            errors.append(look + ': OS appearance was not confirmed')
        video = attempt(look + ' original video', lambda look=look:
                        validate_video(folder, look, context, display, video_probe))
        if video:
            videos[look] = video
    write(folder / 'attachment-map.json', {'sourceCommit': commit, 'originalPNGCount': len(images),
                                          'baselinePageCount': len(pages), 'images': images,
                                          'visualApproval': 'PENDING_HUMAN_REVIEW'})
    write(folder / 'ui-driver-metrics.json', {'sourceCommit': commit, 'lanes': metrics,
                                             'scope': 'RAW_UI_DRIVER_AND_CI_PROCESS_TIMING_ONLY_NOT_ASR_OR_PHYSICAL_DEVICE_P95'})
    sheets = attempt('contact sheets', lambda: contact_sheets(folder, images)) if make_sheets else []
    report = {'status': 'NATIVE_MUSHAF_EVIDENCE_COMPLETE_REVIEW_PENDING' if not errors else 'FAILED_INCOMPLETE_MUSHAF_EVIDENCE',
              'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'sourceCommit': commit, 'actualContext': context, 'testResults': results,
              'uiDriverMetrics': metrics,
              'originalPNGCount': len(images), 'baselinePageCount': len(pages), 'videos': videos,
              'contactSheets': sheets or [], 'errors': errors, 'visualReview': 'PENDING_HUMAN_REVIEW',
              'runtimeComparison': ('REFERENCE_IOS26_2_AVAILABLE_COMPARISON_STILL_REQUIRES_REVIEW'
                                    if context.get('runtimeMatchesPriorReference') is True else
                                    'DIFFERENT_RUNTIME_NOT_MATCHING_PRIOR_IOS26_2_EVIDENCE'),
              'physicalDeviceTesting': 'NOT_VERIFIED', 'ASRLatency': 'NOT_EVALUATED',
              'learnerAccuracy': 'NOT_EVALUATED', 'fullReleaseApproval': False, 'publicationApproved': False}
    write(folder / 'report.json', report)
    print(json.dumps({'status': report['status'], 'displayClass': size, 'errors': errors,
                      'originalPNGCount': len(images), 'baselinePageCount': len(pages)}, ensure_ascii=False))
    return 0 if not errors else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('select', 'command', 'collect', 'log', 'record', 'verify'))
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--expected-size', choices=tuple(DEVICES))
    parser.add_argument('--expected-commit')
    parser.add_argument('--lane')
    parser.add_argument('--exit-code', type=int)
    parser.add_argument('--deadline', type=int)
    parser.add_argument('--look', choices=('light', 'dark'))
    parser.add_argument('--device')
    parser.add_argument('--contact-sheets', action='store_true')
    args = parser.parse_args()
    if args.operation == 'select':
        require(args.expected_size in DEVICES, 'Exact requested display class required')
        select_device(args.output_dir, args.expected_size)
    elif args.operation == 'command':
        require(args.lane and args.exit_code is not None and args.deadline is not None, 'Command result required')
        record_command(args.output_dir, args.lane, args.exit_code, args.deadline)
    elif args.operation == 'collect':
        require(args.lane, 'Exact lane required')
        return collect(args.output_dir, args.lane)
    elif args.operation == 'log':
        require(args.lane, 'Exact lane required')
        return capture_log(args.output_dir, args.lane)
    elif args.operation == 'record':
        require(args.look and args.device, 'Appearance and actual device required')
        return record_video(args.output_dir, args.look, args.device)
    else:
        require(args.expected_size in DEVICES and args.expected_commit, 'Size and full source required')
        return verify(args.output_dir, args.expected_size, args.expected_commit, make_sheets=args.contact_sheets)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

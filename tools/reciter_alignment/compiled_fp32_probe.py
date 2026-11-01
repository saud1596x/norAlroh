"""Nonshipping comparison of the exact prepared app FP32 CTC on macOS.

No conversion, expected-text prompt, learner audio, app build or shipping
configuration change. Pure validators import without Core ML. Only `profile`
loads a real CompiledMLModel; `compare` requires its preserved logits/receipts.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import unicodedata

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
REVISION = 'b539d5fa66deb820c8e4762171ecb284ace4b52d'
GRAPH_SHA = 'a03be761fad1c1da230d0c3522ae3be7e20523147603d219751ad2abaaced5d7'
CONVERTED_WEIGHTS_SHA = 'bb4a2ffd5eb4082d8383c721887294886594ba77ec0d4611b38ea1796e231833'
SOURCE_WEIGHTS_SHA = '202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf'
VOCAB_SHA = '60b9e6174798b6e1a92c92fb5935e32522aebaca4cdd1f481fd220346471644c'
FIXTURE_MANIFEST_SHA = '051a944853f37b7556c49edf08160f1598f3a4cb9255f703b0e090fc16c66b3b'
VERIFICATION_SCOPE = '26fixed public/prefix/negative conversion cases; NOT natural learner or hardware acceptance'
SCOPE = 'NONSHIPPING_COMPILED_APP_FP32_MAC_COMPUTE_COMPARISON_NOT_IPHONE_OR_LEARNER_ACCEPTANCE'
COMPUTES = ('CPU_ONLY', 'CPU_AND_GPU')
POSTERIOR_ATOL = 1e-5  # Fixed strict experiment comparator, never an app threshold.
HEX = re.compile(r'[0-9a-f]{64}\Z')


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''): value.update(chunk)
    return value.hexdigest()


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def safe_relative(name):
    if (not isinstance(name, str) or not name or '\\' in name or ':' in name or '\0' in name
            or any(part in ('', '.', '..') for part in name.split('/'))):
        raise ValueError('Unsafe asset path')


def inventory(folder):
    folder = Path(folder)
    if folder.is_symlink() or not folder.is_dir(): raise ValueError('Missing/linked assets directory')
    result = {}; total = 0
    for item in sorted(folder.rglob('*')):
        if item.is_symlink() or not item.resolve().is_relative_to(folder.resolve()): raise ValueError('Linked/escaping asset')
        if item.is_dir(): continue
        if not item.is_file(): raise ValueError('Nonregular asset')
        name = item.relative_to(folder).as_posix(); safe_relative(name)
        if name == 'verified-model.json': continue
        total += item.stat().st_size
        if len(result) >= 128 or total > 2_000_000_000: raise ValueError('Unbounded asset inventory')
        result[name] = digest(item)
    return result


def validate_descriptor(document, actual, compiler):
    required = {'schema', 'revision', 'precision', 'compiler', 'sourceWeightsSHA256',
                'convertedWeightsSHA256', 'sourceSpecSHA256', 'verificationScope', 'files'}
    if not isinstance(document, dict) or set(document) != required: raise ValueError('Descriptor schema differs')
    expected = dict(schema=1, revision=REVISION, precision='float32', compiler=compiler,
                    sourceWeightsSHA256=SOURCE_WEIGHTS_SHA, convertedWeightsSHA256=CONVERTED_WEIGHTS_SHA,
                    sourceSpecSHA256=GRAPH_SHA, verificationScope=VERIFICATION_SCOPE)
    if type(document['schema']) is not int or not compiler or any(document[key] != value for key, value in expected.items()):
        raise ValueError('Unapproved FP32 source, precision or compiler')
    files = document['files']
    if not isinstance(files, dict) or not 3 <= len(files) <= 128: raise ValueError('Invalid descriptor inventory')
    for name, value in files.items():
        safe_relative(name)
        if not isinstance(value, str) or not HEX.fullmatch(value): raise ValueError('Invalid asset digest')
    if (files != actual or files.get('vocab.json') != VOCAB_SHA or 'NOTICE.txt' not in files
            or not any(name.startswith('quran-ctc.mlmodelc/') for name in files)):
        raise ValueError('Compiled inventory/vocabulary differs')


def verify_assets(folder, source_package, compiler):
    # The compiler's mutable descriptor is not authority to replace source.
    # Reuse the existing reviewed source verifier, with its actual byte pins.
    sys.path.insert(0, str(ROOT / 'scripts'))
    from importlib import import_module
    prepare = import_module('prepare-independent-ctc')
    prepare.verify_source(Path(source_package))
    descriptor = Path(folder) / 'verified-model.json'
    if descriptor.is_symlink() or not descriptor.is_file() or descriptor.stat().st_size > 64_000:
        raise ValueError('Missing/linked/unbounded prepared descriptor')
    document = json.loads(descriptor.read_text(encoding='utf-8'))
    actual = inventory(folder)
    validate_descriptor(document, actual, compiler)
    return {'descriptorSHA256': digest(descriptor), 'inventorySHA256': canonical_hash(actual),
            'files': actual, 'sourceSpecSHA256': GRAPH_SHA, 'convertedWeightsSHA256': CONVERTED_WEIGHTS_SHA,
            'sourceWeightsSHA256': SOURCE_WEIGHTS_SHA, 'vocabularySHA256': VOCAB_SHA, 'compiler': compiler}


def validate_pcm(pcm):
    if (not isinstance(pcm, np.ndarray) or pcm.dtype != np.dtype('float32') or pcm.ndim != 1
            or not 400 <= len(pcm) <= 256000 or not np.isfinite(pcm).all() or np.any(np.abs(pcm) > 1)):
        raise ValueError('Expected unchanged bounded finite Float32 mono PCM')


def condition_pcm(pcm):
    validate_pcm(pcm)
    # Match QuranIndependentCTC's sequential Double accumulation and Float
    # output, rather than numpy's Float32/pairwise reduction. Never alter raw PCM.
    # QuranRecognitionWorker conditions a separate copy for Whisper, but passes
    # the ORIGINAL window into QuranIndependentCTC.recognize(window). Applying
    # its gain/DC removal here would benchmark a different CTC input contract.
    total = 0.0
    for value in pcm: total += float(value)
    mean = total / len(pcm); variance = 0.0
    for value in pcm: variance += math.pow(float(value) - mean, 2)
    divisor = math.sqrt(variance / len(pcm) + 1e-7)
    return np.array([(float(value) - mean) / divisor for value in pcm], dtype=np.float32)[None]


def validate_logits(logits, samples):
    if (type(samples) is not int or not 400 <= samples <= 256000 or not isinstance(logits, np.ndarray)
            or logits.dtype != np.dtype('float32') or logits.shape != (1, (samples - 400) // 320 + 1, 56)
            or not np.isfinite(logits).all()): raise ValueError('Invalid FP32 logits/native frame clock')


def normalized_character(value):
    value = unicodedata.normalize('NFKD', value.replace('ٱ', 'ا'))
    return ''.join(c for c in value if unicodedata.category(c).startswith('L') and c not in 'ـۥۦ')


def decode_logits(logits, samples, vocab):
    validate_logits(logits, samples)
    if (len(vocab) != 56 or set(vocab.values()) != set(range(56)) or vocab.get('<pad>') != 0 or vocab.get('|') != 4):
        raise ValueError('Changed source vocabulary')
    letters = sorted({normalized_character(c) for c in vocab if len(c) == 1 and c != '|' and normalized_character(c)})
    characters = ['', ' '] + letters
    indices = {c: i for i, c in enumerate(characters)}
    projection = [0] * 56
    for c, index in vocab.items(): projection[index] = 1 if c == '|' else indices.get(normalized_character(c), 0) if len(c) == 1 else 0
    posteriors = []; labels = []; symbols = []; previous = 0
    for frame, raw in enumerate(logits[0]):
        scores = [float(value) for value in raw]; peak = max(scores)
        exponentials = [math.exp(value - peak) for value in scores]; total = sum(exponentials)
        projected = [0.0] * len(characters)
        for label in range(56): projected[projection[label]] += exponentials[label] / total
        label = max(range(len(characters)), key=lambda i: projected[i])
        labels.append(label); posteriors.append(projected)
        if label != 0:
            if label == previous and symbols:
                symbols[-1][2] = frame + 1; symbols[-1][3] += projected[label]; symbols[-1][4] += 1
            else: symbols.append([label, frame, frame + 1, projected[label], 1])
        previous = label
    words = []; text = ''; first = end = count = 0; posterior_sum = 0.0
    def finish():
        nonlocal text, count, posterior_sum
        if text and count:
            words.append(dict(text=text, startFrame=first * 320, endFrame=end * 320,
                              meanPosterior=posterior_sum / count))
        text = ''; count = 0; posterior_sum = 0.0
    for label, start, stop, posterior, length in symbols:
        if label == 1: finish(); continue
        if not text: first = start
        text += characters[label]; end = stop; posterior_sum += posterior; count += length
    finish()
    return dict(shape=list(logits.shape), frameLabels=labels, rawWords=[w['text'] for w in words], words=words), np.asarray(posteriors, dtype=np.float64)


def validate_parity(left, right, first, second):
    if (not isinstance(first, np.ndarray) or not isinstance(second, np.ndarray)
            or first.ndim != 2 or second.ndim != 2): raise ValueError('Missing posterior matrices')
    for key in ('id', 'samples', 'startFrame', 'endFrame', 'rawPCM_SHA256', 'conditionedSHA256', 'shape', 'frameLabels', 'rawWords'):
        if key not in left or key not in right or left[key] != right[key]: raise ValueError('Parity drift: ' + key)
    n = left['samples']
    if (type(n) is not int or not 400 <= n <= 256000
            or any(type(row[key]) is not int for row in (left, right) for key in ('startFrame', 'endFrame'))
            or any(type(v) is not int for row in (left, right) for v in row['shape'])
            or left['startFrame'] != 0 or left['endFrame'] != n
            or left['shape'] != [1, (n - 400) // 320 + 1, 56]
            or len(left['frameLabels']) != left['shape'][1]): raise ValueError('Invalid parity frame contract')
    for row in (left, right):
        if (any(not isinstance(row[key], str) or not HEX.fullmatch(row[key]) for key in ('rawPCM_SHA256', 'conditionedSHA256'))
                or any(type(label) is not int or not 0 <= label < first.shape[1] for label in row['frameLabels'])
                or row['rawWords'] != [word['text'] for word in row['words']]): raise ValueError('Invalid parity source/label contract')
    if (first.shape != second.shape or first.ndim != 2 or first.shape[0] != left['shape'][1]
            or not np.isfinite(first).all() or not np.isfinite(second).all()
            or np.any(first < 0) or np.any(first > 1) or np.any(second < 0) or np.any(second > 1)
            or not np.allclose(first.sum(axis=1), 1, rtol=0, atol=1e-12)
            or not np.allclose(second.sum(axis=1), 1, rtol=0, atol=1e-12)
            or first.argmax(axis=1).tolist() != left['frameLabels'] or second.argmax(axis=1).tolist() != right['frameLabels']
            or not np.allclose(first, second, rtol=0, atol=POSTERIOR_ATOL)):
        raise ValueError('Posterior parity exceeds fixed1e-5 tolerance')
    if len(left['words']) != len(right['words']): raise ValueError('Word count drift')
    for a, b in zip(left['words'], right['words']):
        if (any(a[k] != b[k] for k in ('text', 'startFrame', 'endFrame'))
                or type(a['startFrame']) is not int or type(a['endFrame']) is not int
                or type(b['startFrame']) is not int or type(b['endFrame']) is not int
                or not 0 <= a['startFrame'] < a['endFrame'] <= n
                or a['startFrame'] % 320 or a['endFrame'] % 320
                or type(a['meanPosterior']) not in (int, float) or type(b['meanPosterior']) not in (int, float)
                or not math.isfinite(a['meanPosterior']) or not math.isfinite(b['meanPosterior'])
                or not 0 <= a['meanPosterior'] <= 1 or not 0 <= b['meanPosterior'] <= 1
                or abs(a['meanPosterior'] - b['meanPosterior']) > POSTERIOR_ATOL):
            raise ValueError('Native word interval/posterior drift')
    return float(np.max(np.abs(first - second)))


def fixture_sources():
    manifest = ROOT / 'tools/RecitationEngineProbe/fixtures/sources.json'
    if digest(manifest) != FIXTURE_MANIFEST_SHA: raise ValueError('Public fixture manifest changed')
    sources = json.loads(manifest.read_text(encoding='utf-8'))
    sources.append(dict(file='002001.mp3', sha256='48077d6641b2403e04c15585b0ede3b8eb3a3c354ae4d8d6f6a4882dc8106ebb',
                        url='https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/002001.mp3'))
    return sources


def verify_fixtures(folder):
    sources = fixture_sources()
    for source in sources:
        path = Path(folder) / source['file']
        if (not re.fullmatch(r'\d{6}\.mp3', source['file']) or path.is_symlink() or not path.is_file()
                or digest(path) != source['sha256'] or source['url'] != 'https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/' + source['file']):
            raise ValueError('Public fixture source differs')
    return {row['file']: row['sha256'] for row in sources}


def fixture_cases(folder):
    from export_coreml import load_pcm  # Apple decoder only; no convert/main/model construction.
    sources = fixture_sources(); verify_fixtures(folder)
    cases = []; signals = {}
    for source in sources:
        path = Path(folder) / source['file']
        if (not re.fullmatch(r'\d{6}\.mp3', source['file']) or path.is_symlink() or not path.is_file()
                or digest(path) != source['sha256'] or source['url'] != 'https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/' + source['file']):
            raise ValueError('Public fixture source differs')
        raw = load_pcm(path); validate_pcm(raw); signals[source['file']] = raw
        pins = {source['file']: source['sha256']}
        for gain in (1.0, .03):
            cases.append((f"{source['file']}/gain={gain}", np.asarray(raw * np.float32(gain), dtype=np.float32), pins, False))
        if source['file'] in ('001002.mp3', '002001.mp3'):
            cases.append((source['file'] + '/first2s', raw[:32000].copy(), pins, False))
    cases.extend([('negative/silence', np.zeros(16000, dtype=np.float32), {}, True),
                  ('negative/noise-seed14', np.random.default_rng(14).normal(0, .001, 16000).astype(np.float32), {}, True)])
    if len(cases) != 26: raise ValueError('Expected original26 public/prefix/gain/negative cases')
    continuous = np.concatenate([signals['112001.mp3'], signals['114001.mp3']])
    if len(continuous) < 128000: raise ValueError('Insufficient real continuous reference PCM')
    pins = {row['file']: row['sha256'] for row in sources if row['file'] in ('112001.mp3', '114001.mp3')}
    for n in (32000, 66155, 128000):
        for repeat in range(3): cases.append((f'continuous-prefix/{n}/warm={repeat}', continuous[:n].copy(), pins, False))
    return cases


def command(arguments):
    return subprocess.check_output(arguments, text=True, timeout=30, stderr=subprocess.STDOUT).strip()


def environment():
    return dict(source=command(['git', 'rev-parse', 'HEAD']), architecture=platform.machine(),
                macOS=platform.mac_ver()[0], macOSBuild=command(['sw_vers', '-buildVersion']),
                xcode=command(['xcodebuild', '-version']), sdk=command(['xcrun', '--sdk', 'macosx', '--show-sdk-version']),
                python=platform.python_version(), numpy=np.__version__, probeSHA256=digest(__file__),
                nativeWorkerSHA256=digest(ROOT / 'ios/Athar/QuranIndependentCTC.swift'),
                pairedWorkerSHA256=digest(ROOT / 'ios/Athar/QuranRecognitionWorker.swift'),
                primaryConditionerSHA256=digest(ROOT / 'ios/Athar/QuranRecognitionAudio.swift'),
                preparerSHA256=digest(ROOT / 'scripts/prepare-independent-ctc.py'),
                runID=os.environ.get('GITHUB_RUN_ID'), runAttempt=os.environ.get('GITHUB_RUN_ATTEMPT'))


def save(path, document):
    Path(path).write_text(json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def profile(args):
    out = args.output_dir
    out.mkdir(parents=True, exist_ok=False)
    report = dict(schema=1, scope=SCOPE, status='STARTED', computeUnits=args.compute, processID=os.getpid(),
                  gpuExecutionProven=False, cacheScope='First process load; OS/Metal/filesystem caches NOT purged',
                  inputContract='Original captured window -> independent CTC Double normalization -> Float32; primary Whisper gain/DC copy is separate',
                  postdecodeImplementation='Python mirror of native frame/word math; NOT Swift wall-time',
                  warmScope='After26casepass; repeat0 may be first specialization of that input shape',
                  startedAtUTC=datetime.now(timezone.utc).isoformat(), cases=[], errors=[])
    save(out / 'profile.json', report)
    compiler = None; before = None
    try:
        if platform.system() != 'Darwin': raise ValueError('Actual macOS Core ML is required')
        import coremltools as ct
        import resource
        report['environment'] = environment(); compiler = report['environment']['xcode']
        report['environment']['coremltools'] = ct.__version__
        if sys.version_info[:2] != (3, 11) or np.__version__ != '2.1.3' or ct.__version__ != '9.0':
            raise ValueError('Use the existing pinned Python3.11/CoreML9/numpy2.1.3 runtime')
        stage = time.perf_counter_ns()
        before = verify_assets(args.assets_dir, args.source_package, compiler)
        report['assetsBefore'] = before; report['verificationMs'] = (time.perf_counter_ns() - stage) / 1e6
        vocab = json.loads((args.assets_dir / 'vocab.json').read_text(encoding='utf-8'))
        report['fixturesBefore'] = verify_fixtures(args.fixtures)
        cases = fixture_cases(args.fixtures)
        report['plan'] = [dict(id=name, samples=len(pcm), sourceFiles=pins, negativeControl=negative,
                               rawPCM_SHA256=hashlib.sha256(pcm.tobytes()).hexdigest()) for name, pcm, pins, negative in cases]
        save(out / 'profile.json', report)
        stage = time.perf_counter_ns()
        # Prepared compiled app bytes only. There is no package/precision fallback.
        model = ct.models.CompiledMLModel(str(args.assets_dir / 'quran-ctc.mlmodelc'), compute_units=getattr(ct.ComputeUnit, args.compute))
        report['modelLoadMs'] = (time.perf_counter_ns() - stage) / 1e6
        for index, (name, pcm, pins, negative) in enumerate(cases):
            try:
                started = time.perf_counter_ns(); conditioned = condition_pcm(pcm); ready = time.perf_counter_ns()
                logits = np.asarray(model.predict({'input_values': conditioned})['logits']); predicted = time.perf_counter_ns()
                decoded, _ = decode_logits(logits, len(pcm), vocab); decoded_at = time.perf_counter_ns()
                raw_sha = hashlib.sha256(pcm.tobytes()).hexdigest()
                input_sha = hashlib.sha256(conditioned.tobytes()).hexdigest(); hashed_at = time.perf_counter_ns()
                filename = f'logits-{index:02d}.npy'; np.save(out / filename, logits, allow_pickle=False)
                row = dict(id=name, samples=len(pcm), startFrame=0, endFrame=len(pcm), sourceFiles=pins,
                           negativeControl=negative, rawPCM_SHA256=raw_sha, conditionedSHA256=input_sha,
                           logitsFile=filename, logitsSHA256=digest(out / filename), **decoded,
                           timingsMs=dict(normalizationInput=(ready-started)/1e6, prediction=(predicted-ready)/1e6,
                                          pythonPostdecode=(decoded_at-predicted)/1e6, sourceAndConditionedSHA=(hashed_at-decoded_at)/1e6,
                                          total=(hashed_at-started)/1e6))
                report['cases'].append(row)
                if negative and row['rawWords']: report['errors'].append(name + ': negative control produced words')
                print(f'COMPILED_FP32_CASE index={index} samples={len(pcm)} predictionMs={row["timingsMs"]["prediction"]:.6f}', flush=True)
            except Exception as error:
                report['errors'].append(f'{name}: {type(error).__name__}: {error}')
            save(out / 'profile.json', report)
        report['peakRSSBytes'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        if len(report['cases']) != 35: report['errors'].append('Incomplete35case benchmark')
        report['status'] = 'INFERENCE_COMPLETED' if not report['errors'] else 'FAILED'
    except Exception as error:
        report['status'] = 'FAILED'; report['errors'].append(f'{type(error).__name__}: {error}')
    finally:
        if compiler is not None:
            try:
                after = verify_assets(args.assets_dir, args.source_package, compiler)
                report['assetsAfter'] = after
                if before is None or before != after: report['errors'].append('Prepared assets changed during profile')
                report['fixturesAfter'] = verify_fixtures(args.fixtures)
                if report.get('fixturesBefore') != report['fixturesAfter']: report['errors'].append('Public fixtures changed during profile')
            except Exception as error: report['errors'].append('Final asset verification: ' + str(error))
        if report['errors']: report['status'] = 'FAILED'
        report['endedAtUTC'] = datetime.now(timezone.utc).isoformat()
        save(out / 'profile.json', report)
    return 0 if report['status'] == 'INFERENCE_COMPLETED' else 1


def load_logits(folder, row):
    name = row['logitsFile']; safe_relative(name)
    if '/' in name: raise ValueError('Unexpected logits subdirectory')
    path = Path(folder) / name
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1_000_000 or digest(path) != row['logitsSHA256']:
        raise ValueError('Preserved logits changed/missing/unbounded')
    values = np.load(path, allow_pickle=False, mmap_mode='r'); validate_logits(values, row['samples'])
    return values


def compare(args):
    if args.output.exists(): raise ValueError('Refusing to overwrite comparison')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = dict(schema=1, scope=SCOPE, status='FAILED', gpuExecutionProven=False,
                  posteriorAbsoluteTolerance=POSTERIOR_ATOL, cases=[], errors=[])
    try:
        a = json.loads((args.baseline / 'profile.json').read_text(encoding='utf-8'))
        b = json.loads((args.candidate / 'profile.json').read_text(encoding='utf-8'))
        for value, unit in ((a, 'CPU_ONLY'), (b, 'CPU_AND_GPU')):
            if (type(value.get('schema')) is not int or value.get('schema') != 1 or value.get('scope') != SCOPE or value.get('status') != 'INFERENCE_COMPLETED'
                    or value.get('computeUnits') != unit or value.get('gpuExecutionProven') is not False
                    or value.get('errors') or len(value.get('cases', [])) != 35
                    or value.get('assetsBefore') != value.get('assetsAfter')
                    or value.get('fixturesBefore') != value.get('fixturesAfter')): raise ValueError('Incomplete/failed/changed profile')
            if (type(value.get('modelLoadMs')) not in (int, float) or not math.isfinite(value['modelLoadMs'])
                    or value['modelLoadMs'] <= 0): raise ValueError('Invalid actual model load timing')
        for key in ('environment', 'assetsBefore', 'fixturesBefore', 'plan'):
            if a[key] != b[key]: raise ValueError('Different source/runtime/inputs: ' + key)
        if any(type(v.get('processID')) is not int or v['processID'] <= 0 for v in (a, b)) or a['processID'] == b['processID']:
            raise ValueError('Expected two distinct actual compute processes')
        if a['environment']['source'] != args.expected_source: raise ValueError('Wrong expected source commit')
        if len(a['plan']) != 35 or len({r['id'] for r in a['plan']}) != 35: raise ValueError('Invalid35case plan')
        vocab = json.loads((ROOT / 'content-sources/independent-ctc-vocab.json').read_text(encoding='utf-8'))
        if digest(ROOT / 'content-sources/independent-ctc-vocab.json') != VOCAB_SHA: raise ValueError('Changed comparison vocabulary')
        for index, (left, right) in enumerate(zip(a['cases'], b['cases'])):
            outcome = dict(index=index, id=left.get('id'), parity=False)
            try:
                for row in (left, right):
                    plan = a['plan'][index]
                    if any(row[key] != plan[key] for key in ('id', 'samples', 'sourceFiles', 'negativeControl', 'rawPCM_SHA256')):
                        raise ValueError('Case no longer matches original input plan')
                    timings = row['timingsMs']
                    if (set(timings) != {'normalizationInput', 'prediction', 'pythonPostdecode', 'sourceAndConditionedSHA', 'total'}
                            or any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in timings.values())
                            or not math.isclose(sum(v for k, v in timings.items() if k != 'total'), timings['total'], abs_tol=1e-3)):
                        raise ValueError('Invalid measured stage timings')
                x = load_logits(args.baseline, left); y = load_logits(args.candidate, right)
                dx, px = decode_logits(x, left['samples'], vocab); dy, py = decode_logits(y, right['samples'], vocab)
                outcome.update(rawWordParity=dx['rawWords'] == dy['rawWords'], frameLabelParity=dx['frameLabels'] == dy['frameLabels'],
                               nativeWordClockParity=[(w['text'], w['startFrame'], w['endFrame']) for w in dx['words']]
                                   == [(w['text'], w['startFrame'], w['endFrame']) for w in dy['words']],
                               maxPosteriorDifference=float(np.max(np.abs(px-py))) if px.shape == py.shape else None,
                               cpuPredictionMs=left['timingsMs']['prediction'], gpuAllowedPredictionMs=right['timingsMs']['prediction'])
                for row, decoded in ((left, dx), (right, dy)):
                    if any(row[key] != decoded[key] for key in decoded): raise ValueError('Saved decode differs from actual preserved logits')
                    if row['negativeControl'] and row['rawWords']: raise ValueError('Negative control decoded words')
                difference = validate_parity(left, right, px, py)
                outcome.update(parity=True, maxPosteriorDifference=difference)
            except Exception as error:
                outcome['error'] = str(error); report['errors'].append(f'case{index}: {error}')
            finally: report['cases'].append(outcome)
        report['profileSHA256'] = {'CPU_ONLY': digest(args.baseline / 'profile.json'), 'CPU_AND_GPU': digest(args.candidate / 'profile.json')}
        report['modelLoadMs'] = {'CPU_ONLY': a['modelLoadMs'], 'CPU_AND_GPU': b['modelLoadMs']}
        report['environment'] = a['environment']; report['assetIdentity'] = a['assetsBefore']
        if len(report['cases']) == 35 and not report['errors']: report['status'] = 'STRICT_COMPUTE_PARITY_PASSED_NOT_PRODUCTION_APPROVAL'
    except Exception as error: report['errors'].append(f'{type(error).__name__}: {error}')
    finally: save(args.output, report)
    return 1 if report['errors'] else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('profile', 'verify-assets'):
        command_parser = sub.add_parser(name)
        command_parser.add_argument('--assets-dir', type=Path, required=True)
        command_parser.add_argument('--source-package', type=Path, required=True)
        if name == 'profile':
            command_parser.add_argument('--fixtures', type=Path, required=True)
            command_parser.add_argument('--compute', choices=COMPUTES, required=True)
            command_parser.add_argument('--output-dir', type=Path, required=True)
    comparator = sub.add_parser('compare')
    comparator.add_argument('--baseline', type=Path, required=True)
    comparator.add_argument('--candidate', type=Path, required=True)
    comparator.add_argument('--expected-source', required=True)
    comparator.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'profile': return profile(args)
    if args.command == 'compare': return compare(args)
    verify_assets(args.assets_dir, args.source_package, command(['xcodebuild', '-version']))
    return 0


if __name__ == '__main__': sys.exit(main())

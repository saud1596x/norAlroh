"""Recording-specific audit receipts; candidates never imply playback approval."""
import hashlib
import json
from pathlib import Path

SCHEMA = 3
CONTROL_NAMES = {'silence', 'noise', 'wrong-known-text'}
AYAH_POLICY = 'Exact publisher recording boundaries with400ms acoustic context; no interpolation'


def fingerprint(root):
    paths = [
        'content-sources/recitation-word-script.json', 'content-sources/mushaf-snapshot.json.gz',
        'ios/Athar/quran.json', 'ios/Athar/haramain-reciters.json',
        'ios/Athar/surah-ayah-timings.json',
        *[f'tools/reciter_alignment/{name}.py' for name in
          ('ctc', 'quran_ctc', 'quran_onnx', 'stream_audio', 'verify_catalog', 'run_library', 'audit')],
    ]
    hashes = {name: hashlib.sha256((Path(root)/name).read_bytes()).hexdigest() for name in paths}
    digest = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    return {'sha256': digest, 'files': hashes}


def controls_passed(report):
    controls = report.get('controls', [])
    return (len(controls) == 3 and {c.get('name') for c in controls} == CONTROL_NAMES
            and all(c.get('rejected') is True for c in controls))


def compatible(report, inputs, surah, catalog, runtime=None):
    from quran_ctc import REVISION
    return (report.get('auditSchema') == SCHEMA
            and report.get('inputFingerprint') == inputs
            and report.get('modelRevision') == REVISION
            and report.get('ayahWindowPolicy') == AYAH_POLICY
            and isinstance(report.get('inferenceRuntime'), str) and bool(report['inferenceRuntime'])
            and (runtime is None or report['inferenceRuntime'] == runtime)
            and report.get('surah') == surah
            and report.get('selectedReciterIDs') == [r['id'] for r in catalog])


def exact_record(record, reciter, surah):
    return (record.get('reciterID') == reciter['id']
            and record.get('recordingID') == reciter['recordingID']
            and record.get('audioURL') == reciter['server'] + f'{surah:03}.mp3'
            and isinstance(record.get('audioSHA256'), str)
            and len(record['audioSHA256']) == 64)


def complete_report(report, inputs, surah, catalog, runtime=None):
    records = report.get('records', [])
    return (compatible(report, inputs, surah, catalog, runtime) and controls_passed(report)
            and len(records) == len(catalog)
            and all(exact_record(record, reciter, surah)
                    and record.get('status') in ('MEASURED_CANDIDATE_REQUIRES_REVIEW', 'REJECTED')
                    for record, reciter in zip(records, catalog)))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    temporary.replace(path)


def archive_report(path):
    """Keep exact prior bytes before a retry; never rewrite a prior receipt."""
    path = Path(path)
    if not path.exists():
        return
    if path.is_symlink():
        raise ValueError('Linked timing receipt')
    content = path.read_bytes()
    history = path.parent / 'report-history'
    if history.is_symlink():
        raise ValueError('Linked timing receipt history')
    history.mkdir(exist_ok=True)
    destination = history / (hashlib.sha256(content).hexdigest() + '.json')
    if destination.is_symlink():
        raise ValueError('Linked archived timing receipt')
    if destination.exists():
        if destination.read_bytes() != content:
            raise ValueError('Timing receipt archive differs')
        return
    destination.write_bytes(content)


def fetch_failure_record(previous, reciter, surah, status, reason):
    """A failed refetch cannot erase previously measured source intervals.

    The caller must already have checked the complete policy/runtime fingerprint.
    This records a failed check, not a newly measured or revalidated recording.
    """
    failure = {'status': status, 'reason': reason}
    if (previous is not None and exact_record(previous, reciter, surah)
            and (previous.get('spans') or previous.get('ayahResults'))):
        return {**previous, 'lastSourceCheck': failure}
    return {'reciterID': reciter['id'], 'recordingID': reciter['recordingID'],
            'audioURL': reciter['server'] + f'{surah:03}.mp3', **failure}


def library_coverage(root, directories):
    """Always enumerate all114 x catalog readers, including absent reports."""
    root = Path(root)
    catalog = json.loads((root/'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']
    current = fingerprint(root)
    reports = {}
    for directory in directories:
        for path in Path(directory).glob('*/report.json'):
            report = json.loads(path.read_text(encoding='utf-8'))
            surah = report.get('surah')
            if not isinstance(surah, int) or not 1 <= surah <= 114:
                continue
            current_policy = compatible(report, current, surah, catalog)
            for record in report.get('records', []):
                reciter = next((r for r in catalog if r['id'] == record.get('reciterID')), None)
                if reciter is None or not exact_record(record, reciter, surah):
                    continue
                key = (reciter['id'], surah)
                value = {'status': record.get('status', 'NOT_ASSESSED'),
                         'currentPolicy': current_policy,
                         'controlsPassed': controls_passed(report),
                         'inferenceRuntime': report.get('inferenceRuntime'),
                         'audioSHA256': record['audioSHA256'], 'report': str(path),
                         'reportSHA256': hashlib.sha256(path.read_bytes()).hexdigest()}
                previous = reports.get(key)
                # An old-policy candidate must not hide a current-policy rejection.
                if previous is None or current_policy or not previous['currentPolicy']:
                    reports[key] = value
    rows = []
    for reciter in catalog:
        tracks = []
        for surah in range(1, 115):
            evidence = reports.get((reciter['id'], surah), {'status': 'NOT_ASSESSED', 'currentPolicy': False})
            tracks.append({'surah': surah, **evidence,
                           'productionWordTrackingVerified': False})
        rows.append({'reciterID': reciter['id'], 'name': reciter['name'],
                     'recordingID': reciter['recordingID'], 'server': reciter['server'],
                     'tracks': tracks})
    tracks = [t for r in rows for t in r['tracks']]
    return {'auditSchema': SCHEMA, 'scope': 'ALL_CATALOG_READERS_ALL_114_SURAHS',
            'inputFingerprint': current, 'expectedRecordings': len(tracks),
            'observedRecordings': sum(t['status'] != 'NOT_ASSESSED' for t in tracks),
            'currentPolicyCandidates': sum(t['currentPolicy'] and t.get('controlsPassed') is True
                and t['status'] == 'MEASURED_CANDIDATE_REQUIRES_REVIEW' for t in tracks),
            'legacyCandidatesRequireRecheck': sum(not t['currentPolicy']
                and t['status'] == 'MEASURED_CANDIDATE_REQUIRES_REVIEW' for t in tracks),
            'verifiedWholeRecordings': 0, 'humanAcousticReview': 'NOT_RUN',
            'appIntegrationOfTheseCandidates': 'NOT_IMPLEMENTED', 'readers': rows}

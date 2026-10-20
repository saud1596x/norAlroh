"""Pinned inputs and output contract for a screening run, not an accuracy claim."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODEL = 'mohammed/fastconformer-quran-ar'
REVISION = '60973918b40c5fcdc0e93310c13a4a4661525142'
ARCHIVE = 'phase3_full/phase3_full_wer0.0014.nemo'
ARCHIVE_SHA = 'dc3557eea22b25ab5c7af2d8cf01636efd415c4ed417418156e5895056c705d5'
CONFIG_SHA = 'ac55ebbb48ae9c69f12ab7f72e8c0678a26d91d06770b3cc5073dfce4ce5a437'
SCOPE = 'OFFLINE_FP32_SOURCE_SCREENING_NOT_STREAMING_OR_LEARNER_OR_IPHONE_ACCEPTANCE'
COMPLETE = 'COMPLETE_SCREENING_ONLY'
MARKER = 'ACTUAL_SOURCE_CTC '
END_MARKER = 'SOURCE_SCREENING_COMPLETE_NOT_MODEL_OR_APP_ACCEPTANCE'
EXPECTED_CASE_COUNT = 26


def public_sources():
    sources = json.loads((ROOT / 'tools/RecitationEngineProbe/fixtures/sources.json').read_text(encoding='utf-8'))
    sources.append({'file': '002001.mp3', 'sha256': '48077d6641b2403e04c15585b0ede3b8eb3a3c354ae4d8d6f6a4882dc8106ebb'})
    if len(sources) != 11 or len({entry['file'] for entry in sources}) != 11:
        raise ValueError('Expected the eleven pinned public input clips')
    return sources


def expected_cases():
    result = []
    for entry in public_sources():
        for kind in ('public-gain=1.0', 'public-gain=0.03'):
            result.append((entry['file'], kind, entry['sha256']))
        if entry['file'] in ('001002.mp3', '002001.mp3'):
            result.append((entry['file'], 'public-first-two-seconds', entry['sha256']))
    result.extend((name, 'generated-negative-control', None) for name in ('silence', 'noise'))
    if len(result) != EXPECTED_CASE_COUNT:
        raise ValueError('Screening input count changed without updating the contract')
    return result

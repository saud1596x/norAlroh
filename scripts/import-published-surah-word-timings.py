"""Import published playback guidance only after exact source/edition binding.

Offline, reproducible; no network or learner assessment. Unknown coordinates
are excluded, and neither repeats nor gaps receive interpolated timestamps.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/reciter_alignment'))
from published_coordinates import PACKAGES

RECORDINGS = {'ali_al_huthaifi_mp3quran': 74, 'saud_al_shuraim_mp3quran': 31}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidates', type=Path, required=True)
    parser.add_argument('--identity-proof', type=Path, required=True)
    args = parser.parse_args()
    quran = json.loads((ROOT / 'ios/Athar/quran.json').read_bytes())
    keys = [f"{s['number']}:{a['number']}" for s in quran for a in s['ayahs']]
    snapshot_raw = (ROOT / 'content-sources/mushaf-snapshot.json.gz').read_bytes()
    snapshot = json.loads(gzip.decompress(snapshot_raw))
    native = {r['id']: keys[r['verse_id'] - 1] for r in snapshot['records']
              if r['record_type'] == 'mushaf_word' and r['char_type_name'] == 'word'}
    catalog = json.loads((ROOT / 'ios/Athar/haramain-reciters.json').read_bytes())['reciters']
    proof_raw = args.identity_proof.read_bytes()
    proof = json.loads(proof_raw)
    identities = {(r['slug'], r['surah']): r for r in proof['records']}
    result, reports = {}, {}
    for slug, reciter_id in RECORDINGS.items():
        recording = next(r for r in catalog if r['id'] == reciter_id)
        candidate_raw = (args.candidates / (slug + '.json')).read_bytes()
        candidate = json.loads(candidate_raw)
        if (candidate['slug'] != slug or candidate['publishedPackageSHA256'] != PACKAGES[slug]
                or set(candidate['surahs']) != set(map(str, range(1, 115)))):
            raise ValueError('Different/incomplete pinned published candidate')
        chapters = {}
        for chapter, entry in candidate['surahs'].items():
            number = int(chapter)
            expected_url = recording['server'] + f'{number:03}.mp3'
            identity = identities[(slug, number)]
            if (identity['appURL'] != expected_url or identity['publisherURL'] != entry['exactPublisherAudioURL']
                    or identity['app']['status'] != 200 or identity['publisher']['status'] != 200
                    or identity['app']['finalURL'] != expected_url or identity['publisher']['finalURL'] != expected_url):
                raise ValueError('Exact publisher/App audio URL identity is unverified')
            spans = []
            for occurrence in entry['occurrences']:
                verse = occurrence['verse']
                surah, ayah = map(int, verse.split(':'))
                if surah != number:
                    raise ValueError('Foreign surah occurrence')
                for word, start, end in occurrence['spans']:
                    if (native.get(word) != verse or any(type(v) is not int for v in [word, start, end])
                            or not 0 <= start < end <= 21_600_000):
                        raise ValueError('Foreign native word or invalid source clock')
                    spans.append([ayah, word, start, end])
            spans.sort(key=lambda span: (span[2], span[3]))
            if not spans or any(a[3] > b[2] for a, b in zip(spans, spans[1:])):
                raise ValueError('Overlapping or absent published source intervals')
            chapters[chapter] = spans
        result[recording['server']] = {'reciterID': reciter_id, 'recordingID': recording['recordingID'], 'surahs': chapters}
        reports[slug] = {'reciterID': reciter_id, 'recordingID': recording['recordingID'], 'server': recording['server'],
            'surahs': len(chapters), 'spans': sum(map(len, chapters.values())),
            'excludedOccurrences': candidate['excludedOccurrences'],
            'publishedPackageSHA256': PACKAGES[slug], 'boundCandidateSHA256': hashlib.sha256(candidate_raw).hexdigest()}
    document = {'schema': 1, 'nativeSnapshotSHA256': hashlib.sha256(snapshot_raw).hexdigest(), 'recordings': result}
    raw = (json.dumps(document, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
    (ROOT / 'ios/Athar/surah-word-timings.json').write_bytes(raw)
    receipt = {'source': 'https://github.com/QUD-Technologies/quranic-universal-audio/releases/tag/v3.2.0',
        'attribution': 'Wider Community', 'license': 'CC BY 4.0', 'publisherVersion': 'v3.2.0',
        'audioSourceIdentityProofSHA256': hashlib.sha256(proof_raw).hexdigest(),
        'outputSHA256': hashlib.sha256(raw).hexdigest(), 'nativeSnapshotSHA256': document['nativeSnapshotSHA256'],
        'status': 'PUBLISHED_PLAYBACK_GUIDANCE_PARTIAL_AYAH_COVERAGE_NOT_LEARNER_EVIDENCE',
        'acousticReview': 'NOT_RUN; published timing mapped to exact native IDs and source URLs, not all20reader approval',
        'changes': 'Native word/ayah binding; explicit source repetitions and gaps preserved; unmapped verses excluded; no interpolation',
        'recordings': reports}
    directory = ROOT / 'content-sources/reciter-timings'
    (directory / 'published-surah-word-receipt.json').write_bytes((json.dumps(receipt, ensure_ascii=False, indent=2) + '\n').encode())
    print(json.dumps({k: v for k, v in receipt.items() if k != 'recordings'}, indent=2))


if __name__ == '__main__':
    main()

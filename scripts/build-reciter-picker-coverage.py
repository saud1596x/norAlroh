"""Derive small UI coverage metadata from the pinned playback timing payloads.

No clocks or Quran text are changed. Native ID coverage is not audible approval.
"""
import gzip
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def summarize(rows, native, total_verses):
    seen, verses = set(), set()
    for verse, word in rows:
        if native.get(word) != verse:
            raise ValueError('Timing native ID does not belong to its source verse')
        seen.add(word); verses.add(verse)
    missing = set(native)-seen
    return {'timedWords': len(seen), 'totalWords': len(native),
            'timedVerses': len(verses), 'totalVerses': total_verses,
            'onlyMissingFirstBasmala': bool(missing) and missing ==
                {word for word, verse in native.items() if verse == '1:1'}}


def build(root=ROOT):
    raw_native = (root/'content-sources/mushaf-snapshot.json.gz').read_bytes()
    corpus = json.loads((root/'ios/Athar/quran.json').read_bytes())
    keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s['ayahs']]
    native = {r['id']: keys[r['verse_id']-1] for r in json.loads(gzip.decompress(raw_native))['records']
              if r['record_type'] == 'mushaf_word' and r['char_type_name'] == 'word'}
    result = {'schema': 1, 'scope': 'PUBLISHED_TIMING_COVERAGE_NOT_AUDIBLE_APPROVAL',
              'nativeSnapshotSHA256': hashlib.sha256(raw_native).hexdigest(),
              'sourceSHA256': {}, 'recordings': {}}
    for name, swift in [('reciter-word-timings', 'NoorReciterWordTimings'),
                        ('surah-word-timings', 'NoorSurahWordTimings')]:
        raw = (root/'ios/Athar'/f'{name}.json').read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        pin = re.search(r'static let digest = "([a-f0-9]{64})"',
                        (root/'ios/Athar'/f'{swift}.swift').read_text(encoding='utf-8'))
        if not pin or digest != pin[1]:
            raise ValueError('Timing source is not the runtime-pinned payload: ' + name)
        result['sourceSHA256'][name+'.json'] = digest
        document = json.loads(raw)
        if document['schema'] != 1:
            raise ValueError('Unexpected timing schema')
        if name == 'surah-word-timings' and document['nativeSnapshotSHA256'] != result['nativeSnapshotSHA256']:
            raise ValueError('Timing source uses another native edition')
        for source, recording in document['recordings'].items():
            if name == 'reciter-word-timings':
                identity = source
                rows = ((verse, span[0]) for verse, spans in recording.items() for span in spans)
            else:
                identity = f"surah:{recording['reciterID']}:{recording['recordingID']}"
                rows = ((f'{surah}:{span[0]}', span[1])
                        for surah, spans in recording['surahs'].items() for span in spans)
            if identity in result['recordings']:
                raise ValueError('Repeated recording identity')
            result['recordings'][identity] = summarize(rows, native, len(keys))
    return (json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)+'\n').encode('utf-8')


if __name__ == '__main__':
    raw = build()
    (ROOT/'ios/Athar/reciter-picker-coverage.json').write_bytes(raw)
    print('Generated actual timing coverage; pin this SHA256 in NoorReciterPresentation.swift: ' + hashlib.sha256(raw).hexdigest())

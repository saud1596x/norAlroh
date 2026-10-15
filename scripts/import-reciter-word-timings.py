"""Import published recording-specific timing. Never interpolate missing words.

Input: cpfair/quran-align release-2016-11-24 ZIP (CC BY 4.0).
Positions are Tanzil whitespace tokens, bound to this app's verified native IDs.
This validates structure/correspondence, not acoustic accuracy of every segment.
"""
import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path
import unicodedata
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_SHA = "5eeb045d8a7895208c94d2d7ec243567f8f550728835411527c4ffa1e789c9b7"
DIRECTORIES = ["Abdul_Basit_Murattal_64kbps", "Abdurrahmaan_As-Sudais_192kbps", "Saood_ash-Shuraym_128kbps"]

def tokens(text):
    def norm(word):
        return ''.join(c for c in unicodedata.normalize('NFKD', word.replace('ٱ', 'ا'))
                       if unicodedata.category(c).startswith('L') and c not in '\u0640\u06e5\u06e6')
    return [norm(w) for w in text.split() if norm(w)]

def main(archive):
    raw = archive.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == ARCHIVE_SHA, 'Unexpected upstream archive'
    snapshot = json.loads(gzip.decompress((ROOT / 'content-sources/mushaf-snapshot.json.gz').read_bytes()))
    lexical = json.loads((ROOT / 'content-sources/recitation-word-script.json').read_text(encoding='utf-8'))
    quran = json.loads((ROOT / 'ios/Athar/quran.json').read_text(encoding='utf-8'))
    verses = {f"{s['number']}:{a['number']}": tokens(a['text']) for s in quran for a in s['ayahs']}
    keys = list(verses)
    native = collections.defaultdict(list)
    for record in snapshot['records']:
        if record['record_type'] == 'mushaf_word' and record['char_type_name'] == 'word':
            native[keys[record['verse_id'] - 1]].append(record)
    mapping = {}
    for key, words in verses.items():
        rows = sorted(native[key], key=lambda r: r['position_in_verse'])
        groups = lexical['groups'][key]
        assert len(rows) == len(groups)
        ids, bound = [], []
        for row, group in zip(rows, groups):
            assert row['text'] == group[1] and row['page_number'] == group[0]
            parts = tokens(' '.join(group[3]))
            ids.extend([row['id']] * len(parts)); bound.extend(parts)
        assert bound == words, f'Token convention differs: {key}'
        mapping[key] = ids
    result, reports = {}, {}
    with zipfile.ZipFile(archive) as z:
        for directory in DIRECTORIES:
            source = z.read(directory + '.json').decode('utf-8')
            # The published Sudais file contains a crash-log prefix. Preserve
            # its hash/report and parse only the complete JSON array. No rows
            # are invented to replace the upstream failed alignment.
            start = source.find('[{"ayah":')
            assert start >= 0
            data = json.loads(source[start:])
            seen, exported, dropped = set(), {}, 0
            for row in data:
                key = f"{row['surah']}:{row['ayah']}"
                assert key in mapping and key not in seen
                seen.add(key)
                if any(row['stats'].values()):
                    dropped += 1; continue
                segments = []
                for begin, end, milliseconds, until in row['segments']:
                    # Combined-word spans cannot support a single-word cursor.
                    if end != begin + 1 or not 0 <= begin < len(mapping[key]): continue
                    if not 0 <= milliseconds < until <= 3_600_000: continue
                    segments.append([mapping[key][begin], milliseconds, until])
                segments.sort(key=lambda s: s[1])
                if any(a[2] > b[1] for a, b in zip(segments, segments[1:])):
                    dropped += 1; continue
                if segments: exported[key] = segments
            result[directory] = exported
            reports[directory] = {'sourceSHA256': hashlib.sha256(source.encode()).hexdigest(),
                'sourceVerses': len(data), 'ignoredPrefixBytes': len(source[:start].encode()),
                'exportedVerses': len(exported), 'exportedSingleWordSpans': sum(map(len, exported.values())),
                'rejectedAmbiguousVerses': dropped, 'audioBase': f'https://everyayah.com/data/{directory}/'}
        (ROOT / 'content-sources/reciter-timings').mkdir(exist_ok=True)
        (ROOT / 'content-sources/reciter-timings/LICENSE.txt').write_bytes(z.read('LICENSE'))
        (ROOT / 'content-sources/reciter-timings/UPSTREAM-README.txt').write_bytes(z.read('README'))
    output = ROOT / 'ios/Athar/reciter-word-timings.json'
    output.write_text(json.dumps({'schema': 1, 'recordings': result}, separators=(',', ':')), encoding='utf-8')
    report = {'source': 'https://github.com/cpfair/quran-align/releases/tag/release-2016-11-24',
        'author': 'Collin Fair', 'license': 'CC BY 4.0', 'archiveSHA256': ARCHIVE_SHA,
        'outputSHA256': hashlib.sha256(output.read_bytes()).hexdigest(), 'nativeEdition': 382,
        'all6236LexicalBindingsVerified': True, 'recordings': reports,
        'acousticReview': 'NOT_RUN; upstream timings, not independently measured or universally complete',
        'changes': 'Mapped whitespace positions to native IDs; excluded ambiguous and combined-word spans; no interpolation'}
    (ROOT / 'content-sources/reciter-timings/receipt.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('archive', type=Path)
    main(parser.parse_args().archive)

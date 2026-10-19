"""Audit exact published word coordinates against Noor's authored edition.

Offline inputs only. The output remains a timing candidate for the publisher's
exact recording URL, never a same-named voice, learner evidence or release
approval. No fuzzy spelling repairs, interpolated times or downloaded code.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import unicodedata
import zipfile

SCRIPT_SHA256 = '19d5694b057dc68c3811e28f3ad1d58c0f07021a0c67a85cd25619ece7a9bf86'
PACKAGES = {
    'ali_al_huthaifi_mp3quran': '69538d785009f547305057b68e0028d91a552c0e118a3cfcb0eac1698a42a294',
    'saud_al_shuraim_mp3quran': '0b30f23f92874fc54caf7bb83633f3b62da22f992f95a596c1886a681bd36e56',
}


def normalize(text, expand_dagger=False):
    """Same conservative letter normalization as QuranAlignedWord.normalize."""
    if expand_dagger:
        text = text.replace('\u0670', 'ا')
    text = unicodedata.normalize('NFKD', text.replace('ٱ', 'ا'))
    return ''.join(c for c in text if unicodedata.category(c).startswith('L') and c not in 'ـۥۦ')


def map_words(groups, source_words):
    """Return source position -> native group offset, only on one exact path."""
    tokens = [normalize(t) for t in source_words]
    if not groups or not tokens or any(not t for t in tokens):
        return None
    states = {0: {()}}
    for index, group in enumerate(groups):
        aliases = {normalize(''.join(group[column]), expanded)
                   for column in (2, 3) for expanded in (False, True)} - {''}
        max_tokens = max(sum(len(word.split()) for word in group[column]) for column in (2, 3))
        next_states = {}
        for start, paths in states.items():
            for length in range(1, max_tokens + 1):
                stop = start + length
                source_aliases = {normalize(''.join(source_words[start:stop]), expanded) for expanded in (False, True)}
                if stop > len(tokens) or source_aliases.isdisjoint(aliases):
                    continue
                matches = next_states.setdefault(stop, set())
                for path in paths:
                    matches.add(path + (index,) * length)
                    if len(matches) > 1:
                        break  # Two distinct bindings already mean ambiguity.
        states = next_states
        if not states:
            return None
    complete = states.get(len(tokens), set())
    return list(next(iter(complete))) if len(complete) == 1 else None


def bind_row(row, native_ids, source_to_native):
    """Keep each original clock span, including real gaps/repeated groups."""
    if (not isinstance(row, list) or len(row) != 6 or type(row[1]) is not int
            or type(row[2]) is not int or not 0 <= row[1] < row[2] <= 21_600_000
            or type(row[3]) is not bool or type(row[4]) is not int or row[4] < 0
            or not isinstance(row[5], list) or not row[5]):
        raise ValueError('Invalid publisher occurrence')
    previous_time = row[1]
    spans = []
    for word in row[5]:
        if (not isinstance(word, list) or len(word) != 3 or any(type(x) is not int for x in word)
                or not 1 <= word[0] <= len(source_to_native)
                or not previous_time <= word[1] < word[2] <= row[2]):
            raise ValueError('Invalid publisher word index/clock')
        native = source_to_native[word[0] - 1]
        if not 0 <= native < len(native_ids):
            raise ValueError('Foreign native word coordinate')
        spans.append([native_ids[native], word[1], word[2]])
        # A professional reciter can repeat earlier words inside one ayah.
        # Preserve that explicit coordinate; only the audio clock is ordered.
        previous_time = word[2]
    return spans


def pinned(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Published input digest mismatch: ' + path.name)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source = json.loads(pinned(args.inputs / 'digital_khatt_v2_script.json', SCRIPT_SHA256))
    source_verses = {}
    for coordinate, value in source.items():
        if normalize(value['text']):
            key, position = coordinate.rsplit(':', 1)
            source_verses.setdefault(key, []).append((int(position), value['text']))
    script = json.loads((root / 'content-sources/recitation-word-script.json').read_bytes())['groups']
    snapshot = json.loads(gzip.decompress((root / 'content-sources/mushaf-snapshot.json.gz').read_bytes()))
    corpus = json.loads((root / 'ios/Athar/quran.json').read_bytes())
    keys = [f"{surah['number']}:{ayah['number']}" for surah in corpus for ayah in surah['ayahs']]
    records = snapshot['records']
    native = {}
    for record in records:
        if record['record_type'] == 'mushaf_word' and record.get('char_type_name') == 'word':
            native.setdefault(keys[record['verse_id'] - 1], []).append(record)
    coordinates, unresolved = {}, []
    for key, groups in script.items():
        words = native.get(key, [])
        words.sort(key=lambda r: r['position_in_verse'])
        if len(words) != len(groups) or any(r['page_number'] != g[0] for r, g in zip(words, groups)):
            raise ValueError('Authored edition does not match native IDs: ' + key)
        publisher = sorted(source_verses.get(key, []))
        if [position for position, _ in publisher] != list(range(1, len(publisher) + 1)):
            unresolved.append({'verse': key, 'reason': 'NONCONTIGUOUS_SCRIPT_COORDINATES'}); continue
        mapping = map_words(groups, [text for _, text in publisher])
        if mapping is None:
            unresolved.append({'verse': key, 'reason': 'NO_UNIQUE_EXACT_AUTHORED_ALIAS_BINDING'}); continue
        coordinates[key] = ([w['id'] for w in words], mapping)
    report = {'scope': 'PUBLISHED_RECORDING_COORDINATES_ONLY_NOT_ACOUSTIC_OR_RELEASE_APPROVAL',
              'version': 'QUD-v3.2.0', 'nativeVerses': len(script), 'mappedVerses': len(coordinates),
              'unresolvedVerses': unresolved, 'productionPromoted': False, 'recordings': {}}
    args.output.mkdir(parents=True, exist_ok=True)
    for slug, digest in PACKAGES.items():
        with zipfile.ZipFile(io.BytesIO(pinned(args.inputs / (slug + '.zip'), digest))) as archive:
            metadata = json.loads(archive.read('catalog.json'))
            entry = archive.getinfo('word_timestamps.json.gz')
            if entry.file_size > 64_000_000:
                raise ValueError('Oversized timing archive')
            with gzip.GzipFile(fileobj=io.BytesIO(archive.read(entry))) as stream:
                expanded = stream.read(64_000_001)
            if len(expanded) > 64_000_000:
                raise ValueError('Oversized timing document')
            timing = json.loads(expanded)
        meta = timing['_meta']
        if (meta['schema_version'] != 3 or meta['script_sha256'] != SCRIPT_SHA256
                or meta['slug'] != slug or meta['units'] != 'ms' or meta['tier'] != 'word'
                or meta['audio_category'] != 'by_surah' or meta['riwayah'] != 'hafs'):
            raise ValueError('Different published timing contract')
        accepted, excluded = {}, []
        for row in timing['rows']:
            key = row[0]
            if key not in coordinates:
                excluded.append({'verse': key, 'reason': 'UNRESOLVED_NATIVE_COORDINATE'}); continue
            try:
                spans = bind_row(row, *coordinates[key])
            except ValueError as error:
                excluded.append({'verse': key, 'reason': str(error)}); continue
            surah = key.split(':')[0]
            source_url = metadata['audio']['chapter_urls'][surah]
            chapter = accepted.setdefault(surah, {'exactPublisherAudioURL': source_url, 'occurrences': []})
            chapter['occurrences'].append({'verse': key, 'canonical': row[3], 'spans': spans})
        candidate = {'schema': 1, 'slug': slug, 'publishedPackageSHA256': digest,
                     'sourceIdentityBridgeToApp': 'NOT_VERIFIED', 'productionPromoted': False,
                     'surahs': accepted, 'excludedOccurrences': excluded}
        (args.output / (slug + '.json')).write_bytes((json.dumps(candidate, ensure_ascii=False) + '\n').encode())
        report['recordings'][slug] = {'surahs': len(accepted), 'mappedOccurrences': sum(len(c['occurrences']) for c in accepted.values()),
            'nativeTimedSpans': sum(len(o['spans']) for c in accepted.values() for o in c['occurrences']),
            'excludedOccurrences': len(excluded), 'exactSourceBridge': 'NOT_VERIFIED'}
    (args.output / 'report.json').write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + '\n').encode())
    print(json.dumps({k: v for k, v in report.items() if k != 'unresolvedVerses'}, ensure_ascii=False))


if __name__ == '__main__':
    main()

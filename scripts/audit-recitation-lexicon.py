#!/usr/bin/env python3
"""Validate user-supplied QUL locations against the exact rendered edition.

QUL's numeric IDs and Content Sync word_id belong to different databases.
Never join those IDs or infer a compound from matching total counts. A verse
with differing boundaries is quarantined in its entirety, including its tail.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import zipfile
import unicodedata

EXPECTED_JSON_SHA256 = "60b5341ecf04b6dbcdd2c42cc9b377003d9185ac6a76ad104a109ed669b0cf3c"


def canonical_groups(corpus, mapping):
    """Verified display-corpus aliases; never change displayed text or glyphs.

    The three reviewed بعد ما compounds share the original group boundary.
    37:130 is explicitly one QUL group 'ال ياسين', not two rendered words.
    Any other boundary mismatch stops export instead of shifting later words.
    """
    result = {}
    joins = {'2:181': 3, '8:6': 4, '13:37': 8, '37:130': 3}
    for surah in corpus:
        for ayah in surah['ayahs']:
            key = f"{surah['number']}:{ayah['number']}"
            groups = [[token] for token in ayah['text'].split()
                      if any(unicodedata.category(char).startswith('L')
                             and ord(char) not in (0x6e5, 0x6e6) for char in token)]
            if key in joins:
                index = joins[key] - 1
                source = mapping[key][index]['spoken_words']
                if key == '37:130':
                    if source != ['ال ياسين']:
                        raise ValueError('Unverified Ilyasin compound')
                elif source != ['بعد', 'ما']:
                    raise ValueError(f'Unverified canonical compound: {key}')
                groups[index:index + 2] = [groups[index] + groups[index + 1]]
            if len(groups) != len(mapping[key]):
                raise ValueError(f'Canonical aliases do not fit authored groups: {key}')
            result[key] = groups
    return result


def audit(raw, snapshot, corpus, reviewed=None):
    source_hash = hashlib.sha256(raw).hexdigest()
    if source_hash != EXPECTED_JSON_SHA256:
        raise ValueError("Lexicon changed; inspect and approve its identity before updating the pin")
    data = json.loads(raw)
    keys = [f"{surah['number']}:{ayah['number']}"
            for surah in corpus for ayah in surah['ayahs']]
    if len(keys) != 6236 or len(set(keys)) != 6236:
        raise ValueError("Canonical verse identity is incomplete")
    lexicon = collections.defaultdict(list)
    source_ids = set()
    for location, item in data.items():
        if location != item['location'] or location != f"{item['surah']}:{item['ayah']}:{item['word']}":
            raise ValueError(f"Invalid source location: {location}")
        if int(item['id']) in source_ids or not item['text'].strip():
            raise ValueError(f"Duplicate ID or empty word: {location}")
        source_ids.add(int(item['id']))
        lexicon[f"{item['surah']}:{item['ayah']}"].append(item)
    if set(lexicon) != set(keys) or len(data) != 83668:
        raise ValueError("Incomplete source verse/word coverage")
    native = collections.defaultdict(list)
    native_ids = set()
    for item in snapshot['records']:
        if item['record_type'] != 'mushaf_word':
            continue
        if item['id'] in native_ids or not 1 <= item['verse_id'] <= len(keys):
            raise ValueError("Invalid native word identity")
        native_ids.add(item['id'])
        native[keys[item['verse_id'] - 1]].append(item)
    if set(native) != set(keys) or len(native_ids) != 83665:
        raise ValueError("Incomplete rendered edition")
    unresolved = []
    mapped = 0
    markers = 0
    correspondences = {}
    reviews = {row['verse']: row for row in (reviewed or {}).get('compounds', [])}
    if reviewed and (reviewed.get('source_sha256') != source_hash
                     or len(reviews) != len(reviewed['compounds'])):
        raise ValueError("Compound reviews do not belong to this source")
    if not set(reviews).issubset(set(keys)):
        raise ValueError("Reviewed compound refers to an unknown verse")
    for key in keys:
        source = sorted(lexicon[key], key=lambda row: int(row['word']))
        target = sorted(native[key], key=lambda row: row['position_in_verse'])
        if [int(x['word']) for x in source] != list(range(1, len(source) + 1)):
            raise ValueError(f"Source positions are not contiguous: {key}")
        if [x['position_in_verse'] for x in target] != list(range(1, len(target) + 1)):
            raise ValueError(f"Native positions are not contiguous: {key}")
        ayah_number = int(key.split(':')[1])
        if not source[-1]['text'].isdigit() or int(source[-1]['text']) != ayah_number:
            raise ValueError(f"Wrong source ayah marker: {key}")
        if target[-1]['char_type_name'] != 'end' or any(x['char_type_name'] != 'word' for x in target[:-1]):
            raise ValueError(f"Wrong native ayah marker: {key}")
        markers += 1
        groups = [[word] for word in source[:-1]]
        if key in reviews:
            row = reviews[key]
            position = row['native_position']
            if row['source_positions'] != [position, position + 1]:
                raise ValueError(f"Invalid reviewed compound positions: {key}")
            item = target[position - 1]
            source_group = source[position - 1:position + 1]
            if (item['text'] != row['native_code'] or item['page_number'] != row['native_page']
                    or [x['text'] for x in source_group] != row['source_texts']):
                raise ValueError(f"Reviewed compound identity changed: {key}")
            groups[position - 1:position + 1] = [source_group]
        if len(groups) != len(target) - 1:
            unresolved.append(dict(verse=key, source_count=len(source), native_count=len(target),
                reason="Different authored word boundaries; no guessed tail shift",
                source_words=[dict(location=x['location'], text=x['text']) for x in source]))
        else:
            mapped += len(target) - 1
            correspondences[key] = [dict(position=item['position_in_verse'],
                native_word_id=item['id'], native_code=item['text'], page=item['page_number'],
                source_locations=[word['location'] for word in group],
                spoken_words=[word['text'] for word in group])
                for item, group in zip(target[:-1], groups)]
    return dict(schema_version=1, source_sha256=source_hash,
        strategy="Canonical verse key and authored position, plus pinned manually reviewed compounds; never cross-database numeric ID",
        verses_checked=len(keys), markers_checked=markers,
        position_compatible_verses=len(keys) - len(unresolved),
        position_compatible_words=mapped, unresolved_verses=unresolved,
        complete_correspondence_verified=not unresolved,
        reviewed_compounds=len(reviews),
        correspondences=correspondences,
        scope="Position audit only. Does not approve ASR, display text replacement or pronunciation grading.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lexicon', type=Path, required=True)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--canonical', type=Path, default=Path('ios/Athar/quran.json'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reviewed-compounds', type=Path)
    parser.add_argument('--word-script-output', type=Path)
    args = parser.parse_args()
    if zipfile.is_zipfile(args.lexicon):
        with zipfile.ZipFile(args.lexicon) as archive:
            if archive.namelist() != ['imlaei-simple.json']:
                raise ValueError("Expected exactly the supplied JSON; do not extract arbitrary ZIP paths")
            raw = archive.read('imlaei-simple.json')
    else:
        raw = args.lexicon.read_bytes()
    reviewed = json.loads(args.reviewed_compounds.read_bytes()) if args.reviewed_compounds else None
    result = audit(raw, json.loads(args.snapshot.read_bytes()), json.loads(args.canonical.read_bytes()), reviewed)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Keep the audit small; the exact correspondence is a separate source asset.
    mapping = result.pop('correspondences')
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    if args.word_script_output and result['complete_correspondence_verified']:
        aliases = canonical_groups(json.loads(args.canonical.read_bytes()), mapping)
        compact = {key: [[word['page'], word['native_code'], word['spoken_words'], alias]
                         for word, alias in zip(words, aliases[key])]
                   for key, words in mapping.items()}
        args.word_script_output.parent.mkdir(parents=True, exist_ok=True)
        args.word_script_output.write_text(json.dumps(dict(schema_version=2,
            source_sha256=result['source_sha256'],
            edition=dict(resource_group='mushafs', resource_id=1, resource_content_id=382),
            groups=compact), ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f"Checked {result['verses_checked']} verses and {result['markers_checked']} markers; "
          f"{len(result['unresolved_verses'])} boundary differences quarantined.")
    return 0 if result['complete_correspondence_verified'] else 2


if __name__ == '__main__':
    raise SystemExit(main())

"""No approximate labels, source-clock interpolation or foreign word IDs."""
import pytest
import copy
from functools import lru_cache
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import zipfile
from collections import Counter, defaultdict
import re
import struct
from published_coordinates import (map_words, map_published_words, published_aliases,
    bind_row, normalize, PACKAGES, SCRIPT_SHA256, AUTHORED_SCRIPT_SHA256,
    NATIVE_SNAPSHOT_SHA256, PUBLISHED_ALIASES_PATH, PUBLISHED_ALIASES_SHA256)

ROOT = Path(__file__).resolve().parents[2]
REVIEWED = published_aliases(ROOT / PUBLISHED_ALIASES_PATH)


@lru_cache(maxsize=1)
def native_inputs():
    groups = json.loads((ROOT / 'content-sources/recitation-word-script.json').read_bytes())['groups']
    quran = json.loads((ROOT / 'ios/Athar/quran.json').read_bytes())
    keys = [f"{surah['number']}:{ayah['number']}" for surah in quran for ayah in surah['ayahs']]
    snapshot = json.loads(gzip.decompress((ROOT / 'content-sources/mushaf-snapshot.json.gz').read_bytes()))
    rows = {}
    for row in snapshot['records']:
        if row['record_type'] == 'mushaf_word' and row['char_type_name'] == 'word':
            rows.setdefault(keys[row['verse_id'] - 1], []).append(row)
    ids = {verse: [row['id'] for row in sorted(records, key=lambda row: row['position_in_verse'])]
           for verse, records in rows.items()}
    return groups, ids


def group(imlaei, canonical=None):
    return [1, '', imlaei, canonical or imlaei]


def test_only_existing_authored_aliases_allow_edition_spellings():
    assert map_words([group(['في'], ['فِى'])], ['فِي']) == [0]
    assert map_words([group(['على'])], ['علي']) is None
    assert map_words([group(['مالك'])], ['ملك']) is None
    assert map_words([group(['كتاب'], ['كِتَٰب'])], ['كِتَاب']) == [0]
    assert normalize('صلى') != normalize('صلي')
    assert map_words([group(['يا بني'], ['يَٰبَنِىٓ'])], ['يَٰبَنِيٓ']) == [0]


@pytest.mark.parametrize('word_id,entry', list(REVIEWED.items()), ids=list(REVIEWED))
def test_all_98_reviewed_tuples_bind_only_their_exact_native_publisher_coordinates(word_id, entry):
    script, native_ids = native_inputs()
    groups = script[entry['verse']]
    index = entry['position'] - 1
    # Exercise the complete expected identity partition with every reviewed
    # exception for this ayah, and strict authored words at other positions.
    ids = list(native_ids[entry['verse']])
    source = [''.join(g[3]) for g in groups]
    for current_id, current in REVIEWED.items():
        if current['verse'] == entry['verse']:
            position = current['position'] - 1
            assert ids[position] == int(current_id)
            source[position] = current['publisherWord']
    assert map_words([groups[index]], [source[index]]) is None
    assert map_published_words(entry['verse'], groups, source, ids, REVIEWED) == list(range(len(groups)))
    wrong = list(source); wrong[index] = 'سيارة'
    assert map_published_words(entry['verse'], groups, wrong, ids, REVIEWED) is None
    altered = copy.deepcopy(groups); altered[index][3] = ['علي']
    assert map_published_words(entry['verse'], altered, source, ids, REVIEWED) is None
    wrong_ids = list(ids); wrong_ids[index] = 999_999
    assert map_published_words(entry['verse'], groups, source, wrong_ids, REVIEWED) is None
    assert map_published_words('114:6', groups, source, ids, REVIEWED) is None


def test_publisher_bridge_cannot_authorize_global_yeh_fold_missing_words_or_count_only_matching():
    assert map_words([group(['على'])], ['علي']) is None
    assert map_published_words('2:26', [group(['على'])], ['علي'], [529830], REVIEWED) is None
    assert map_published_words('2:26', [group(['مالك'])], ['ملك'], [529830], REVIEWED) is None
    assert map_published_words('2:26', [group(['قل'])], [], [529830], REVIEWED) is None
    assert map_published_words('2:26', [group(['قل']), group(['هو'])], ['قل'], [529830, 529831], REVIEWED) is None


def test_reviewed_bridge_and_both_editions_are_pinned_and_tampering_is_rejected(tmp_path):
    path = ROOT / PUBLISHED_ALIASES_PATH
    document = json.loads(path.read_bytes())
    assert len(REVIEWED) == 98
    assert document['publisherScriptSHA256'] == SCRIPT_SHA256
    assert document['publishedPackagesSHA256'] == PACKAGES
    assert hashlib.sha256((ROOT / 'content-sources/recitation-word-script.json').read_bytes()).hexdigest() == AUTHORED_SCRIPT_SHA256
    assert hashlib.sha256((ROOT / 'content-sources/mushaf-snapshot.json.gz').read_bytes()).hexdigest() == NATIVE_SNAPSHOT_SHA256
    assert hashlib.sha256(path.read_bytes()).hexdigest() == PUBLISHED_ALIASES_SHA256
    altered = tmp_path / 'altered-aliases.json'
    document['aliases']['529830']['publisherWord'] = 'سيارة'
    altered.write_text(json.dumps(document), encoding='utf-8')
    with pytest.raises(ValueError, match='digest mismatch'):
        published_aliases(altered)


def test_regenerated_resource_has_exact_native_coverage_and_keeps_missing_shuraim_basmala():
    _, native_ids = native_inputs()
    expected = {word for ids in native_ids.values() for word in ids}
    assert len(expected) == 77_429
    path = ROOT / 'ios/Athar/surah-word-timings.json'
    document = json.loads(path.read_bytes())
    assert document['nativeSnapshotSHA256'] == NATIVE_SNAPSHOT_SHA256
    source = (ROOT / 'ios/Athar/NoorSurahWordTimings.swift').read_text(encoding='utf-8')
    assert re.search(r'static let digest = "([0-9a-f]{64})"', source)[1] == hashlib.sha256(path.read_bytes()).hexdigest()
    mapping = {word: verse for verse, ids in native_ids.items() for word in ids}
    actual = {}
    for recording in document['recordings'].values():
        assert set(recording['surahs']) == set(map(str, range(1, 115)))
        words = set()
        for chapter, spans in recording['surahs'].items():
            assert all(a[3] <= b[2] for a, b in zip(spans, spans[1:]))
            for ayah, word, start, end in spans:
                assert mapping[word] == f'{chapter}:{ayah}'
                assert all(type(value) is int for value in (ayah, word, start, end))
                assert 0 <= start < end <= 21_600_000
                words.add(word)
        actual[recording['reciterID']] = words
    assert actual[74] == expected
    assert expected - actual[31] == set(native_ids['1:1']) == {529417, 529418, 529419, 529420}
    assert len(actual[31]) == 77_425
    receipt = json.loads((ROOT / 'content-sources/reciter-timings/published-surah-word-receipt.json').read_bytes())
    assert receipt['outputSHA256'] == hashlib.sha256(path.read_bytes()).hexdigest()
    assert receipt['exactCoordinateBridgeSHA256'] == PUBLISHED_ALIASES_SHA256
    assert receipt['audioSourceIdentityProofSHA256'] == '188ca482f9927c10cd4477f79fb38f0702f27095531bdb1e756387f58c29b941'
    assert receipt['recordings']['ali_al_huthaifi_mp3quran']['missingNativeWordIDs'] == []
    assert receipt['recordings']['saud_al_shuraim_mp3quran']['missingNativeWordIDs'] == [529417, 529418, 529419, 529420]


@pytest.mark.parametrize('slug', list(PACKAGES))
def test_regenerated_rows_preserve_every_original_pinned_source_clock_repeat_and_gap(slug):
    # The pinned upstream inputs are external development evidence, not bundled
    # model/audio data. This audit is explicitly skipped when they are absent.
    if not os.environ.get('NOOR_QUD_INPUTS'):
        pytest.skip('Pinned QUD input directory required for original-source clock audit')
    inputs = Path(os.environ['NOOR_QUD_INPUTS'])
    script_raw = (inputs / 'digital_khatt_v2_script.json').read_bytes()
    assert hashlib.sha256(script_raw).hexdigest() == SCRIPT_SHA256
    published = defaultdict(list)
    for coordinate, value in json.loads(script_raw).items():
        if normalize(value['text']):
            verse, position = coordinate.rsplit(':', 1)
            published[verse].append((int(position), value['text']))
    groups, native_ids = native_inputs()
    mappings = {verse: map_published_words(verse, value,
        [word for _, word in sorted(published[verse])], native_ids[verse], REVIEWED)
        for verse, value in groups.items()}
    assert len(mappings) == 6236 and all(value is not None for value in mappings.values())
    archive_raw = (inputs / (slug + '.zip')).read_bytes()
    assert hashlib.sha256(archive_raw).hexdigest() == PACKAGES[slug]
    with zipfile.ZipFile(io.BytesIO(archive_raw)) as archive:
        raw = json.loads(gzip.decompress(archive.read('word_timestamps.json.gz')))
    expected = defaultdict(list)
    for row in raw['rows']:
        verse = row[0]; chapter, ayah = verse.split(':')
        for word, start, end in bind_row(row, native_ids[verse], mappings[verse]):
            expected[chapter].append([int(ayah), word, start, end])
    document = json.loads((ROOT / 'ios/Athar/surah-word-timings.json').read_bytes())
    # Publisher URLs may redirect to the exact application URL; the existing
    # importer independently verifies that bridge against its pinned receipt.
    reciter_id = 74 if slug == 'ali_al_huthaifi_mp3quran' else 31
    recording = next(value for value in document['recordings'].values() if value['reciterID'] == reciter_id)
    for chapter, spans in expected.items():
        ordered = sorted(spans, key=lambda span: (span[2], span[3]))
        actual = recording['surahs'][chapter]
        assert actual == ordered
        assert b''.join(struct.pack('<4q', *span) for span in actual) == b''.join(struct.pack('<4q', *span) for span in ordered)
    if reciter_id == 31:
        assert not any(row[0] == '1:1' for row in raw['rows'])
    # Every interval of the pre-bridge artifact must survive with multiplicity.
    if os.environ.get('NOOR_QUD_PRIOR_TIMING'):
        before_raw = Path(os.environ['NOOR_QUD_PRIOR_TIMING']).read_bytes()
        assert hashlib.sha256(before_raw).hexdigest() == '60fa8fe85296ba685ca273e1c19f24a0d4b3c9838ecd20f5ece340c700d72cfe'
        prior = next(value for value in json.loads(before_raw)['recordings'].values() if value['reciterID'] == reciter_id)
        for chapter, spans in prior['surahs'].items():
            assert not (Counter(map(tuple, spans)) - Counter(map(tuple, recording['surahs'][chapter])))


def test_compound_native_groups_keep_exact_published_subword_spans_and_gaps():
    mapping = map_words([group(['بعد', 'ما']), group(['سمعه'])], ['بَعْدِ', 'مَا', 'سَمِعَهُ'])
    assert mapping == [0, 0, 1]
    assert map_words([group(['بعد ما']), group(['سمعه'])], ['بَعْدِ', 'مَا', 'سَمِعَهُ']) == mapping
    row = ['2:181', 100, 900, True, 0, [[1, 100, 200], [2, 400, 500], [3, 600, 800]]]
    assert bind_row(row, [10, 11], mapping) == [[10, 100, 200], [10, 400, 500], [11, 600, 800]]


def test_unspoken_or_ambiguous_coordinates_cannot_supply_missing_words():
    assert map_words([group(['قل']), group(['هو'])], ['قل']) is None
    assert map_words([group(['قل'])], ['قل', 'هو']) is None
    assert map_words([group(['قل'])], []) is None
    # Distinct exact segmentations into the same count of authored groups.
    ambiguous = [group(['ب', 'ب'], ['ب']), group(['ب', 'ب'], ['ب'])]
    assert map_words(ambiguous, ['ب', 'ب', 'ب']) is None


@pytest.mark.parametrize('words', [
    [[1, 0, 100]], [[1, 100, 500], [2, 400, 600]], [[0, 100, 200]],
    [[3, 100, 200]], [[1, 100, 1100]], [[True, 100, 200]], [[1, 200, 100]]])
def test_foreign_indices_overlap_and_outside_occurrence_clocks_fail(words):
    with pytest.raises(ValueError):
        bind_row(['1:1', 100, 1000, True, 0, words], [7, 8], [0, 1])


def test_repeated_partial_occurrence_uses_its_explicit_positions_only():
    row = ['1:1', 1500, 2000, False, 0, [[2, 1600, 1700]]]
    assert bind_row(row, [7, 8], [0, 1]) == [[8, 1600, 1700]]


def test_real_reciter_repetition_can_return_to_prior_words_without_rewriting_clocks():
    row = ['1:1', 100, 1000, True, 0, [[1, 100, 200], [2, 200, 400], [1, 500, 600], [2, 650, 800]]]
    assert bind_row(row, [7, 8], [0, 1]) == [[7, 100, 200], [8, 200, 400], [7, 500, 600], [8, 650, 800]]

"""Coverage metadata is source-derived; these tests do not certify audio sync."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReciterPickerCoverageTests(unittest.TestCase):
    def test_generator_reproduces_receipt_and_rejects_borrowed_native_ids(self):
        spec = importlib.util.spec_from_file_location('picker_coverage', ROOT/'scripts/build-reciter-picker-coverage.py')
        generator = importlib.util.module_from_spec(spec); spec.loader.exec_module(generator)
        self.assertEqual(generator.build(), (ROOT/'ios/Athar/reciter-picker-coverage.json').read_bytes())
        native = {10: '1:1', 11: '1:2'}
        actual = generator.summarize([('1:2', 11), ('1:2', 11)], native, 2)
        self.assertEqual(actual['timedWords'], 1, 'Real repetitions are not distinct word coverage')
        self.assertTrue(actual['onlyMissingFirstBasmala'])
        with self.assertRaisesRegex(ValueError, 'does not belong'):
            generator.summarize([('1:1', 11)], native, 2)

    def test_shipped_coverage_matches_exact_current_recordings_and_native_ids(self):
        path = ROOT / 'ios/Athar/reciter-picker-coverage.json'
        self.assertTrue(path.is_file(), 'Picker has no source-bound coverage receipt')
        receipt = json.loads(path.read_bytes())
        self.assertEqual(receipt['schema'], 1)
        self.assertEqual(receipt['scope'], 'PUBLISHED_TIMING_COVERAGE_NOT_AUDIBLE_APPROVAL')
        for name in ('reciter-word-timings.json', 'surah-word-timings.json', 'additional-surah-word-timings.json'):
            self.assertEqual(receipt['sourceSHA256'][name], hashlib.sha256((ROOT/'ios/Athar'/name).read_bytes()).hexdigest())
        raw = (ROOT/'content-sources/mushaf-snapshot.json.gz').read_bytes()
        self.assertEqual(receipt['nativeSnapshotSHA256'], hashlib.sha256(raw).hexdigest())
        corpus = json.loads((ROOT/'ios/Athar/quran.json').read_bytes())
        keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s['ayahs']]
        native = {r['id']: keys[r['verse_id']-1] for r in json.loads(gzip.decompress(raw))['records']
                  if r['record_type']=='mushaf_word' and r['char_type_name']=='word'}
        sources = {}
        verses = json.loads((ROOT/'ios/Athar/reciter-word-timings.json').read_bytes())['recordings']
        for identity, rows in verses.items():
            sources[identity] = ({span[0] for spans in rows.values() for span in spans}, set(rows))
        whole = json.loads((ROOT/'ios/Athar/surah-word-timings.json').read_bytes())['recordings']
        whole.update(json.loads((ROOT/'ios/Athar/additional-surah-word-timings.json').read_bytes())['recordings'])
        for row in whole.values():
            sources[f"surah:{row['reciterID']}:{row['recordingID']}"] = (
                {span[1] for spans in row['surahs'].values() for span in spans},
                {f'{surah}:{span[0]}' for surah, spans in row['surahs'].items() for span in spans})
        self.assertEqual(set(receipt['recordings']), {
            'Abdul_Basit_Murattal_64kbps','Abdurrahmaan_As-Sudais_192kbps',
            'Saood_ash-Shuraym_128kbps','surah:74:74','surah:31:31',
            'surah:1000001:1000001','surah:1000002:1000002','surah:1000003:1000003'})
        for identity, row in receipt['recordings'].items():
            words, timed = sources[identity]
            self.assertEqual(row['timedWords'], len(words))
            self.assertEqual(row['totalWords'], len(native))
            self.assertEqual(row['timedVerses'], len(timed))
            self.assertEqual(row['totalVerses'], len(keys))
            missing = set(native)-words
            self.assertEqual(row['onlyMissingFirstBasmala'], bool(missing) and
                             missing == {word for word, verse in native.items() if verse=='1:1'})
        self.assertEqual(receipt['recordings']['surah:74:74']['timedWords'], 77429)
        self.assertEqual(receipt['recordings']['surah:31:31']['timedWords'], 77425)
        self.assertTrue(receipt['recordings']['surah:31:31']['onlyMissingFirstBasmala'])

    def test_receipt_hash_is_pinned_by_the_runtime_label_reader(self):
        path = ROOT/'ios/Athar/reciter-picker-coverage.json'
        self.assertTrue(path.is_file(), 'Missing bundled timing coverage')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        self.assertIn('"'+digest+'"', (ROOT/'ios/Athar/NoorReciterPresentation.swift').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()

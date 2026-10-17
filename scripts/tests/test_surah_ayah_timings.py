import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('surah_import', ROOT / 'scripts/import-surah-ayah-timings.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SurahAyahTimingTests(unittest.TestCase):
    def test_complete_offline_import_is_byte_identical_and_preserves_rejections(self):
        raw, rejected = module.build()
        self.assertEqual(raw, (ROOT/'ios/Athar/surah-ayah-timings.json').read_bytes())
        self.assertEqual(len(rejected),122)

    def test_all_tracks_have_exact_native_numbering_recording_and_coverage(self):
        raw = (ROOT / 'ios/Athar/surah-ayah-timings.json').read_bytes()
        document = json.loads(raw)
        receipt = json.loads((ROOT / 'content-sources/reciter-ayah-timings/receipt.json').read_text(encoding='utf-8'))
        coverage_raw = (ROOT / 'ios/Athar/surah-ayah-timing-coverage.json').read_bytes()
        coverage = json.loads(coverage_raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(), receipt['outputSHA256'])
        self.assertEqual(coverage['dataSHA256'], receipt['outputSHA256'])
        swift = (ROOT / 'ios/Athar/NoorSurahAyahTimings.swift').read_text(encoding='utf-8')
        self.assertIn(hashlib.sha256(raw).hexdigest(), swift)
        self.assertIn(hashlib.sha256(coverage_raw).hexdigest(), swift)
        catalog = {r['server']: r for r in json.loads((ROOT / 'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']}
        counts = {s['number']: len(s['ayahs']) for s in json.loads((ROOT / 'ios/Athar/quran.json').read_text(encoding='utf-8'))}
        indexed = {r['server']: r for r in coverage['recordings']}
        total = 0
        for server, recording in document['recordings'].items():
            for field, native in [('reciterID', 'id'), ('recordingID', 'recordingID')]:
                self.assertEqual(recording[field], catalog[server][native])
                self.assertEqual(indexed[server][field], recording[field])
            self.assertEqual(indexed[server]['surahs'], sorted(map(int, recording['surahs'])))
            for surah, spans in recording['surahs'].items():
                self.assertEqual([v[0] for v in spans], list(range(1, counts[int(surah)] + 1)))
                self.assertTrue(all(type(x) is int for v in spans for x in v))
                self.assertTrue(all(0 <= v[1] < v[2] <= 21_600_000 for v in spans))
                self.assertTrue(all(a[2] <= b[1] for a, b in zip(spans, spans[1:])))
                total += 1
        self.assertEqual(total, 1816)
        self.assertEqual(set(indexed), set(document['recordings']))
        for rejected in receipt['rejectedTracks']:
            self.assertNotIn(str(rejected['surah']), document['recordings'][rejected['server']]['surahs'])

    def test_no_number_shifts_overlaps_partial_chapters_or_boolean_times(self):
        invalid = [
            [{'ayah': 0, 'start_time': 0, 'end_time': 2}, {'ayah': 1, 'start_time': 2, 'end_time': 4}],
            [{'ayah': 1, 'start_time': 0, 'end_time': 3}, {'ayah': 2, 'start_time': 2, 'end_time': 4}],
            [{'ayah': 1, 'start_time': True, 'end_time': 2}],
        ]
        for rows in invalid:
            with self.assertRaises(ValueError): module.valid_spans(rows, 2)
        rows = [{'ayah': 0, 'start_time': 0, 'end_time': 5}, {'ayah': 1, 'start_time': 5, 'end_time': 9}]
        self.assertEqual(module.valid_spans(rows, 1), [[1, 5, 9]])

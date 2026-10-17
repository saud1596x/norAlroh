"""Verify shipped timing bindings, not audible synchronization or iPhone UI."""
import gzip
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ReciterTimingResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = (ROOT / 'ios/Athar/reciter-word-timings.json').read_bytes()
        cls.data = json.loads(cls.raw)['recordings']
        cls.receipt = json.loads((ROOT / 'content-sources/reciter-timings/receipt.json').read_text(encoding='utf-8'))
        snapshot = json.loads(gzip.decompress((ROOT / 'content-sources/mushaf-snapshot.json.gz').read_bytes()))
        quran = json.loads((ROOT / 'ios/Athar/quran.json').read_text(encoding='utf-8'))
        keys = [f"{s['number']}:{a['number']}" for s in quran for a in s['ayahs']]
        cls.native = {r['id']: keys[r['verse_id'] - 1] for r in snapshot['records']
                      if r['record_type'] == 'mushaf_word' and r['char_type_name'] == 'word'}

    def test_integrity_and_recording_identity(self):
        digest = hashlib.sha256(self.raw).hexdigest()
        self.assertEqual(digest, self.receipt['outputSHA256'])
        self.assertIn('"' + digest + '"', (ROOT / 'ios/Athar/NoorReciterWordTimings.swift').read_text(encoding='utf-8'))
        self.assertEqual(set(self.data), set(self.receipt['recordings']))
        self.assertNotIn('Abdurrahmaan_As-Sudais_64kbps', self.data)
        self.assertNotIn('Saood_ash-Shuraym_64kbps', self.data)

    def test_every_segment_binds_to_its_own_native_verse_with_nonoverlapping_intervals(self):
        total = 0
        for directory, verses in self.data.items():
            self.assertEqual(len(verses), self.receipt['recordings'][directory]['exportedVerses'])
            for verse, spans in verses.items():
                previous = 0
                for word, start, end in spans:
                    self.assertEqual(self.native[word], verse)
                    self.assertGreaterEqual(start, previous)
                    self.assertGreater(end, start)
                    previous = end; total += 1
        self.assertEqual(total, sum(r['exportedSingleWordSpans'] for r in self.receipt['recordings'].values()))

    def test_licenses_remain_in_distribution(self):
        self.assertEqual((ROOT / 'ios/Athar/Reciter-Timings-LICENSE.txt').read_bytes(),
                         (ROOT / 'content-sources/reciter-timings/LICENSE.txt').read_bytes())
        notice = (ROOT / 'ios/Athar/NoorLegalContent.swift').read_text(encoding='utf-8')
        self.assertIn('Collin Fair', notice)
        self.assertIn('https://creativecommons.org/licenses/by/4.0/', notice)

if __name__ == '__main__':
    unittest.main()

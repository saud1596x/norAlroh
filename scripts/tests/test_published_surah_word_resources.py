"""Real imported playback coordinates; not audible synchronization evidence."""
import gzip
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublishedSurahWordResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = (ROOT/'ios/Athar/surah-word-timings.json').read_bytes()
        cls.data = json.loads(cls.raw)
        cls.receipt = json.loads((ROOT/'content-sources/reciter-timings/published-surah-word-receipt.json').read_bytes())
        snapshot_raw = (ROOT/'content-sources/mushaf-snapshot.json.gz').read_bytes()
        cls.snapshot_sha = hashlib.sha256(snapshot_raw).hexdigest()
        corpus = json.loads((ROOT/'ios/Athar/quran.json').read_bytes())
        keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s['ayahs']]
        cls.native = {r['id']: keys[r['verse_id']-1] for r in json.loads(gzip.decompress(snapshot_raw))['records']
                      if r['record_type'] == 'mushaf_word' and r['char_type_name'] == 'word'}
        cls.catalog = {r['server']:r for r in json.loads((ROOT/'ios/Athar/haramain-reciters.json').read_bytes())['reciters']}

    def test_bundle_pins_exact_edition_and_recording_identity(self):
        digest = hashlib.sha256(self.raw).hexdigest()
        self.assertEqual(self.receipt['outputSHA256'], digest)
        self.assertIn('"'+digest+'"', (ROOT/'ios/Athar/NoorSurahWordTimings.swift').read_text(encoding='utf-8'))
        self.assertEqual(self.data['nativeSnapshotSHA256'], self.snapshot_sha)
        self.assertEqual({r['reciterID'] for r in self.data['recordings'].values()}, {31,74})
        for server, recording in self.data['recordings'].items():
            self.assertEqual(recording['reciterID'], self.catalog[server]['id'])
            self.assertEqual(recording['recordingID'], self.catalog[server]['recordingID'])
            self.assertEqual(set(recording['surahs']), set(map(str,range(1,115))))

    def test_every_span_is_its_exact_native_ayah_with_real_source_clock_order(self):
        total = 0
        for recording in self.data['recordings'].values():
            for surah, spans in recording['surahs'].items():
                previous = 0
                for ayah, native, start, end in spans:
                    self.assertEqual(self.native[native], f'{surah}:{ayah}')
                    self.assertGreaterEqual(start, previous); self.assertGreater(end,start)
                    self.assertLessEqual(end,21_600_000);previous=end;total+=1
        self.assertEqual(total,156624)

    def test_unmapped_ayahs_and_missing_publisher_basmala_remain_absent(self):
        for source in self.receipt['recordings'].values():
            spans = self.data['recordings'][source['server']]['surahs']
            for excluded in source['excludedOccurrences']:
                surah, ayah = excluded['verse'].split(':')
                self.assertFalse(any(row[0] == int(ayah) for row in spans[surah]))
        shuraim = next(r for r in self.data['recordings'].values() if r['reciterID']==31)
        self.assertFalse(any(row[0]==1 for row in shuraim['surahs']['1']))

    def test_attribution_outside_privacy_and_release_payload_are_preserved(self):
        notice = (ROOT/'ios/Athar/Published-Surah-Word-Timings-SOURCE.txt').read_text(encoding='utf-8')
        self.assertIn('Wider Community',notice);self.assertIn('CC BY',notice)
        legal = (ROOT/'ios/Athar/NoorLegalContent.swift').read_text(encoding='utf-8')
        self.assertIn('Wider Community',legal)
        gate = (ROOT/'scripts/verify-release-ipa.py').read_text(encoding='utf-8')
        for resource in ['surah-word-timings.json','Published-Surah-Word-Timings-SOURCE.txt','Published-Surah-Word-Timings-LICENSE.txt']:
            self.assertIn("'"+resource+"'",gate)


if __name__ == '__main__':
    unittest.main()
